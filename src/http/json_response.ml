let respond_json ?(status = `OK) json =
  let headers = Cohttp.Header.of_list [ "content-type", "application/json" ] in
  Cohttp_lwt_unix.Server.respond_string
    ~status
    ~headers
    ~body:(Yojson.Safe.to_string json)
    ()
;;

let respond_error error =
  let status = Cohttp.Code.status_of_code error.Domain_error.status in
  respond_json ~status (Domain_error.to_openai_json error)
;;
