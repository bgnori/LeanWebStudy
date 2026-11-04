import LeanWebStudy.Chat
import Std.Async
import Std.Sync.Mutex
import StdExt

namespace LeanWebStudy.SamePortChat

open Std.Async
open Std.Http.WebSocket

private structure Subscriber where
  id : Nat
  queue : Std.CloseableChannel String
  overflow : IO.Ref Bool

private structure State where
  nextId : UInt64 := 1
  nextSubscriber : Nat := 1
  history : Array Lean.Json := #[]
  subscribers : Array Subscriber := #[]

structure Server where
  private state : Std.Mutex State

def new : IO Server :=
  return { state := ← Std.Mutex.new {} }

private def enqueue (subscriber : Subscriber) (text : String) : IO Unit := do
  unless ← subscriber.queue.trySend text do
    subscriber.overflow.set true

private def subscribe (server : Server) : IO (Option Subscriber) := do
  let queue ← Std.CloseableChannel.new (some 64)
  let overflow ← IO.mkRef false
  server.state.atomically do
    let state ← get
    if state.subscribers.size >= 64 then
      return none
    let subscriber := { id := state.nextSubscriber, queue, overflow }
    let history := (Lean.Json.mkObj [
      ("type", Lean.toJson ("history" : String)),
      ("messages", .arr state.history)]).compress
    enqueue subscriber history
    set { state with
      nextSubscriber := state.nextSubscriber + 1
      subscribers := state.subscribers.push subscriber }
    return some subscriber

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
      IO.eprintln s!"same-port chat: invalid input: {text}"
      enqueue sender text

private def receiveLoop (server : Server) (socket : WebSocket)
    (subscriber : Subscriber) : Async Unit := do
  let mut running := true
  while running do
    match ← socket.recv with
    | some (.text content) => publish server subscriber content.toUTF8
    | some (.binary _) =>
      socket.close 1003 "binary messages are not supported"
      running := false
    | none => running := false

def serveConnection (server : Server) (socket : WebSocket) : Async Unit := do
  match ← subscribe server with
  | none =>
    socket.close 1013 "too many chat clients"
  | some subscriber =>
    let readerDone ← IO.mkRef false
    try
      if let some history ← subscriber.queue.tryRecv then
        socket.sendText history
      let _reader ← Async.toIO do
        try
          receiveLoop server socket subscriber
        catch error =>
          IO.eprintln s!"same-port chat receive failed: {error}"
        finally
          readerDone.set true
      let mut running := true
      while running do
        if ← subscriber.overflow.get then
          IO.eprintln "same-port chat: slow subscriber"
          socket.close 1008 "slow subscriber"
          running := false
        else if ← readerDone.get then
          running := false
        else if let some text ← subscriber.queue.tryRecv then
          socket.sendText text
        else
          sleep 10
    finally
      server.state.atomically do
        modify fun state => {
          state with subscribers := state.subscribers.filter (·.id != subscriber.id) }
      discard <| subscriber.queue.close

end LeanWebStudy.SamePortChat
