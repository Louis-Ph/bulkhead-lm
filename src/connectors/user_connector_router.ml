type matched_connector =
  | Telegram of Config.telegram_connector
  | Whatsapp of Config.whatsapp_connector
  | Google_chat of Config.google_chat_connector

let find (config : Config.t) ~path =
  match Telegram_connector.find_webhook_config config ~path with
  | Some connector -> Some (Telegram connector)
  | None ->
    (match Whatsapp_connector.find_webhook_config config ~path with
     | Some connector -> Some (Whatsapp connector)
     | None ->
       Option.map
         (fun connector -> Google_chat connector)
         (Google_chat_connector.find_webhook_config config ~path))
;;

let handle store req body = function
  | Telegram connector -> Telegram_connector.handle_webhook store req body connector
  | Whatsapp connector -> Whatsapp_connector.handle_webhook store req body connector
  | Google_chat connector -> Google_chat_connector.handle_webhook store req body connector
