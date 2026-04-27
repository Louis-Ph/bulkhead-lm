(** On-disk cache of provider model listings.

    Each provider has its own cache file at [{cache_root}/{provider_key}.json].
    The cache stores a freshness timestamp so callers can decide whether to
    refresh; when a refresh fails the stale cache is returned with a
    [Stale_fallback] flag rather than thrown away.

    The cache root follows the XDG convention by default
    ([$XDG_CACHE_HOME/bulkhead-lm/models] or [~/.cache/bulkhead-lm/models]),
    but tests and headless deployments can override it explicitly via
    [BULKHEAD_LM_MODEL_CACHE_DIR]. *)

open Lwt.Infix

type cached_listing =
  { provider_key : string
  ; provider_kind : string
  ; api_base : string
  ; fetched_at : float (* Unix epoch seconds *)
  ; entries : Provider_models_listing.model_entry list
  }

(** Three observable states surfaced to the wizard so users can tell whether
    they are looking at network-fresh data, a fast cache read, or a stale
    fallback after a fetch failure. *)
type freshness =
  | Live (** Just fetched from the provider in this call. *)
  | Cached_fresh of { age_seconds : float }
      (** Returned from cache without hitting the network. *)
  | Stale_fallback of
      { age_seconds : float
      ; reason : Provider_models_listing.fetch_error
      }
      (** Fetch failed; older cache contents returned. *)

type lookup_result =
  { listing : cached_listing
  ; freshness : freshness
  }

let default_ttl_seconds = 24. *. 60. *. 60.

let env_first names =
  List.find_map
    (fun name ->
      match Sys.getenv_opt name with
      | Some value when String.trim value <> "" -> Some (String.trim value)
      | _ -> None)
    names
;;

(* Resolve the cache root. Honours [BULKHEAD_LM_MODEL_CACHE_DIR] for tests and
   [XDG_CACHE_HOME] for standard installs; otherwise falls back to
   [~/.cache/bulkhead-lm/models]. *)
let default_cache_dir () =
  match env_first [ "BULKHEAD_LM_MODEL_CACHE_DIR" ] with
  | Some explicit -> explicit
  | None ->
    let xdg =
      match env_first [ "XDG_CACHE_HOME" ] with
      | Some value -> value
      | None ->
        let home =
          match env_first [ "HOME" ] with
          | Some value -> value
          | None -> "."
        in
        Filename.concat home ".cache"
    in
    Filename.concat (Filename.concat xdg "bulkhead-lm") "models"
;;

(* Reject anything that could escape the cache directory. We require a strict
   alphabet so a hostile or sloppy provider_key cannot path-traverse, embed a
   NUL, or otherwise corrupt filenames. The current built-in keys all match. *)
let safe_provider_key_re =
  Str.regexp "^[A-Za-z0-9][A-Za-z0-9._-]*$"
;;

let validate_provider_key provider_key =
  if String.length provider_key = 0
  then Error "provider key is empty"
  else if String.length provider_key > 64
  then Error (Fmt.str "provider key %S is too long for a filename" provider_key)
  else if not (Str.string_match safe_provider_key_re provider_key 0)
  then
    Error
      (Fmt.str
         "provider key %S contains characters that are unsafe in filenames"
         provider_key)
  else Ok provider_key
;;

let rec ensure_dir path =
  if path = "" || path = "." || path = "/"
  then ()
  else if Sys.file_exists path
  then ()
  else (
    ensure_dir (Filename.dirname path);
    try Unix.mkdir path 0o700 with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> ())
;;

(* File names live next to other Bulkhead artefacts that are user-readable but
   not particularly secret; we still create the directory and the file with
   restrictive permissions so cached upstream metadata cannot be read by
   other accounts. *)
let cache_file ~cache_dir ~provider_key =
  match validate_provider_key provider_key with
  | Ok safe -> Ok (Filename.concat cache_dir (safe ^ ".json"))
  | Error message -> Error message
;;

let listing_to_yojson (listing : cached_listing) =
  `Assoc
    [ "provider_key", `String listing.provider_key
    ; "provider_kind", `String listing.provider_kind
    ; "api_base", `String listing.api_base
    ; "fetched_at", `Float listing.fetched_at
    ; ( "entries"
      , `List (List.map Provider_models_listing.entry_to_yojson listing.entries) )
    ]
;;

let listing_of_yojson = function
  | `Assoc fields ->
    let string_field name =
      match List.assoc_opt name fields with
      | Some (`String value) -> Some value
      | _ -> None
    in
    let float_field name =
      match List.assoc_opt name fields with
      | Some (`Float value) -> Some value
      | Some (`Int value) -> Some (float_of_int value)
      | _ -> None
    in
    (match
       string_field "provider_key", string_field "provider_kind", string_field "api_base"
     with
     | Some provider_key, Some provider_kind, Some api_base ->
       let fetched_at = float_field "fetched_at" |> Option.value ~default:0.0 in
       let entries =
         match List.assoc_opt "entries" fields with
         | Some (`List entries) ->
           List.filter_map
             (fun entry ->
               match Provider_models_listing.entry_of_yojson entry with
               | Ok value -> Some value
               | Error _ -> None)
             entries
         | _ -> []
       in
       Some { provider_key; provider_kind; api_base; fetched_at; entries }
     | _ -> None)
  | _ -> None
;;

(* Cache reads have three meaningful outcomes; collapsing them all to [None]
   would make a permission error look identical to "not yet cached" which
   makes UX guidance impossible. *)
type read_outcome =
  | Cache_missing
  | Cache_unreadable of string
  | Cache_present of cached_listing

let read_cache_file path =
  match Unix.access path [ Unix.F_OK ] with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Cache_missing
  | exception Unix.Unix_error (err, _, _) ->
    Cache_unreadable (Unix.error_message err)
  | () ->
    (try
       let ic = open_in path in
       Fun.protect
         ~finally:(fun () -> close_in_noerr ic)
         (fun () ->
           let length = in_channel_length ic in
           let buffer = Bytes.create length in
           really_input ic buffer 0 length;
           let contents = Bytes.to_string buffer in
           match Yojson.Safe.from_string contents with
           | exception Yojson.Json_error err ->
             Cache_unreadable ("invalid JSON: " ^ err)
           | json ->
             (match listing_of_yojson json with
              | Some listing -> Cache_present listing
              | None -> Cache_unreadable "JSON did not match listing schema"))
     with
     | Sys_error err -> Cache_unreadable err
     | Unix.Unix_error (err, _, _) -> Cache_unreadable (Unix.error_message err))
;;

(* Use a per-process tmp suffix so two concurrent wizards refreshing the same
   provider cannot stomp on each other's [.tmp] file. *)
let unique_tmp_path path =
  let pid = Unix.getpid () in
  let now = Unix.gettimeofday () in
  Fmt.str "%s.%d-%d.tmp" path pid (int_of_float (now *. 1_000_000.))
;;

let write_file path contents =
  ensure_dir (Filename.dirname path);
  let tmp = unique_tmp_path path in
  let oc = open_out_gen [ Open_wronly; Open_creat; Open_trunc ] 0o600 tmp in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc contents);
  Sys.rename tmp path
;;

let load_cached ?(cache_dir = default_cache_dir ()) ~provider_key () =
  match cache_file ~cache_dir ~provider_key with
  | Error _ -> None
  | Ok path ->
    (match read_cache_file path with
     | Cache_present listing -> Some listing
     | Cache_missing | Cache_unreadable _ -> None)
;;

let inspect ?(cache_dir = default_cache_dir ()) ~provider_key () =
  match cache_file ~cache_dir ~provider_key with
  | Error _ -> Cache_missing
  | Ok path -> read_cache_file path
;;

(* Don't blow away a previously-good listing with an empty array: empty
   responses are most often a transient provider hiccup, not a real change. *)
let entries_safe_to_overwrite ~previous ~next =
  if next <> [] then true
  else
    match previous with
    | None -> true
    | Some prior -> prior = []
;;

type store_outcome =
  | Stored
  | Skipped_empty
  | Store_failed of string

let store ?(cache_dir = default_cache_dir ()) ?previous (listing : cached_listing) =
  match cache_file ~cache_dir ~provider_key:listing.provider_key with
  | Error message -> Store_failed message
  | Ok path ->
    if not (entries_safe_to_overwrite ~previous ~next:listing.entries)
    then Skipped_empty
    else (
      let json = listing_to_yojson listing in
      try
        write_file path (Yojson.Safe.pretty_to_string json);
        Stored
      with
      | Sys_error err -> Store_failed err
      | Unix.Unix_error (err, _, _) -> Store_failed (Unix.error_message err))
;;

let invalidate ?(cache_dir = default_cache_dir ()) ~provider_key () =
  match cache_file ~cache_dir ~provider_key with
  | Error _ -> ()
  | Ok path ->
    (try Sys.remove path with
     | Sys_error _ -> ())
;;

let cache_age ~now (listing : cached_listing) = now -. listing.fetched_at

let is_fresh ?(ttl_seconds = default_ttl_seconds) ~now listing =
  cache_age ~now listing <= ttl_seconds
;;

(** Lookup, with a live fetch when the cache is missing or stale.

    The returned [lookup_result] always contains a listing if at least one of
    the cache or the live fetch succeeded. The semantics are:

    - If a fresh cache exists and [force_refresh = false], return it without
      hitting the network ([Cached_fresh]).
    - Otherwise, try to fetch live. On success, the cache is updated and the
      listing is tagged [Live].
    - On fetch failure, fall back to the cached listing (any age) tagged
      [Stale_fallback]; if no cache exists, propagate the fetch error.

    [on_store_error] is invoked whenever the cache write itself fails so the
    wizard can surface a one-shot warning. *)
let lookup
  ?(cache_dir = default_cache_dir ())
  ?(ttl_seconds = default_ttl_seconds)
  ?(force_refresh = false)
  ?(on_store_error = fun _ -> ())
  ~provider_key
  ~provider_kind
  ~api_base
  ~api_key
  ()
  =
  let now = Unix.time () in
  let cached = load_cached ~cache_dir ~provider_key () in
  let cache_is_fresh =
    match cached with
    | Some listing -> is_fresh ~ttl_seconds ~now listing
    | None -> false
  in
  if cache_is_fresh && not force_refresh
  then (
    match cached with
    | Some listing ->
      let age = cache_age ~now listing in
      Lwt.return
        (Ok { listing; freshness = Cached_fresh { age_seconds = age } })
    | None ->
      Lwt.return
        (Error
           (Provider_models_listing.make_error "internal: cache went missing")))
  else
    Provider_models_listing.fetch ~provider_kind ~api_base ~api_key ()
    >>= function
    | Ok entries ->
      let listing =
        { provider_key
        ; provider_kind = Config.provider_kind_to_string provider_kind
        ; api_base
        ; fetched_at = now
        ; entries
        }
      in
      (match store ~cache_dir ?previous:(Option.map (fun l -> l.entries) cached) listing with
       | Stored | Skipped_empty -> ()
       | Store_failed message -> on_store_error message);
      Lwt.return (Ok { listing; freshness = Live })
    | Error err ->
      (match cached with
       | Some listing ->
         let age = cache_age ~now listing in
         Lwt.return
           (Ok
              { listing
              ; freshness = Stale_fallback { age_seconds = age; reason = err }
              })
       | None -> Lwt.return (Error err))
;;
