type lifecycle =
  | Stable
  | Preview
  | Limited_preview
  | General_availability

type provider_model =
  { key : string
  ; public_model : string
  ; upstream_model : string
  ; family_label : string
  ; version_label : string option
  ; mode_label : string option
  ; lifecycle : lifecycle
  ; capabilities : string list
  ; docs_url : string option
  }

type provider_family =
  { key : string
  ; label : string
  ; provider_id_prefix : string
  ; provider_kind : Config.provider_kind
  ; api_base : string
  ; api_key_env : string
  ; docs_url : string option
  ; models : provider_model list
  }

let last_verified = "2026-04-14"

let lifecycle_to_string = function
  | Stable -> "stable"
  | Preview -> "preview"
  | Limited_preview -> "limited_preview"
  | General_availability -> "ga"
;;

let model_label (model : provider_model) =
  let parts =
    [ Some model.family_label; model.version_label; model.mode_label ]
    |> List.filter_map Fun.id
  in
  String.concat " " parts
;;

let model_hierarchy_parts (model : provider_model) =
  [ Some model.family_label; model.version_label; model.mode_label ]
  |> List.filter_map Fun.id
;;

let provider_families =
  [ { key = "anthropic"
    ; label = "Anthropic"
    ; provider_id_prefix = "anthropic"
    ; provider_kind = Config.Anthropic
    ; api_base = "https://api.anthropic.com/v1"
    ; api_key_env = "ANTHROPIC_API_KEY"
    ; docs_url = Some "https://docs.anthropic.com/"
    ; models =
        [ { key = "claude-opus"
          ; public_model = "claude-opus"
          ; upstream_model = "claude-opus-4-1"
          ; family_label = "Claude Opus"
          ; version_label = Some "4.1"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://docs.anthropic.com/"
          }
        ; { key = "claude-sonnet"
          ; public_model = "claude-sonnet"
          ; upstream_model = "claude-sonnet-4-5"
          ; family_label = "Claude Sonnet"
          ; version_label = Some "4.5"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://docs.anthropic.com/"
          }
        ; { key = "claude-haiku"
          ; public_model = "claude-haiku"
          ; upstream_model = "claude-haiku-4-5"
          ; family_label = "Claude Haiku"
          ; version_label = Some "4.5"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://docs.anthropic.com/"
          }
        ]
    }
  ; { key = "openrouter"
    ; label = "OpenRouter"
    ; provider_id_prefix = "openrouter"
    ; provider_kind = Config.Openrouter_openai
    ; api_base = "https://openrouter.ai/api/v1"
    ; api_key_env = "OPEN_ROUTER_KEY"
    ; docs_url = Some "https://openrouter.ai/docs/quickstart"
    ; models =
        [ { key = "openrouter-auto"
          ; public_model = "openrouter-auto"
          ; upstream_model = "openrouter/auto"
          ; family_label = "OpenRouter"
          ; version_label = None
          ; mode_label = Some "auto router"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "routing" ]
          ; docs_url = Some "https://openrouter.ai/docs/quickstart"
          }
        ; { key = "openrouter-free"
          ; public_model = "openrouter-free"
          ; upstream_model = "openrouter/free"
          ; family_label = "OpenRouter"
          ; version_label = None
          ; mode_label = Some "free router"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "routing" ]
          ; docs_url =
              Some
                "https://openrouter.ai/docs/guides/routing/routers/free-models-router"
          }
        ; { key = "openrouter-gpt-5.2"
          ; public_model = "openrouter-gpt-5.2"
          ; upstream_model = "openai/gpt-5.2"
          ; family_label = "GPT"
          ; version_label = Some "5.2"
          ; mode_label = Some "via OpenRouter"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://openrouter.ai/docs/quickstart"
          }
        ]
    }
  ; { key = "openai"
    ; label = "OpenAI"
    ; provider_id_prefix = "openai"
    ; provider_kind = Config.Openai_compat
    ; api_base = "https://api.openai.com/v1"
    ; api_key_env = "OPENAI_API_KEY"
    ; docs_url = Some "https://platform.openai.com/docs/models"
    ; models =
        [ { key = "gpt-5"
          ; public_model = "gpt-5"
          ; upstream_model = "gpt-5"
          ; family_label = "GPT"
          ; version_label = Some "5"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.openai.com/docs/models"
          }
        ; { key = "gpt-5-mini"
          ; public_model = "gpt-5-mini"
          ; upstream_model = "gpt-5-mini"
          ; family_label = "GPT"
          ; version_label = Some "5 mini"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.openai.com/docs/models"
          }
        ; { key = "gpt-5-nano"
          ; public_model = "gpt-5-nano"
          ; upstream_model = "gpt-5-nano"
          ; family_label = "GPT"
          ; version_label = Some "5 nano"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.openai.com/docs/models"
          }
        ]
    }
  ; { key = "google"
    ; label = "Google AI Studio"
    ; provider_id_prefix = "google"
    ; provider_kind = Config.Google_openai
    ; api_base = "https://generativelanguage.googleapis.com/v1beta/openai/"
    ; api_key_env = "GOOGLE_API_KEY"
    ; docs_url = Some "https://ai.google.dev/gemini-api/docs/openai"
    ; models =
        [ { key = "gemini-2.5-pro"
          ; public_model = "gemini-2.5-pro"
          ; upstream_model = "gemini-2.5-pro"
          ; family_label = "Gemini"
          ; version_label = Some "2.5 Pro"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://ai.google.dev/gemini-api/docs/openai"
          }
        ; { key = "gemini-2.5-flash"
          ; public_model = "gemini-2.5-flash"
          ; upstream_model = "gemini-2.5-flash"
          ; family_label = "Gemini"
          ; version_label = Some "2.5 Flash"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://ai.google.dev/gemini-api/docs/openai"
          }
        ; { key = "gemini-2.5-flash-lite"
          ; public_model = "gemini-2.5-flash-lite"
          ; upstream_model = "gemini-2.5-flash-lite"
          ; family_label = "Gemini"
          ; version_label = Some "2.5 Flash-Lite"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://ai.google.dev/gemini-api/docs/openai"
          }
        ]
    }
  ; { key = "vertex"
    ; label = "Google Vertex AI"
    ; provider_id_prefix = "vertex"
    ; provider_kind = Config.Vertex_openai
    ; api_base =
        "https://aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/global/endpoints/openapi"
    ; api_key_env = "VERTEX_AI_ACCESS_TOKEN"
    ; docs_url =
        Some
          "https://docs.cloud.google.com/vertex-ai/generative-ai/docs/migrate/openai/overview"
    ; models =
        [ { key = "vertex-gemini-2.5-pro"
          ; public_model = "vertex-gemini-2.5-pro"
          ; upstream_model = "google/gemini-2.5-pro"
          ; family_label = "Gemini"
          ; version_label = Some "2.5 Pro"
          ; mode_label = Some "via Vertex"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url =
              Some
                "https://docs.cloud.google.com/vertex-ai/generative-ai/docs/migrate/openai/overview"
          }
        ; { key = "vertex-gemini-2.5-flash"
          ; public_model = "vertex-gemini-2.5-flash"
          ; upstream_model = "google/gemini-2.5-flash"
          ; family_label = "Gemini"
          ; version_label = Some "2.5 Flash"
          ; mode_label = Some "via Vertex"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url =
              Some
                "https://docs.cloud.google.com/vertex-ai/generative-ai/docs/migrate/openai/overview"
          }
        ; { key = "gpt-oss-120b"
          ; public_model = "gpt-oss-120b"
          ; upstream_model = "gpt-oss-120b-maas"
          ; family_label = "gpt-oss"
          ; version_label = Some "120B"
          ; mode_label = Some "MaaS"
          ; lifecycle = General_availability
          ; capabilities = [ "chat"; "reasoning"; "function_calling"; "structured_output" ]
          ; docs_url =
              Some "https://docs.cloud.google.com/vertex-ai/generative-ai/docs/maas/openai/gpt-oss-120b"
          }
        ]
    }
  ; { key = "xai"
    ; label = "xAI"
    ; provider_id_prefix = "xai"
    ; provider_kind = Config.Xai_openai
    ; api_base = "https://api.x.ai/v1"
    ; api_key_env = "XAI_API_KEY"
    ; docs_url = Some "https://docs.x.ai/"
    ; models =
        [ { key = "grok-4"
          ; public_model = "grok-4"
          ; upstream_model = "grok-4"
          ; family_label = "Grok"
          ; version_label = Some "4"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://docs.x.ai/"
          }
        ; { key = "grok-4-20-reasoning"
          ; public_model = "grok-4.20-reasoning"
          ; upstream_model = "grok-4.20-reasoning"
          ; family_label = "Grok"
          ; version_label = Some "4.20"
          ; mode_label = Some "reasoning"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "reasoning" ]
          ; docs_url = Some "https://docs.x.ai/developers/regions"
          }
        ; { key = "grok-4-1-fast-reasoning"
          ; public_model = "grok-4-1-fast-reasoning"
          ; upstream_model = "grok-4-1-fast-reasoning"
          ; family_label = "Grok"
          ; version_label = Some "4.1"
          ; mode_label = Some "fast reasoning"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "reasoning" ]
          ; docs_url = Some "https://docs.x.ai/developers/regions"
          }
        ]
    }
  ; { key = "meta"
    ; label = "Meta Llama API Preview"
    ; provider_id_prefix = "meta"
    ; provider_kind = Config.Meta_openai
    ; api_base = "https://api.llama.com/compat/v1"
    ; api_key_env = "META_API_KEY"
    ; docs_url =
        Some "https://about.fb.com/br/news/2025/04/tudo-o-que-anunciamos-no-nosso-primeiro-llamacon/"
    ; models =
        [ { key = "llama-4-scout"
          ; public_model = "meta-llama-4-scout"
          ; upstream_model = "llama-4-scout"
          ; family_label = "Llama"
          ; version_label = Some "4"
          ; mode_label = Some "Scout"
          ; lifecycle = Limited_preview
          ; capabilities = [ "chat" ]
          ; docs_url =
              Some
                "https://about.fb.com/br/news/2025/04/tudo-o-que-anunciamos-no-nosso-primeiro-llamacon/"
          }
        ; { key = "llama-4-maverick"
          ; public_model = "meta-llama-4-maverick"
          ; upstream_model = "llama-4-maverick"
          ; family_label = "Llama"
          ; version_label = Some "4"
          ; mode_label = Some "Maverick"
          ; lifecycle = Limited_preview
          ; capabilities = [ "chat" ]
          ; docs_url =
              Some
                "https://about.fb.com/br/news/2025/04/tudo-o-que-anunciamos-no-nosso-primeiro-llamacon/"
          }
        ; { key = "llama-3-3-8b"
          ; public_model = "meta-llama-3.3-8b"
          ; upstream_model = "llama-3.3-8b"
          ; family_label = "Llama"
          ; version_label = Some "3.3 8B"
          ; mode_label = Some "customizable"
          ; lifecycle = Limited_preview
          ; capabilities = [ "chat"; "fine_tuning" ]
          ; docs_url =
              Some
                "https://about.fb.com/br/news/2025/04/tudo-o-que-anunciamos-no-nosso-primeiro-llamacon/"
          }
        ]
    }
  ; { key = "mistral"
    ; label = "Mistral"
    ; provider_id_prefix = "mistral"
    ; provider_kind = Config.Mistral_openai
    ; api_base = "https://api.mistral.ai/v1"
    ; api_key_env = "MISTRAL_API_KEY"
    ; docs_url = Some "https://docs.mistral.ai/"
    ; models =
        [ { key = "mistral-medium"
          ; public_model = "mistral-medium"
          ; upstream_model = "mistral-medium-latest"
          ; family_label = "Mistral Medium"
          ; version_label = Some "latest"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings" ]
          ; docs_url = Some "https://docs.mistral.ai/"
          }
        ; { key = "mistral-small"
          ; public_model = "mistral-small"
          ; upstream_model = "mistral-small-latest"
          ; family_label = "Mistral Small"
          ; version_label = Some "latest"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings" ]
          ; docs_url = Some "https://docs.mistral.ai/"
          }
        ; { key = "codestral"
          ; public_model = "codestral"
          ; upstream_model = "codestral-latest"
          ; family_label = "Codestral"
          ; version_label = Some "latest"
          ; mode_label = Some "coding"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings"; "coding" ]
          ; docs_url = Some "https://docs.mistral.ai/"
          }
        ]
    }
  ; { key = "alibaba"
    ; label = "Alibaba Qwen"
    ; provider_id_prefix = "alibaba"
    ; provider_kind = Config.Alibaba_openai
    ; api_base = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ; api_key_env = "DASHSCOPE_API_KEY"
    ; docs_url = Some "https://www.alibabacloud.com/help/en/model-studio/openai-compatibility"
    ; models =
        [ { key = "qwen-max"
          ; public_model = "qwen-max"
          ; upstream_model = "qwen-max"
          ; family_label = "Qwen"
          ; version_label = Some "Max"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings" ]
          ; docs_url =
              Some
                "https://www.alibabacloud.com/help/en/model-studio/openai-compatibility"
          }
        ; { key = "qwen-plus"
          ; public_model = "qwen-plus"
          ; upstream_model = "qwen-plus"
          ; family_label = "Qwen"
          ; version_label = Some "Plus"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings" ]
          ; docs_url =
              Some
                "https://www.alibabacloud.com/help/en/model-studio/openai-compatibility"
          }
        ; { key = "qwen-turbo"
          ; public_model = "qwen-turbo"
          ; upstream_model = "qwen-turbo"
          ; family_label = "Qwen"
          ; version_label = Some "Turbo"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat"; "embeddings" ]
          ; docs_url =
              Some
                "https://www.alibabacloud.com/help/en/model-studio/openai-compatibility"
          }
        ]
    }
  ; { key = "moonshot"
    ; label = "Moonshot Kimi"
    ; provider_id_prefix = "moonshot"
    ; provider_kind = Config.Moonshot_openai
    ; api_base = "https://api.moonshot.ai/v1"
    ; api_key_env = "MOONSHOT_API_KEY"
    ; docs_url = Some "https://platform.moonshot.ai/docs"
    ; models =
        [ { key = "kimi-latest"
          ; public_model = "kimi-latest"
          ; upstream_model = "kimi-latest"
          ; family_label = "Kimi"
          ; version_label = Some "latest"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.moonshot.ai/docs"
          }
        ; { key = "kimi-k2"
          ; public_model = "kimi-k2"
          ; upstream_model = "kimi-k2"
          ; family_label = "Kimi"
          ; version_label = Some "K2"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.moonshot.ai/docs"
          }
        ; { key = "kimi-k2.5"
          ; public_model = "kimi-k2.5"
          ; upstream_model = "kimi-k2.5"
          ; family_label = "Kimi"
          ; version_label = Some "K2.5"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.moonshot.ai/docs"
          }
        ; { key = "kimi-k2.6"
          ; public_model = "kimi-k2.6"
          ; upstream_model = "kimi-k2.6"
          ; family_label = "Kimi"
          ; version_label = Some "K2.6"
          ; mode_label = Some "standard"
          ; lifecycle = Stable
          ; capabilities = [ "chat" ]
          ; docs_url = Some "https://platform.moonshot.ai/docs"
          }
        ]
    }
  ]
;;

let all_models =
  provider_families
  |> List.concat_map (fun (family : provider_family) ->
    List.map (fun model -> family, model) family.models)
;;

let find_by_public_model public_model =
  all_models
  |> List.find_opt (fun (_family, model) -> String.equal model.public_model public_model)
;;

let find_by_upstream_model upstream_model =
  all_models
  |> List.find_opt (fun (_family, model) -> String.equal model.upstream_model upstream_model)
;;
