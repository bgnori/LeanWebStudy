import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
        "<title>Parameterized query - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p>" ++
        "<h1>MapleSQLのパラメーター付きクエリ</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<p>ユーザーIDをパラメーターとして渡してクエリを実行します。</p>" ++
        "<p><a href=\"/api/query\">JSON APIを実行</a></p>" ++
        "</body></html>")
