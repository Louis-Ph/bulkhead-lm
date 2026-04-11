type role =
  | User
  | Assistant

type turn =
  { role : role
  ; content : string
  }

type compression_event =
  { archived_turn_count : int
  ; summary_char_count : int
  }

type stats =
  { recent_turn_count : int
  ; compressed_turn_count : int
  ; summary_char_count : int
  ; estimated_context_chars : int
  }

type limits =
  { keep_recent_turns : int
  ; compress_threshold_chars : int
  ; turn_excerpt_chars : int
  ; summary_max_chars : int
  ; summary_intro : string
  }

type t =
  { summary : string option
  ; recent_turns : turn list
  ; compressed_turn_count : int
  }

let empty = { summary = None; recent_turns = []; compressed_turn_count = 0 }

let normalize_text text =
  text
  |> String.split_on_char '\n'
  |> List.map String.trim
  |> List.filter (fun line -> line <> "")
  |> String.concat " "
;;

let abbreviate_text limits text =
  let normalized = normalize_text text in
  if String.length normalized <= limits.turn_excerpt_chars
  then normalized
  else String.sub normalized 0 (max 0 (limits.turn_excerpt_chars - 3)) ^ "..."
;;

let role_label = function
  | User -> "User"
  | Assistant -> "Assistant"
;;

let turn_line limits (turn : turn) =
  Fmt.str "%s: %s" (role_label turn.role) (abbreviate_text limits turn.content)
;;

let trim_summary limits text =
  if String.length text <= limits.summary_max_chars
  then text
  else "..." ^ String.sub text (String.length text - (limits.summary_max_chars - 3)) (limits.summary_max_chars - 3)
;;

let split_oldest turns ~keep_latest =
  let total = List.length turns in
  let archive_count = max 0 (total - keep_latest) in
  let rec loop index archived kept = function
    | [] -> List.rev archived, List.rev kept
    | turn :: rest ->
      if index < archive_count
      then loop (index + 1) (turn :: archived) kept rest
      else loop (index + 1) archived (turn :: kept) rest
  in
  loop 0 [] [] turns
;;

let turn_char_count (turn : turn) = String.length turn.content + 12

let estimated_chars conversation =
  let summary_chars =
    match conversation.summary with
    | None -> 0
    | Some summary -> String.length summary
  in
  summary_chars
  + List.fold_left (fun total turn -> total + turn_char_count turn) 0 conversation.recent_turns
;;

let maybe_compress limits conversation =
  if List.length conversation.recent_turns <= limits.keep_recent_turns
     || estimated_chars conversation <= limits.compress_threshold_chars
  then conversation, None
  else (
    let archived, kept = split_oldest conversation.recent_turns ~keep_latest:limits.keep_recent_turns in
    let fragment = archived |> List.map (turn_line limits) |> String.concat "\n" in
    let merged_summary =
      match conversation.summary with
      | None -> fragment
      | Some summary -> summary ^ "\n" ^ fragment
    in
    let summary = trim_summary limits merged_summary in
    let updated =
      { summary = Some summary
      ; recent_turns = kept
      ; compressed_turn_count = conversation.compressed_turn_count + List.length archived
      }
    in
    updated, Some { archived_turn_count = List.length archived; summary_char_count = String.length summary })
;;

let commit_exchange limits conversation ~user ~assistant =
  let updated =
    { conversation with
      recent_turns =
        conversation.recent_turns
        @ [ { role = User; content = user }; { role = Assistant; content = assistant } ]
    }
  in
  maybe_compress limits updated
;;

let clear () = empty

let system_summary_message limits summary : Openai_types.message =
  { Openai_types.role = "system"; content = limits.summary_intro ^ "\n\n" ^ summary }
;;

let turn_to_message (turn : turn) : Openai_types.message =
  { Openai_types.role =
      (match turn.role with
       | User -> "user"
       | Assistant -> "assistant")
  ; content = turn.content
  }
;;

let request_messages limits conversation ~pending_user : Openai_types.message list =
  let summary_messages =
    match conversation.summary with
    | None -> []
    | Some summary -> [ system_summary_message limits summary ]
  in
  summary_messages
  @ List.map turn_to_message conversation.recent_turns
  @ [ ({ Openai_types.role = "user"; content = pending_user } : Openai_types.message) ]
;;

let stats conversation =
  { recent_turn_count = List.length conversation.recent_turns
  ; compressed_turn_count = conversation.compressed_turn_count
  ; summary_char_count =
      (match conversation.summary with
       | None -> 0
       | Some summary -> String.length summary)
  ; estimated_context_chars = estimated_chars conversation
  }
;;
