import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>LeanWebStudy</title></head><body><h1>LeanWebStudy</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<h2>習作</h2><ul>" ++
        "<li><a href=\"/sqlite/\">MapleSQLで操作するSQLite</a></li>" ++
        "<li><a href=\"/templates/\">lean-htmlテンプレート</a></li>" ++
        "<li><a href=\"/board/\">掲示板 Webアプリ</a></li>" ++
        "<li><a href=\"/wiki/\">Wiki Webアプリ</a></li>" ++
        "<li><a href=\"/chat/\">WebSocket リアルタイムチャット</a></li>" ++
        "</ul></body></html>")
