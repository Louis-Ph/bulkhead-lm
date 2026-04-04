let make backend =
  match backend.Config.provider_kind with
  | Config.Anthropic -> Anthropic_provider.make ()
  | Config.Openai_compat
  | Config.Google_openai
  | Config.Ollama_openai
  | Config.Alibaba_openai
  | Config.Moonshot_openai
  | Config.Aegis_peer -> Openai_compat_provider.make ()
  | Config.Aegis_ssh_peer -> Ssh_peer_provider.make ()
;;
