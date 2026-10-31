import MapleSQL
import Html
import LeanWebStudy.Database
import LeanWebStudy.DevPages
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
  database : Std.Mutex Database
  devPages : Option DevPages := none

def rowsJson (rows : Array (Array MapleSQL.Value)) : Lean.Json :=
  .arr (rows.map fun row => .arr (row.map valueJson))

def escapeHtml := Page.escapeHtml

def usersHtml (rows : Array (Array MapleSQL.Value)) : IO String := do
  let items <- rows.mapM fun row =>
    match row.toList with
    | [.integer id, .text name] => pure s!"<li>{id}: {escapeHtml name}</li>"
    | _ => throw (IO.userError "Unexpected users query result")
  return "<ul>" ++ String.join items.toList ++ "</ul>"

def WebHandler.execute (self : WebHandler) (query : MapleSQL.Formatted) :
    IO (Array (Array MapleSQL.Value)) :=
  self.database.atomically do
    let db <- get
    db.execute query

def WebHandler.nextRequestId (self : WebHandler) : IO Nat :=
  self.counter.atomically do
    modify (fun n => n + 1)
    get

def WebHandler.pageContext (self : WebHandler) (path : String) : IO Page.Context := do
  let requestId <- self.nextRequestId
  let query <- renderQuery (.select #[.all] "users" none)
  let users <- usersHtml (← self.execute query)
  return { requestId, path, usersHtml := users }

def WebHandler.serveDevPage (self : WebHandler) (path : String) :
    Std.Async.Async (Response Body.Full) := do
  let some pages := self.devPages | return <- Response.notFound.text "Not found\n"
  try
    let html <- Std.Async.Async.ofAsyncTask (← IO.asTask (prio := .dedicated) do
      let some source <- pages.find path | return none
      return some (← DevPages.render source (← self.pageContext path)))
    match html with
    | some html => return <- (Response.ok.header! "Cache-Control" "no-store").html html
    | none => return <- (Response.notFound.header! "Cache-Control" "no-store").text "Not found\n"
  catch error =>
    IO.eprintln s!"Development page request failed ({path}): {error}"
    return <- (Response.internalServerError.header! "Cache-Control" "no-store").text
      "Development page request failed\n"

instance : Server.Handler WebHandler where
  ResponseBody := Body.Full
  onRequest self request := do
    if request.line.method != .get then
      return <- (Response.withStatus .methodNotAllowed
        |>.header! "Allow" "GET").text "Only GET is supported\n"
    match toString request.line.uri.path with
    | "/" =>
      if self.devPages.isNone then
        try
          let context <- self.pageContext "/"
          return <- (Response.ok.header! "Cache-Control" "no-store").html
            (Page.home context)
        catch error =>
          IO.eprintln s!"Database request failed: {error}"
          return <- Response.internalServerError.text "Database request failed\n"
      else
        return <- self.serveDevPage "/"
    | "/health" =>
      return <- Response.ok.json "{\"status\":\"ok\"}"
    | "/api/query" =>
      let requestId <- self.nextRequestId
      match sampleQuery requestId with
      | .ok query =>
        try
          let rows <- self.execute query
          let response := Lean.Json.mkObj [
            ("requestId", Lean.toJson requestId),
            ("sql", Lean.toJson query.sql),
            ("params", .arr (query.params.map valueJson)),
            ("rows", rowsJson rows)]
          return <- (Response.ok.header! "Cache-Control" "no-store").json response.compress
        catch error =>
          IO.eprintln s!"Database request failed: {error}"
          return <- Response.internalServerError.text "Database request failed\n"
      | .error error =>
        IO.eprintln s!"SQL generation failed: {error}"
        return <- Response.internalServerError.text "SQL generation failed\n"
    | path => return <- self.serveDevPage path
  onFailure _ error := IO.eprintln s!"HTTP transport failure: {error}"

end LeanWebStudy
