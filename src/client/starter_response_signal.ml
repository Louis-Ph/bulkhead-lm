type level = Starter_constants.Assistant_signal.level =
  | Normal
  | Green
  | Orange
  | Red

type event =
  | Text of string
  | Set_level of level

type stream_state =
  { active_level : level
  ; directive_allowed : bool
  ; pending : string
  }

let initial_state = { active_level = Normal; directive_allowed = true; pending = "" }

let directives = Starter_constants.Assistant_signal.directives

let starts_with text ~offset prefix =
  let prefix_length = String.length prefix in
  String.length text >= offset + prefix_length
  && String.sub text offset prefix_length = prefix
;;

let suffix_is_possible_directive text ~offset =
  let suffix_length = String.length text - offset in
  List.exists
    (fun (directive, _) ->
      String.length directive >= suffix_length
      && String.sub directive 0 suffix_length = String.sub text offset suffix_length)
    directives
;;

let matching_directive text ~offset =
  List.find_opt (fun (directive, _) -> starts_with text ~offset directive) directives
;;

let flush_text buffer events =
  if Buffer.length buffer = 0
  then events
  else (
    let text = Buffer.contents buffer in
    Buffer.clear buffer;
    Text text :: events)
;;

let feed state chunk =
  let input = state.pending ^ chunk in
  let input_length = String.length input in
  let text_buffer = Buffer.create input_length in
  let rec loop index directive_allowed active_level events =
    if index >= input_length
    then
      let events = flush_text text_buffer events |> List.rev in
      { active_level; directive_allowed; pending = "" }, events
    else if directive_allowed
    then (
      match matching_directive input ~offset:index with
      | Some (directive, next_level) ->
        let events =
          flush_text text_buffer events
          |> fun acc ->
          if next_level = active_level then acc else Set_level next_level :: acc
        in
        loop (index + String.length directive) true next_level events
      | None when suffix_is_possible_directive input ~offset:index ->
        let events = flush_text text_buffer events |> List.rev in
        ( { active_level
          ; directive_allowed
          ; pending = String.sub input index (input_length - index)
          }
        , events )
      | None ->
        let ch = input.[index] in
        Buffer.add_char text_buffer ch;
        loop (index + 1) (Char.equal ch '\n') active_level events)
    else
      let ch = input.[index] in
      Buffer.add_char text_buffer ch;
      loop (index + 1) (Char.equal ch '\n') active_level events
  in
  loop 0 state.directive_allowed state.active_level []
;;

let finish state =
  if state.pending = ""
  then { state with pending = "" }, []
  else { state with pending = "" }, [ Text state.pending ]
;;

let strip_markup text =
  let state, events = feed initial_state text in
  let _, tail_events = finish state in
  let buffer = Buffer.create (String.length text) in
  List.iter
    (function
      | Text value -> Buffer.add_string buffer value
      | Set_level _ -> ())
    (events @ tail_events);
  Buffer.contents buffer
;;
