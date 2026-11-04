# Std拡張WebSocketの開発（移転済み）

この開発トラックは独立リポジトリへ移転した:

**https://github.com/bgnori/same-port-websocket**

設計文書・検証記録・判断台帳・Autobahn準拠テストを含む全文書は移転先の
[docs/](https://github.com/bgnori/same-port-websocket/tree/main/docs)にある。
以後の実装・文書の変更は移転先でのみ行う（本リポジトリはコミット固定の
`require`で利用し、追従はlakefileの更新で行う）。

- 移転の計画と判断: [websocket-separation-plan.md](https://github.com/bgnori/same-port-websocket/blob/main/docs/websocket-separation-plan.md)
- 本リポジトリに残るもの: `/ws-echo`のプロトコル実証と
  `/chat-same-port/`のチャット利用例（利用側）、
  [tests/test_ws_std.py](../../tests/test_ws_std.py) と
  [tests/test_chat.py](../../tests/test_chat.py)（アプリ結合回帰）、
  派生元の経緯 [application-study](../application-study/README.md)
  （とくに[WebSocketリスク・リターン報告](../application-study/websocket-risk-return-report.md)）
- 移転前の経緯はこのディレクトリのgit履歴で辿れる
