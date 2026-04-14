let make backend =
  match backend.Config.provider_kind with
  | Config.Anthropic -> Anthropic_provider.make ()
  | Config.Openai_compat
  | Config.Openrouter_openai
  | Config.Google_openai
  | Config.Vertex_openai
  | Config.Mistral_openai
  | Config.Ollama_openai
  | Config.Alibaba_openai
  | Config.Moonshot_openai
  | Config.Xai_openai
  | Config.Meta_openai
  | Config.Deepseek_openai
  | Config.Groq_openai
  | Config.Perplexity_openai
  | Config.Together_openai
  | Config.Cerebras_openai
  | Config.Cohere_openai
  | Config.Bulkhead_peer -> Openai_compat_provider.make ()
  | Config.Bulkhead_ssh_peer -> Ssh_peer_provider.make ()
;;
