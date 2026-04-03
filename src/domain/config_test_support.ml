let virtual_key
  ?token_hash
  ~token_plaintext
  ~name
  ?(daily_token_budget = 1000)
  ?(requests_per_minute = 60)
  ?(allowed_routes = [])
  ()
  =
  { Config.name
  ; token_plaintext = Some token_plaintext
  ; token_hash
  ; daily_token_budget
  ; requests_per_minute
  ; allowed_routes
  }
;;

let ssh_transport
  ?(host = "peer.example.test")
  ?remote_config_path
  ?remote_switch
  ?(remote_jobs = 1)
  ?(options = [])
  ~destination
  ~remote_worker_command
  ()
  =
  { Config.destination
  ; host
  ; remote_worker_command
  ; remote_config_path
  ; remote_switch
  ; remote_jobs
  ; options
  }
;;

let backend
  ?ssh_transport
  ~provider_id
  ~provider_kind
  ~api_base
  ~upstream_model
  ~api_key_env
  ()
  =
  let target =
    match ssh_transport with
    | Some transport -> Config.Ssh_target transport
    | None -> Config.Http_target api_base
  in
  { Config.provider_id; provider_kind; target; upstream_model; api_key_env }
;;

let route ~public_model ~backends () = { Config.public_model; backends }

let sample_config
  ?(virtual_keys = [ virtual_key ~token_plaintext:"sk-test" ~name:"test" () ])
  ?(routes = [ route ~public_model:"gpt-4o-mini" ~backends:[] () ])
  ()
  =
  { Config.security_policy = Security_policy.default ()
  ; persistence = { sqlite_path = None; busy_timeout_ms = 5000 }
  ; error_catalog = `Assoc []
  ; providers_schema = `Assoc []
  ; routes
  ; virtual_keys
  }
;;
