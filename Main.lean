import LeanWebStudy

def main (args : List String) : IO Unit := do
  let (portArgs, directory) <- match args with
    | ["--dev"] => pure ([], some "Pages")
    | ["--dev", directory] => pure ([], some directory)
    | [port, "--dev"] => pure ([port], some "Pages")
    | [port, "--dev", directory] => pure ([port], some directory)
    | args => pure (args, none)
  let port <- match portArgs with
    | [] => pure 8080
    | [value] =>
      match value.toNat? with
      | some port =>
        if port > 0 && port <= 65535 then pure port
        else throw (IO.userError "Port must be between 1 and 65535")
      | none => throw (IO.userError "Port must be an integer")
    | _ => throw (IO.userError "Usage: leanwebstudy [port] [--dev [page-directory]]")
  let pages <- LeanWebStudy.DevPages.open (directory.getD "Pages")
  let counter <- Std.Mutex.new 0
  let database <- Std.Mutex.new (← LeanWebStudy.Database.seededMemory)
  let orderBook <- Std.Mutex.new LeanWebStudy.OrderBook.initial
  let sseChat <- LeanWebStudy.SSEChat.new
  let chat ← LeanWebStudy.Chat.openServer port.toUInt16
    LeanWebStudy.Chat.response LeanWebStudy.Pong.response
  let chatPort ← LeanWebStudy.Chat.port chat
  let wsChat ← LeanWebStudy.WsChat.openServer port.toUInt16
  let handler := LeanWebStudy.WebHandler.create counter database orderBook pages sseChat
    port.toUInt16 chatPort wsChat.port
  Std.Async.Async.block do
    let server <- Std.Http.Server.serveUpgradable
      (.v4 { addr := Std.Net.IPv4Addr.ofParts 127 0 0 1, port := port.toUInt16 })
      handler
    IO.println s!"Listening on http://127.0.0.1:{port}"
    IO.println s!"Pages: {pages.directory} (reloaded per request)"
    IO.println s!"WebSocket chat: ws://127.0.0.1:{chatPort}/chat/socket"
    IO.println s!"ws-lean chat: ws://127.0.0.1:{wsChat.port}/chat-ws/socket"
    IO.println s!"WebSocket Pong: ws://127.0.0.1:{chatPort}/pong/socket"
    IO.println s!"SSE chat: http://127.0.0.1:{port}/chat-sse/"
    IO.println s!"WebSocket echo (same port, StdExt upgrade API): ws://127.0.0.1:{port}/ws-echo/socket"
    discard <| Std.Async.Async.concurrently server.waitShutdown
      (Std.Async.Async.concurrently (LeanWebStudy.WsChat.run wsChat)
        (Std.Async.Async.ofAsyncTask (← IO.asTask (prio := .dedicated)
          (LeanWebStudy.Chat.run chat))))
