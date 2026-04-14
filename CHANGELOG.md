# Changelog

## Unreleased

### Added

- **6 new direct provider kinds**: `deepseek_openai`, `groq_openai`, `perplexity_openai`, `together_openai`, `cerebras_openai`, `cohere_openai`
  - All six dispatch through the existing OpenAI-compatible adapter (`Openai_compat_provider`)
  - New env vars: `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `PERPLEXITY_API_KEY`, `TOGETHER_API_KEY`, `CEREBRAS_API_KEY`, `COHERE_API_KEY`
  - Embeddings support: `together_openai`, `cohere_openai`
  - Chat only: `deepseek_openai`, `groq_openai`, `perplexity_openai`, `cerebras_openai`

- **18 new example routes** in `config/example.gateway.json` (28 → 46 total):
  - DeepSeek: `deepseek-v3`, `deepseek-r1`, `deepseek-r1-lite`
  - Groq: `groq-llama-3.3-70b`, `groq-llama-3.1-8b`, `groq-qwen-qwq-32b`
  - Perplexity: `perplexity-sonar-pro`, `perplexity-sonar`, `perplexity-sonar-reasoning`
  - Together AI: `together-llama-3.3-70b`, `together-deepseek-v3`, `together-qwen-2.5-72b`
  - Cerebras: `cerebras-llama-3.3-70b`, `cerebras-llama-3.1-8b`
  - Cohere: `cohere-command-r-plus`, `cohere-command-r`, `cohere-embed-v3`

- Updated `config/defaults/providers.schema.json` with all 6 new provider kinds and their capabilities

### Changed

- `README.md`: expanded provider table to 19 kinds with key env vars, API base URLs, and route counts
- `readme_for_dummies.md`: added DeepSeek, Groq, Cerebras, Perplexity, Together AI, Cohere to cheapest-path guide and key-variable reference
