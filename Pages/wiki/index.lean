import Html
import LeanWebStudy.Page

open Html

private def wikiArticleCard (article : LeanWebStudy.Page.WikiArticle) : Node .flow :=
  Html.article [
    h2 [a { href := s!"/wiki/{article.slug}" } [article.title]],
    p [String.ofList (article.content.toList.take 150)]
      { style := "color:#596579;line-height:1.7;white-space:pre-wrap" },
    p [a { href := s!"/wiki/edit/{article.slug}" } ["編集"]]
  ] { style := "padding:1.2rem 1.4rem;border:1px solid #e2e8f0;border-radius:12px;background:#fff" }

private def wikiArticleForm (article? : Option LeanWebStudy.Page.WikiArticle) : Node .flow :=
  let editing := article?.isSome
  let article := article?.getD { slug := "", title := "", content := "" }
  form [
    if editing then
      div [
        label ["記事ID"] { for_ := "slug-display" },
        input { value := article.slug, readonly := true }
          [("id", "slug-display"), ("style", "width:100%;padding:.7rem;border:1px solid #cbd5e1;border-radius:8px")]
      ]
    else
      div [
        label ["記事ID（英小文字・数字・ハイフン）"] { for_ := "slug" },
        input { name := "slug", required := true, placeholder := "例: lean-basics" }
          [("id", "slug"), ("maxlength", "48"),
            ("style", "width:100%;padding:.7rem;border:1px solid #cbd5e1;border-radius:8px")]
      ],
    if editing then
      input { type := "hidden", name := "slug", value := article.slug } []
    else
      p [],
    label ["タイトル"] { for_ := "title" },
    input { name := "title", value := article.title, required := true, placeholder := "記事のタイトル" }
      [("id", "title"), ("maxlength", "120"),
        ("style", "width:100%;padding:.7rem;border:1px solid #cbd5e1;border-radius:8px;margin:.4rem 0 1rem")],
    label ["本文（プレーンテキスト）"] { for_ := "content" },
    textarea article.content { name := "content", rows := "14", required := true }
      [("id", "content"), ("maxlength", "10000"),
        ("placeholder", "記事の内容を入力してください"),
        ("style", "width:100%;box-sizing:border-box;padding:.8rem;border:1px solid #cbd5e1;border-radius:8px;line-height:1.7")],
    p ["1〜10,000文字。HTMLとしては解釈されず、安全なテキストとして表示されます。"]
      { style := "color:#64748b;font-size:.9rem" },
    button [if editing then "変更を保存" else "記事を作成"]
      { type := "submit", style := "border:0;border-radius:8px;background:#155eef;color:#fff;padding:.75rem 1.1rem;font-weight:700;cursor:pointer" }
  ] { action := if editing then "/wiki/save" else "/wiki/create", method := "post" }

private def wikiPage (context : LeanWebStudy.Page.Context) : String := Id.run do
  let segments := (context.path.splitOn "/").drop 2
  let segments := if segments.getLast? == some "" then segments.dropLast else segments
  let findArticle (slug : String) : Option LeanWebStudy.Page.WikiArticle :=
    context.wikiArticles.find? fun (article : LeanWebStudy.Page.WikiArticle) =>
      article.slug == slug
  let selected? := match segments with
    | [slug] => findArticle slug
    | ["edit", slug] => findArticle slug
    | _ => none
  let isEdit := match segments with
    | ["edit", _] => true
    | _ => false
  let isNew := segments == ["new"]
  let isIndex := segments.isEmpty
  let pageTitle := if isNew then "新しい記事" else if isEdit then "記事を編集" else
    match selected? with
    | some article => article.title
    | none => "Lean Wiki"
  let pageContent : List (Node .flow) :=
    if isNew then
      [p [a { href := "/wiki/" } ["← 記事一覧"]],
       h1 ["新しい記事"],
       p ["記事IDは作成後に変更できません。英小文字・数字・ハイフンで入力してください。"],
       wikiArticleForm none]
    else if isEdit then
      match selected? with
      | some article =>
        [p [a { href := s!"/wiki/{article.slug}" } ["← 記事に戻る"]],
         h1 ["記事を編集"],
         wikiArticleForm (some article),
         form [
           p ["記事を削除すると元に戻せません。"],
           input { type := "hidden", name := "slug", value := article.slug } [],
           button ["この記事を削除"]
             { type := "submit", style := "border:1px solid #dc2626;border-radius:8px;background:#fff;color:#b91c1c;padding:.65rem 1rem;cursor:pointer" }
         ] { action := "/wiki/delete", method := "post" }]
      | none => [h1 ["記事が見つかりません"]]
    else if isIndex then
      [div [
         div [
           p ["LEARN • WRITE • SHARE"] { style := "color:#155eef;font-size:.8rem;font-weight:800;letter-spacing:.14em" },
           h1 ["知識を、みんなで育てる。"] { style := "font-size:clamp(2rem,5vw,3.2rem);line-height:1.15;letter-spacing:-.04em;margin:.4rem 0 1rem" },
           p ["Lean / SQLiteで動く小さなWikiサンプルです。記事を読んだり、自由に編集したりできます。"]
             { style := "font-size:1.05rem;color:#596579;line-height:1.8;max-width:42rem" },
           a { href := "/wiki/new", style := "display:inline-block;margin-top:.7rem;padding:.8rem 1.1rem;border-radius:8px;background:#155eef;color:white;text-decoration:none;font-weight:700" }
             ["＋ 新しい記事"]
         ] { style := "padding:2rem 0 2.5rem" }
       ],
       section_ [
         h2 ["記事一覧"] { style := "font-size:1.45rem" },
         if context.wikiArticles.isEmpty then
           p ["まだ記事がありません。最初の記事を作成してください。"]
         else
           div (context.wikiArticles.toList.map wikiArticleCard)
             { style := "display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:1rem" }
       ]]
    else
      match selected? with
      | some article =>
        [p [a { href := "/wiki/" } ["← 記事一覧"]],
         Html.article [
           p ["WIKI ARTICLE"] { style := "color:#155eef;font-size:.8rem;font-weight:800;letter-spacing:.12em" },
           h1 [article.title] { style := "font-size:clamp(2rem,5vw,3rem);line-height:1.2;margin:.5rem 0 1.5rem" },
           p [article.content] { style := "white-space:pre-wrap;line-height:1.9;color:#334155;font-size:1.05rem" }
         ] { style := "padding:1.5rem 0;max-width:48rem" },
         p [a { href := s!"/wiki/edit/{article.slug}" } ["この記事を編集"]]]
      | none => [h1 ["記事が見つかりません"]]
  document
    (head (title s!"{pageTitle} - Lean Wiki") [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
      meta_ [("name", "theme-color"), ("content", "#f7f8fc")]
    ])
    (body [
      header [
        nav [
          a { href := "/wiki/", style := "font-weight:800;color:#17233b;text-decoration:none;font-size:1.1rem" } ["Lean Wiki"],
          a { href := "/", style := "color:#596579;text-decoration:none" } ["LeanWebStudy"]
        ] { style := "display:flex;justify-content:space-between;align-items:center;padding:1.2rem 0;border-bottom:1px solid #e2e8f0" }
      ],
      main pageContent { style := "max-width:960px;margin:0 auto;padding:0 1.25rem 3rem" },
      footer [
        p ["Lean 4 · lean-html · Lithe · MapleSQL · SQLite"]
          { style := "max-width:960px;margin:0 auto;padding:1.5rem 1.25rem;color:#64748b;border-top:1px solid #e2e8f0;font-size:.9rem" }
      ]
    ]) (lang := "ja") (pretty := true)

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (wikiPage context)
