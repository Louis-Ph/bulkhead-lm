let contains pattern text =
  try
    ignore (Str.search_forward pattern text 0);
    true
  with
  | Not_found -> false
;;

let first_literal_match text values =
  let rec loop = function
    | [] -> None
    | value :: rest ->
      let trimmed = String.trim value in
      if trimmed = ""
      then loop rest
      else if contains (Str.regexp_case_fold (Str.quote trimmed)) text
      then Some trimmed
      else loop rest
  in
  loop values
;;

let prefixed_token_pattern prefix =
  Str.regexp_case_fold (Str.quote prefix ^ "[A-Za-z0-9._=-]+")
;;

let redact_prefixed_tokens ~replacement prefixes text =
  List.fold_left
    (fun acc prefix ->
      let trimmed = String.trim prefix in
      if trimmed = ""
      then acc
      else Str.global_replace (prefixed_token_pattern trimmed) replacement acc)
    text
    prefixes
;;

let first_prefixed_token_match text prefixes =
  let rec loop = function
    | [] -> None
    | prefix :: rest ->
      let trimmed = String.trim prefix in
      if trimmed = ""
      then loop rest
      else if contains (prefixed_token_pattern trimmed) text
      then Some trimmed
      else loop rest
  in
  loop prefixes
;;

let redact_literal_matches ~replacement values text =
  List.fold_left
    (fun acc value ->
      let trimmed = String.trim value in
      if trimmed = ""
      then acc
      else Str.global_replace (Str.regexp_case_fold (Str.quote trimmed)) replacement acc)
    text
    values
;;
