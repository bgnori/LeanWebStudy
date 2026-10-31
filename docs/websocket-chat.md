# WebSocket チャットの技術選定と使い方

## 要件と既存構成

2026-10-31 に調査。チャットの送受信は POST/GET やポーリングではなく、
**接続を維持した WebSocket の双方向メッセージ**で行う。
ページの初回取得と HTTP Upgrade のハンドシェイクは通常の HTTP を使用する。
開発 watcher 自体の `/__dev/status` ポーリングは既存の更新通知用であり、
チャットの取得・送信には使用しない。

既存の Lean 4、Std.Async / Std.Http.Server、Lithe、lean-html、MapleSQL、
SQLite は変更しない。固定された Lean 4.35.0 の
`Std.Http.Server.Handler` には生のソケットを引き渡す Upgrade API がなく、
通常の HTTP レスポンスに 101 を設定するだけでは WebSocket に移行できない。

## 候補とトレードオフ

| 候補 | 利点 | 費用・制約 | 判断 |
| --- | --- | --- | --- |
| Std.Async.TCP 上で RFC 6455 を自作 | Lean のみで同じポートに統合できる | SHA-1/Base64、マスク、断片化、UTF-8、Ping/Pong、Close、バックプレッシャーを維持・検証する必要がある | サンプルのための独自プロトコル実装を避ける |
| [websocket.lean](https://github.com/cleissonbarbosa/websocket.lean) | Lean のプロトコル・サーバー API がある | 公開 README は beta。調査時の `lean-toolchain` は 4.21.0、Alloy を master から取得。4.35.0 との互換性・固定化の検証が別途必要 | 今回は不採用。互換性がないと断定したわけではない |
| [Python websockets](https://websockets.readthedocs.io/en/stable/intro/index.html) | フレーム処理が成熟し、asyncio / Sans-I/O を提供 | Python サービスと追加パッケージの起動・終了・依存管理が必要。アプリ本体が複数ランタイムになる | 既存 Python は開発ツールのみなので不採用 |
| [libwebsockets](https://libwebsockets.org/) | 継続的に開発される C ライブラリー。非同期イベントループ、断片化、制御フレームなどを担当。既存 SQLite C FFI と同じビルド方式に乗る | システム開発ライブラリーが増える。C のキュー・ライフサイクル管理、別リスナーが必要 | **採用** |

libwebsockets はプロトコル処理、Lean は JSON の検証・配信イベント生成を担当する。
最新 upstream のライセンスは公式サイト上 MIT。配布版のライセンスはその版の
同梱文書を確認する（Ubuntu のパッケージには別の履歴上の表記があり得る）。
本リポジトリにはライブラリーのコードをコピーせず、システムライブラリーにリンクする。
Ubuntu のパッケージ更新を利用するため Lake の Git 依存には追加しない。

## 起動

```sh
sudo apt-get install build-essential libsqlite3-dev libwebsockets-dev
lake build
lake exe leanwebstudy
# または既存の watcher
python3 tools/dev.py
```

<http://127.0.0.1:8080/chat/> を二つのタブで開く。名前と本文を送信すると、
送信元を含む全接続へ即座に配信される。チャットの履歴は SQLite に保存せず、
プロセスのメモリーに最新 50 件だけ保持し、再起動で消える。

<http://127.0.0.1:8080/pong/> を二つのタブまたは端末で開くと、通信対戦 Pong を
遊べる。左側のプレイヤー1がボール状態をシミュレーションし、両プレイヤーの
パドル位置とボール・スコアを WebSocket で同期する。サーバーはLeanでイベントを
検証し、対戦相手と観戦者へ中継する。先に7点取ると勝利。1つのルームのみで、
プレイヤー1が切断すると状態は引き継がれない。

### ポートとプレビュー

- 通常起動: HTTP は指定ポート、WebSocket は OS が選ぶ空きポートに bind。
  両方とも `127.0.0.1` のみ。WebSocket URL は起動ログに表示され、
  ページの meta にポートを渡す。別ターミナルでサービスを起動する必要はない。
- watcher: ページのポート情報を空にし、ブラウザーは同じプレビュー URL の
  `/chat/socket` または `/pong/socket` に接続する。Python のプレビューが handshake
  とバイト列を転送する。フレームの解析・再実装や HTTP ポーリングは行わない。
- `GET /chat/endpoint` は watcher の接続時のポート発見用メタデータ。
  投稿や履歴は返さない。従来の `/health` JSON は変更しない。
- Origin は `http://127.0.0.1:<HTTPポート>` と
  `http://localhost:<HTTPポート>` のみ許可。Origin のない接続や他サイトは拒否する。
  プレビューは自身の Host/Origin を検証してから内部 Origin に変換する。
- 通常起動をリモートからポート転送する場合は HTTP と WebSocket の両ポートが必要。
  watcher 経由のローカルプレビューでは一つのポートで済む。
  公開ドメイン、任意の Origin、TLS 終端の設定はこのローカルサンプルの対象外。

## プロトコル

チャットはパス `/chat/socket`、サブプロトコル `leanwebstudy-chat`、
UTF-8 JSON text message。

クライアントから:

```json
{"type":"message","requestId":"unique-per-send","author":"Ada","message":"こんにちは"}
```

サーバーから:

```json
{"type":"history","messages":[]}
{"type":"message","id":1,"requestId":"unique-per-send","author":"Ada","message":"こんにちは"}
{"type":"error","message":"名前は 1〜24 文字で入力してください。"}
```

- 接続直後に履歴、続けて新着を送る。同じイベントループで履歴と配信を順序付けする。
  id はサーバーが割り当てる連番で、再起動時にリセット。
- 名前 1〜24、本文 1〜500、requestId 1〜64 Unicode コードポイント。
  名前・本文の前後の ASCII 空白を除去し、空入力を拒否する。
- JSON の型・必須フィールドをサーバー側で検証。通常の入力エラーは送信元だけに
  error イベントを返し、ログにも記録する。無効な投稿は履歴・連番を変更しない。
- メッセージ全体 8192 バイトまで。断片化を結合してから検証。
  binary は Close 1003、サイズ超過は 1009。Ping/Pong・Close・UTF-8 は
  libwebsockets が処理する。アイドル時は 20 秒で Ping、30 秒間通信の
  有効性を確認できない接続は切断する。
- 最大 64 接続、接続ごとの送信待ち最大 64 イベント。遅いクライアントは
  1008 で切断してメモリー増大を防ぐ。ライブラリー側の HTTP ヘッダー・FD 数も制限する。
- ブラウザーは `textContent` で表示し、HTML を実行しない。
  最新 50 件だけ描画し、連番で重複を防ぐ。
- 配信が届くまでは「送信中」。requestId で自分の送信結果を確認し、
  確認後だけ入力を消去する（送信待ち中に編集された本文は消さない）。
  1〜10 秒のバックオフで再接続し、切断中は送信不可。
  **自動再送はしない**。送信後の切断では結果不明と表示し、履歴を確認して再送する。

認証、複数ルーム、永続履歴、複数プロセス間配信、レート制限は実装していない。
接続・サイズ・キュー制限は認証やレート制限の代わりではない。
本番化には TLS、認証/認可、Origin の適切な設定、監視、永続化、
冪等な送信確認・再送設計、負荷対策が必要。

### Pong プロトコル

パス `/pong/socket`、サブプロトコル `leanwebstudy-pong`。接続時にサーバーが
プレイヤー番号（1、2、または観戦者0）と参加人数を送る。入力は以下のJSONで、
Leanが座標とスコアの範囲を検証する。

```json
{"type":"paddle","y":123}
{"type":"ball","x":400,"y":225,"left":1,"right":0}
```

サーバーは送信者番号を付けて対戦中の接続へ中継する。ボール更新はプレイヤー1
のみ送信できる。ブラウザー上の物理演算をプレイヤー1が担当する学習用設計であり、
サーバー権威型ではない。認証のないローカルサンプルであるため、公開環境で使わない。

## 検証

```sh
lake test
python3 -m unittest discover -s tests -p 'test_chat.py'
python3 -m unittest discover -s tests -p 'test_dev.py'
```

チャットテストは自分で起動・停止する実サーバーに対して、複数接続への配信、
履歴・再接続・最新50件、入力・接続数制限、断片化、Ping/Pong、Close、
Origin・サブプロトコル拒否、Pongのプレイヤー割当・入力検証・中継・切断通知、
プレビュートンネルを検証する。Python 標準ライブラリーのみを使い、
テストのための WebSocket パッケージは追加しない。
