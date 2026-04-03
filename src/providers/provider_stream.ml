open Lwt.Infix

let chunk_text ?(size = 16) text =
  let rec loop acc offset =
    if offset >= String.length text
    then List.rev acc
    else (
      let remaining = String.length text - offset in
      let length = min size remaining in
      let part = String.sub text offset length in
      loop (part :: acc) (offset + length))
  in
  if text = "" then [ "" ] else loop [] 0
;;

let text_of_chat_response (response : Openai_types.chat_response) =
  response.choices
  |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
    let content = choice.message.content in
    if content = "" then None else Some content)
  |> String.concat "\n"
;;

let of_chat_response response =
  let events =
    text_of_chat_response response
    |> chunk_text
    |> List.map (fun text -> Provider_client.Text_delta text)
    |> Lwt_stream.of_list
  in
  { Provider_client.response; events; close = (fun () -> Lwt.return_unit) }
;;
