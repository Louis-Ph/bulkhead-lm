(** Tests for the named-pool feature.

    Each test builds a small in-memory runtime store with a couple of
    declarative pools and exercises the selector, the budget ledger, and the
    JSON exposure. We deliberately avoid network: the routes have a fake
    backend just so [Config.route] is well-formed and the circuit-breaker
    integration can be exercised. *)

module Config = Bulkhead_lm.Config
module Config_test_support = Bulkhead_lm.Config_test_support
module Runtime_state = Bulkhead_lm.Runtime_state
module Pool_latency = Bulkhead_lm.Pool_latency
module Pool_selector = Bulkhead_lm.Pool_selector
module Pool_runtime = Bulkhead_lm.Pool_runtime
module Backend_circuit = Bulkhead_lm.Backend_circuit

let stub_backend ~provider_id ~upstream_model =
  Config_test_support.backend
    ~provider_id
    ~provider_kind:Config.Openai_compat
    ~api_base:"https://api.example.test/v1"
    ~upstream_model
    ~api_key_env:"FAKE_KEY"
    ()
;;

let stub_route ~public_model =
  Config_test_support.route
    ~public_model
    ~backends:[ stub_backend ~provider_id:(public_model ^ "-primary") ~upstream_model:public_model ]
    ()
;;

let make_store ~routes ~pools =
  let config = Config_test_support.sample_config ~routes ~pools () in
  match Runtime_state.create_result config with
  | Ok store -> store
  | Error err -> Alcotest.failf "expected runtime store: %s" err
;;

let pool ~name ?(is_global = false) members = { Config.name; members; is_global }

let member ~route ?(budget = 5_000) () =
  { Config.route_model = route; daily_token_budget = budget }
;;

(* --- Selector ranks lowest-latency in-budget healthy member -------------- *)

let selector_ranks_by_latency_test _switch () =
  let routes = [ stub_route ~public_model:"fast"; stub_route ~public_model:"slow" ] in
  let pool_def =
    pool ~name:"pool-01" [ member ~route:"fast" (); member ~route:"slow" () ]
  in
  let store = make_store ~routes ~pools:[ pool_def ] in
  Pool_latency.record_success
    store.pool_latency
    ~pool_name:"pool-01"
    ~route_model:"fast"
    ~latency_ms:50.;
  Pool_latency.record_success
    store.pool_latency
    ~pool_name:"pool-01"
    ~route_model:"slow"
    ~latency_ms:500.;
  let ranking = Pool_selector.rank store pool_def in
  let ranked_routes =
    ranking.ranked
    |> List.map (fun (m : Pool_selector.ranked_member) -> m.member.route_model)
  in
  Alcotest.(check (list string))
    "fastest member ranks first"
    [ "fast"; "slow" ]
    ranked_routes;
  Lwt.return_unit
;;

(* --- Members never observed sort BEFORE well-known slow members ---------- *)

let unobserved_member_gets_a_chance_test _switch () =
  let routes = [ stub_route ~public_model:"known"; stub_route ~public_model:"fresh" ] in
  let pool_def =
    pool ~name:"pool-02" [ member ~route:"known" (); member ~route:"fresh" () ]
  in
  let store = make_store ~routes ~pools:[ pool_def ] in
  (* [known] is observed slow; [fresh] has no sample yet. *)
  Pool_latency.record_success
    store.pool_latency
    ~pool_name:"pool-02"
    ~route_model:"known"
    ~latency_ms:300.;
  let ranking = Pool_selector.rank store pool_def in
  let ranked_routes =
    ranking.ranked
    |> List.map (fun (m : Pool_selector.ranked_member) -> m.member.route_model)
  in
  Alcotest.(check (list string))
    "unobserved member is probed before a well-known slow one"
    [ "fresh"; "known" ]
    ranked_routes;
  Lwt.return_unit
;;

(* --- Empty pool returns a structured error explaining why every member
       was rejected. --------------------------------------------------------- *)

let empty_pool_returns_clear_error_test _switch () =
  let routes = [ stub_route ~public_model:"only-one" ] in
  let bad_member = member ~route:"missing-route" () in
  let pool_def = pool ~name:"pool-empty" [ bad_member ] in
  let store = make_store ~routes ~pools:[ pool_def ] in
  let ranking = Pool_selector.rank store pool_def in
  Alcotest.(check int)
    "no member is viable"
    0
    (List.length ranking.ranked);
  Alcotest.(check int)
    "the missing route is reported"
    1
    (List.length ranking.rejected);
  let err = Pool_selector.exhaustion_error ~pool_name:"pool-empty" ranking in
  let message = Bulkhead_lm.Domain_error.to_string err in
  let contains haystack needle =
    let needle_length = String.length needle in
    let haystack_length = String.length haystack in
    let rec loop index =
      if index + needle_length > haystack_length
      then false
      else if String.sub haystack index needle_length = needle
      then true
      else loop (index + 1)
    in
    loop 0
  in
  Alcotest.(check bool)
    "error mentions the pool name"
    true
    (contains message "pool-empty");
  Alcotest.(check bool)
    "error mentions the missing route"
    true
    (contains message "missing-route");
  Lwt.return_unit
;;

(* --- Circuit-broken member is filtered out ------------------------------- *)

let circuit_broken_member_excluded_test _switch () =
  let routes = [ stub_route ~public_model:"healthy"; stub_route ~public_model:"broken" ] in
  let pool_def =
    pool ~name:"pool-03" [ member ~route:"healthy" (); member ~route:"broken" () ]
  in
  let store = make_store ~routes ~pools:[ pool_def ] in
  (* Trip the circuit on [broken]'s only backend. *)
  let circuit = store.backend_circuit in
  for _ = 1 to 100 do
    Backend_circuit.record_failure circuit "broken-primary"
  done;
  let ranking = Pool_selector.rank store pool_def in
  let ranked_routes =
    ranking.ranked
    |> List.map (fun (m : Pool_selector.ranked_member) -> m.member.route_model)
  in
  Alcotest.(check (list string))
    "circuit-broken route is not ranked"
    [ "healthy" ]
    ranked_routes;
  Alcotest.(check bool)
    "rejected list mentions the broken member"
    true
    (List.exists
       (fun (rej : Pool_selector.rejected_member) ->
         String.equal rej.route_model "broken"
         && rej.reason = Pool_selector.All_circuits_open)
       ranking.rejected);
  Lwt.return_unit
;;

(* --- Global pool aggregates every configured route ----------------------- *)

let global_pool_includes_every_route_test _switch () =
  let routes =
    [ stub_route ~public_model:"a"
    ; stub_route ~public_model:"b"
    ; stub_route ~public_model:"c"
    ]
  in
  let pool_def = pool ~name:"global" ~is_global:true [] in
  let store = make_store ~routes ~pools:[ pool_def ] in
  let effective = Config.effective_pool_members store.config pool_def in
  let routes_in_pool =
    effective |> List.map (fun (m : Config.pool_member) -> m.route_model)
  in
  Alcotest.(check (list string))
    "global pool reflects every route in config order"
    [ "a"; "b"; "c" ]
    routes_in_pool;
  Lwt.return_unit
;;

(* --- Pool runtime mutations are reflected in selector ranking ------------ *)

let pool_runtime_create_add_remove_test _switch () =
  let routes = [ stub_route ~public_model:"r1"; stub_route ~public_model:"r2" ] in
  let store = make_store ~routes ~pools:[] in
  Alcotest.(check bool)
    "no pools to start"
    true
    (Pool_runtime.snapshot store = []);
  (match Pool_runtime.create_pool store ~name:"p1" with
   | Ok () -> ()
   | Error err -> Alcotest.failf "expected pool creation to succeed: %s" err);
  (match Pool_runtime.add_member store ~pool_name:"p1" ~route_model:"r1" ~daily_token_budget:1000 with
   | Ok () -> ()
   | Error err -> Alcotest.failf "expected add_member success: %s" err);
  (match
     Pool_runtime.add_member
       store
       ~pool_name:"p1"
       ~route_model:"unknown"
       ~daily_token_budget:1000
   with
   | Ok () -> Alcotest.fail "expected add_member to reject unknown route"
   | Error _ -> ());
  let pools = Pool_runtime.snapshot store in
  let p1 = Pool_runtime.find_pool pools "p1" in
  Alcotest.(check (option int))
    "p1 has one member"
    (Some 1)
    (Option.map (fun (p : Config.pool) -> List.length p.members) p1);
  (match Pool_runtime.remove_member store ~pool_name:"p1" ~route_model:"r1" with
   | Ok () -> ()
   | Error err -> Alcotest.failf "remove_member: %s" err);
  let p1 = Pool_runtime.find_pool (Pool_runtime.snapshot store) "p1" in
  Alcotest.(check (option int))
    "p1 has no members after removal"
    (Some 0)
    (Option.map (fun (p : Config.pool) -> List.length p.members) p1);
  Lwt.return_unit
;;

(* --- /v1/models exposes pools in data and pools[] ------------------------ *)

let models_json_exposes_pools_test _switch () =
  let routes = [ stub_route ~public_model:"r1" ] in
  let pool_def =
    pool ~name:"pool-x" [ member ~route:"r1" ~budget:1000 () ]
  in
  let config =
    Config_test_support.sample_config ~routes ~pools:[ pool_def ] ()
  in
  let json = Bulkhead_lm.Server.models_json config in
  let fields =
    match json with
    | `Assoc fields -> fields
    | _ -> Alcotest.fail "expected JSON object"
  in
  let data =
    match List.assoc_opt "data" fields with
    | Some (`List items) -> items
    | _ -> Alcotest.fail "expected data array"
  in
  let ids =
    data
    |> List.filter_map (fun item ->
      match item with
      | `Assoc fields ->
        (match List.assoc_opt "id" fields with
         | Some (`String value) -> Some value
         | _ -> None)
      | _ -> None)
  in
  Alcotest.(check bool)
    "pool name is present in /v1/models data"
    true
    (List.mem "pool-x" ids);
  let pools_section =
    match List.assoc_opt "pools" fields with
    | Some (`List items) -> items
    | _ -> Alcotest.fail "expected pools array"
  in
  Alcotest.(check int)
    "pools section has one entry"
    1
    (List.length pools_section);
  Lwt.return_unit
;;

let tests =
  [ Alcotest_lwt.test_case
      "pool selector ranks members by lowest latency"
      `Quick
      selector_ranks_by_latency_test
  ; Alcotest_lwt.test_case
      "pool selector probes never-observed members first"
      `Quick
      unobserved_member_gets_a_chance_test
  ; Alcotest_lwt.test_case
      "empty pool returns a structured error"
      `Quick
      empty_pool_returns_clear_error_test
  ; Alcotest_lwt.test_case
      "circuit-broken member is excluded from ranking"
      `Quick
      circuit_broken_member_excluded_test
  ; Alcotest_lwt.test_case
      "global pool aggregates every configured route"
      `Quick
      global_pool_includes_every_route_test
  ; Alcotest_lwt.test_case
      "runtime create/add/remove keeps the snapshot consistent"
      `Quick
      pool_runtime_create_add_remove_test
  ; Alcotest_lwt.test_case
      "/v1/models exposes pools in data and pools[]"
      `Quick
      models_json_exposes_pools_test
  ]
;;

let suite = "17.pools/selector-and-router", tests
