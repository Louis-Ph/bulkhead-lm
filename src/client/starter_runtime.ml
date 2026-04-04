type t =
  { conversation : Starter_conversation.t
  ; pending_admin_plan : Admin_assistant.pending_plan option
  ; pending_attachments : Starter_attachment.t list
  }

let create () =
  { conversation = Starter_conversation.empty
  ; pending_admin_plan = None
  ; pending_attachments = []
  }
;;

let clear_conversation runtime =
  { runtime with conversation = Starter_conversation.clear () }
;;

let update_conversation runtime conversation = { runtime with conversation }
let set_pending_admin_plan runtime pending_admin_plan = { runtime with pending_admin_plan }
let clear_pending_admin_plan runtime = { runtime with pending_admin_plan = None }
let set_pending_attachments runtime pending_attachments = { runtime with pending_attachments }
let clear_pending_attachments runtime = { runtime with pending_attachments = [] }
