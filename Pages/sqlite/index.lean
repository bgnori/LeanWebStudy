import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
        "<title>SQLite - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p><h1>SQLite</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<p>SQLiteのデータベースを使う習作です。</p>" ++
        "<ul><li><a href=\"/sqlite/users\">ユーザー一覧</a></li></ul>" ++
        "</body></html>")
