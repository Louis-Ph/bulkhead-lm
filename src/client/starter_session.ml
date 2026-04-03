type command =
  | Empty
  | Help
  | Show_config
  | Choose_model
  | Show_models
  | Show_memory
  | Forget_memory
  | Show_providers
  | Show_env
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
  | Show_config_path of string
  | Select_model
  | List_models
  | Show_memory_status
  | Reset_memory
  | List_providers
  | List_env
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
  let swap_prefix = Starter_constants.Command.swap ^ " " in
  let thread_prefix = Starter_constants.Command.thread ^ " " in
  if trimmed = ""
  then Empty
  else if String.equal trimmed Starter_constants.Command.help
  then Help
  else if String.equal trimmed Starter_constants.Command.config
  then Show_config
  else if String.equal trimmed Starter_constants.Command.model
  then Choose_model
  else if String.equal trimmed Starter_constants.Command.models
  then Show_models
  else if String.equal trimmed Starter_constants.Command.memory
  then Show_memory
  else if String.equal trimmed Starter_constants.Command.forget
  then Forget_memory
  else if String.equal trimmed Starter_constants.Command.providers
  then Show_providers
  else if String.equal trimmed Starter_constants.Command.env
  then Show_env
  else if String.equal trimmed Starter_constants.Command.quit
  then Quit
  else if String.equal trimmed Starter_constants.Command.thread
  then Invalid Starter_constants.Text.thread_usage
  else if String.equal trimmed Starter_constants.Command.swap
  then Invalid Starter_constants.Text.swap_usage
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
  else Prompt trimmed
;;

let step state input =
  match state, parse_command input with
  | Closed, _ -> Closed, Noop
  | Streaming context, _ ->
    Streaming context, Print_message Starter_constants.Text.busy_message
  | Ready context, Empty -> Ready context, Noop
  | Ready context, Help -> Ready context, Show_help
  | Ready context, Show_config -> Ready context, Show_config_path context.config_path
  | Ready context, Choose_model -> Ready context, Select_model
  | Ready context, Show_models -> Ready context, List_models
  | Ready context, Show_memory -> Ready context, Show_memory_status
  | Ready context, Forget_memory -> Ready context, Reset_memory
  | Ready context, Show_providers -> Ready context, List_providers
  | Ready context, Show_env -> Ready context, List_env
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
