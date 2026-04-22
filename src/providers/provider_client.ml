type chat_result = (Openai_types.chat_response, Domain_error.t) result

type upstream_context =
  { peer_headers : (string * string) list
  ; peer_context : Peer_mesh.context option
  }

type chat_stream_event =
  | Text_delta of string
  | Reasoning_delta of string

type chat_stream =
  { response : Openai_types.chat_response
  ; events : chat_stream_event Lwt_stream.t
  ; close : unit -> unit Lwt.t
  }

type chat_stream_result = (chat_stream, Domain_error.t) result
type embeddings_result = (Openai_types.embeddings_response, Domain_error.t) result

type t =
  { invoke_chat :
      upstream_context -> Config.backend -> Openai_types.chat_request -> chat_result Lwt.t
  ; invoke_chat_stream :
      upstream_context
      -> Config.backend
      -> Openai_types.chat_request
      -> chat_stream_result Lwt.t
  ; invoke_embeddings :
      upstream_context
      -> Config.backend
      -> Openai_types.embeddings_request
      -> embeddings_result Lwt.t
  }
