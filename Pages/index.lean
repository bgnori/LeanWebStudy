import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>LeanWebStudy</title></head><body><h1>LeanWebStudy</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<h2>習作</h2><ul>" ++
        "<li><a href=\"/sqlite/users\">SQLiteのユーザー一覧</a></li>" ++
        "<li><a href=\"/maplesql/parameterized-query\">MapleSQLのパラメーター付きクエリ</a></li>" ++
        "<li><a href=\"/templates/lean-html\">lean-htmlのテンプレートサンプル</a></li>" ++
        "</ul></body></html>")
