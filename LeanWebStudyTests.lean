import LeanWebStudy

open LeanWebStudy

def queryMatches (requestId : Nat) : Bool :=
  match sampleQuery requestId with
  | .ok formatted =>
    formatted.sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" &&
      formatted.params == #[.integer (Int.ofNat requestId)]
  | .error _ => false

#guard queryMatches 7
#guard queryMatches 8
#guard queryMatches 0

#guard match queryJson 7 with
  | .ok json => json == Lean.Json.mkObj [
      ("requestId", Lean.toJson (7 : Nat)),
      ("sql", Lean.toJson ("SELECT * FROM \"users\" WHERE \"id\" > ?" : String)),
      ("params", .arr #[Lean.toJson (7 : Int)])]
  | .error _ => false

#guard valueJson (.text "\"<user>") == Lean.toJson ("\"<user>" : String)

#guard escapeHtml "<script>&\"'" == "&lt;script&gt;&amp;&quot;&#39;"

#guard DevPages.relativePath "/" == some (System.FilePath.mk "index.lean")
#guard DevPages.relativePath "/hello" == some (System.FilePath.mk "hello.lean")
#guard DevPages.relativePath "/sqlite/" ==
  some (System.FilePath.mk "sqlite/index.lean")
#guard DevPages.relativePath "/blog/new-page_2" ==
  some (System.FilePath.mk "blog/new-page_2.lean")
#guard DevPages.relativePath "/../Main" == none
#guard DevPages.relativePath "/%2e%2e/Main" == none
#guard DevPages.relativePath "/hello/" ==
  some (System.FilePath.mk "hello/index.lean")
#guard DevPages.relativePath "//hello" == none
#guard DevPages.relativePath "/hello\\world" == none
#guard DevPages.relativePath "hello" == none

#guard rowsJson #[#[.integer 4, .text "Dave"]] ==
  Lean.Json.arr #[Lean.Json.arr #[Lean.toJson (4 : Int), Lean.toJson ("Dave" : String)]]

def expectFailure (action : IO α) (message : String) : IO Unit := do
  let error <- try
    discard action
    pure none
  catch error =>
    pure (some error.toString)
  match error with
  | some error =>
    unless (error.splitOn message).length > 1 do
      throw (IO.userError s!"Expected error containing '{message}', got '{error}'")
  | none => throw (IO.userError s!"Expected failure: {message}")

def main : IO Unit := do
  let context : Page.Context := {
    requestId := 7, path := "/hello", usersHtml := "<ul></ul>", sqliteDemoHtml := "<pre>demo</pre>",
    boardPosts := #[{ id := 3, author := "Ada", message := "Hello" }],
    wikiArticles := #[{ slug := "hello", title := "Hello", content := "Wiki text" }] }
  match (Lean.fromJson? (Lean.toJson context) : Except String Page.Context) with
  | .ok decoded =>
    unless decoded.requestId == context.requestId && decoded.path == context.path &&
        decoded.usersHtml == context.usersHtml && decoded.sqliteDemoHtml == context.sqliteDemoHtml &&
        decoded.boardPosts == context.boardPosts && decoded.wikiArticles == context.wikiArticles do
      throw (IO.userError "Page context must preserve every field through JSON")
  | .error error => throw (IO.userError s!"Page context decoding failed: {error}")
  let legacyContext := Lean.Json.mkObj [
    ("requestId", Lean.toJson (1 : Nat)), ("path", Lean.toJson ("/" : String)),
    ("usersHtml", Lean.toJson ("<ul></ul>" : String))]
  match (Lean.fromJson? legacyContext : Except String Page.Context) with
  | .ok decoded =>
    unless decoded.sqliteDemoHtml.isEmpty && decoded.boardPosts.isEmpty &&
        decoded.wikiArticles.isEmpty do
      throw (IO.userError "Legacy page context must default optional fields")
  | .error error => throw (IO.userError s!"Legacy page context decoding failed: {error}")
  let invalidContext := Lean.Json.mkObj [
    ("requestId", Lean.toJson (1 : Nat)), ("path", Lean.toJson ("/" : String)),
    ("usersHtml", Lean.toJson ("<ul></ul>" : String)), ("sqliteDemoHtml", .null)]
  match (Lean.fromJson? invalidContext : Except String Page.Context) with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Present but invalid demo HTML must not be silently defaulted")
  let db <- Database.seededMemory
  let query <- match sampleQuery 3 with
    | .ok query => pure query
    | .error error => throw (IO.userError error)
  let expected := SampleData.users.extract 3 10
  unless (← db.execute query) == expected do
    throw (IO.userError "Parameterized query returned incorrect rows")
  let all <- renderQuery (.select #[.all] "users" none)
  unless SampleData.users.size == 10 && (← db.execute all) == SampleData.users do
    throw (IO.userError "Seeded database must contain exactly the ten synthetic source users")
  unless (← db.execute {
      sql := "SELECT sql FROM sqlite_master WHERE name = ?"
      params := #[.text "users"] }) == #[#[.text SampleData.sqliteSchema]] do
    throw (IO.userError "Displayed schema must match the actual database schema")
  let boardSelect <- renderQuery (.select #[.all] "posts" none)
  unless (← db.execute boardSelect).isEmpty do
    throw (IO.userError "A newly seeded bulletin board must have no posts")
  let boardInsert <- renderQuery (.insert "posts" #["author", "message"]
    #[#[.text "Ada", .text "Hello from SQLite"]])
  let _ ← db.execute boardInsert
  unless (← db.execute boardSelect) ==
      #[#[.integer 1, .text "Ada", .text "Hello from SQLite"]] do
    throw (IO.userError "MapleSQL post insertion and retrieval must use the shared SQLite database")
  let wikiSelect <- renderQuery (.select #[.all] "wiki_articles" none)
  unless (← db.execute wikiSelect).size == 3 do
    throw (IO.userError "A newly seeded wiki must contain three starter articles")
  for row in SampleData.users do
    match row.toList with
    | [.integer id, .text _, .text email] =>
      unless email == s!"user-{id}@example.invalid" do
        throw (IO.userError "Dummy emails must use the reserved invalid domain")
    | _ => throw (IO.userError "Dummy users must have id, name and email")
  let emailQuery <- renderQuery (SampleData.emailsByNameStatement SampleData.duplicateName)
  unless emailQuery.sql == "SELECT \"email\" FROM \"users\" WHERE \"name\" = ?" &&
      emailQuery.params == #[.text SampleData.duplicateName] do
    throw (IO.userError "Email projection must bind the name separately")
  let expectedEmails := #[#[.text "user-1@example.invalid"], #[.text "user-2@example.invalid"]]
  let emails <- db.execute emailQuery
  unless emails == expectedEmails do
    throw (IO.userError "Same-name SELECT must return exactly two email-only rows")
  let missingName <- renderQuery (SampleData.emailsByNameStatement "No such dummy user")
  unless (← db.execute missingName).isEmpty do
    throw (IO.userError "Unmatched names must return no emails")
  let demo <- sqliteDemoHtml query (← db.execute query) emailQuery emails
  for text in #[SampleData.sourceUrl, SampleData.licenseUrl, SampleData.generatorUrl,
      escapeHtml SampleData.sourceSchema, escapeHtml SampleData.sqliteSchema,
      escapeHtml query.sql, escapeHtml (rowsJson expected).compress,
      escapeHtml (reprStr (sampleStatement 3)), escapeHtml emailQuery.sql,
      escapeHtml (Lean.Json.arr (emailQuery.params.map valueJson)).compress,
      escapeHtml (rowsJson expectedEmails).compress] do
    unless (demo.splitOn text).length > 1 do
      throw (IO.userError s!"Demo must display actual source, schema, and query output: {text}")
  let emptyQuery <- renderQuery (sampleStatement 10)
  unless (← db.execute emptyQuery).isEmpty do
    throw (IO.userError "IDs at or above ten must return empty results")

  let name := "'; DROP TABLE users; -- <script>&\""
  let email := "<script>&\"'@example.invalid"
  let insert <- renderQuery (.insert "users" #["id", "name", "email"]
    #[#[.integer 11, .text name, .text email]])
  unless (← db.execute insert).isEmpty do
    throw (IO.userError "INSERT should not return rows")
  let byName <- renderQuery (.select #[.all] "users"
    (some (.equal (.column "name") (.parameter (.text name)))))
  unless (← db.execute byName) == #[#[.integer 11, .text name, .text email]] do
    throw (IO.userError "Text parameters must round-trip without SQL interpolation")
  let injectedNameQuery <- renderQuery (SampleData.emailsByNameStatement name)
  unless (← db.execute injectedNameQuery) == #[#[.text email]] do
    throw (IO.userError "Email SELECT must bind SQL-like names without interpolation")
  unless (← usersHtml #[#[.integer 11, .text name, .text email]]) ==
      ("<ul><li>11: &#39;; DROP TABLE users; -- &lt;script&gt;&amp;&quot;" ++
        " <span>(&lt;script&gt;&amp;&quot;&#39;@example.invalid)</span></li></ul>") do
    throw (IO.userError "Database content must be HTML-escaped")

  let min : Int := -9223372036854775808
  let max : Int := 9223372036854775807
  unless (← db.execute { sql := "SELECT ?, ?", params := #[.integer min, .integer max] }) ==
      #[#[.integer min, .integer max]] do
    throw (IO.userError "SQLite integer boundaries must round-trip")
  let nulText := "before" ++ String.singleton (Char.ofNat 0) ++ "after"
  unless (← db.execute { sql := "SELECT ?", params := #[.text nulText] }) ==
      #[#[.text nulText]] do
    throw (IO.userError "SQLite text parameters must preserve embedded NUL bytes")

  expectFailure (db.execute { sql := "SELECT ?", params := #[.integer (max + 1)] })
    "signed 64-bit"
  expectFailure (db.execute { sql := "SELECT ?", params := #[.integer (min - 1)] })
    "signed 64-bit"
  expectFailure (db.execute { sql := "SELECT ?", params := #[] }) "parameter count mismatch"
  expectFailure (db.execute { sql := "SELECT 1", params := #[.integer 1] })
    "parameter count mismatch"
  expectFailure (db.execute { sql := "SELECT 1; DROP TABLE users", params := #[] })
    "one SQL statement"
  expectFailure (db.execute { sql := "", params := #[] }) "one statement"
  expectFailure (db.execute {
    sql := "SELECT 1" ++ String.singleton (Char.ofNat 0), params := #[] }) "NUL bytes"
  expectFailure (db.execute { sql := "SELECT * FROM missing", params := #[] })
    "no such table"
  expectFailure (db.execute { sql := "SELECT NULL", params := #[] }) "Unsupported"
  expectFailure (db.execute { sql := "SELECT 1.5", params := #[] }) "Unsupported"
  expectFailure (db.execute { sql := "SELECT x'00'", params := #[] }) "Unsupported"
  expectFailure (db.execute insert) "UNIQUE constraint"
  let repeatedEmail <- renderQuery (.insert "users" #["id", "name", "email"]
    #[#[.integer 12, .text "Another dummy", .text "user-1@example.invalid"]])
  expectFailure (db.execute repeatedEmail) "UNIQUE constraint"
  let missingEmail <- renderQuery (.insert "users" #["id", "name"]
    #[#[.integer 12, .text "Another dummy"]])
  expectFailure (db.execute missingEmail) "NOT NULL constraint"
  unless (← db.execute all).size == 11 do
    throw (IO.userError "Data should persist on the shared connection after query failures")
  let fresh <- Database.seededMemory
  unless (← fresh.execute all) == SampleData.users do
    throw (IO.userError "In-memory databases must be isolated per connection")
  IO.println "PASS: SQLite execution, binding, result types, error recovery, memory isolation"
