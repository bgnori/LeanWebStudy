# WebSocket チャットの技術選定と使い方

実装を通して得られた知見のリスク・リターン / コスト・リターン分析は
[websocket-risk-return-report.md](./websocket-risk-return-report.md) を参照。

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

## HTTP Upgrade と接続の引き渡し

Lean の `Std.Http.Server` と `ws-lean` を組み合わせること自体が不可能という
意味ではない。難所は WebSocket フレーム処理よりも、既存 HTTP 接続を HTTP
サーバーから WebSocket ランタイムへ渡す境界にある。

`Std.Http.Server.Handler` はリクエストを受けて HTTP Response を返す抽象であり、
接続ソケットを Handler に公開しない。101 を通常の Response として返しても、
サーバー側の接続処理はその接続を引き続き所有するため、以後の読み書きを
WebSocket に切り替える契約にはならない。統合するなら、Upgrade を通常応答と
区別して表現し、101 の送信後に接続の読み書き権限を一方的に移す仕組みが要る。

この引き渡しでは、少なくとも次の状態を一貫させなければならない。

- HTTP パーサーがソケットから先読みしたバイトがあれば、Upgrade 後の最初の
  WebSocket フレームを失わないよう、その残りをストリームとともに渡す。
- 101 の送信前後で HTTP と WebSocket の両方が同じソケットを読んだり書いたり
  しないよう、所有権と切り替え時点を明確にする。
- 接続ごとの非同期タスク、キャンセル、切断、サーバー停止、エラー時の後始末を
  HTTP サーバーの接続管理と WebSocket 側で二重管理しない。
- Lithe を経由する場合は、Lithe の WebSocket Handler が要求する Rust Shim 側の
  Upgrade と、Std HTTP サーバー側の接続引き渡しの両方を接続する。

つまり、単に `ws-lean` の API を呼び出すだけでは済まず、Handler の結果型、
HTTP 接続ループ、ストリーム／バッファ、非同期タスクのライフサイクルにまたがる
設計変更になり得る。これは「仕様が汚い」と断定するより、短い HTTP request /
response を前提にした抽象と、長時間存続する双方向セッションとの境界が噛み合わず、
接続状態と処理状態の整合性を保つ責任が呼び出し側に漏れやすい、と捉えるのが
正確である。

## 初期実装の判断（2026-10-31）

2026-10-31 時点では、現状の libwebsockets を使う方針は妥当と判断する。
Std HTTP サーバーへの Upgrade 機能追加や独自接続ループの保守を避けつつ、
HTTP は既存の Std / Lithe 構成のまま、WebSocket のプロトコル処理は専用ライブラリーに
任せられるためである。別リスナーとシステム開発ライブラリーへの依存は代償だが、
このローカル学習用アプリでは、接続所有権の移譲を新たに実装・保守するより小さい。

同一ポート化や Lean のみでの実装が要件になった場合は、Std 側の Upgrade API、
接続ループの独自実装、または別の HTTP サーバーへの移行を改めて比較する。
`ws-lean` は有力なプロトコル層の候補だが、HTTP 接続の引き渡し経路は別途必要であり、
公開 README ではプレリリースで高レベル API が変更され得るとされている。

## 候補とトレードオフ

| 候補 | 利点 | 費用・制約 | 判断 |
| --- | --- | --- | --- |
| Std.Async.TCP 上で RFC 6455 を自作 | Lean のみで同じポートに統合できる | SHA-1/Base64、マスク、断片化、UTF-8、Ping/Pong、Close、バックプレッシャーを維持・検証する必要がある | サンプルのための独自プロトコル実装を避ける |
| [websocket.lean](https://github.com/cleissonbarbosa/websocket.lean) | Lean のプロトコル・サーバー API がある | 公開 README は beta。調査時の `lean-toolchain` は 4.21.0、Alloy を master から取得。4.35.0 との互換性・固定化の検証が別途必要 | 今回は不採用。互換性がないと断定したわけではない |
| [ws-lean](https://github.com/pb64-lean/ws-lean) | Lean 製の RFC 6455 プロトコル層。HTTP/1.1 Upgrade、TCP/TLS、非同期接続ランタイム等を提供 | プレリリースで高レベル API は変更され得る。既存 Std HTTP 接続をUpgrade後に渡す経路は別途必要 | 将来の候補。現行構成では接続引き渡しの設計・保守が増える |
| [Python websockets](https://websockets.readthedocs.io/en/stable/intro/index.html) | フレーム処理が成熟し、asyncio / Sans-I/O を提供 | Python サービスと追加パッケージの起動・終了・依存管理が必要。アプリ本体が複数ランタイムになる | 既存 Python は開発ツールのみなので不採用 |
| [libwebsockets](https://libwebsockets.org/) | 継続的に開発される C ライブラリー。非同期イベントループ、断片化、制御フレームなどを担当。既存 SQLite C FFI と同じビルド方式に乗る | システム開発ライブラリーが増える。C のキュー・ライフサイクル管理、別リスナーが必要 | **採用** |

## ws-lean 比較版（2026-11-02）

`/chat/`（libwebsockets）を残し、`/chat-ws/`（ws-lean）を追加した。
トップページと両チャットのリンクから切り替えられる。両方をそれぞれ二つのタブで
開いて比較する。履歴・連番・接続は実装ごとに独立しており、相互には配信しない。
画面の再接続、送信確認、重複防止、HTML 安全表示は
`LeanWebStudy/ChatPage.lean` を共有し、サーバーの JSON 検証は
`LeanWebStudy.Chat.response` を共有する。

### Lake と Lean 4.35.0 での確認結果

Codespaces の既存ツールチェーン `leanprover/lean4:v4.35.0` を変更せず、
`lake update ws-lean` で取得し、実際にビルドした。upstream の toolchain は
`nightly-2026-04-25` だが、それだけを理由に利用不可とはしていない。

- `lakefile.lean` で ws-lean を
  `2a6665a120993533122bcbfa076ef35c17025bea` に固定。
  `lake-manifest.json` もコミットし、推移依存の http2-lean
  `82fc066025f3e5fdec54c836f4e9659c2f8176ab`、tls13-lean
  `4fa14fe068d9ea17c85294a6a27c224b2de5cddb` を再現する。
- `lake build Ws` は `Tls.Handshake` と `Http2.Frame` の証明の型・rewrite エラーで失敗した。
  upstream は Bazel を正式なビルド、Lake をエディター用モデルとしている。
  **ws-lean 全体の Lean 4.35.0 互換性を確認できたという意味ではない。**
- HTTP/1.1 に必要な `Ws.Message`、`Ws.Transport.Http1`、
  `Ws.Transport.Plain` に import を限定すると、無改変の upstream で
  `lake build LeanWebStudy.WsChat` と `lake build` が成功した。
  `Http2.CancellationToken` の小さな互換ヘルパーは利用するが、HTTP/2/TLS は使わない。
- `Ws.Connection` もコンパイルできたが、その高レベル送受信は通常ワーカーの
  IO ポーリングを使い、この 2 CPU 環境では履歴送信が停止した。
  そのため本サンプルは同 API や `Ws.Server` を使わず、sans-I/O 層を採用する。
  過去の ws-lean 版は `../grpc-lean` という相対依存を持つため採用しなかった。
- 依存キャッシュへのパッチ、`sorry`、ツールチェーン変更、コピーしたプロトコル実装はない。
  圧縮・TLS を使わないため upstream の zlib/HACL ネイティブ FFI もリンクしない。
  既存版と SQLite のシステム依存は引き続き必要。

再確認は `lake update ws-lean`、`lake build LeanWebStudy.WsChat`、`lake build`。
アップグレード時は SHA と manifest を一緒に更新し、以下の実通信テストを再実行する。
`lake build Ws` の成功を本サンプルのビルド条件にはしない。

### 実装と比較範囲

`LeanWebStudy/WsChat.lean` は別の loopback TCP リスナーを同一プロセス内で起動する。
ws-lean が HTTP/1.1 Upgrade、先読みバイト保持、フレームのマスク・サイズ・opcode
検証、断片化、UTF-8、Close payload を処理する。アプリ側が履歴・配信・Origin と
サブプロトコルの許可、Ping/Pong の送信、タスクの後始末を担当する。
Std HTTP サーバーからの接続移譲は不要で、C ブリッジは追加していない。

| 項目 | libwebsockets `/chat/` | ws-lean `/chat-ws/` |
| --- | --- | --- |
| WebSocket パス | `/chat/socket` | `/chat-ws/socket` |
| ポート発見 | `/chat/endpoint` | `/chat-ws/endpoint` |
| JSON / サブプロトコル | 下記の共通仕様 | 同じ `leanwebstudy-chat` |
| 履歴 / 検証 / 再接続 UI | 最新50件、全接続配信 | 同じ、ただし履歴は別 |
| プロトコル層 | システム C ライブラリー | Lean の ws-lean sans-I/O |
| 実行・待ち行列 | C イベントループ | Std.Async と有界キュー |

ws-lean 版は未完了 Upgrade を含む最大64接続、接続ごとの配信待ち最大64イベント、
制御待ち最大64フレーム。履歴登録・購読開始・配信投入は同じ mutex 内で順序付けし、
履歴を最初に送ってから受信を始める。ネットワーク書き込みは mutex の外で単一の
送信処理が担当し、遅い接続は Close 1008 または書き込み失敗・期限で切断する。
キュー確認には短い Async sleep を使うが、ネットワーク上のポーリングは行わない。

受信フレーム・結合メッセージは8192バイト、断片数4096、HTTP head は16 KiB、
ヘッダー最大32個。送信履歴は8192バイトを超えても全50件を返す。
binary は1003、無効 UTF-8 は1007、サイズ超過は1009。
20秒間隔で Ping、最後の有効フレームから30秒無応答で1001。
Upgrade は10秒、書き込みは5秒、Close の応答待ちは最大1秒。
受信タスクと期限付き処理は明示的に回収し、成功後に切断する残存タイマーを作らない。
圧縮・TLS・HTTP/2 は交渉せず、この比較版も認証のないローカル学習用途に限定する。

libwebsockets はプロトコル処理、Lean は JSON の検証・配信イベント生成を担当する。
最新 upstream のライセンスは公式サイト上 MIT。配布版のライセンスはその版の
同梱文書を確認する（Ubuntu のパッケージには別の履歴上の表記があり得る）。
本リポジトリにはライブラリーのコードをコピーせず、システムライブラリーにリンクする。
Ubuntu のパッケージ更新を利用するため Lake の Git 依存には追加しない。

## SSE 版チャット

比較用に `/chat-sse/` も実装している。受信は同じ Std HTTP サーバーのストリーミング
レスポンス上の Server-Sent Events、投稿は `/chat-sse/send` への URL-encoded POST。
ブラウザーの `EventSource` が切断後の再接続を行い、接続時にサーバーから最新50件を
再送する。イベントには連番IDと投稿ごとの requestId を含め、画面側で重複表示を避ける。

SSE はサーバーからクライアントへの一方向配信なので、投稿は別のHTTP要求になる。
この用途では双方向WebSocketのHTTP Upgradeは不要だが、Std HTTPのストリーミングBodyを
使えるようLitheレスポンスをStdのストリーミングBodyへ変換するアダプターが必要だった。
開発プレビューも `/chat-sse/events` の応答を逐次転送し、投稿POSTをバックエンドへ中継する。
プレビューはHost/Originを検証し、バックエンドも投稿OriginをHostと照合する。

SSE版もメモリー内の履歴は最新50件、最大64接続で、各接続の待ち行列には上限を設ける。
履歴は再起動で消える。チャットの比較・学習用であり、認証や永続化を備えた本番用途ではない。
WebSocket版は `/chat/` と `/chat-ws/` から利用できる。

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
ws-lean 版は <http://127.0.0.1:8080/chat-ws/> を二つのタブで開く。
watcher 経由でも既定の <http://127.0.0.1:8080/> から両方を選べる。

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
  `/chat/socket`、`/chat-ws/socket` または `/pong/socket` に接続する。Python のプレビューが handshake
  とバイト列を転送する。フレームの解析・再実装や HTTP ポーリングは行わない。
- `GET /chat/endpoint` は watcher の接続時のポート発見用メタデータ。
  ws-lean の場合は `GET /chat-ws/endpoint` で別リスナーを発見する。
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
python3 -m unittest discover -s tests -p 'test_dev*.py'
```

チャットテストは自分で起動・停止する実サーバーに対して、両WebSocket実装で共通の複数接続への配信、
履歴・再接続・最新50件、入力・接続数制限、断片化、Ping/Pong、Close、
Origin・サブプロトコル拒否、Pongのプレイヤー割当・入力検証・中継・切断通知、
プレビュートンネルを検証する。Python 標準ライブラリーのみを使い、
テストのための WebSocket パッケージは追加しない。
ws-lean 固有では履歴の分離、8192バイトを超える履歴、同時投稿の配信順、
Upgrade と同時に届く最初のフレーム、Close 後のデータ無視、Ping/Pong の生存確認、
無応答切断、未完了 Upgrade の期限も検証する。タイマー検証は実時間で約30秒かかる。
動的ページは別プロセスで Lean を起動するため、HTTP テストは初回生成を最大30秒待つ。
watcher 統合テストは更新ごとに全ページを検査し、各更新を最大180秒待つ。
保存・エラー復旧・追加・削除を繰り返すため、全体で10分以上かかる場合がある。
