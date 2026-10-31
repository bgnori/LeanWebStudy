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
  let chat ← LeanWebStudy.Chat.openServer port.toUInt16 LeanWebStudy.Chat.response
  let chatPort ← LeanWebStudy.Chat.port chat
  let handler := LeanWebStudy.WebHandler.create counter database pages chatPort
  Std.Async.Async.block do
    let server <- Std.Http.Server.serve
      (.v4 { addr := Std.Net.IPv4Addr.ofParts 127 0 0 1, port := port.toUInt16 })
      handler
    IO.println s!"Listening on http://127.0.0.1:{port}"
    IO.println s!"Pages: {pages.directory} (reloaded per request)"
    IO.println s!"Chat WebSocket: ws://127.0.0.1:{chatPort}/chat/socket"
    discard <| Std.Async.Async.concurrently server.waitShutdown
      (Std.Async.Async.ofAsyncTask (← IO.asTask (prio := .dedicated)
        (LeanWebStudy.Chat.run chat)))
