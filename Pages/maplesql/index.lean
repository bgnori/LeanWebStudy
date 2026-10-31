import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
        "<title>MapleSQL - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p><h1>MapleSQL</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<p>MapleSQLでSQLを生成し、パラメーターを分離して実行します。</p>" ++
        "<ul><li><a href=\"/maplesql/parameterized-query\">パラメーター付きクエリ</a></li>" ++
        "<li><a href=\"/api/query\">クエリAPI (JSON)</a></li></ul>" ++
        "</body></html>")
