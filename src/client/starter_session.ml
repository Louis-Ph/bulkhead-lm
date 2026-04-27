type command =
  | Empty
  | Help
  | Show_tools
  | Show_control_plane
  | Admin_request of string
  | Package_request
  | Show_admin_plan
  | Apply_admin_plan
  | Discard_admin_plan
  | Show_config
  | Choose_model
  | Show_models
  | Show_memory
  | Replace_memory of string
  | Forget_memory
  | Show_providers
  | Discover_provider_models
  | Refresh_provider_models
  | Show_env
  | Pool_list
  | Pool_show of string
  | Pool_create of string
  | Pool_drop of string
  | Pool_add of { name : string; route : string; budget : int option }
  | Pool_remove of { name : string; route : string }
  | Pool_global_set of bool
  | Persona_list
  | Attach_file of string
  | Show_pending_files
  | Clear_pending_files
  | Explore_path of string
  | Open_path of string
  | Run_command of string
  | Quit
  | Set_thread of bool
  | Swap_model of string
  | Prompt of string
  | Invalid of string

type ready_context =
  { model : string
  ; config_path : string
  ; conversation_enabled : bool
  }

type t =
  | Ready of ready_context
  | Streaming of ready_context
  | Closed

type effect =
  | Noop
  | Show_help
  | Show_tools_panel
  | Show_control_plane_status
  | Begin_admin_request of string
  | Begin_package_request
  | Show_pending_admin_plan
  | Execute_pending_admin_plan
  | Drop_pending_admin_plan
  | Show_config_path of string
  | Select_model
  | List_models
  | Show_memory_status
  | Substitute_memory of string
  | Reset_memory
  | List_providers
  | List_discovered_models
  | Refresh_discovered_models
  | List_env
  | Show_pool_list
  | Show_pool of string
  | Create_pool of string
  | Drop_pool of string
  | Add_pool_member of { name : string; route : string; budget : int option }
  | Remove_pool_member of { name : string; route : string }
  | Set_global_pool of bool
  | Show_persona_list
  | Attach_local_file of string
  | List_pending_files
  | Reset_pending_files
  | Explore_local_path of string
  | Open_local_path of string
  | Run_local_command of string
  | Update_thread of bool
  | Exit
  | Print_message of string
  | Begin_prompt of string
  | Attempt_swap of string

let create ~model ~config_path = Ready { model; config_path; conversation_enabled = true }

let context = function
  | Ready context | Streaming context -> Some context
  | Closed -> None
;;

let current_model state = Option.map (fun context -> context.model) (context state)
let current_config_path state = Option.map (fun context -> context.config_path) (context state)
let conversation_enabled state = Option.value (Option.map (fun context -> context.conversation_enabled) (context state)) ~default:false

let parse_command input =
  let trimmed = String.trim input in
  let admin_prefix = Starter_constants.Command.admin ^ " " in
  let swap_prefix = Starter_constants.Command.swap ^ " " in
  let memory_replace_prefix = Starter_constants.Command.memory_replace ^ " " in
  let thread_prefix = Starter_constants.Command.thread ^ " " in
  let file_prefix = Starter_constants.Command.file ^ " " in
  let explore_prefix = Starter_constants.Command.explore ^ " " in
  let open_prefix = Starter_constants.Command.open_file ^ " " in
  let run_prefix = Starter_constants.Command.run ^ " " in
  if trimmed = ""
  then Empty
  else if String.equal trimmed Starter_constants.Command.help
  then Help
  else if String.equal trimmed Starter_constants.Command.tools
  then Show_tools
  else if String.equal trimmed Starter_constants.Command.control
  then Show_control_plane
  else if String.equal trimmed Starter_constants.Command.package
  then Package_request
  else if String.equal trimmed Starter_constants.Command.plan
  then Show_admin_plan
  else if String.equal trimmed Starter_constants.Command.apply
  then Apply_admin_plan
  else if String.equal trimmed Starter_constants.Command.discard
  then Discard_admin_plan
  else if String.equal trimmed Starter_constants.Command.config
  then Show_config
  else if String.equal trimmed Starter_constants.Command.model
  then Choose_model
  else if String.equal trimmed Starter_constants.Command.models
  then Show_models
  else if String.equal trimmed Starter_constants.Command.memory
  then Show_memory
  else if String.equal trimmed Starter_constants.Command.memory_replace
  then Invalid Starter_constants.Text.memory_replace_usage
  else if String.equal trimmed Starter_constants.Command.forget
  then Forget_memory
  else if String.equal trimmed Starter_constants.Command.providers
  then Show_providers
  else if String.equal trimmed Starter_constants.Command.discover
  then Discover_provider_models
  else if String.equal trimmed Starter_constants.Command.refresh_models
  then Refresh_provider_models
  else if String.equal trimmed Starter_constants.Command.pool_list
       || String.equal trimmed Starter_constants.Command.pool
  then Pool_list
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_show ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_show + 1 in
    let name = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if name = ""
    then Invalid "/pool show expects a pool name, e.g. /pool show pool-01"
    else Pool_show name)
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_create ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_create + 1 in
    let name = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if name = ""
    then Invalid "/pool create expects a pool name, e.g. /pool create pool-01"
    else Pool_create name)
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_drop ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_drop + 1 in
    let name = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if name = ""
    then Invalid "/pool drop expects a pool name, e.g. /pool drop pool-01"
    else Pool_drop name)
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_add ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_add + 1 in
    let payload =
      String.sub trimmed offset (String.length trimmed - offset) |> String.trim
    in
    let parts =
      String.split_on_char ' ' payload |> List.filter (fun s -> s <> "")
    in
    match parts with
    | [ name; route ] -> Pool_add { name; route; budget = None }
    | [ name; route; raw_budget ] ->
      (match int_of_string_opt raw_budget with
       | Some budget when budget >= 0 ->
         Pool_add { name; route; budget = Some budget }
       | _ ->
         Invalid
           "/pool add: BUDGET must be a non-negative integer (tokens per day)")
    | _ ->
      Invalid
        "/pool add expects: /pool add NAME ROUTE [BUDGET], e.g. /pool add pool-01 \
         claude-haiku 5000")
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_remove ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_remove + 1 in
    let payload =
      String.sub trimmed offset (String.length trimmed - offset) |> String.trim
    in
    let parts =
      String.split_on_char ' ' payload |> List.filter (fun s -> s <> "")
    in
    match parts with
    | [ name; route ] -> Pool_remove { name; route }
    | _ ->
      Invalid
        "/pool remove expects: /pool remove NAME ROUTE, e.g. /pool remove pool-01 \
         claude-haiku")
  else if String.starts_with
            ~prefix:(Starter_constants.Command.pool_global ^ " ")
            trimmed
  then (
    let offset = String.length Starter_constants.Command.pool_global + 1 in
    let value =
      String.sub trimmed offset (String.length trimmed - offset)
      |> String.trim
      |> String.lowercase_ascii
    in
    match value with
    | "on" | "true" | "yes" -> Pool_global_set true
    | "off" | "false" | "no" -> Pool_global_set false
    | _ -> Invalid "/pool global expects on or off")
  else if String.equal trimmed Starter_constants.Command.persona_list
       || String.equal trimmed Starter_constants.Command.persona
  then Persona_list
  else if String.equal trimmed Starter_constants.Command.env
  then Show_env
  else if String.equal trimmed Starter_constants.Command.files
  then Show_pending_files
  else if String.equal trimmed Starter_constants.Command.clearfiles
  then Clear_pending_files
  else if String.equal trimmed Starter_constants.Command.explore
  then Explore_path "."
  else if String.equal trimmed Starter_constants.Command.open_file
  then Invalid Starter_constants.Text.open_usage
  else if String.equal trimmed Starter_constants.Command.run
  then Invalid Starter_constants.Text.run_usage
  else if String.equal trimmed Starter_constants.Command.quit
  then Quit
  else if String.equal trimmed Starter_constants.Command.thread
  then Invalid Starter_constants.Text.thread_usage
  else if String.equal trimmed Starter_constants.Command.swap
  then Invalid Starter_constants.Text.swap_usage
  else if String.equal trimmed Starter_constants.Command.file
  then Invalid Starter_constants.Text.file_usage
  else if String.equal trimmed Starter_constants.Command.admin
  then Invalid Starter_constants.Text.admin_usage
  else if String.starts_with ~prefix:admin_prefix trimmed
  then
    let offset = String.length admin_prefix in
    let goal = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if goal = "" then Invalid Starter_constants.Text.admin_usage else Admin_request goal
  else if String.starts_with ~prefix:thread_prefix trimmed
  then (
    let offset = String.length thread_prefix in
    match String.sub trimmed offset (String.length trimmed - offset) |> String.trim |> String.lowercase_ascii with
    | "on" -> Set_thread true
    | "off" -> Set_thread false
    | _ -> Invalid Starter_constants.Text.thread_usage)
  else if String.starts_with ~prefix:swap_prefix trimmed
  then
    let offset = String.length swap_prefix in
    let model = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if model = "" then Invalid Starter_constants.Text.swap_usage else Swap_model model
  else if String.starts_with ~prefix:memory_replace_prefix trimmed
  then
    let offset = String.length memory_replace_prefix in
    let summary = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if summary = ""
    then Invalid Starter_constants.Text.memory_replace_usage
    else Replace_memory summary
  else if String.starts_with ~prefix:file_prefix trimmed
  then
    let offset = String.length file_prefix in
    let path = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if path = "" then Invalid Starter_constants.Text.file_usage else Attach_file path
  else if String.starts_with ~prefix:explore_prefix trimmed
  then
    let offset = String.length explore_prefix in
    let path = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if path = "" then Explore_path "." else Explore_path path
  else if String.starts_with ~prefix:open_prefix trimmed
  then
    let offset = String.length open_prefix in
    let path = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if path = "" then Invalid Starter_constants.Text.open_usage else Open_path path
  else if String.starts_with ~prefix:run_prefix trimmed
  then
    let offset = String.length run_prefix in
    let command = String.sub trimmed offset (String.length trimmed - offset) |> String.trim in
    if command = "" then Invalid Starter_constants.Text.run_usage else Run_command command
  else Prompt trimmed
;;

let step state input =
  match state, parse_command input with
  | Closed, _ -> Closed, Noop
  | Streaming context, _ ->
    Streaming context, Print_message Starter_constants.Text.busy_message
  | Ready context, Empty -> Ready context, Noop
  | Ready context, Help -> Ready context, Show_help
  | Ready context, Show_tools -> Ready context, Show_tools_panel
  | Ready context, Show_control_plane -> Ready context, Show_control_plane_status
  | Ready context, Admin_request goal -> Streaming context, Begin_admin_request goal
  | Ready context, Package_request -> Streaming context, Begin_package_request
  | Ready context, Show_admin_plan -> Ready context, Show_pending_admin_plan
  | Ready context, Apply_admin_plan -> Ready context, Execute_pending_admin_plan
  | Ready context, Discard_admin_plan -> Ready context, Drop_pending_admin_plan
  | Ready context, Show_config -> Ready context, Show_config_path context.config_path
  | Ready context, Choose_model -> Ready context, Select_model
  | Ready context, Show_models -> Ready context, List_models
  | Ready context, Show_memory -> Ready context, Show_memory_status
  | Ready context, Replace_memory summary -> Ready context, Substitute_memory summary
  | Ready context, Forget_memory -> Ready context, Reset_memory
  | Ready context, Show_providers -> Ready context, List_providers
  | Ready context, Discover_provider_models ->
    Ready context, List_discovered_models
  | Ready context, Refresh_provider_models ->
    Ready context, Refresh_discovered_models
  | Ready context, Show_env -> Ready context, List_env
  | Ready context, Pool_list -> Ready context, Show_pool_list
  | Ready context, Pool_show name -> Ready context, Show_pool name
  | Ready context, Pool_create name -> Ready context, Create_pool name
  | Ready context, Pool_drop name -> Ready context, Drop_pool name
  | Ready context, Pool_add { name; route; budget } ->
    Ready context, Add_pool_member { name; route; budget }
  | Ready context, Pool_remove { name; route } ->
    Ready context, Remove_pool_member { name; route }
  | Ready context, Pool_global_set enabled -> Ready context, Set_global_pool enabled
  | Ready context, Persona_list -> Ready context, Show_persona_list
  | Ready context, Attach_file path -> Ready context, Attach_local_file path
  | Ready context, Show_pending_files -> Ready context, List_pending_files
  | Ready context, Clear_pending_files -> Ready context, Reset_pending_files
  | Ready context, Explore_path path -> Ready context, Explore_local_path path
  | Ready context, Open_path path -> Ready context, Open_local_path path
  | Ready context, Run_command command -> Ready context, Run_local_command command
  | Ready context, Set_thread enabled ->
    Ready { context with conversation_enabled = enabled }, Update_thread enabled
  | Ready _, Quit -> Closed, Exit
  | Ready context, Swap_model model -> Ready context, Attempt_swap model
  | Ready context, Prompt prompt -> Streaming context, Begin_prompt prompt
  | Ready context, Invalid message -> Ready context, Print_message message
;;

let set_model state model =
  match state with
  | Ready context -> Ready { context with model }
  | Streaming context -> Streaming { context with model }
  | Closed -> Closed
;;

let finish_stream = function
  | Streaming context -> Ready context
  | state -> state
;;

let interrupt_stream = finish_stream
