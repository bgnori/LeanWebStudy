# LeanでWeb Applicationをどう書くかのStudy

[二つの取り組みの入口](../README.md) / [起動・使い方](../../README.md)

## 目的と範囲

LeanでWebアプリを組み立てる方法を、動く例を通じて学ぶ。
Std HTTP・Lithe、HTML生成、SQLite・MapleSQL、動的ページ更新、
チャット・SSE・Pong等を扱う。特定のWebSocket実装を完成させること自体が目的ではない。
アプリはローカル開発・学習用であり、本番提供を保証するものではない。

## まず読むもの

| したいこと | 文書 |
|---|---|
| 起動、ルート、サンプルの構成を知る | [ルートREADME](../../README.md) |
| 用語を確認する | [用語集](./glossary.md) |
| 保存・再読み込み・DB変更の反映を理解する | [モジュール更新の調査](./module-reload.md) |
| チャット・Pongを使い、WebSocketとSSEを比較する | [通信方式の選定と使い方](./websocket-chat.md) |
| なぜStd拡張の研究へ派生したかを知る | [リスク・コスト分析](./websocket-risk-return-report.md) |

## WebSocket開発との境界

既存の通信構成を試した結果、Std HTTPへの接続移譲や別ポートの管理が重く、
アプリの使い手に自然な形では扱いにくい、という問題が見えた。
そこから[Std拡張WebSocket開発](../std-websocket/README.md)が派生した。

- `/chat/`、`/chat-ws/`、`/chat-same-port/`、`/chat-sse/`はアプリから見た方式比較。
- `/chat-same-port/`は移転済みの `same-port-websocket` を使う同一ポートのチャット実装。
- `/ws-echo/socket`は派生側の接続移譲のプロトコル実証。
- Studyの通信方式を全面置換する決定はしていない。
- リスク分析の付録には派生研究の初期案が含まれる。現在の採用方針は派生側を参照する。

アプリの画面・データ・利用手順の変更はこのトラックで扱う。
フレーム処理、Transport契約、終了・寿命管理、形式証明は派生側で扱う。
