import Lean.Data.Json

namespace LeanWebStudy.Chat

private def decode (bytes : ByteArray) : Except String (String × String × String) := do
  let some text := String.fromUTF8? bytes
    | throw "UTF-8 のテキストを送信してください。"
  let json ← Lean.Json.parse text
  let kind ← json.getObjValAs? String "type"
  unless kind == "message" do throw "type は message を指定してください。"
  let author := (← json.getObjValAs? String "author").trimAscii.toString
  let message := (← json.getObjValAs? String "message").trimAscii.toString
  let requestId ← json.getObjValAs? String "requestId"
  unless !requestId.isEmpty && requestId.length <= 64 do
    throw "requestId は 1〜64 文字で指定してください。"
  unless !author.isEmpty && author.length <= 24 do
    throw "名前は 1〜24 文字で入力してください。"
  unless !message.isEmpty && message.length <= 500 do
    throw "メッセージは 1〜500 文字で入力してください。"
  return (author, message, requestId)

def response (id : UInt64) (bytes : ByteArray) : Bool × String :=
  match decode bytes with
  | .ok (author, message, requestId) =>
    (true, (Lean.Json.mkObj [
      ("type", Lean.toJson ("message" : String)), ("id", Lean.toJson id.toNat),
      ("author", Lean.toJson author), ("message", Lean.toJson message),
      ("requestId", Lean.toJson requestId)]).compress)
  | .error error =>
    (false, (Lean.Json.mkObj [
      ("type", Lean.toJson ("error" : String)), ("message", Lean.toJson error)]).compress)

private opaque ServerImpl : NonemptyType
def Server : Type := ServerImpl.type
instance : Nonempty Server := ServerImpl.property

@[extern "leanwebstudy_chat_open"]
opaque openServer
    (httpPort : UInt16)
    (chatHandler : UInt64 → ByteArray → Bool × String)
    (pongHandler : UInt64 → ByteArray → Bool × String) : IO Server

@[extern "leanwebstudy_chat_port"]
opaque port (server : @& Server) : IO UInt16

@[extern "leanwebstudy_chat_service"]
opaque service (server : @& Server) : IO Unit

def run (server : Server) : IO Unit := do
  while true do
    service server

end LeanWebStudy.Chat
