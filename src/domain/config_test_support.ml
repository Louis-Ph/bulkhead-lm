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

let backend ~provider_id ~provider_kind ~api_base ~upstream_model ~api_key_env () =
  { Config.provider_id; provider_kind; api_base; upstream_model; api_key_env }
;;

let route ~public_model ~backends () = { Config.public_model; backends }

let sample_config
  ?(virtual_keys = [ virtual_key ~token_plaintext:"sk-test" ~name:"test" () ])
  ?(routes = [ route ~public_model:"gpt-4o-mini" ~backends:[] () ])
  ()
  =
  { Config.security_policy = Security_policy.default ()
  ; error_catalog = `Assoc []
  ; providers_schema = `Assoc []
  ; routes
  ; virtual_keys
  }
;;
