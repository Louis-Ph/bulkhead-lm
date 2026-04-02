let make backend =
  match backend.Config.provider_kind with
  | Config.Openai_compat -> Openai_compat_provider.make ()
  | Config.Anthropic -> Anthropic_provider.make ()
;;
