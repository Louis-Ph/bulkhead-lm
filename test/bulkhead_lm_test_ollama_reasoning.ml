open Lwt.Infix

let assoc_string name = function
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`String value) -> Some value
     | _ -> None)
  | _ -> None
;;

let chat_response_uses_reasoning_when_content_is_empty_test _switch () =
  let response_json =
    `Assoc
      [ "id", `String "chatcmpl-ollama"
      ; "created", `Int 1776266701
      ; "model", `String "qwen3:4b"
      ; ( "choices"
        , `List
            [ `Assoc
                [ "index", `Int 0
                ; ( "message"
                  , `Assoc
                      [ "role", `String "assistant"
                      ; "content", `String ""
                      ; "reasoning", `String "Feasible with a config-driven validator."
                      ] )
                ; "finish_reason", `String "stop"
                ]
            ] )
      ; ( "usage"
        , `Assoc
            [ "prompt_tokens", `Int 10
            ; "completion_tokens", `Int 20
            ; "total_tokens", `Int 30
            ] )
      ]
  in
  match Bulkhead_lm.Openai_types.chat_response_of_yojson response_json with
  | Error err -> Alcotest.failf "expected response parse success, got %s" err
  | Ok response ->
    let choice = List.hd response.Bulkhead_lm.Openai_types.choices in
    Alcotest.(check string)
      "reasoning promoted into visible content"
      "Feasible with a config-driven validator."
      choice.message.content;
    Lwt.return_unit
;;

let chat_response_uses_thinking_when_content_is_empty_test _switch () =
  let response_json =
    `Assoc
      [ "id", `String "chatcmpl-ollama"
      ; "created", `Int 1776266701
      ; "model", `String "qwen3:4b"
      ; ( "choices"
        , `List
            [ `Assoc
                [ "index", `Int 0
                ; ( "message"
                  , `Assoc
                      [ "role", `String "assistant"
                      ; "content", `String ""
                      ; "thinking", `String "A concise answer is ready."
                      ] )
                ; "finish_reason", `String "stop"
                ]
            ] )
      ; ( "usage"
        , `Assoc
            [ "prompt_tokens", `Int 10
            ; "completion_tokens", `Int 20
            ; "total_tokens", `Int 30
            ] )
      ]
  in
  match Bulkhead_lm.Openai_types.chat_response_of_yojson response_json with
  | Error err -> Alcotest.failf "expected response parse success, got %s" err
  | Ok response ->
    let choice = List.hd response.Bulkhead_lm.Openai_types.choices in
    Alcotest.(check string)
      "thinking promoted into visible content"
      "A concise answer is ready."
      choice.message.content;
    Lwt.return_unit
;;

let ollama_chat_request_body_disables_reasoning_test _switch () =
  let backend =
    Bulkhead_lm.Config_test_support.backend
      ~provider_id:"ollama-qwen"
      ~provider_kind:Bulkhead_lm.Config.Ollama_openai
      ~api_base:"http://127.0.0.1:11434/v1"
      ~upstream_model:"qwen3:4b"
      ~api_key_env:"OLLAMA_API_KEY"
      ()
  in
  let request : Bulkhead_lm.Openai_types.chat_request =
    { model = "qwen3-4b-local"
    ; messages = [ { role = "user"; content = "hello" } ]
    ; stream = false
    ; max_tokens = Some 128
    }
  in
  let body = Bulkhead_lm.Openai_compat_provider.chat_request_body backend request in
  Alcotest.(check (option string))
    "reasoning effort disabled for ollama"
    (Some "none")
    (assoc_string "reasoning_effort" body);
  Alcotest.(check (option string))
    "upstream model kept"
    (Some "qwen3:4b")
    (assoc_string "model" body);
  Lwt.return_unit
;;

let non_ollama_chat_request_body_keeps_default_shape_test _switch () =
  let backend =
    Bulkhead_lm.Config_test_support.backend
      ~provider_id:"openai-primary"
      ~provider_kind:Bulkhead_lm.Config.Openai_compat
      ~api_base:"https://api.example.test/v1"
      ~upstream_model:"gpt-5-mini"
      ~api_key_env:"OPENAI_API_KEY"
      ()
  in
  let request : Bulkhead_lm.Openai_types.chat_request =
    { model = "public-route"
    ; messages = [ { role = "user"; content = "hello" } ]
    ; stream = false
    ; max_tokens = Some 64
    }
  in
  let body = Bulkhead_lm.Openai_compat_provider.chat_request_body backend request in
  Alcotest.(check (option string))
    "no ollama-only override"
    None
    (assoc_string "reasoning_effort" body);
  Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case
      "chat response uses reasoning when content is empty"
      `Quick
      chat_response_uses_reasoning_when_content_is_empty_test
  ; Alcotest_lwt.test_case
      "chat response uses thinking when content is empty"
      `Quick
      chat_response_uses_thinking_when_content_is_empty_test
  ; Alcotest_lwt.test_case
      "ollama chat request disables reasoning"
      `Quick
      ollama_chat_request_body_disables_reasoning_test
  ; Alcotest_lwt.test_case
      "non ollama chat request keeps default shape"
      `Quick
      non_ollama_chat_request_body_keeps_default_shape_test
  ]
;;

let suite = "16.ollama-reasoning", tests
