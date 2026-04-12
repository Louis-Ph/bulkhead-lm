type role = Session_memory.role =
  | User
  | Assistant

type turn = Session_memory.turn =
  { role : role
  ; content : string
  }

type compression_event = Session_memory.compression_event =
  { archived_turn_count : int
  ; summary_char_count : int
  }

type stats = Session_memory.stats =
  { recent_turn_count : int
  ; compressed_turn_count : int
  ; summary_char_count : int
  ; estimated_context_chars : int
  }

type t = Session_memory.t =
  { summary : string option
  ; recent_turns : turn list
  ; compressed_turn_count : int
  }

let limits =
  { Session_memory.keep_recent_turns = Session_memory_defaults.keep_recent_turns
  ; compress_threshold_chars = Session_memory_defaults.compress_threshold_chars
  ; turn_excerpt_chars = Session_memory_defaults.turn_excerpt_chars
  ; summary_max_chars = Session_memory_defaults.summary_max_chars
  ; summary_intro =
      "Compressed memory from earlier in this session. Use it as context, but prefer the recent verbatim turns if they differ."
  }
;;

let empty = Session_memory.empty
let clear = Session_memory.clear

let normalize_summary text =
  text
  |> String.split_on_char '\n'
  |> List.map String.trim
  |> List.filter (fun line -> line <> "")
  |> String.concat " "
;;

let trim_summary text =
  if String.length text <= limits.summary_max_chars
  then text
  else "..." ^ String.sub text (String.length text - (limits.summary_max_chars - 3)) (limits.summary_max_chars - 3)
;;

let replace_with_summary ~summary =
  let summary = normalize_summary summary |> trim_summary in
  { summary = Some summary; recent_turns = []; compressed_turn_count = 0 }
;;

let commit_exchange conversation ~user ~assistant = Session_memory.commit_exchange limits conversation ~user ~assistant
let request_messages conversation ~pending_user = Session_memory.request_messages limits conversation ~pending_user
let stats = Session_memory.stats
