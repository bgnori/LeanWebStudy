import MapleSQL
import Html
import LeanWebStudy.Database
import LeanWebStudy.DevPages
import Lean.Data.Json
import Lithe.Router.Builder
import Lithe.Runtime.Dispatch
import Lithe.Core.Context
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
  pages : DevPages
  router : Lithe.Router

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

def WebHandler.servePage (self : WebHandler) (path : String) : IO Lithe.Response := do
  try
    let some source <- self.pages.find path |
      return ((Lithe.Response.text "Not found\n").withStatus 404)
        |>.setHeader "Cache-Control" "no-store"
    let context <- self.pageContext path
    let html <- DevPages.render source context
    return (Lithe.Response.html html).setHeader "Cache-Control" "no-store"
  catch error =>
    IO.eprintln s!"Page request failed ({path}): {error}"
    return ((Lithe.Response.text "Page request failed\n").withStatus 500)
      |>.setHeader "Cache-Control" "no-store"

def WebHandler.fallback (self : WebHandler) : Lithe.Handler := fun context => do
  if context.req.method != .GET then
    return (Lithe.Response.text "Only GET is supported\n").withStatus 405
      |>.setHeader "Allow" "GET"
  self.servePage context.req.path

def WebHandler.healthRoute (self : WebHandler) : Lithe.Handler := fun context => do
  if context.req.path != "/health" then
    self.fallback context
  else
    pure (Lithe.Response.json (Lean.Json.mkObj [("status", Lean.toJson ("ok" : String))]))

def WebHandler.queryResponse (self : WebHandler) : IO Lithe.Response := do
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
      pure ((Lithe.Response.json response).setHeader "Cache-Control" "no-store")
    catch error =>
      IO.eprintln s!"Database request failed: {error}"
      pure ((Lithe.Response.text "Database request failed\n").withStatus 500)
  | .error error =>
    IO.eprintln s!"SQL generation failed: {error}"
    pure ((Lithe.Response.text "SQL generation failed\n").withStatus 500)

def WebHandler.queryRoute (self : WebHandler) : Lithe.Handler := fun context => do
  if context.req.path != "/api/query" then
    self.fallback context
  else
    self.queryResponse

def WebHandler.registerRoutes (self : WebHandler) : Lithe.Router :=
  Lithe.Router.empty
    |>.get "/health" (self.healthRoute)
    |>.get "/api/query" (self.queryRoute)
    |>.withFallback (self.fallback)

def WebHandler.create
    (counter : Std.Mutex Nat) (database : Std.Mutex Database) (pages : DevPages) :
    WebHandler :=
  let handler : WebHandler := { counter, database, pages, router := .empty }
  { handler with router := handler.registerRoutes }

def WebHandler.toLitheRequest (request : Request Body.Stream) : Lithe.Request :=
  { method := (Lithe.Method.ofString? (toString request.line.method)).getD .POST
    path := toString request.line.uri.path
    query := request.line.uri.query.toRawString
    headers := request.line.headers.toArray.map fun (name, value) =>
      (toString name, toString value)
    body := ByteArray.empty }

def WebHandler.toHttpResponse (response : Lithe.Response) :
    Std.Async.Async (Response Body.Full) := do
  if response.bodyStream.isSome then
    throw (IO.userError "Streaming Lithe responses are not supported by this server adapter")
  let some status := Std.Http.Status.ofCode none response.status.code
    | throw (IO.userError s!"Invalid Lithe response status: {response.status.code}")
  let some body := String.fromUTF8? response.body
    | throw (IO.userError "Lithe response body is not valid UTF-8")
  let builder := response.headers.foldl
    (fun builder (name, value) => builder.header! name value)
    (Std.Http.Response.new.status status)
  builder.text body

instance : Server.Handler WebHandler where
  ResponseBody := Body.Full
  onRequest self request := do
    let response <- Std.Async.Async.ofAsyncTask (← IO.asTask (prio := .dedicated) do
      Lithe.dispatch self.router (Lithe.RequestCtx.ofRequest
        (WebHandler.toLitheRequest request)))
    WebHandler.toHttpResponse response
  onFailure _ error := IO.eprintln s!"HTTP transport failure: {error}"

end LeanWebStudy
