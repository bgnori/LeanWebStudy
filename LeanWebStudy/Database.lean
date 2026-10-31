import MapleSQL
import LeanWebStudy.SampleData

namespace LeanWebStudy

private opaque DatabaseImpl : NonemptyType

def Database : Type := DatabaseImpl.type

instance : Nonempty Database := DatabaseImpl.property

@[extern "leanwebstudy_sqlite_open_memory"]
opaque Database.openMemory : IO Database

@[extern "leanwebstudy_sqlite_execute"]
private opaque Database.executeNative (db : @& Database) (sql : @& String)
    (params : @& Array MapleSQL.Value) : IO (Array (Array MapleSQL.Value))

-- SQLite INTEGER is signed 64-bit, whereas MapleSQL integers are unbounded.
def Database.execute (db : Database) (query : MapleSQL.Formatted) :
    IO (Array (Array MapleSQL.Value)) := do
  for param in query.params do
    if let .integer value := param then
      if value < -9223372036854775808 || value > 9223372036854775807 then
        throw (IO.userError "SQL parameter is outside SQLite's signed 64-bit integer range")
  db.executeNative query.sql query.params

def renderQuery (statement : MapleSQL.Statement) : IO MapleSQL.Formatted :=
  match MapleSQL.render statement with
  | .ok query => pure query
  | .error error => throw (IO.userError s!"SQL generation failed: {error}")

def Database.seededMemory : IO Database := do
  let db <- Database.openMemory
  discard <| db.execute {
    sql := SampleData.sqliteSchema
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL, message TEXT NOT NULL)"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE wiki_articles (slug TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL)"
    params := #[] }
  let wikiSeed := #[
    #["welcome", "Wikiへようこそ", "このWikiはLean 4、lean-html、Lithe、MapleSQL、SQLiteで作られています。\n\n記事の新規作成・編集・削除を試せます。"],
    #["lean-basics", "Lean 4の基本", "Leanは定理証明支援系であり、関数型プログラミング言語でもあります。\n\nこのサンプルのページとサーバーはLeanで実装されています。"],
    #["sqlite-basics", "SQLiteの基本", "SQLiteはアプリケーションに組み込める軽量なリレーショナルデータベースです。\n\nこのWikiでは記事をSQLiteに保存し、MapleSQLでSQLとパラメーターを分けて操作します。"]]
  let wikiInsert <- renderQuery (.insert "wiki_articles" #["slug", "title", "content"]
    (wikiSeed.map fun row => row.map MapleSQL.Value.text))
  discard <| db.execute wikiInsert
  let insert <- renderQuery SampleData.insertStatement
  discard <| db.execute insert
  return db

end LeanWebStudy
