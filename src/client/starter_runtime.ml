type t =
  { conversation : Starter_conversation.t
  }

let create () = { conversation = Starter_conversation.empty }
let clear_conversation _runtime = { conversation = Starter_conversation.clear () }

let update_conversation _runtime conversation = { conversation }
