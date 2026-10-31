import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
        "<title>HTML templates - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p><h1>HTMLテンプレート</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<p>LeanのHTML DSLを使った習作です。</p>" ++
        "<ul><li><a href=\"/templates/lean-html\">lean-htmlサンプル</a></li></ul>" ++
        "</body></html>")
