# モジュール更新後に SQLite ページが変わらない場合

## 結論

**このリポジトリの実装では、Lithe とページの動的読み込みの相性が悪いという
証拠はありません。更新対象によって、読み直される範囲が異なります。**

ブラウザーの再読み込みで更新されるのは、リクエストごとに実行するページ本体です。
import 先のソースや、常駐サーバーの実装・SQLite 初期データまで更新する仕組みでは
ありません。ページが新しくても、そのページに渡す HTML やデータが旧サーバー由来なら、
表示の一部は旧実装のままになります。

2026-10-31、コミット `f5089c46ee77f4eca0e2b4d2aa9c63403fb629d5` のコードと
Lean 4.35.0、固定された Lithe `197bc2d6ba0f79c307cf01e2426c84299a1c23d6` で調査しました。
元の事象のサーバー起動時刻・起動コマンド・応答・ログは取得していないため、
当時の直接原因は断定できません。ただし、SQLite 更新が反映されない経路は
コードと実行の両方で確認できました。

## 実際の読み込み経路

```text
ブラウザーから GET /sqlite/users
  → Std.Http.Server
  → Lithe.dispatch（起動時に作った Router）
  → fallback → WebHandler.servePage
  → Pages/sqlite/users.lean の存在・パスを確認
  → 常駐サーバーが SQLite を問い合わせ、Page.Context を生成
      usersHtml / sqliteDemoHtml はここで生成
  → 新しいプロセスで lake env lean --run <ページソース>
      ページ本体は現在のソース、import 先はビルド成果物
  → ページが Context の HTML を組み合わせて返す
  → Cache-Control: no-store を付けて応答
```

- [DevPages.render](../LeanWebStudy/DevPages.lean) は毎回 `IO.Process.output` で
  worker を起動します。ページソースやレンダリング結果のキャッシュはありません。
- [Lithe の dispatch](../.lake/packages/lithe/Lithe/Runtime/Dispatch.lean) は
  ルートに一致する handler または fallback をそのリクエストで実行します。
  この経路に応答キャッシュはありません。
- [ルート登録と pageContext](../LeanWebStudy.lean) では `/health`、`/api/query` を
  明示登録し、ページは fallback に渡します。ページの追加ごとのルート登録は不要です。
- [Main](../Main.lean) は起動時に database、counter、handler を作り、そのまま
  サーバーを動かします。実行中の handler を新しいバイナリーへ差し替える処理はありません。

これは **別プロセスでのページソース再実行** です。サーバープロセス内での
ネイティブモジュールの unload/reload や hot replacement ではありません。
Lithe の一般的な動的ライブラリー交換の可否まで検証した結果ではなく、
本プロジェクトで使用する経路についての結論です。

## SQLite サンプルで特に起きやすい理由

[SQLite users ページ](../Pages/sqlite/users.lean) と
[SQLite index ページ](../Pages/sqlite/index.lean) は主に外枠を組み立て、
`context.usersHtml` と `context.sqliteDemoHtml` を挿入します。
SQL の説明、Statement、パラメーター、実行結果の HTML はページ側ではなく、
[サーバーの sqliteDemoHtml / pageContext](../LeanWebStudy.lean) にあります。

今回のコミットでは、同名の2人から email 列だけを SELECT する例とその HTML、
[SampleData](../LeanWebStudy/SampleData.lean) の fixture などが変更されています。
これらは常駐サーバーに組み込まれる変更です。**ページを再読み込みするだけでは
追加された SELECT 例や変更された fixture は反映されません。**

さらに [Database.seededMemory](../LeanWebStudy/Database.lean) は起動時に一度だけ
`:memory:` データベースを作り、fixture を投入します。`lake build` に成功しても、
すでに動いているプロセスのコードやデータベースは変わりません。新しいバイナリーで
再起動する必要があり、その際に DB とリクエスト番号はリセットされます。

### 新旧の Context が混ざる場合

[Page.Context の JSON decoder](../LeanWebStudy/Page.lean) は、
`sqliteDemoHtml` フィールドがない入力を互換性のため `""` として受け入れます。
そのため、古い Context producer と新しいページ・decoder の組み合わせでは、
HTTP エラーにならず、SQLite の説明部分だけが欠けることがあります。

これは欠落フィールドに対する互換処理です。古いサーバーが `sqliteDemoHtml` を
送っている場合は、その古い HTML が表示されます。今回の元の事象でフィールド欠落が
起きたと断定するものではありません。

## 更新対象ごとの必要操作

| 変更対象 | ブラウザーの再読み込みだけ | 必要操作 |
| --- | --- | --- |
| `Pages/**/*.lean` のページ本体 | 反映される | 保存して再読み込み |
| ページの追加・削除 | 反映される | 追加先の URL を開く／削除後は 404 |
| ページだけが import する helper | ソース変更だけでは反映されない | 対象モジュールを `lake build <module>` して再読み込み |
| ページとサーバーが共有する helper / `Page.Context` | 両者をそろえる必要あり | `lake build` 後、新しいサーバーへ再起動 |
| `LeanWebStudy.lean` の SQL・HTML 生成・ルート・handler | 反映されない | `lake build` 後、再起動 |
| `Database.lean` / `SampleData.lean` / native bridge | 反映されない | `lake build` 後、再起動・DB 再作成 |
| Lake 依存の更新 | 更新解決だけでは不十分 | 必要な依存を更新し、ビルド。サーバーが使う依存なら再起動 |

ページ helper の例は `lake build LeanWebStudy.Page` です。ただしこのモジュールは
サーバーも使うため、共有インターフェースを変更した場合は再起動まで行ってください。

`lake env` は環境を設定してコマンドを起動するもので、import 先を自動ビルドする
コマンドではありません。`lake exe` は実行対象を必要に応じてビルドしてから
**新しいプロセス** を起動します。すでに起動済みのサーバーは更新しません。
`lake update` も依存の解決・更新であり、実行中のサーバーのリロードではありません。

また、`--dev` なしでもページ worker は毎回実行されます。現在の `--dev` は
ページディレクトリーの指定に使われ、サーバーモジュールの監視・再起動を有効にする
スイッチではありません。

## 確実な反映手順

SQLite のサンプル実装や初期データを変えた場合は、プロジェクトのルートで実行します。

1. 既存サーバーを、その起動ターミナルの Ctrl+C で停止する。
2. 次を実行し、ビルド成功とサーバーの起動ログを確認する。

   ```sh
   lake build
   lake exe leanwebstudy 8080
   ```

3. <http://127.0.0.1:8080/sqlite/users> を開く。今回の変更なら
   「4. 同名の2人のemailだけをSELECT」と、以下の結果が表示される。

   ```json
   [["user-1@example.invalid"],["user-2@example.invalid"]]
   ```

`lake exe` の起動時ビルドだけに任せることもできますが、上の手順はビルドと起動を
切り分けて確認できます。依存指定を変更していなければ、通常は `lake update` は不要です。

## 表示が変わらないときの診断

### 1. ブラウザーを介さず HTTP 応答を見る

```sh
curl -fsS -D - http://127.0.0.1:8080/sqlite/users
```

ページ応答の `Cache-Control: no-store` と本文を確認します。curl でも旧本文なら、
まずサーバー・ビルド・ページディレクトリーを調べます。curl が新しくブラウザーだけ
古ければ、URL／ポートやブラウザー・中間層の状態を調べます。アプリケーション側の
キャッシュ無効化だけで、すべての外部キャッシュが不存在とは断定できません。

### 2. 起動したプロセスとページディレクトリーを確認する

起動ログの `Listening on ...` と `Pages: ...` が、アクセス先と編集対象に一致するか
確認します。別ポート・別 checkout・`--dev` で指定した別ディレクトリーに注意します。
すでにポートが使われているなど、新サーバーの起動が失敗した場合は、ブラウザーが
旧サーバーを見続ける可能性があります。起動成功を確認せずに更新済みと判断しないでください。

### 3. ページ外枠とサーバー由来の内容を区別する

ページ本体の見出し変更は反映されるのに SQL の説明が変わらないなら、
`sqliteDemoHtml` の生成側を確認します。`Page request` が増えることは新しい
リクエストの証拠であって、サーバーが新しいコードになった証拠ではありません。

`/api/query` はリクエスト番号を `id > ?` のパラメーターに使うので、番号が10以上なら
空配列になります。ページの固定 `id > 3` のデモとは別です。
API の空配列だけをリロード失敗の判定に使わないでください。

### 4. ビルドエラー・worker エラーを確認する

import 先をビルドせずページだけを実行すると、旧成果物を読むか、
成果物が存在しなければ import エラーになります。ページのコンパイル・実行・
プロトコルエラーは HTTP 500 となり、詳細はサーバーの stderr に記録されます。
ビルドが失敗した場合も、そのまま旧バイナリーを起動しないでください。

## 実行確認の結果

調査中の検証は一時 fixture と専用ポートを使い、検証用サーバーは終了させました。
アプリケーションの実装は変更していません。

| 検証 | 結果 |
| --- | --- |
| `lake build leanwebstudy LeanWebStudy.Page` | 成功 |
| `bash tests/dev-pages-smoke.sh 19182` | PASS。サーバーを再起動せず、ページ編集・追加・削除、入れ子、エラー復旧、共有状態、パス制限、遅いページ中の health 応答を確認 |
| 一時 helper の `.olean` を v1 で作成後、helper ソースとページ本体を v2 にして新しい worker を実行 | `page-v2/helper-v1`。ページだけ新しく、import 先は旧成果物 |
| helper の `.olean` を v2 で再生成して新しい worker を実行 | `page-v2/helper-v2` |
| ビルド済みの現行サーバーをポート19183で新規起動して `/sqlite/users` にアクセス | 新しい email SELECT の見出し、正確に2行の email 結果、`no-store` を確認 |
| `sqliteDemoHtml` を含まない JSON を現行 SQLite ページへ渡す | 実行は成功し、デモ部分は非表示。互換 decoder の挙動を確認 |

既存の [dev-pages-smoke.sh](../tests/dev-pages-smoke.sh) が保証しているのは、
ページ本体の再読み込みです。サーバーモジュールの自動差し替えや、import 先の
自動ビルドを検証するテストではありません。

## 追記：保存だけで反映する開発ループ

調査後、第1段階として [tools/dev.py](../tools/dev.py) を追加しました。
`python3 tools/dev.py` で開発用プレビューを起動すると、保存検知 →
ビルド → 全ページの型チェック → サーバー再起動 → health 確認 →
ブラウザー自動更新を行います。失敗・更新中・監視との切断は画面に明示します。
元の通常サーバーに hot replacement を追加するものではありません。

このモードでは SQLite の初期データ変更も再起動で反映されますが、
毎回インメモリー DB とカウンターがリセットされます。
画面の URL・スクロール位置は保ち、フォーム入力などは保持しません。
更新途中の旧画面は残しますが、新旧コード混在を避けるため旧バックエンドは
ビルド前に停止します。詳細と制限は [README](../README.md#save-to-preview-development-loop)
を参照してください。

以下は第2段階以降の検討事項です。まずは更新漏れを防ぐ広い監視と
毎回のビルド・再起動を使い、ログの処理時間を基に必要な箇所だけ短縮します。

第1段階の検証環境では、ページ編集の更新処理は約9〜11秒、fixture の変更は
約15秒でした。これはビルド開始から health 成功までの時間で、保存検知・
debounce・ブラウザーのページ実行と描画は含みません。環境依存の参考値であり、
即時・サブ秒の反映を保証するものではありません。

Lithe を交換する前に、更新境界を設計する必要があります。

- 表示専用の構成をページ側へ移す。ただし import helper のビルド問題は残る。
- ページのみ・ページ専用 helper の変更では、依存関係を確認して
  サーバー再起動を省略する。現在は変更対象を区別せず再起動する。
- DB の持続が必要なら、再起動で消える `:memory:` と別に、永続化・migration を設計する。

Context の新旧混在を明示的に検出したい場合は、バージョン照合も検討対象です。
互換 decoder をただ厳格化すると旧 producer を壊すため、意図した仕様変更として
テストする必要があります。これらの最適化・永続化・Context バージョン照合は
実装していません。

## 根拠

- [Main.lean](../Main.lean)：起動時の DB 作成、handler 作成、ページディレクトリー選択。
- [LeanWebStudy.lean](../LeanWebStudy.lean)：サーバー側の SQLite HTML 生成、
  Context 作成、ページ応答の `no-store`、Lithe へのルート登録・dispatch。
- [DevPages.lean](../LeanWebStudy/DevPages.lean)：リクエストごとのページ探索と
  `lake env lean --run` worker。
- [Page.lean](../LeanWebStudy/Page.lean)：Context の互換 decoder とページ実行プロトコル。
- [Database.lean](../LeanWebStudy/Database.lean) /
  [SampleData.lean](../LeanWebStudy/SampleData.lean)：起動時の fixture 投入。
- [固定依存の Lithe dispatch](../.lake/packages/lithe/Lithe/Runtime/Dispatch.lean) /
  [Router](../.lake/packages/lithe/Lithe/Router/Router.lean)：handler の保持・選択・実行。
  これらのローカルリンクは依存取得後に参照可能。
- インストール済み Lean 4.35.0 の `Lake/CLI/Actions.lean` の `env` / `exe` 実装、
  および `lake help env` / `lake help exe`：
  `env` は環境付きプロセス起動、`exe` はビルドして起動。
