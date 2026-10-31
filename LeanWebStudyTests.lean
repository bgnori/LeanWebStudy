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
#guard DevPages.relativePath "/blog/new-page_2" ==
  some (System.FilePath.mk "blog/new-page_2.lean")
#guard DevPages.relativePath "/../Main" == none
#guard DevPages.relativePath "/%2e%2e/Main" == none
#guard DevPages.relativePath "/hello/" == none
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
  let context : Page.Context := { requestId := 7, path := "/hello", usersHtml := "<ul></ul>" }
  match (Lean.fromJson? (Lean.toJson context) : Except String Page.Context) with
  | .ok decoded =>
    unless decoded.requestId == context.requestId && decoded.path == context.path &&
        decoded.usersHtml == context.usersHtml do
      throw (IO.userError "Page context must preserve every field through JSON")
  | .error error => throw (IO.userError s!"Page context decoding failed: {error}")
  let db <- Database.seededMemory
  let query <- match sampleQuery 3 with
    | .ok query => pure query
    | .error error => throw (IO.userError error)
  unless (← db.execute query) == #[#[.integer 4, .text "Dave"]] do
    throw (IO.userError "Parameterized query returned incorrect rows")
  let all <- renderQuery (.select #[.all] "users" none)
  unless (← db.execute all).size == 4 do
    throw (IO.userError "Seeded database should contain four users")

  let name := "'; DROP TABLE users; -- <script>&\""
  let insert <- renderQuery (.insert "users" #["id", "name"]
    #[#[.integer 5, .text name]])
  unless (← db.execute insert).isEmpty do
    throw (IO.userError "INSERT should not return rows")
  let byName <- renderQuery (.select #[.all] "users"
    (some (.equal (.column "name") (.parameter (.text name)))))
  unless (← db.execute byName) == #[#[.integer 5, .text name]] do
    throw (IO.userError "Text parameters must round-trip without SQL interpolation")
  unless (← usersHtml #[#[.integer 5, .text name]]) ==
      "<ul><li>5: &#39;; DROP TABLE users; -- &lt;script&gt;&amp;&quot;</li></ul>" do
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
  unless (← db.execute all).size == 5 do
    throw (IO.userError "Data should persist on the shared connection after query failures")
  let fresh <- Database.seededMemory
  unless (← fresh.execute all).size == 4 do
    throw (IO.userError "In-memory databases must be isolated per connection")
  IO.println "PASS: SQLite execution, binding, result types, error recovery, memory isolation"
