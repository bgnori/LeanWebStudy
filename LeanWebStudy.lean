import MapleSQL
import Html
import LeanWebStudy.Database
import LeanWebStudy.DevPages
import Lean.Data.Json
import Lithe.Router.Builder
import Lithe.Runtime.Dispatch
import Lithe.Core.Context
import Lithe.Extractor.Form
import Std.Http.Server
import Std.Sync.Mutex

namespace LeanWebStudy

open Std.Http

def sampleStatement (minimumId : Nat) : MapleSQL.Statement :=
  .select #[.all] "users"
    (some (.greaterThan (.column "id") (.parameter (.integer (Int.ofNat minimumId)))))

def sampleQuery (requestId : Nat) : Except String MapleSQL.Formatted :=
  MapleSQL.render (sampleStatement requestId)

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
    | [.integer id, .text name, .text email] =>
      pure s!"<li>{id}: {escapeHtml name} <span>({escapeHtml email})</span></li>"
    | _ => throw (IO.userError "Unexpected users query result")
  return "<ul>" ++ String.join items.toList ++ "</ul>"

private def codeHtml (text : String) : String :=
  "<pre><code>" ++ escapeHtml text ++ "</code></pre>"

def sqliteDemoHtml (query : MapleSQL.Formatted)
    (rows : Array (Array MapleSQL.Value)) (emailQuery : MapleSQL.Formatted)
    (emails : Array (Array MapleSQL.Value)) : IO String := do
  let insert <- renderQuery SampleData.insertStatement
  return ("<h2>ダミーデータの出典と利用条件</h2>" ++
      s!"<p><a href=\"{SampleData.sourceUrl}\">JSONPlaceholder users（固定コミット）</a>の" ++
      s!"<a href=\"{SampleData.generatorUrl}\">Fakerで生成された架空データ</a>から、" ++
      "idとnameの10件を基に、ID 2の名前をID 1と同名に変更しました。" ++
      "実在人物を示すデータではありません。emailは元データを使わず、" ++
      "user-{id}@example.invalidを生成しました。予約された.invalidドメインのため" ++
      "実在する送信先には使えません。電話・住所・Webサイト・画像は取り込まず、" ++
      "メール送信や外部通信もしません。</p>" ++
      s!"<p><a href=\"{SampleData.licenseUrl}\">MIT License</a> / " ++
      "Copyright (c) 2013 typicode。ライセンス全文はリポジトリに同梱しています。</p>" ++
      "<h2>元データのスキーマ</h2>" ++
      "<p>元JSONのusers配列の構造（型の説明であり、JSON Schemaではありません）。" ++
      "他の配列は使用しません。geoの緯度・経度も元データでは文字列です。</p>" ++
      codeHtml SampleData.sourceSchema ++
      "<h2>SQLiteに取り込むスキーマ</h2>" ++
      "<p>users[].id → users.id、users[].name → users.name（ID 2のみ同名に変更）。" ++
      "emailはIDから生成します。nameは重複可能、emailはUNIQUEです。" ++
      "残りのフィールドは破棄します。起動時に:memory:へ取り込み、終了時に消えます。</p>" ++
      codeHtml SampleData.sqliteSchema ++
      "<h2>1. MapleSQLでINSERTを生成</h2>" ++
      "<p>Statement.insertにテーブル名、列名、行の配列を渡します。" ++
      "MapleSQLは識別子を引用し、値をSQLとは別のparams配列に分離します。</p>" ++
      codeHtml (reprStr SampleData.insertStatement) ++
      codeHtml insert.sql ++
      codeHtml (Lean.Json.arr (insert.params.map valueJson)).compress ++
      "<h2>2. MapleSQLでSELECTを生成</h2>" ++
      "<p>このページの例は常にid &gt; 3です（リクエスト番号とは独立）。" ++
      "以下は実際にrenderしたStatement、生成SQL、paramsです。</p>" ++
      codeHtml (reprStr (sampleStatement 3)) ++
      codeHtml query.sql ++
      codeHtml (Lean.Json.arr (query.params.map valueJson)).compress ++
      "<h2>3. SQLiteで実行した結果</h2>" ++
      "<p>SQLiteがSQLをprepareし、?へ整数・文字列をbindして実行します。" ++
      "MapleSQL自体はDB接続・実行・スキーマ検証を行いません。" ++
      "結果は[id, name, email]の配列で、表示時にHTMLエスケープします。</p>" ++
      codeHtml (rowsJson rows).compress ++
      "<h2>4. 同名の2人のemailだけをSELECT</h2>" ++
      "<p>名前がLeanne Grahamの行をWHEREで絞り込み、SelectItem.namedで" ++
      "email列だけを取得します。名前は一意ではないので2件返ります。" ++
      "名前もSQLに埋め込まず、文字列パラメーターとして渡します。</p>" ++
      codeHtml (reprStr (SampleData.emailsByNameStatement SampleData.duplicateName)) ++
      codeHtml emailQuery.sql ++
      codeHtml (Lean.Json.arr (emailQuery.params.map valueJson)).compress ++
      "<h3>実行結果（各行は[email]）</h3>" ++
      codeHtml (rowsJson emails).compress ++
      "<p><a href=\"/api/query\">APIのSQL・params・結果を見る</a>。" ++
      "APIはリクエスト番号をid &gt; ?の値に使うため、10以降は空配列になります。</p>")

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
  let demoQuery <- renderQuery (sampleStatement 3)
  let emailQuery <- renderQuery (SampleData.emailsByNameStatement SampleData.duplicateName)
  let demo <- sqliteDemoHtml demoQuery (← self.execute demoQuery)
    emailQuery (← self.execute emailQuery)
  return { requestId, path, usersHtml := users, sqliteDemoHtml := demo }

def WebHandler.boardPosts (self : WebHandler) : IO (Array Page.BoardPost) := do
  let query <- renderQuery (.select #[.all] "posts" none)
  let rows <- self.execute query
  rows.mapM fun row =>
    match row.toList with
    | [.integer id, .text author, .text message] =>
      pure { id, author, message }
    | _ => throw (IO.userError "Unexpected bulletin board query result")

def WebHandler.insertBoardPost (self : WebHandler) (author message : String) :
    IO (Except String Unit) := do
  try
    let insert ← renderQuery (.insert "posts" #["author", "message"]
      #[#[.text author, .text message]])
    let _ ← self.execute insert
    pure (.ok ())
  catch error =>
    pure (.error error.toString)

def WebHandler.servePage (self : WebHandler) (path : String) : IO Lithe.Response := do
  try
    let some source <- self.pages.find path |
      return ((Lithe.Response.text "Not found\n").withStatus 404)
        |>.setHeader "Cache-Control" "no-store"
    let context <- self.pageContext path
    let context ←
      if path == "/board" || path == "/board/" then
        pure { context with boardPosts := (← self.boardPosts).reverse }
      else
        pure context
    let html <- DevPages.render source context
    return (Lithe.Response.html html).setHeader "Cache-Control" "no-store"
  catch error =>
    IO.eprintln s!"Page request failed ({path}): {error}"
    return ((Lithe.Response.text "Page request failed\n").withStatus 500)
      |>.setHeader "Cache-Control" "no-store"

def WebHandler.boardGetRoute (self : WebHandler) : Lithe.Handler := fun context => do
  pure (← self.servePage context.req.path)

def WebHandler.boardPostRoute (self : WebHandler) : Lithe.Handler := fun context => do
  let params ← Lithe.Form.params (limit := some 8192) context
  let field (name : String) : Option String := do
    let values ← params.get? name
    if values.size == 1 then values[0]? else none
  let some author := field "author" |
    throw (Lithe.HttpError.badRequest "missing or repeated form field 'author'")
  let some message := field "message" |
    throw (Lithe.HttpError.badRequest "missing or repeated form field 'message'")
  let author := author.trimAscii.toString
  let message := message.trimAscii.toString
  if author.isEmpty || message.isEmpty then
    throw (Lithe.HttpError.badRequest "author and message must not be empty")
  if author.length > 24 then
    throw (Lithe.HttpError.badRequest "author must be at most 24 characters")
  if message.length > 500 then
    throw (Lithe.HttpError.badRequest "message must be at most 500 characters")
  match ← self.insertBoardPost author message with
  | .ok _ => pure (Lithe.Response.empty 303 |>.setHeader "Location" "/board/")
  | .error error =>
    IO.eprintln s!"Bulletin board POST failed: {error}"
    pure (Lithe.Response.text "Post could not be saved\n" |>.withStatus 500)

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
    |>.get "/board/" (self.boardGetRoute)
    |>.post "/board/" (self.boardPostRoute)
    |>.withFallback (self.fallback)

def WebHandler.create
    (counter : Std.Mutex Nat) (database : Std.Mutex Database) (pages : DevPages) :
    WebHandler :=
  let handler : WebHandler := { counter, database, pages, router := .empty }
  { handler with router := handler.registerRoutes }

def WebHandler.toLitheRequest (request : Request Body.Stream) : IO Lithe.Request := do
  let bodyStream : Lithe.BodyStream := {
    next := ExceptT.mk do
      try
        let chunk? ← Std.Async.Async.block request.body.recv
        pure (.ok (chunk?.map fun chunk => chunk.data))
      catch error =>
        IO.eprintln s!"HTTP request body read failed: {error}"
        pure (.error {
          status := 500
          code := "request_body_read_failed"
          message := "Request body could not be read" })
  }
  return {
    method := (Lithe.Method.ofString? (toString request.line.method)).getD .POST
    path := toString request.line.uri.path
    query := request.line.uri.query.toRawString
    headers := request.line.headers.toArray.map fun (name, value) =>
      (toString name, toString value)
    body := ByteArray.empty
    bodyStream := some bodyStream }

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
  builder.fromBytes body.toUTF8

instance : Server.Handler WebHandler where
  ResponseBody := Body.Full
  onRequest self request := do
    let response <- Std.Async.Async.ofAsyncTask (← IO.asTask (prio := .dedicated) do
      let litheRequest ← WebHandler.toLitheRequest request
      Lithe.dispatch self.router (Lithe.RequestCtx.ofRequest
        litheRequest))
    WebHandler.toHttpResponse response
  onFailure _ error := IO.eprintln s!"HTTP transport failure: {error}"

end LeanWebStudy
