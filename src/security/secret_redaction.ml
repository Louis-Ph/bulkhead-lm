let redact_json ~sensitive_keys ~replacement json =
  let sensitive_set = sensitive_keys |> List.map String.lowercase_ascii in
  let rec go = function
    | `Assoc fields ->
      `Assoc
        (List.map
           (fun (key, value) ->
             if List.mem (String.lowercase_ascii key) sensitive_set
             then key, `String replacement
             else key, go value)
           fields)
    | `List values -> `List (List.map go values)
    | other -> other
  in
  go json
;;

let redact_headers ~sensitive_keys ~replacement headers =
  headers
  |> List.map (fun (key, value) ->
    if List.mem
         (String.lowercase_ascii key)
         (List.map String.lowercase_ascii sensitive_keys)
    then key, replacement
    else key, value)
;;
