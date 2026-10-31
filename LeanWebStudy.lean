import MapleSQL
import Lean.Data.Json
import Std.Http.Server
import Std.Sync.Mutex

namespace LeanWebStudy

open Std.Http

def sampleQuery (requestId : Nat) : Except String MapleSQL.Formatted :=
  MapleSQL.render (.select #[.all] "users"
    (some (.greaterThan (.column "id") (.parameter (.integer (Int.ofNat requestId))))))

def valueJson : MapleSQL.Value -> Lean.Json
  | .text value => Lean.toJson value
  | .integer value => Lean.toJson value

def queryJson (requestId : Nat) : Except String Lean.Json := do
  let formatted <- sampleQuery requestId
  pure (Lean.Json.mkObj [
    ("requestId", Lean.toJson requestId),
    ("sql", Lean.toJson formatted.sql),
    ("params", .arr (formatted.params.map valueJson))])

structure WebHandler where
  counter : Std.Mutex Nat

def WebHandler.nextRequestId (self : WebHandler) : IO Nat :=
  self.counter.atomically do
    modify (fun n => n + 1)
    get

instance : Server.Handler WebHandler where
  ResponseBody := Body.Full
  onRequest self request := do
    if request.line.method != .get then
      return <- (Response.withStatus .methodNotAllowed
        |>.header! "Allow" "GET").text "Only GET is supported\n"
    match toString request.line.uri.path with
    | "/" =>
      let requestId <- self.nextRequestId
      return <- (Response.ok.header! "Cache-Control" "no-store").html
        ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
          "<title>LeanWebStudy</title></head><body><h1>LeanWebStudy</h1>" ++
          s!"<p>Dynamic page request: {requestId}</p>" ++
          "<p><a href=\"/api/query\">Generate a parameterized SQL query</a></p>" ++
          "</body></html>")
    | "/health" =>
      return <- Response.ok.json "{\"status\":\"ok\"}"
    | "/api/query" =>
      let requestId <- self.nextRequestId
      match queryJson requestId with
      | .ok json =>
        return <- (Response.ok.header! "Cache-Control" "no-store").json json.compress
      | .error error =>
        IO.eprintln s!"SQL generation failed: {error}"
        return <- Response.internalServerError.text "SQL generation failed\n"
    | _ =>
      return <- Response.notFound.text "Not found\n"
  onFailure _ error := IO.eprintln s!"HTTP transport failure: {error}"

end LeanWebStudy
