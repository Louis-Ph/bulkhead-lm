type chat_result = (Openai_types.chat_response, Domain_error.t) result
type embeddings_result = (Openai_types.embeddings_response, Domain_error.t) result

type t =
  { invoke_chat : Config.backend -> Openai_types.chat_request -> chat_result Lwt.t
  ; invoke_embeddings :
      Config.backend -> Openai_types.embeddings_request -> embeddings_result Lwt.t
  }
