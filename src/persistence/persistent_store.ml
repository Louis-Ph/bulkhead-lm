module String_map = Map.Make (String)

type stored_principal =
  { name : string
  ; token_hash : string
  ; daily_token_budget : int
  ; requests_per_minute : int
  ; allowed_routes : string list
  }

type stored_connector_session =
  { summary : string option
  ; recent_turns : Session_memory.turn list
  ; compressed_turn_count : int
  }

type audit_event =
  { event_type : string
  ; principal_name : string option
  ; route_model : string option
  ; provider_id : string option
  ; status_code : int
  ; details : Yojson.Safe.t
  }

type t =
  { db : Sqlite3.db
  ; lock : Mutex.t
  ; path : string
  }

let timestamp_now () =
  let tm = Unix.gmtime (Unix.time ()) in
  Fmt.str
    "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.tm_year + 1900)
    (tm.tm_mon + 1)
    tm.tm_mday
    tm.tm_hour
    tm.tm_min
    tm.tm_sec
;;

let rec ensure_dir path =
  if path = "" || path = "." || path = "/"
  then ()
  else if Sys.file_exists path
  then ()
  else (
    ensure_dir (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let ensure_parent_dir path = ensure_dir (Filename.dirname path)
let hash_token token = Digestif.SHA256.digest_string token |> Digestif.SHA256.to_hex
let rc_ok rc = rc = Sqlite3.Rc.OK || rc = Sqlite3.Rc.DONE || rc = Sqlite3.Rc.ROW

let expect_rc db context rc =
  if rc_ok rc
  then ()
  else
    failwith
      (Fmt.str
         "SQLite error during %s: %s (%s)"
         context
         (Sqlite3.Rc.to_string rc)
         (Sqlite3.errmsg db))
;;

let with_stmt db sql f =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () -> f stmt)
;;

let with_lock store f =
  Mutex.lock store.lock;
  match f () with
  | result ->
    Mutex.unlock store.lock;
    result
  | exception exn ->
    Mutex.unlock store.lock;
    raise exn
;;

let exec db context sql = expect_rc db context (Sqlite3.exec db sql)

let setup_schema db =
  exec db "pragma journal_mode" "PRAGMA journal_mode=WAL";
  exec db "pragma synchronous" "PRAGMA synchronous=NORMAL";
  exec db "pragma foreign_keys" "PRAGMA foreign_keys=ON";
  exec
    db
    "virtual_keys schema"
    {|CREATE TABLE IF NOT EXISTS virtual_keys (
         name TEXT PRIMARY KEY,
         token_hash TEXT NOT NULL UNIQUE,
         daily_token_budget INTEGER NOT NULL,
         requests_per_minute INTEGER NOT NULL,
         allowed_routes_json TEXT NOT NULL,
         created_at TEXT NOT NULL,
         updated_at TEXT NOT NULL
       )|};
  exec
    db
    "budget_usage schema"
    {|CREATE TABLE IF NOT EXISTS budget_usage (
         usage_day TEXT NOT NULL,
         principal_name TEXT NOT NULL,
         consumed_tokens INTEGER NOT NULL,
         updated_at TEXT NOT NULL,
         PRIMARY KEY (usage_day, principal_name)
       )|};
  exec
    db
    "audit_log schema"
    {|CREATE TABLE IF NOT EXISTS audit_log (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         created_at TEXT NOT NULL,
         event_type TEXT NOT NULL,
         principal_name TEXT,
         route_model TEXT,
         provider_id TEXT,
         status_code INTEGER NOT NULL,
         details_json TEXT NOT NULL
       )|}
;
  exec
    db
    "connector_sessions schema"
    {|CREATE TABLE IF NOT EXISTS connector_sessions (
         session_key TEXT PRIMARY KEY,
         summary TEXT,
         recent_turns_json TEXT NOT NULL,
         compressed_turn_count INTEGER NOT NULL,
         updated_at TEXT NOT NULL
       )|};
  (* Tracks the daily token consumption per pool member so a pool with many
     tightly-budgeted models can enforce its limits across restarts. The key
     mirrors [budget_usage] but is keyed by (pool_name, route_model) so the
     same route used in multiple pools tracks budgets independently. *)
  exec
    db
    "pool_member_usage schema"
    {|CREATE TABLE IF NOT EXISTS pool_member_usage (
         usage_day TEXT NOT NULL,
         pool_name TEXT NOT NULL,
         route_model TEXT NOT NULL,
         consumed_tokens INTEGER NOT NULL,
         updated_at TEXT NOT NULL,
         PRIMARY KEY (usage_day, pool_name, route_model)
       )|};
  (* Stores wizard-driven mutations to pool definitions as a single JSON blob
     so the runtime can survive a restart without forcing the user to edit
     gateway.json. Keyed by [scope] for forward extensibility. *)
  exec
    db
    "pool_overrides schema"
    {|CREATE TABLE IF NOT EXISTS pool_overrides (
         scope TEXT PRIMARY KEY,
         payload_json TEXT NOT NULL,
         updated_at TEXT NOT NULL
       )|}
;;

let sync_virtual_key db security_policy (virtual_key : Config.virtual_key) =
  let token_hash =
    match virtual_key.token_hash, virtual_key.token_plaintext with
    | Some hash, _ -> hash
    | None, Some plaintext ->
      if security_policy.Security_policy.auth.hash_algorithm <> "sha256"
      then failwith "Only sha256 hashing is supported for persisted virtual keys"
      else hash_token plaintext
    | None, None -> failwith "Virtual key requires token_plaintext or token_hash"
  in
  with_stmt
    db
    {|INSERT OR REPLACE INTO virtual_keys (
         name,
         token_hash,
         daily_token_budget,
         requests_per_minute,
         allowed_routes_json,
         created_at,
         updated_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?)|}
    (fun stmt ->
       let now = timestamp_now () in
       expect_rc db "bind key name" (Sqlite3.bind_text stmt 1 virtual_key.name);
       expect_rc db "bind token hash" (Sqlite3.bind_text stmt 2 token_hash);
       expect_rc db "bind budget" (Sqlite3.bind_int stmt 3 virtual_key.daily_token_budget);
       expect_rc db "bind rpm" (Sqlite3.bind_int stmt 4 virtual_key.requests_per_minute);
       expect_rc
         db
         "bind allowed routes"
         (Sqlite3.bind_text
            stmt
            5
            (Yojson.Safe.to_string
               (`List (List.map (fun route -> `String route) virtual_key.allowed_routes))));
       expect_rc db "bind created_at" (Sqlite3.bind_text stmt 6 now);
       expect_rc db "bind updated_at" (Sqlite3.bind_text stmt 7 now);
       expect_rc db "upsert virtual key" (Sqlite3.step stmt))
;;

let load_principals db =
  with_stmt
    db
    {|SELECT name, token_hash, daily_token_budget, requests_per_minute, allowed_routes_json
      FROM virtual_keys
      ORDER BY name|}
    (fun stmt ->
       let rec loop acc =
         match Sqlite3.step stmt with
         | Sqlite3.Rc.ROW ->
           let allowed_routes =
             try
               Yojson.Safe.from_string (Sqlite3.column_text stmt 4)
               |> function
               | `List values ->
                 values
                 |> List.filter_map (function
                   | `String route -> Some route
                   | _ -> None)
               | _ -> []
             with
             | _ -> []
           in
           let principal =
             { name = Sqlite3.column_text stmt 0
             ; token_hash = Sqlite3.column_text stmt 1
             ; daily_token_budget = Sqlite3.column_int stmt 2
             ; requests_per_minute = Sqlite3.column_int stmt 3
             ; allowed_routes
             }
           in
           loop (principal :: acc)
         | Sqlite3.Rc.DONE -> List.rev acc
         | rc ->
           failwith
             (Fmt.str "SQLite error during load_principals: %s" (Sqlite3.Rc.to_string rc))
       in
       loop [])
;;

let open_or_bootstrap (config : Config.t) =
  match config.persistence.sqlite_path with
  | None -> Ok None
  | Some path ->
    (try
       ensure_parent_dir path;
       let db = Sqlite3.db_open ~mutex:`FULL path in
       let store = { db; lock = Mutex.create (); path } in
       exec
         db
         "busy_timeout"
         (Fmt.str "PRAGMA busy_timeout=%d" config.persistence.busy_timeout_ms);
       setup_schema db;
       List.iter (sync_virtual_key db config.security_policy) config.virtual_keys;
       let principals = load_principals db in
       Ok (Some (store, principals))
     with
     | exn -> Error ("Persistent store initialization failed: " ^ Printexc.to_string exn))
;;

let consume_budget store ~principal_name ~daily_token_budget ~usage_day ~tokens =
  with_lock store (fun () ->
    try
      exec store.db "begin budget tx" "BEGIN IMMEDIATE";
      let consumed =
        with_stmt
          store.db
          {|SELECT consumed_tokens
            FROM budget_usage
            WHERE usage_day = ? AND principal_name = ?|}
          (fun stmt ->
             expect_rc store.db "bind usage_day" (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc
               store.db
               "bind principal_name"
               (Sqlite3.bind_text stmt 2 principal_name);
             match Sqlite3.step stmt with
             | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
             | Sqlite3.Rc.DONE -> 0
             | rc ->
               failwith
                 (Fmt.str
                    "SQLite error during load budget row: %s"
                    (Sqlite3.Rc.to_string rc)))
      in
      if consumed + tokens > daily_token_budget
      then (
        exec store.db "rollback budget tx" "ROLLBACK";
        Error (Domain_error.budget_exceeded ()))
      else (
        with_stmt
          store.db
          {|INSERT INTO budget_usage (
               usage_day,
               principal_name,
               consumed_tokens,
               updated_at
             ) VALUES (?, ?, ?, ?)
             ON CONFLICT(usage_day, principal_name) DO UPDATE SET
               consumed_tokens = excluded.consumed_tokens,
               updated_at = excluded.updated_at|}
          (fun stmt ->
             let updated = consumed + tokens in
             let now = timestamp_now () in
             expect_rc
               store.db
               "bind usage_day upsert"
               (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc
               store.db
               "bind principal_name upsert"
               (Sqlite3.bind_text stmt 2 principal_name);
             expect_rc store.db "bind consumed_tokens" (Sqlite3.bind_int stmt 3 updated);
             expect_rc store.db "bind updated_at usage" (Sqlite3.bind_text stmt 4 now);
             expect_rc store.db "upsert budget usage" (Sqlite3.step stmt));
        exec store.db "commit budget tx" "COMMIT";
        Ok ())
    with
    | exn ->
      ignore (Sqlite3.exec store.db "ROLLBACK");
      raise exn)
;;

(* Read the running consumption for one pool member without changing it; used
   by the pool selector to filter out members that are already exhausted
   today. Returns [0] when the row does not exist yet. *)
let pool_member_consumption store ~usage_day ~pool_name ~route_model =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|SELECT consumed_tokens
        FROM pool_member_usage
        WHERE usage_day = ? AND pool_name = ? AND route_model = ?|}
      (fun stmt ->
         expect_rc store.db "bind usage_day" (Sqlite3.bind_text stmt 1 usage_day);
         expect_rc store.db "bind pool_name" (Sqlite3.bind_text stmt 2 pool_name);
         expect_rc store.db "bind route_model" (Sqlite3.bind_text stmt 3 route_model);
         match Sqlite3.step stmt with
         | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
         | Sqlite3.Rc.DONE -> 0
         | rc ->
           failwith
             (Fmt.str
                "SQLite error during pool member lookup: %s"
                (Sqlite3.Rc.to_string rc))))
;;

(* Atomically charge tokens against a pool member's daily budget.
   Returns [Ok ()] when the charge succeeds and [Error budget_exceeded] when
   the increment would push past [daily_token_budget]. The transaction is
   IMMEDIATE so two concurrent requests cannot both see a stale "below the
   limit" snapshot. *)
let consume_pool_member_budget
  store
  ~pool_name
  ~route_model
  ~daily_token_budget
  ~usage_day
  ~tokens
  =
  with_lock store (fun () ->
    try
      exec store.db "begin pool budget tx" "BEGIN IMMEDIATE";
      let consumed =
        with_stmt
          store.db
          {|SELECT consumed_tokens
            FROM pool_member_usage
            WHERE usage_day = ? AND pool_name = ? AND route_model = ?|}
          (fun stmt ->
             expect_rc store.db "bind usage_day" (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc store.db "bind pool_name" (Sqlite3.bind_text stmt 2 pool_name);
             expect_rc store.db "bind route_model" (Sqlite3.bind_text stmt 3 route_model);
             match Sqlite3.step stmt with
             | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
             | Sqlite3.Rc.DONE -> 0
             | rc ->
               failwith
                 (Fmt.str
                    "SQLite error during pool budget read: %s"
                    (Sqlite3.Rc.to_string rc)))
      in
      if consumed + tokens > daily_token_budget
      then (
        exec store.db "rollback pool budget tx" "ROLLBACK";
        Error (Domain_error.budget_exceeded ()))
      else (
        with_stmt
          store.db
          {|INSERT INTO pool_member_usage (
               usage_day,
               pool_name,
               route_model,
               consumed_tokens,
               updated_at
             ) VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(usage_day, pool_name, route_model) DO UPDATE SET
               consumed_tokens = excluded.consumed_tokens,
               updated_at = excluded.updated_at|}
          (fun stmt ->
             let updated = consumed + tokens in
             let now = timestamp_now () in
             expect_rc store.db "bind usage_day upsert" (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc store.db "bind pool_name upsert" (Sqlite3.bind_text stmt 2 pool_name);
             expect_rc
               store.db
               "bind route_model upsert"
               (Sqlite3.bind_text stmt 3 route_model);
             expect_rc
               store.db
               "bind consumed_tokens"
               (Sqlite3.bind_int stmt 4 updated);
             expect_rc
               store.db
               "bind updated_at usage"
               (Sqlite3.bind_text stmt 5 now);
             expect_rc store.db "upsert pool budget" (Sqlite3.step stmt));
        exec store.db "commit pool budget tx" "COMMIT";
        Ok ())
    with
    | exn ->
      ignore (Sqlite3.exec store.db "ROLLBACK");
      raise exn)
;;

(* Pool override blob persistence. The wizard rewrites the entire blob on
   every mutation so reads are atomic and we don't have to model partial
   updates separately. *)
let load_pool_overrides store =
  with_lock store (fun () ->
    with_stmt
      store.db
      "SELECT payload_json FROM pool_overrides WHERE scope = 'pools'"
      (fun stmt ->
         match Sqlite3.step stmt with
         | Sqlite3.Rc.ROW ->
           let raw = Sqlite3.column_text stmt 0 in
           (match Yojson.Safe.from_string raw with
            | exception Yojson.Json_error _ -> None
            | json -> Some json)
         | _ -> None))
;;

let save_pool_overrides store payload_json =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|INSERT INTO pool_overrides (scope, payload_json, updated_at)
        VALUES ('pools', ?, ?)
        ON CONFLICT(scope) DO UPDATE SET
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at|}
      (fun stmt ->
         let now = timestamp_now () in
         expect_rc
           store.db
           "bind pool_overrides payload"
           (Sqlite3.bind_text stmt 1 (Yojson.Safe.to_string payload_json));
         expect_rc
           store.db
           "bind pool_overrides updated_at"
           (Sqlite3.bind_text stmt 2 now);
         expect_rc store.db "upsert pool overrides" (Sqlite3.step stmt)))
;;

let append_audit_event store (event : audit_event) =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|INSERT INTO audit_log (
           created_at,
           event_type,
           principal_name,
           route_model,
           provider_id,
           status_code,
           details_json
         ) VALUES (?, ?, ?, ?, ?, ?, ?)|}
      (fun stmt ->
         let bind_text_opt position = function
           | Some value ->
             expect_rc
               store.db
               "bind audit optional text"
               (Sqlite3.bind_text stmt position value)
           | None ->
             expect_rc
               store.db
               "bind audit null"
               (Sqlite3.bind stmt position Sqlite3.Data.NULL)
         in
         expect_rc
           store.db
           "bind audit created_at"
           (Sqlite3.bind_text stmt 1 (timestamp_now ()));
         expect_rc
           store.db
           "bind audit event_type"
           (Sqlite3.bind_text stmt 2 event.event_type);
         bind_text_opt 3 event.principal_name;
         bind_text_opt 4 event.route_model;
         bind_text_opt 5 event.provider_id;
         expect_rc
           store.db
           "bind audit status_code"
           (Sqlite3.bind_int stmt 6 event.status_code);
         expect_rc
           store.db
           "bind audit details"
           (Sqlite3.bind_text stmt 7 (Yojson.Safe.to_string event.details));
         expect_rc store.db "insert audit row" (Sqlite3.step stmt)))
;;

let audit_count store =
  with_lock store (fun () ->
    with_stmt store.db "SELECT COUNT(*) FROM audit_log" (fun stmt ->
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
      | rc ->
        failwith (Fmt.str "SQLite error during audit_count: %s" (Sqlite3.Rc.to_string rc))))
;;

let session_role_to_string = function
  | Session_memory.User -> "user"
  | Session_memory.Assistant -> "assistant"
;;

let session_role_of_string = function
  | "user" -> Some Session_memory.User
  | "assistant" -> Some Session_memory.Assistant
  | _ -> None
;;

let connector_turns_to_json turns =
  `List
    (List.map
       (fun (turn : Session_memory.turn) ->
         `Assoc
           [ "role", `String (session_role_to_string turn.role)
           ; "content", `String turn.content
           ])
       turns)
;;

let connector_turns_of_json = function
  | `List values ->
    values
    |> List.filter_map (function
      | `Assoc fields ->
        (match List.assoc_opt "role" fields, List.assoc_opt "content" fields with
         | Some (`String role), Some (`String content) ->
           Option.map
             (fun parsed_role -> ({ Session_memory.role = parsed_role; content } : Session_memory.turn))
             (session_role_of_string role)
         | _ -> None)
      | _ -> None)
  | _ -> []
;;

let load_connector_session store ~session_key =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|SELECT summary, recent_turns_json, compressed_turn_count
        FROM connector_sessions
        WHERE session_key = ?|}
      (fun stmt ->
         expect_rc
           store.db
           "bind connector session key"
           (Sqlite3.bind_text stmt 1 session_key);
         match Sqlite3.step stmt with
         | Sqlite3.Rc.ROW ->
           let summary =
             match Sqlite3.column stmt 0 with
             | Sqlite3.Data.TEXT value -> Some value
             | _ -> None
           in
           let recent_turns =
             try
               Sqlite3.column_text stmt 1
               |> Yojson.Safe.from_string
               |> connector_turns_of_json
             with _ -> []
           in
           Some
             { summary
             ; recent_turns
             ; compressed_turn_count = Sqlite3.column_int stmt 2
             }
         | Sqlite3.Rc.DONE -> None
         | rc ->
           failwith
             (Fmt.str
                "SQLite error during load_connector_session: %s"
                (Sqlite3.Rc.to_string rc))))
;;

let upsert_connector_session
    store
    ~session_key
    (session : Session_memory.t)
  =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|INSERT INTO connector_sessions (
           session_key,
           summary,
           recent_turns_json,
           compressed_turn_count,
           updated_at
         ) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(session_key) DO UPDATE SET
           summary = excluded.summary,
           recent_turns_json = excluded.recent_turns_json,
           compressed_turn_count = excluded.compressed_turn_count,
           updated_at = excluded.updated_at|}
      (fun stmt ->
         expect_rc
           store.db
           "bind connector session key upsert"
           (Sqlite3.bind_text stmt 1 session_key);
         (match session.summary with
          | Some summary ->
            expect_rc
              store.db
              "bind connector session summary"
              (Sqlite3.bind_text stmt 2 summary)
          | None ->
            expect_rc
              store.db
              "bind connector session summary null"
              (Sqlite3.bind stmt 2 Sqlite3.Data.NULL));
         expect_rc
           store.db
           "bind connector session turns"
           (Sqlite3.bind_text
              stmt
              3
              (Yojson.Safe.to_string
                 (connector_turns_to_json session.recent_turns)));
         expect_rc
           store.db
           "bind connector session compressed count"
           (Sqlite3.bind_int stmt 4 session.compressed_turn_count);
         expect_rc
           store.db
           "bind connector session updated_at"
           (Sqlite3.bind_text stmt 5 (timestamp_now ()));
         expect_rc store.db "upsert connector session" (Sqlite3.step stmt)))
;;

let delete_connector_session store ~session_key =
  with_lock store (fun () ->
    with_stmt
      store.db
      "DELETE FROM connector_sessions WHERE session_key = ?"
      (fun stmt ->
         expect_rc
           store.db
           "bind connector session key delete"
           (Sqlite3.bind_text stmt 1 session_key);
         expect_rc store.db "delete connector session" (Sqlite3.step stmt)))
;;
