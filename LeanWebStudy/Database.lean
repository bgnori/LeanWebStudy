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
  let insert <- renderQuery SampleData.insertStatement
  discard <| db.execute insert
  return db

end LeanWebStudy
