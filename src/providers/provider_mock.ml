let sample_chat_response ~model ~content () =
  { Openai_types.id = "chatcmpl-mock"
  ; created = 1_700_000_000
  ; model
  ; choices =
      [ { index = 0; message = { role = "assistant"; content }; finish_reason = "stop" } ]
  ; usage = { prompt_tokens = 1; completion_tokens = 1; total_tokens = 2 }
  }
;;

let make responses =
  let table = Hashtbl.create (List.length responses) in
  List.iter (fun (model, result) -> Hashtbl.replace table model result) responses;
  let lookup backend =
    match Hashtbl.find_opt table backend.Config.upstream_model with
    | Some result -> result
    | None ->
      Error
        (Domain_error.upstream
           ~provider_id:backend.Config.provider_id
           ("No mock response registered for " ^ backend.Config.upstream_model))
  in
  { Provider_client.invoke_chat = (fun backend _request -> Lwt.return (lookup backend))
  ; invoke_embeddings =
      (fun backend _request ->
        Lwt.return
          (Error
             (Domain_error.unsupported_feature
                ("mock embeddings for provider " ^ backend.Config.provider_id))))
  }
;;
