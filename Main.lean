import LeanWebStudy

def main (args : List String) : IO Unit := do
  let port <- match args with
    | [] => pure 8080
    | [value] =>
      match value.toNat? with
      | some port =>
        if port > 0 && port <= 65535 then pure port
        else throw (IO.userError "Port must be between 1 and 65535")
      | none => throw (IO.userError "Port must be an integer")
    | _ => throw (IO.userError "Usage: leanwebstudy [port]")
  let counter <- Std.Mutex.new 0
  Std.Async.Async.block do
    let server <- Std.Http.Server.serve
      (.v4 { addr := Std.Net.IPv4Addr.ofParts 127 0 0 1, port := port.toUInt16 })
      (LeanWebStudy.WebHandler.mk counter)
    IO.println s!"Listening on http://127.0.0.1:{port}"
    server.waitShutdown
