import Html
import LeanWebStudy.Page

open Html

def templatePage (context : LeanWebStudy.Page.Context) : String :=
  document
    (head (title "Lean HTML template sample") [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")]
    ])
    (body [
      header [
        p [a { href := "/" } ["LeanWebStudy"]],
        h1 ["lean-html テンプレートサンプル"]
      ],
      main [
        p ["Leanの型付きHTML DSLからページを組み立てています。"],
        section_ [
          h2 ["リクエスト情報"],
          p ["Request ID: ", toString context.requestId],
          p ["Path: ", code [context.path]]
        ],
        section_ [
          h2 ["HTML構造"],
          ul [
            li ["タグの組み合わせをLeanの型で検査"],
            li ["テキストと属性値を自動エスケープ"],
            li ["HTML全体をStringとして既存のPage.runへ返却"]
          ]
        ]
      ]
    ])
    (lang := "ja") (pretty := true)

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (templatePage context)
