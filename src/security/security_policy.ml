type server =
  { listen_host : string
  ; listen_port : int
  ; max_request_body_bytes : int
  ; request_timeout_ms : int
  }

type auth =
  { header : string
  ; bearer_prefix : string
  ; hash_algorithm : string
  ; require_virtual_key : bool
  }

type redaction =
  { json_keys : string list
  ; replacement : string
  }

type egress =
  { deny_private_ranges : bool
  ; allowed_schemes : string list
  ; blocked_hosts : string list
  }

type mesh =
  { enabled : bool
  ; max_hops : int
  ; request_id_header : string
  ; hop_count_header : string
  }

type routing =
  { max_fallbacks : int
  ; strategy : string
  }

type rate_limit = { default_requests_per_minute : int }
type budget = { default_daily_tokens : int }

type t =
  { server : server
  ; auth : auth
  ; redaction : redaction
  ; egress : egress
  ; mesh : mesh
  ; routing : routing
  ; rate_limit : rate_limit
  ; budget : budget
  }

let default () =
  { server =
      { listen_host = "127.0.0.1"
      ; listen_port = 4100
      ; max_request_body_bytes = 1_048_576
      ; request_timeout_ms = 30_000
      }
  ; auth =
      { header = "authorization"
      ; bearer_prefix = "Bearer "
      ; hash_algorithm = "sha256"
      ; require_virtual_key = true
      }
  ; redaction =
      { json_keys =
          [ "api_key"
          ; "authorization"
          ; "x-api-key"
          ; "proxy-authorization"
          ; "client_secret"
          ; "password"
          ]
      ; replacement = "[REDACTED]"
      }
  ; egress =
      { deny_private_ranges = true
      ; allowed_schemes = [ "https"; "http" ]
      ; blocked_hosts = [ "localhost"; "127.0.0.1"; "::1" ]
      }
  ; mesh =
      { enabled = true
      ; max_hops = 1
      ; request_id_header = "x-aegislm-request-id"
      ; hop_count_header = "x-aegislm-hop-count"
      }
  ; routing = { max_fallbacks = 2; strategy = "priority" }
  ; rate_limit = { default_requests_per_minute = 60 }
  ; budget = { default_daily_tokens = 200_000 }
  }
;;

let string_member name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`String value) -> value
     | _ -> default)
  | _ -> default
;;

let int_member name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`Int value) -> value
     | Some (`Intlit value) -> int_of_string value
     | _ -> default)
  | _ -> default
;;

let bool_member name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`Bool value) -> value
     | _ -> default)
  | _ -> default
;;

let list_member name json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`List values) ->
       values
       |> List.filter_map (function
         | `String value -> Some value
         | _ -> None)
     | _ -> [])
  | _ -> []
;;

let object_member name json =
  match json with
  | `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null
  | _ -> `Null
;;

let of_yojson json =
  let defaults = default () in
  let server_json = object_member "server" json in
  let auth_json = object_member "auth" json in
  let redaction_json = object_member "redaction" json in
  let egress_json = object_member "egress" json in
  let mesh_json = object_member "mesh" json in
  let routing_json = object_member "routing" json in
  let rate_limit_json = object_member "rate_limit" json in
  let budget_json = object_member "budget" json in
  { server =
      { listen_host =
          string_member "listen_host" server_json ~default:defaults.server.listen_host
      ; listen_port =
          int_member "listen_port" server_json ~default:defaults.server.listen_port
      ; max_request_body_bytes =
          int_member
            "max_request_body_bytes"
            server_json
            ~default:defaults.server.max_request_body_bytes
      ; request_timeout_ms =
          int_member
            "request_timeout_ms"
            server_json
            ~default:defaults.server.request_timeout_ms
      }
  ; auth =
      { header = string_member "header" auth_json ~default:defaults.auth.header
      ; bearer_prefix =
          string_member "bearer_prefix" auth_json ~default:defaults.auth.bearer_prefix
      ; hash_algorithm =
          string_member "hash_algorithm" auth_json ~default:defaults.auth.hash_algorithm
      ; require_virtual_key =
          bool_member
            "require_virtual_key"
            auth_json
            ~default:defaults.auth.require_virtual_key
      }
  ; redaction =
      { json_keys =
          (match list_member "json_keys" redaction_json with
           | [] -> defaults.redaction.json_keys
           | keys -> keys)
      ; replacement =
          string_member
            "replacement"
            redaction_json
            ~default:defaults.redaction.replacement
      }
  ; egress =
      { deny_private_ranges =
          bool_member
            "deny_private_ranges"
            egress_json
            ~default:defaults.egress.deny_private_ranges
      ; allowed_schemes =
          (match list_member "allowed_schemes" egress_json with
           | [] -> defaults.egress.allowed_schemes
           | values -> values)
      ; blocked_hosts =
          (match list_member "blocked_hosts" egress_json with
           | [] -> defaults.egress.blocked_hosts
           | values -> values)
      }
  ; mesh =
      { enabled = bool_member "enabled" mesh_json ~default:defaults.mesh.enabled
      ; max_hops = int_member "max_hops" mesh_json ~default:defaults.mesh.max_hops
      ; request_id_header =
          string_member
            "request_id_header"
            mesh_json
            ~default:defaults.mesh.request_id_header
      ; hop_count_header =
          string_member
            "hop_count_header"
            mesh_json
            ~default:defaults.mesh.hop_count_header
      }
  ; routing =
      { max_fallbacks =
          int_member "max_fallbacks" routing_json ~default:defaults.routing.max_fallbacks
      ; strategy =
          string_member "strategy" routing_json ~default:defaults.routing.strategy
      }
  ; rate_limit =
      { default_requests_per_minute =
          int_member
            "default_requests_per_minute"
            rate_limit_json
            ~default:defaults.rate_limit.default_requests_per_minute
      }
  ; budget =
      { default_daily_tokens =
          int_member
            "default_daily_tokens"
            budget_json
            ~default:defaults.budget.default_daily_tokens
      }
  }
;;

let load_file path = Yojson.Safe.from_file path |> of_yojson
