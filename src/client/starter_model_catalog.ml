type provider_model =
  { key : string
  ; label : string
  ; public_model : string
  ; upstream_model : string
  }

type provider_family =
  { key : string
  ; label : string
  ; provider_id_prefix : string
  ; provider_kind : Config.provider_kind
  ; api_base : string
  ; api_key_env : string
  ; models : provider_model list
  }

let last_verified = "2026-04-09"

let provider_families =
  [ { key = "anthropic"
    ; label = "Anthropic"
    ; provider_id_prefix = "anthropic"
    ; provider_kind = Config.Anthropic
    ; api_base = "https://api.anthropic.com/v1"
    ; api_key_env = "ANTHROPIC_API_KEY"
    ; models =
        [ { key = "claude-opus"
          ; label = "Claude Opus"
          ; public_model = "claude-opus"
          ; upstream_model = "claude-opus-4-1"
          }
        ; { key = "claude-sonnet"
          ; label = "Claude Sonnet"
          ; public_model = "claude-sonnet"
          ; upstream_model = "claude-sonnet-4-5"
          }
        ; { key = "claude-haiku"
          ; label = "Claude Haiku"
          ; public_model = "claude-haiku"
          ; upstream_model = "claude-haiku-4-5"
          }
        ]
    }
  ; { key = "openrouter"
    ; label = "OpenRouter"
    ; provider_id_prefix = "openrouter"
    ; provider_kind = Config.Openrouter_openai
    ; api_base = "https://openrouter.ai/api/v1"
    ; api_key_env = "OPEN_ROUTER_KEY"
    ; models =
        [ { key = "openrouter-auto"
          ; label = "Auto Router"
          ; public_model = "openrouter-auto"
          ; upstream_model = "openrouter/auto"
          }
        ; { key = "openrouter-free"
          ; label = "Free Models Router"
          ; public_model = "openrouter-free"
          ; upstream_model = "openrouter/free"
          }
        ; { key = "openrouter-gpt-5.2"
          ; label = "GPT-5.2 via OpenRouter"
          ; public_model = "openrouter-gpt-5.2"
          ; upstream_model = "openai/gpt-5.2"
          }
        ]
    }
  ; { key = "openai"
    ; label = "OpenAI"
    ; provider_id_prefix = "openai"
    ; provider_kind = Config.Openai_compat
    ; api_base = "https://api.openai.com/v1"
    ; api_key_env = "OPENAI_API_KEY"
    ; models =
        [ { key = "gpt-5"
          ; label = "GPT-5"
          ; public_model = "gpt-5"
          ; upstream_model = "gpt-5"
          }
        ; { key = "gpt-5-mini"
          ; label = "GPT-5 mini"
          ; public_model = "gpt-5-mini"
          ; upstream_model = "gpt-5-mini"
          }
        ; { key = "gpt-5-nano"
          ; label = "GPT-5 nano"
          ; public_model = "gpt-5-nano"
          ; upstream_model = "gpt-5-nano"
          }
        ]
    }
  ; { key = "google"
    ; label = "Google Gemini"
    ; provider_id_prefix = "google"
    ; provider_kind = Config.Google_openai
    ; api_base = "https://generativelanguage.googleapis.com/v1beta/openai/"
    ; api_key_env = "GOOGLE_API_KEY"
    ; models =
        [ { key = "gemini-2.5-pro"
          ; label = "Gemini 2.5 Pro"
          ; public_model = "gemini-2.5-pro"
          ; upstream_model = "gemini-2.5-pro"
          }
        ; { key = "gemini-2.5-flash"
          ; label = "Gemini 2.5 Flash"
          ; public_model = "gemini-2.5-flash"
          ; upstream_model = "gemini-2.5-flash"
          }
        ; { key = "gemini-2.5-flash-lite"
          ; label = "Gemini 2.5 Flash-Lite"
          ; public_model = "gemini-2.5-flash-lite"
          ; upstream_model = "gemini-2.5-flash-lite"
          }
        ]
    }
  ; { key = "mistral"
    ; label = "Mistral"
    ; provider_id_prefix = "mistral"
    ; provider_kind = Config.Mistral_openai
    ; api_base = "https://api.mistral.ai/v1"
    ; api_key_env = "MISTRAL_API_KEY"
    ; models =
        [ { key = "mistral-medium"
          ; label = "Mistral Medium"
          ; public_model = "mistral-medium"
          ; upstream_model = "mistral-medium-latest"
          }
        ; { key = "mistral-small"
          ; label = "Mistral Small"
          ; public_model = "mistral-small"
          ; upstream_model = "mistral-small-latest"
          }
        ; { key = "codestral"
          ; label = "Codestral"
          ; public_model = "codestral"
          ; upstream_model = "codestral-latest"
          }
        ]
    }
  ; { key = "alibaba"
    ; label = "Alibaba Qwen"
    ; provider_id_prefix = "alibaba"
    ; provider_kind = Config.Alibaba_openai
    ; api_base = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ; api_key_env = "DASHSCOPE_API_KEY"
    ; models =
        [ { key = "qwen-max"
          ; label = "Qwen Max"
          ; public_model = "qwen-max"
          ; upstream_model = "qwen-max"
          }
        ; { key = "qwen-plus"
          ; label = "Qwen Plus"
          ; public_model = "qwen-plus"
          ; upstream_model = "qwen-plus"
          }
        ; { key = "qwen-turbo"
          ; label = "Qwen Turbo"
          ; public_model = "qwen-turbo"
          ; upstream_model = "qwen-turbo"
          }
        ]
    }
  ; { key = "moonshot"
    ; label = "Moonshot Kimi"
    ; provider_id_prefix = "moonshot"
    ; provider_kind = Config.Moonshot_openai
    ; api_base = "https://api.moonshot.ai/v1"
    ; api_key_env = "MOONSHOT_API_KEY"
    ; models =
        [ { key = "kimi-latest"
          ; label = "Kimi Latest"
          ; public_model = "kimi-latest"
          ; upstream_model = "kimi-latest"
          }
        ; { key = "kimi-k2"
          ; label = "Kimi K2"
          ; public_model = "kimi-k2"
          ; upstream_model = "kimi-k2"
          }
        ; { key = "kimi-k2.5"
          ; label = "Kimi K2.5"
          ; public_model = "kimi-k2.5"
          ; upstream_model = "kimi-k2.5"
          }
        ]
    }
  ]
;;
