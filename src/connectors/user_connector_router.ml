type matched_connector =
  | Telegram of Config.telegram_connector
  | Whatsapp of Config.whatsapp_connector
  | Messenger of Config.messenger_connector
  | Instagram of Config.instagram_connector
  | Line of Config.line_connector
  | Viber of Config.viber_connector
  | Wechat of Config.wechat_connector
  | Google_chat of Config.google_chat_connector

let find (config : Config.t) ~path =
  match Telegram_connector.find_webhook_config config ~path with
  | Some connector -> Some (Telegram connector)
  | None ->
    (match Whatsapp_connector.find_webhook_config config ~path with
     | Some connector -> Some (Whatsapp connector)
     | None ->
       (match Messenger_connector.find_webhook_config config ~path with
        | Some connector -> Some (Messenger connector)
        | None ->
          (match Instagram_connector.find_webhook_config config ~path with
           | Some connector -> Some (Instagram connector)
           | None ->
             (match Line_connector.find_webhook_config config ~path with
              | Some connector -> Some (Line connector)
              | None ->
                (match Viber_connector.find_webhook_config config ~path with
                 | Some connector -> Some (Viber connector)
                 | None ->
                   (match Wechat_connector.find_webhook_config config ~path with
                    | Some connector -> Some (Wechat connector)
                    | None ->
                      Option.map
                        (fun connector -> Google_chat connector)
                        (Google_chat_connector.find_webhook_config config ~path)))))))
;;

let handle store req body = function
  | Telegram connector -> Telegram_connector.handle_webhook store req body connector
  | Whatsapp connector -> Whatsapp_connector.handle_webhook store req body connector
  | Messenger connector -> Messenger_connector.handle_webhook store req body connector
  | Instagram connector -> Instagram_connector.handle_webhook store req body connector
  | Line connector -> Line_connector.handle_webhook store req body connector
  | Viber connector -> Viber_connector.handle_webhook store req body connector
  | Wechat connector -> Wechat_connector.handle_webhook store req body connector
  | Google_chat connector -> Google_chat_connector.handle_webhook store req body connector
;;
