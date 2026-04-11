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

let telegram_connector
  ?(webhook_path = "/connectors/telegram/webhook")
  ?secret_token_env
  ?system_prompt
  ?(allowed_chat_ids = [])
  ~bot_token_env
  ~authorization_env
  ~route_model
  ()
  =
  { Config.webhook_path
  ; bot_token_env
  ; secret_token_env
  ; authorization_env
  ; route_model
  ; system_prompt
  ; allowed_chat_ids
  }
;;

let whatsapp_connector
  ?(webhook_path = "/connectors/whatsapp/webhook")
  ?app_secret_env
  ?system_prompt
  ?(allowed_sender_numbers = [])
  ?(api_base = "https://graph.facebook.com/v23.0")
  ~verify_token_env
  ~access_token_env
  ~authorization_env
  ~route_model
  ()
  =
  { Config.webhook_path
  ; verify_token_env
  ; app_secret_env
  ; access_token_env
  ; authorization_env
  ; route_model
  ; system_prompt
  ; allowed_sender_numbers
  ; api_base
  }
;;

let google_chat_id_token_auth
  ?(certs_url = "https://www.googleapis.com/oauth2/v1/certs")
  ~audience
  ()
  =
  { Config.audience; certs_url }
;;

let google_chat_connector
  ?(webhook_path = "/connectors/google-chat/webhook")
  ?system_prompt
  ?(allowed_space_names = [])
  ?(allowed_user_names = [])
  ?id_token_auth
  ~authorization_env
  ~route_model
  ()
  =
  { Config.webhook_path
  ; authorization_env
  ; route_model
  ; system_prompt
  ; allowed_space_names
  ; allowed_user_names
  ; id_token_auth
  }
;;

let sample_config
  ?security_policy
  ?(user_connectors = { Config.telegram = None; whatsapp = None; google_chat = None })
  ?(virtual_keys = [ virtual_key ~token_plaintext:"sk-test" ~name:"test" () ])
  ?(routes = [ route ~public_model:"gpt-4o-mini" ~backends:[] () ])
  ()
  =
  { Config.security_policy = Option.value security_policy ~default:(Security_policy.default ())
  ; persistence = { sqlite_path = None; busy_timeout_ms = 5000 }
  ; error_catalog = `Assoc []
  ; providers_schema = `Assoc []
  ; user_connectors
  ; routes
  ; virtual_keys
  }
;;
