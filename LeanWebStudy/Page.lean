import Lean

namespace LeanWebStudy.Page

structure BoardPost where
  id : Int
  author : String
  message : String
  deriving Lean.ToJson, Lean.FromJson, BEq

structure WikiArticle where
  slug : String
  title : String
  content : String
  deriving Lean.ToJson, Lean.FromJson, BEq

structure Context where
  requestId : Nat
  path : String
  usersHtml : String
  sqliteDemoHtml : String := ""
  boardPosts : Array BoardPost := #[]
  wikiArticles : Array WikiArticle := #[]
  chatPort : Nat := 0
  deriving Lean.ToJson

instance : Lean.FromJson Context where
  fromJson? json := do
    let fields <- json.getObj?
    let sqliteDemoHtml <- match fields.get? "sqliteDemoHtml" with
      | some value => value.getStr?
      | none => pure ""
    let boardPosts <- match fields.get? "boardPosts" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let wikiArticles <- match fields.get? "wikiArticles" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let chatPort <- match fields.get? "chatPort" with
      | some value => do
        let port ← value.getNat?
        unless port <= 65535 do throw "chatPort must be at most 65535"
        pure port
      | none => pure 0
    return {
      requestId := ← json.getObjValAs? Nat "requestId"
      path := ← json.getObjValAs? String "path"
      usersHtml := ← json.getObjValAs? String "usersHtml"
      sqliteDemoHtml
      boardPosts
      wikiArticles
      chatPort }

def escapeHtml (text : String) : String :=
  text.replace "&" "&amp;" |>.replace "<" "&lt;" |>.replace ">" "&gt;"
    |>.replace "\"" "&quot;" |>.replace "'" "&#39;"

-- stdout is reserved for the JSON response; page diagnostics belong on stderr.
def run (render : Context -> IO String) : IO Unit := do
  let input <- (← IO.getStdin).readToEnd
  let context <- match Lean.Json.parse input >>= Lean.fromJson? with
    | .ok context => pure context
    | .error error => throw (IO.userError s!"Invalid page context: {error}")
  let html <- render context
  (← IO.getStdout).putStr (Lean.toJson html).compress

end LeanWebStudy.Page
