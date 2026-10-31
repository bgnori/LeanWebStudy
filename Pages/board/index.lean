import Html
import LeanWebStudy.Page

open Html

def boardPostNode (post : LeanWebStudy.Page.BoardPost) : Node .listItem :=
  li [
    h3 [s!"投稿 #{post.id}"],
    p [strong [post.author]],
    p [post.message]
  ] { class_ := "post" }

def boardPage (context : LeanWebStudy.Page.Context) : String :=
  document
    (head (title "みんなの掲示板 - LeanWebStudy") [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
      meta_ [("name", "theme-color"), ("content", "#f4f6fb")]
    ])
    (body [
      header [
        p [a { href := "/" } ["LeanWebStudy"]],
        h1 ["みんなの掲示板"],
        p ["投稿はサーバー上のSQLiteに保存されます。"]
      ] { class_ := "site-header" },
      main [
        p [s!"Page request: {context.requestId}"],
        section_ [
          h2 ["新しい投稿"],
          form [
            label ["名前"] { for_ := "author" },
            input { name := "author", required := true }
              [("id", "author"), ("maxlength", "24"), ("autocomplete", "nickname")],
            p ["24文字以内"],
            label ["投稿内容"] { for_ := "message" },
            textarea "" { name := "message", rows := "5", required := true }
              [("id", "message"), ("maxlength", "500"),
                ("placeholder", "メッセージを入力してください")],
            p ["500文字以内"],
            button ["投稿する"] { type := "submit", class_ := "submit-button" }
          ] { action := "/board/", method := "post" }
        ] { class_ := "panel" },
        section_ [
          h2 [s!"投稿一覧（{context.boardPosts.size}件）"],
          if context.boardPosts.isEmpty then
            p ["まだ投稿はありません。最初の投稿をどうぞ。"] { class_ := "empty" }
          else
            ul (context.boardPosts.toList.map boardPostNode) { class_ := "posts" }
        ] { class_ := "panel" },
        p ["投稿はこのサーバーのメモリー上のSQLiteデータベースに保存され、サーバー再起動時に消去されます。"]
          { class_ := "footnote" }
      ] { class_ := "page" }
    ])
    (lang := "ja") (pretty := true)

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (boardPage context)
