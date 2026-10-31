import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure
      ("<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\">" ++
        "<title>MapleSQLとSQLite - LeanWebStudy</title></head><body>" ++
        "<p><a href=\"/\">LeanWebStudy</a></p><h1>MapleSQLで操作するSQLite</h1>" ++
        s!"<p>Page request: {context.requestId}</p>" ++
        "<p>MapleSQLでSQL文とパラメーターを生成し、SQLiteで実行します。" ++
        "値をSQL文に埋め込まず、安全に受け渡します。</p>" ++
        "<h2>SQLiteのユーザー</h2>" ++ context.usersHtml ++
        "<h2>パラメーター付きクエリ</h2>" ++
        "<p>ユーザーIDをパラメーターとしてMapleSQLでクエリを組み立て、" ++
        "SQLiteで実行する例です。</p>" ++
        "<p><a href=\"/api/query\">クエリを実行してJSON結果を見る</a></p>" ++
        "</body></html>")
