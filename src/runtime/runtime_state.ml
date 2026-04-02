type principal =
  { name : string
  ; token_hash : string
  ; daily_token_budget : int
  ; requests_per_minute : int
  ; allowed_routes : string list
  }

type provider_factory = Config.backend -> Provider_client.t

type t =
  { config : Config.t
  ; principals : (string, principal) Hashtbl.t
  ; budget_usage : (string, int) Hashtbl.t
  ; request_windows : (string, int) Hashtbl.t
  ; provider_factory : provider_factory
  }

let hash_token token = Digestif.SHA256.digest_string token |> Digestif.SHA256.to_hex

let principal_of_virtual_key virtual_key security_policy =
  let token_hash =
    match virtual_key.Config.token_hash, virtual_key.token_plaintext with
    | Some hash, _ -> hash
    | None, Some plaintext ->
      if security_policy.Security_policy.auth.hash_algorithm <> "sha256"
      then invalid_arg "Only sha256 hashing is supported"
      else hash_token plaintext
    | None, None -> invalid_arg "Virtual key requires token_plaintext or token_hash"
  in
  { name = virtual_key.name
  ; token_hash
  ; daily_token_budget = virtual_key.daily_token_budget
  ; requests_per_minute = virtual_key.requests_per_minute
  ; allowed_routes = virtual_key.allowed_routes
  }
;;

let create ?provider_factory config =
  let principals = Hashtbl.create 16 in
  List.iter
    (fun virtual_key ->
      let principal =
        principal_of_virtual_key virtual_key config.Config.security_policy
      in
      Hashtbl.replace principals principal.token_hash principal)
    config.Config.virtual_keys;
  let default_provider_factory backend = Provider_registry.make backend in
  { config
  ; principals
  ; budget_usage = Hashtbl.create 32
  ; request_windows = Hashtbl.create 32
  ; provider_factory = Option.value provider_factory ~default:default_provider_factory
  }
;;
