import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>SQLite users - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p><h1>SQLiteのユーザー一覧</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++ context.usersHtml ++
        "</body></html>")
