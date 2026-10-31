import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>LeanWebStudy</title></head><body><h1>LeanWebStudy</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<h2>習作</h2><ul>" ++
        "<li><a href=\"/sqlite/\">SQLite</a></li>" ++
        "<li><a href=\"/maplesql/\">MapleSQL</a></li>" ++
        "<li><a href=\"/templates/\">lean-htmlテンプレート</a></li>" ++
        "</ul></body></html>")
