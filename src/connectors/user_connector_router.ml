type matched_connector = User_connector_registry.matched_connector

let find = User_connector_registry.find

let handle store req body = function
  | User_connector_registry.Telegram connector ->
    Telegram_connector.handle_webhook store req body connector
  | User_connector_registry.Whatsapp connector ->
    Whatsapp_connector.handle_webhook store req body connector
  | User_connector_registry.Messenger connector ->
    Messenger_connector.handle_webhook store req body connector
  | User_connector_registry.Instagram connector ->
    Instagram_connector.handle_webhook store req body connector
  | User_connector_registry.Line connector ->
    Line_connector.handle_webhook store req body connector
  | User_connector_registry.Viber connector ->
    Viber_connector.handle_webhook store req body connector
  | User_connector_registry.Wechat connector ->
    Wechat_connector.handle_webhook store req body connector
  | User_connector_registry.Discord connector ->
    Discord_connector.handle_webhook store req body connector
  | User_connector_registry.Google_chat connector ->
    Google_chat_connector.handle_webhook store req body connector
;;
