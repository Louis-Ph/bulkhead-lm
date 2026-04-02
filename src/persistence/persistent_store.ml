module String_map = Map.Make (String)

type stored_principal =
  { name : string
  ; token_hash : string
  ; daily_token_budget : int
  ; requests_per_minute : int
  ; allowed_routes : string list
  }

type audit_event =
  { event_type : string
  ; principal_name : string option
  ; route_model : string option
  ; provider_id : string option
  ; status_code : int
  ; details : Yojson.Safe.t
  }

type t =
  { db : Sqlite3.db
  ; lock : Mutex.t
  ; path : string
  }

let timestamp_now () =
  let tm = Unix.gmtime (Unix.time ()) in
  Fmt.str
    "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.tm_year + 1900)
    (tm.tm_mon + 1)
    tm.tm_mday
    tm.tm_hour
    tm.tm_min
    tm.tm_sec
;;

let rec ensure_dir path =
  if path = "" || path = "." || path = "/"
  then ()
  else if Sys.file_exists path
  then ()
  else (
    ensure_dir (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let ensure_parent_dir path = ensure_dir (Filename.dirname path)
let hash_token token = Digestif.SHA256.digest_string token |> Digestif.SHA256.to_hex
let rc_ok rc = rc = Sqlite3.Rc.OK || rc = Sqlite3.Rc.DONE || rc = Sqlite3.Rc.ROW

let expect_rc db context rc =
  if rc_ok rc
  then ()
  else
    failwith
      (Fmt.str
         "SQLite error during %s: %s (%s)"
         context
         (Sqlite3.Rc.to_string rc)
         (Sqlite3.errmsg db))
;;

let with_stmt db sql f =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () -> f stmt)
;;

let with_lock store f =
  Mutex.lock store.lock;
  match f () with
  | result ->
    Mutex.unlock store.lock;
    result
  | exception exn ->
    Mutex.unlock store.lock;
    raise exn
;;

let exec db context sql = expect_rc db context (Sqlite3.exec db sql)

let setup_schema db =
  exec db "pragma journal_mode" "PRAGMA journal_mode=WAL";
  exec db "pragma synchronous" "PRAGMA synchronous=NORMAL";
  exec db "pragma foreign_keys" "PRAGMA foreign_keys=ON";
  exec
    db
    "virtual_keys schema"
    {|CREATE TABLE IF NOT EXISTS virtual_keys (
         name TEXT PRIMARY KEY,
         token_hash TEXT NOT NULL UNIQUE,
         daily_token_budget INTEGER NOT NULL,
         requests_per_minute INTEGER NOT NULL,
         allowed_routes_json TEXT NOT NULL,
         created_at TEXT NOT NULL,
         updated_at TEXT NOT NULL
       )|};
  exec
    db
    "budget_usage schema"
    {|CREATE TABLE IF NOT EXISTS budget_usage (
         usage_day TEXT NOT NULL,
         principal_name TEXT NOT NULL,
         consumed_tokens INTEGER NOT NULL,
         updated_at TEXT NOT NULL,
         PRIMARY KEY (usage_day, principal_name)
       )|};
  exec
    db
    "audit_log schema"
    {|CREATE TABLE IF NOT EXISTS audit_log (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         created_at TEXT NOT NULL,
         event_type TEXT NOT NULL,
         principal_name TEXT,
         route_model TEXT,
         provider_id TEXT,
         status_code INTEGER NOT NULL,
         details_json TEXT NOT NULL
       )|}
;;

let sync_virtual_key db security_policy (virtual_key : Config.virtual_key) =
  let token_hash =
    match virtual_key.token_hash, virtual_key.token_plaintext with
    | Some hash, _ -> hash
    | None, Some plaintext ->
      if security_policy.Security_policy.auth.hash_algorithm <> "sha256"
      then failwith "Only sha256 hashing is supported for persisted virtual keys"
      else hash_token plaintext
    | None, None -> failwith "Virtual key requires token_plaintext or token_hash"
  in
  with_stmt
    db
    {|INSERT INTO virtual_keys (
         name,
         token_hash,
         daily_token_budget,
         requests_per_minute,
         allowed_routes_json,
         created_at,
         updated_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET
         token_hash = excluded.token_hash,
         daily_token_budget = excluded.daily_token_budget,
         requests_per_minute = excluded.requests_per_minute,
         allowed_routes_json = excluded.allowed_routes_json,
         updated_at = excluded.updated_at|}
    (fun stmt ->
       let now = timestamp_now () in
       expect_rc db "bind key name" (Sqlite3.bind_text stmt 1 virtual_key.name);
       expect_rc db "bind token hash" (Sqlite3.bind_text stmt 2 token_hash);
       expect_rc db "bind budget" (Sqlite3.bind_int stmt 3 virtual_key.daily_token_budget);
       expect_rc db "bind rpm" (Sqlite3.bind_int stmt 4 virtual_key.requests_per_minute);
       expect_rc
         db
         "bind allowed routes"
         (Sqlite3.bind_text
            stmt
            5
            (Yojson.Safe.to_string
               (`List (List.map (fun route -> `String route) virtual_key.allowed_routes))));
       expect_rc db "bind created_at" (Sqlite3.bind_text stmt 6 now);
       expect_rc db "bind updated_at" (Sqlite3.bind_text stmt 7 now);
       expect_rc db "upsert virtual key" (Sqlite3.step stmt))
;;

let load_principals db =
  with_stmt
    db
    {|SELECT name, token_hash, daily_token_budget, requests_per_minute, allowed_routes_json
      FROM virtual_keys
      ORDER BY name|}
    (fun stmt ->
       let rec loop acc =
         match Sqlite3.step stmt with
         | Sqlite3.Rc.ROW ->
           let allowed_routes =
             try
               Yojson.Safe.from_string (Sqlite3.column_text stmt 4)
               |> function
               | `List values ->
                 values
                 |> List.filter_map (function
                   | `String route -> Some route
                   | _ -> None)
               | _ -> []
             with
             | _ -> []
           in
           let principal =
             { name = Sqlite3.column_text stmt 0
             ; token_hash = Sqlite3.column_text stmt 1
             ; daily_token_budget = Sqlite3.column_int stmt 2
             ; requests_per_minute = Sqlite3.column_int stmt 3
             ; allowed_routes
             }
           in
           loop (principal :: acc)
         | Sqlite3.Rc.DONE -> List.rev acc
         | rc ->
           failwith
             (Fmt.str "SQLite error during load_principals: %s" (Sqlite3.Rc.to_string rc))
       in
       loop [])
;;

let open_or_bootstrap (config : Config.t) =
  match config.persistence.sqlite_path with
  | None -> Ok None
  | Some path ->
    (try
       ensure_parent_dir path;
       let db = Sqlite3.db_open ~mutex:`FULL path in
       let store = { db; lock = Mutex.create (); path } in
       exec
         db
         "busy_timeout"
         (Fmt.str "PRAGMA busy_timeout=%d" config.persistence.busy_timeout_ms);
       setup_schema db;
       List.iter (sync_virtual_key db config.security_policy) config.virtual_keys;
       let principals = load_principals db in
       Ok (Some (store, principals))
     with
     | exn -> Error ("Persistent store initialization failed: " ^ Printexc.to_string exn))
;;

let consume_budget store ~principal_name ~daily_token_budget ~usage_day ~tokens =
  with_lock store (fun () ->
    try
      exec store.db "begin budget tx" "BEGIN IMMEDIATE";
      let consumed =
        with_stmt
          store.db
          {|SELECT consumed_tokens
            FROM budget_usage
            WHERE usage_day = ? AND principal_name = ?|}
          (fun stmt ->
             expect_rc store.db "bind usage_day" (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc
               store.db
               "bind principal_name"
               (Sqlite3.bind_text stmt 2 principal_name);
             match Sqlite3.step stmt with
             | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
             | Sqlite3.Rc.DONE -> 0
             | rc ->
               failwith
                 (Fmt.str
                    "SQLite error during load budget row: %s"
                    (Sqlite3.Rc.to_string rc)))
      in
      if consumed + tokens > daily_token_budget
      then (
        exec store.db "rollback budget tx" "ROLLBACK";
        Error (Domain_error.budget_exceeded ()))
      else (
        with_stmt
          store.db
          {|INSERT INTO budget_usage (
               usage_day,
               principal_name,
               consumed_tokens,
               updated_at
             ) VALUES (?, ?, ?, ?)
             ON CONFLICT(usage_day, principal_name) DO UPDATE SET
               consumed_tokens = excluded.consumed_tokens,
               updated_at = excluded.updated_at|}
          (fun stmt ->
             let updated = consumed + tokens in
             let now = timestamp_now () in
             expect_rc
               store.db
               "bind usage_day upsert"
               (Sqlite3.bind_text stmt 1 usage_day);
             expect_rc
               store.db
               "bind principal_name upsert"
               (Sqlite3.bind_text stmt 2 principal_name);
             expect_rc store.db "bind consumed_tokens" (Sqlite3.bind_int stmt 3 updated);
             expect_rc store.db "bind updated_at usage" (Sqlite3.bind_text stmt 4 now);
             expect_rc store.db "upsert budget usage" (Sqlite3.step stmt));
        exec store.db "commit budget tx" "COMMIT";
        Ok ())
    with
    | exn ->
      ignore (Sqlite3.exec store.db "ROLLBACK");
      raise exn)
;;

let append_audit_event store (event : audit_event) =
  with_lock store (fun () ->
    with_stmt
      store.db
      {|INSERT INTO audit_log (
           created_at,
           event_type,
           principal_name,
           route_model,
           provider_id,
           status_code,
           details_json
         ) VALUES (?, ?, ?, ?, ?, ?, ?)|}
      (fun stmt ->
         let bind_text_opt position = function
           | Some value ->
             expect_rc
               store.db
               "bind audit optional text"
               (Sqlite3.bind_text stmt position value)
           | None ->
             expect_rc
               store.db
               "bind audit null"
               (Sqlite3.bind stmt position Sqlite3.Data.NULL)
         in
         expect_rc
           store.db
           "bind audit created_at"
           (Sqlite3.bind_text stmt 1 (timestamp_now ()));
         expect_rc
           store.db
           "bind audit event_type"
           (Sqlite3.bind_text stmt 2 event.event_type);
         bind_text_opt 3 event.principal_name;
         bind_text_opt 4 event.route_model;
         bind_text_opt 5 event.provider_id;
         expect_rc
           store.db
           "bind audit status_code"
           (Sqlite3.bind_int stmt 6 event.status_code);
         expect_rc
           store.db
           "bind audit details"
           (Sqlite3.bind_text stmt 7 (Yojson.Safe.to_string event.details));
         expect_rc store.db "insert audit row" (Sqlite3.step stmt)))
;;

let audit_count store =
  with_lock store (fun () ->
    with_stmt store.db "SELECT COUNT(*) FROM audit_log" (fun stmt ->
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0
      | rc ->
        failwith (Fmt.str "SQLite error during audit_count: %s" (Sqlite3.Rc.to_string rc))))
;;
