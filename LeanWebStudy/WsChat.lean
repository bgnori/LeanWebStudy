import Ws.Message
import Ws.Transport.Http1
import Ws.Transport.Plain
import LeanWebStudy.Chat

namespace LeanWebStudy.WsChat

open Std.Async
open Ws

private structure Subscriber where
  id : Nat
  queue : Std.CloseableChannel String
  overflow : IO.Promise Unit

private structure State where
  nextId : UInt64 := 1
  nextSubscriber : Nat := 1
  active : Nat := 0
  history : Array Lean.Json := #[]
  subscribers : Array Subscriber := #[]

structure Server where
  listener : TCP.Socket.Server
  port : UInt16
  httpPort : UInt16
  private state : Std.Mutex State

def openServer (httpPort : UInt16) : IO Server := do
  let listener ← TCP.Socket.Server.mk
  listener.bind (.v4 { addr := Std.Net.IPv4Addr.ofParts 127 0 0 1, port := 0 })
  listener.listen 64
  listener.noDelay
  let address ← listener.getSockName
  let port := match address with
    | .v4 address => address.port
    | .v6 address => address.port
  return { listener, port, httpPort, state := ← Std.Mutex.new {} }

private def limits : Limits := {
  maxHandshakeBytes := 16384
  maxStartLineBytes := 4096
  maxHeaderCount := 32
  maxHeaderValueBytes := 4096
  maxFramePayloadBytes := 8192
  maxMessagePayloadBytes := 8192 }

private def enqueue (subscriber : Subscriber) (text : String) : IO Unit := do
  unless ← subscriber.queue.trySend text do
    discard <| subscriber.overflow.resolve ()

private def subscribe (server : Server) : IO Subscriber := do
  let queue ← Std.CloseableChannel.new (some 64)
  let overflow ← IO.Promise.new
  server.state.atomically do
    let state ← get
    let subscriber := { id := state.nextSubscriber, queue, overflow }
    enqueue subscriber (Lean.Json.mkObj [
      ("type", Lean.toJson ("history" : String)),
      ("messages", .arr state.history)]).compress
    set { state with
      nextSubscriber := state.nextSubscriber + 1
      subscribers := state.subscribers.push subscriber }
    return subscriber

private def publish (server : Server) (sender : Subscriber) (bytes : ByteArray) : IO Unit := do
  server.state.atomically do
    let state ← get
    let (valid, text) := Chat.response state.nextId bytes
    if valid then
      let json ← match Lean.Json.parse text with
        | .ok json => pure json
        | .error error => throw (IO.userError error)
      let history := (state.history.push json).extract
        (if state.history.size >= 50 then 1 else 0) (state.history.size + 1)
      for subscriber in state.subscribers do enqueue subscriber text
      set { state with nextId := state.nextId + 1, history }
    else
      IO.eprintln s!"ws-lean chat: invalid input: {text}"
      enqueue sender text

private def within (stream : Transport.ByteStream) (milliseconds : Nat)
    (action : Async α) : Async α := do
  let task ← Async.toIO action
  let deadline := (← IO.monoMsNow) + milliseconds
  while !(← IO.hasFinished task) && (← IO.monoMsNow) < deadline do sleep 10
  unless ← IO.hasFinished task do
    stream.abort
  Async.ofAsyncTask task

private def sendFrame (stream : Transport.ByteStream) (frame : Frame.Frame) : Async Unit := do
  let bytes ← match Frame.encode .server none frame with
    | .ok bytes => pure bytes
    | .error error => throw (IO.userError error.message)
  match ← within stream 5000 (stream.send bytes) with
  | .ok _ => pure ()
  | .error error => throw (IO.userError error.message)

private def closeFrame (code : CloseCode) : Frame.Frame :=
  match Message.Close.create .server (some code) >>= Message.Close.payload .server with
  | .ok payload => { opcode := .close, payload }
  | .error _ => { opcode := .close }

private def receiveLoop (server : Server) (stream : Transport.ByteStream)
    (subscriber : Subscriber) (controls : Std.CloseableChannel Frame.Frame)
  (lastSeen : IO.Ref Nat) (closing : IO.Ref Bool) : Async Unit := do
  let mut frames := Frame.Decoder.new .server limits
  let mut messages := Message.Decoder.new .server limits
  let mut running := true
  while running do
    match ← stream.recv? with
    | .ok (some bytes) =>
      let batch := frames.feedBatch bytes
      frames := batch.decoder
      for frame in batch.frames do
        if !running then break
        match messages.feed frame with
        | .error error =>
          discard <| controls.trySend (closeFrame (error.closeCode?.getD .protocolError))
          running := false
        | .ok (next, events) =>
          messages := next
          lastSeen.set (← IO.monoMsNow)
          for event in events do
            match event with
            | .message message =>
              match message.kind with
              | .text => unless ← closing.get do publish server subscriber message.data
              | .binary =>
                discard <| controls.trySend (closeFrame .unsupportedData)
                running := false
            | .ping payload =>
              unless ← controls.trySend { opcode := .pong, payload } do
                discard <| subscriber.overflow.resolve ()
                running := false
            | .pong _ => pure ()
            | .close close =>
              let payload ← match close.payload .server with
                | .ok payload => pure payload
                | .error error => throw (IO.userError error.message)
              discard <| controls.trySend { opcode := .close, payload }
              running := false
      if running then
        if let some error := batch.error? then
          discard <| controls.trySend (closeFrame (error.closeCode?.getD .protocolError))
          running := false
    | _ => running := false

private def sendLoop (stream : Transport.ByteStream) (subscriber : Subscriber)
    (controls : Std.CloseableChannel Frame.Frame) (lastSeen : IO.Ref Nat)
    (readerDone closing : IO.Ref Bool) : Async Unit := do
  let finishClose := fun frame => do
    closing.set true
    sendFrame stream frame
    let deadline := (← IO.monoMsNow) + 1000
    while !(← readerDone.get) && (← IO.monoMsNow) < deadline do sleep 10
  let mut lastPing ← IO.monoMsNow
  let mut running := true
  while running do
    if ← IO.hasFinished subscriber.overflow.result? then
      IO.eprintln "ws-lean chat: slow subscriber"
      finishClose (closeFrame .policyViolation)
      running := false
    else if let some frame ← controls.tryRecv then
      if frame.opcode == .close then
        finishClose frame
        running := false
      else sendFrame stream frame
    else if ← readerDone.get then
      running := false
    else
      let now ← IO.monoMsNow
      if now - (← lastSeen.get) >= 30000 then
        finishClose (closeFrame .goingAway)
        running := false
      else if now - lastPing >= 20000 then
        sendFrame stream { opcode := .ping }
        lastPing := now
      else if let some text ← subscriber.queue.tryRecv then
        sendFrame stream { opcode := .text, payload := text.toUTF8 }
      else sleep 10

private def application (server : Server) (stream : Transport.ByteStream) : Async Unit := do
  let subscriber ← subscribe server
  let controls ← Std.CloseableChannel.new (some 64)
  let lastSeen ← IO.mkRef (← IO.monoMsNow)
  let readerDone ← IO.mkRef false
  let closing ← IO.mkRef false
  let mut reader? : Option (AsyncTask Unit) := none
  try
    if let some history ← subscriber.queue.tryRecv then
      sendFrame stream { opcode := .text, payload := history.toUTF8 }
    reader? := some (← Async.toIO do
      try receiveLoop server stream subscriber controls lastSeen closing
      finally readerDone.set true)
    sendLoop stream subscriber controls lastSeen readerDone closing
  finally
    server.state.atomically do
      modify fun state => { state with
        subscribers := state.subscribers.filter (·.id != subscriber.id) }
    discard <| subscriber.queue.close
    discard <| controls.close
    stream.abort
    if let some reader := reader? then Async.ofAsyncTask reader

private def reject (stream : Transport.ByteStream) : Async Unit := do
  discard <| within stream 5000 (stream.send
    "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toUTF8)

private def upgrade (server : Server) (stream : Transport.ByteStream) :
    Async (Option Transport.ByteStream) := do
  match ← Transport.Http1.receiveUpgrade stream limits with
  | .error _ => reject stream; return none
  | .ok (request, upgraded) =>
    let originAllowed := request.origin? == some s!"http://127.0.0.1:{server.httpPort}" ||
      request.origin? == some s!"http://localhost:{server.httpPort}"
    let protocol := request.subprotocols.find? (·.value == "leanwebstudy-chat")
    unless request.target == "/chat-ws/socket" && originAllowed && protocol.isSome do
      reject stream
      return none
    match ← Transport.Http1.acceptUpgrade upgraded request { subprotocol? := protocol } with
    | .ok _ => return some upgraded
    | .error _ => return none

private def handle (server : Server) (stream : Transport.ByteStream) : Async Unit := do
  try
    let upgraded? ← within stream 10000 (upgrade server stream)
    if let some upgraded := upgraded? then
      application server upgraded
  catch error =>
    IO.eprintln s!"ws-lean chat: {error}"
  finally
    stream.abort
    stream.retire
    server.state.atomically do modify fun state => { state with active := state.active - 1 }

def run (server : Server) : Async Unit := do
  let mut tasks : Array (AsyncTask Unit) := #[]
  while true do
    let socket ← server.listener.accept
    let stream ← Transport.Plain.ofSocket socket
    let admitted ← server.state.atomically do
      let state ← get
      if state.active >= 64 then return false
      set { state with active := state.active + 1 }
      return true
    if admitted then
      let mut remaining := #[]
      for task in tasks do
        if ← IO.hasFinished task then
          Async.ofAsyncTask task
        else remaining := remaining.push task
      tasks := remaining.push (← Async.toIO (handle server stream))
    else
      stream.abort
      stream.retire

end LeanWebStudy.WsChat
