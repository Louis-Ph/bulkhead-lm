type runtime_class =
  | Webhook_outbound_api_reply
  | Webhook_inline_reply
  | Deferred_interaction

type matched_connector =
  | Telegram of Config.telegram_connector
  | Whatsapp of Config.whatsapp_connector
  | Messenger of Config.messenger_connector
  | Instagram of Config.instagram_connector
  | Line of Config.line_connector
  | Viber of Config.viber_connector
  | Wechat of Config.wechat_connector
  | Discord of Config.discord_connector
  | Google_chat of Config.google_chat_connector

type descriptor =
  { connector_id : string
  ; wave : int
  ; runtime_class : runtime_class
  ; find : Config.t -> path:string -> matched_connector option
  }

let runtime_class_label = function
  | Webhook_outbound_api_reply -> "webhook-outbound-api-reply"
  | Webhook_inline_reply -> "webhook-inline-reply"
  | Deferred_interaction -> "deferred-interaction"
;;

let connector_id = function
  | Telegram _ -> "telegram"
  | Whatsapp _ -> "whatsapp"
  | Messenger _ -> "messenger"
  | Instagram _ -> "instagram"
  | Line _ -> "line"
  | Viber _ -> "viber"
  | Wechat _ -> "wechat"
  | Discord _ -> "discord"
  | Google_chat _ -> "google_chat"
;;

let runtime_class = function
  | Telegram _
  | Whatsapp _
  | Messenger _
  | Instagram _
  | Line _
  | Viber _ -> Webhook_outbound_api_reply
  | Wechat _ | Google_chat _ -> Webhook_inline_reply
  | Discord _ -> Deferred_interaction
;;

let descriptor ~connector_id ~wave ~runtime_class find =
  { connector_id; wave; runtime_class; find }
;;

let descriptors =
  [ descriptor
      ~connector_id:"telegram"
      ~wave:1
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Telegram connector)
          (Telegram_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"whatsapp"
      ~wave:1
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Whatsapp connector)
          (Whatsapp_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"messenger"
      ~wave:1
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Messenger connector)
          (Messenger_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"instagram"
      ~wave:1
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Instagram connector)
          (Instagram_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"line"
      ~wave:2
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Line connector)
          (Line_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"viber"
      ~wave:2
      ~runtime_class:Webhook_outbound_api_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Viber connector)
          (Viber_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"wechat"
      ~wave:2
      ~runtime_class:Webhook_inline_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Wechat connector)
          (Wechat_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"discord"
      ~wave:3
      ~runtime_class:Deferred_interaction
      (fun config ~path ->
        Option.map
          (fun connector -> Discord connector)
          (Discord_connector.find_webhook_config config ~path))
  ; descriptor
      ~connector_id:"google_chat"
      ~wave:1
      ~runtime_class:Webhook_inline_reply
      (fun config ~path ->
        Option.map
          (fun connector -> Google_chat connector)
          (Google_chat_connector.find_webhook_config config ~path))
  ]
;;

let find config ~path = List.find_map (fun item -> item.find config ~path) descriptors
