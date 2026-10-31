import Lean.Data.Json
import Lithe.Http.BodyStream
import Lithe.Http.SSE
import Lithe.Runtime.StreamQueue
import Std.Sync.Mutex

namespace LeanWebStudy.SSEChat

open Lithe

private structure Message where
  id : Nat
  author : String
  message : String
  requestId : String

private structure Subscriber where
  id : Nat
  writer : BodyWriter

private structure State where
  nextMessageId : Nat := 1
  nextSubscriberId : Nat := 1
  history : Array Message := #[]
  subscribers : Array Subscriber := #[]

structure Server where
  state : Std.Mutex State

def new : IO Server := do
  return { state := ← Std.Mutex.new {} }

private def validate (author message requestId : String) : Except String Unit := do
  let author := author.trimAscii.toString
  let message := message.trimAscii.toString
  unless !requestId.isEmpty && requestId.length <= 64 do
    throw "requestId は 1〜64 文字で指定してください。"
  unless !author.isEmpty && author.length <= 24 do
    throw "名前は 1〜24 文字で入力してください。"
  unless !message.isEmpty && message.length <= 500 do
    throw "メッセージは 1〜500 文字で入力してください。"

private def messageBytes (message : Message) : ByteArray :=
  SSEEvent.toBytes <| SSEEvent.ofData
    ((Lean.Json.mkObj [
      ("type", Lean.toJson ("message" : String)),
      ("id", Lean.toJson message.id),
      ("author", Lean.toJson message.author),
      ("message", Lean.toJson message.message),
      ("requestId", Lean.toJson message.requestId)]).compress)
    (id? := some (toString message.id))

private def historyBytes (state : State) : ByteArray :=
  let messages := state.history.map fun message =>
    Lean.Json.mkObj [
      ("id", Lean.toJson message.id),
      ("author", Lean.toJson message.author),
      ("message", Lean.toJson message.message),
      ("requestId", Lean.toJson message.requestId)]
  SSEEvent.toBytes <| SSEEvent.ofData
    ((Lean.Json.mkObj [
      ("type", Lean.toJson ("history" : String)),
      ("messages", Lean.Json.arr messages)]).compress)
    (id? := some (toString (state.nextMessageId - 1)))

def subscribe (server : Server) : IO (Option (Nat × BodyStream)) := do
  let queue ← StreamQueue.new 262144
  let queueMutex ← Std.Mutex.new queue
  let writer : BodyWriter := {
    push := fun chunk => do
      queueMutex.atomically do
        let queue ← get
        StreamQueue.push queue chunk
    close := queueMutex.atomically do
      let queue ← get
      StreamQueue.close queue
  }
  server.state.atomically do
    let state ← get
    if state.subscribers.size >= 64 then
      return none
    let id := state.nextSubscriberId
    match ← writer.push (historyBytes state) |>.run with
    | .ok true => pure ()
    | .ok false => throw (IO.userError "Could not queue SSE chat history")
    | .error error => throw (IO.userError s!"Could not queue SSE chat history: {error.message}")
    set { state with
      nextSubscriberId := id + 1
      subscribers := state.subscribers.push { id, writer } }
    let stream : BodyStream := {
      next := do
        let start ← IO.monoNanosNow
        let heartbeatAfter := start + 15_000_000_000
        let mut finished := false
        let mut result : Option ByteArray := none
        while !finished do
          let (chunk?, closed) ← queueMutex.atomically do
            let queue ← get
            let chunk? ← StreamQueue.pop? queue
            let closed ← StreamQueue.isClosed queue
            return (chunk?, closed)
          match chunk? with
          | some chunk =>
            result := some chunk
            finished := true
          | none =>
            if closed then
              finished := true
            else if (← IO.monoNanosNow) >= heartbeatAfter then
              result := some (SSEEvent.toBytes (SSEEvent.keepAlive))
              finished := true
            else
              let _ ← liftM (Std.Async.Async.block (Std.Async.sleep 100))
              pure ()
        pure result
    }
    return some (id, stream)

def unsubscribe (server : Server) (id : Nat) : IO Unit := do
  server.state.atomically do
    let state ← get
    let removed := state.subscribers.filter (·.id == id)
    let remaining := state.subscribers.filter (·.id != id)
    set { state with subscribers := remaining }
    for subscriber in removed do
      discard <| subscriber.writer.close.run

def publish (server : Server) (author message requestId : String) : IO (Except String Nat) := do
  match validate author message requestId with
  | .error error => return .error error
  | .ok () =>
    server.state.atomically do
      let state ← get
      let message : Message := {
        id := state.nextMessageId
        author := author.trimAscii.toString
        message := message.trimAscii.toString
        requestId }
      let bytes := messageBytes message
      let mut subscribers := #[]
      for subscriber in state.subscribers do
        match ← subscriber.writer.push bytes |>.run with
        | .ok true => subscribers := subscribers.push subscriber
        | .ok false =>
          IO.eprintln s!"SSE chat: removing slow or closed subscriber {subscriber.id}"
          discard <| subscriber.writer.close.run
        | .error error =>
          IO.eprintln s!"SSE chat: failed to queue for subscriber {subscriber.id}: {error.message}"
          discard <| subscriber.writer.close.run
      let history := (state.history.push message).extract
        (if state.history.size >= 50 then 1 else 0)
        (state.history.size + 1)
      set { state with
        nextMessageId := state.nextMessageId + 1
        history
        subscribers }
      return .ok message.id

end LeanWebStudy.SSEChat
