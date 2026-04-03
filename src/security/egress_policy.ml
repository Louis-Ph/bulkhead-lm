let is_private_ipv4 host =
  let parts =
    String.split_on_char '.' host |> List.filter_map (fun part -> int_of_string_opt part)
  in
  match parts with
  | [ a; b; _; _ ] ->
    a = 10
    || a = 127
    || a = 0
    || (a = 169 && b = 254)
    || (a = 172 && b >= 16 && b <= 31)
    || (a = 192 && b = 168)
  | _ -> false
;;

let is_private_ipv6 host =
  let lower = String.lowercase_ascii host in
  lower = "::1"
  || String.starts_with ~prefix:"fc" lower
  || String.starts_with ~prefix:"fd" lower
  || String.starts_with ~prefix:"fe80" lower
;;

let ensure_host_allowed policy ~scheme ~host =
  if host = ""
  then Error (Domain_error.provider_denied "Provider URL must include a host.")
  else if not (List.mem scheme policy.Security_policy.egress.allowed_schemes)
  then Error (Domain_error.provider_denied (Fmt.str "Blocked URI scheme: %s" scheme))
  else if List.mem host policy.Security_policy.egress.blocked_hosts
  then Error (Domain_error.provider_denied (Fmt.str "Blocked host by policy: %s" host))
  else if policy.Security_policy.egress.deny_private_ranges
          && (is_private_ipv4 host
              || is_private_ipv6 host
              || String.ends_with ~suffix:".local" host)
  then
    Error
      (Domain_error.provider_denied
         (Fmt.str "Private or loopback destination blocked: %s" host))
  else Ok ()
;;

let ensure_http_allowed policy url =
  let uri = Uri.of_string url in
  let scheme = Uri.scheme uri |> Option.value ~default:"" |> String.lowercase_ascii in
  let host = Uri.host uri |> Option.value ~default:"" |> String.lowercase_ascii in
  ensure_host_allowed policy ~scheme ~host
;;

let ensure_allowed policy (backend : Config.backend) =
  match backend.target with
  | Config.Http_target api_base -> ensure_http_allowed policy api_base
  | Config.Ssh_target transport ->
    ensure_host_allowed policy ~scheme:"ssh" ~host:(String.lowercase_ascii transport.host)
;;
