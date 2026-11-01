import MapleSQL
import LeanWebStudy.SampleData

namespace LeanWebStudy

private opaque DatabaseImpl : NonemptyType

def Database : Type := DatabaseImpl.type

instance : Nonempty Database := DatabaseImpl.property

@[extern "leanwebstudy_sqlite_open_memory"]
opaque Database.openMemory : IO Database

@[extern "leanwebstudy_sqlite_execute"]
private opaque Database.executeNative (db : @& Database) (sql : @& String)
    (params : @& Array MapleSQL.Value) : IO (Array (Array MapleSQL.Value))

-- SQLite INTEGER is signed 64-bit, whereas MapleSQL integers are unbounded.
def Database.execute (db : Database) (query : MapleSQL.Formatted) :
    IO (Array (Array MapleSQL.Value)) := do
  for param in query.params do
    if let .integer value := param then
      if value < -9223372036854775808 || value > 9223372036854775807 then
        throw (IO.userError "SQL parameter is outside SQLite's signed 64-bit integer range")
  db.executeNative query.sql query.params

def renderQuery (statement : MapleSQL.Statement) : IO MapleSQL.Formatted :=
  match MapleSQL.render statement with
  | .ok query => pure query
  | .error error => throw (IO.userError s!"SQL generation failed: {error}")

def Database.seededMemory : IO Database := do
  let db <- Database.openMemory
  discard <| db.execute {
    sql := SampleData.sqliteSchema
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL, message TEXT NOT NULL)"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE wiki_articles (slug TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL)"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE shop_products (slug TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, price INTEGER NOT NULL, art TEXT NOT NULL, kind TEXT NOT NULL, badge TEXT NOT NULL, description TEXT NOT NULL, details TEXT NOT NULL)"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE shop_cart_items (product_slug TEXT PRIMARY KEY, quantity INTEGER NOT NULL, FOREIGN KEY (product_slug) REFERENCES shop_products(slug))"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE shop_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_name TEXT NOT NULL, postal_code TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, total INTEGER NOT NULL, payment_status TEXT NOT NULL, fulfillment_status TEXT NOT NULL)"
    params := #[] }
  discard <| db.execute {
    sql := "CREATE TABLE shop_order_items (order_id INTEGER NOT NULL, product_slug TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price INTEGER NOT NULL, FOREIGN KEY (order_id) REFERENCES shop_orders(id), FOREIGN KEY (product_slug) REFERENCES shop_products(slug))"
    params := #[] }
  let shopProducts := #[
    #["canvas-tote", "毎日のキャンバストート", "バッグ · オーガニックコットン",
      "3850", "👜", "tote", "BEST SELLER",
      "しっかりとしたオーガニックコットンのトート。A4サイズがすっぽり入り、肩にかけても手に持っても使いやすい長さに仕上げました。",
      "カラー：生成り\nサイズ：約 幅36 × 高さ38 × マチ10 cm\n素材：オーガニックコットン 100%"],
    #["linen-shirt", "風をまとうリネンシャツ", "ウェア · リネン100%",
      "8800", "👕", "shirt", "NEW",
      "さらりとした肌ざわりのリネンを、ゆったりとしたシルエットに。洗いざらしの自然な風合いを楽しめる一枚です。",
      "カラー：セージグリーン\nサイズ：フリー\n素材：リネン 100%"],
    #["cotton-scarf", "やわらかコットンスカーフ", "小物 · コットンガーゼ",
      "2750", "🧣", "scarf", "再入荷",
      "空気をふくんだ二重ガーゼのスカーフ。首もとに巻いたり、日よけにしたり、季節を問わず軽やかに使えます。",
      "カラー：テラコッタ\nサイズ：約 50 × 180 cm\n素材：コットン 100%"],
    #["canvas-sneakers", "歩くためのキャンバススニーカー", "靴 · コットンキャンバス",
      "13200", "👟", "shoes", "NEW",
      "足の動きに沿うやわらかなソールと、丈夫なキャンバス地のスニーカー。街歩きにも小さな旅にも似合う、飾りすぎない一足です。",
      "カラー：オフホワイト\nサイズ：23 / 24 / 25 / 26 / 27 cm\n素材：コットン、天然ゴム"],
    #["brass-ballpoint", "真鍮のボールペン", "文房具 · 無垢真鍮",
      "2400", "🖊️", "pen", "LONG LIFE",
      "使うほど手になじみ、色つやが深まる無垢真鍮のボールペン。替芯を交換しながら長く使える、日々のための筆記具です。",
      "カラー：真鍮素地\nサイズ：約 13.5 cm\n素材：真鍮\n替芯：油性黒 0.7 mm"],
    #["storage-box-small", "重なる収納箱・小", "収納 · 再生紙",
      "990", "📦", "box-small", "SMALL",
      "文房具やケーブルなど、細かなものをまとめる小さな収納箱。棚の中でも机の上でも使いやすいサイズです。",
      "カラー：クラフト\nサイズ：約 幅18 × 奥行12 × 高さ8 cm\n素材：再生紙"],
    #["storage-box-medium", "重なる収納箱・中", "収納 · 再生紙",
      "1800", "📦", "box-medium", "MEDIUM",
      "手帳や郵便物、日用品をひとまとめに。小サイズを二つ並べて収められ、同じシリーズで気持ちよく重なります。",
      "カラー：クラフト\nサイズ：約 幅36 × 奥行24 × 高さ12 cm\n素材：再生紙"],
    #["storage-box-large", "重なる収納箱・大", "収納 · 再生紙",
      "3200", "📦", "box-large", "LARGE",
      "衣類やブランケットまで収まる大きな収納箱。持ち手穴があり、クローゼットからの出し入れも簡単です。",
      "カラー：クラフト\nサイズ：約 幅48 × 奥行36 × 高さ24 cm\n素材：再生紙"]]
  let shopInsert <- renderQuery (.insert "shop_products"
    #["slug", "name", "category", "price", "art", "kind", "badge", "description", "details"]
    (shopProducts.map fun row => #[
      .text row[0]!, .text row[1]!, .text row[2]!, .integer row[3]!.toInt!,
      .text row[4]!, .text row[5]!, .text row[6]!, .text row[7]!, .text row[8]!]))
  discard <| db.execute shopInsert
  let inventoryInsert <- renderQuery (.insert "shop_inventory" #["product_slug", "stock"]
    (shopProducts.map fun row => #[.text row[0]!, .integer 20]))
  discard <| db.execute {
    sql := "CREATE TABLE shop_inventory (product_slug TEXT PRIMARY KEY, stock INTEGER NOT NULL, FOREIGN KEY (product_slug) REFERENCES shop_products(slug))"
    params := #[] }
  discard <| db.execute inventoryInsert
  let wikiSeed := #[
    #["welcome", "Wikiへようこそ", "このWikiはLean 4、lean-html、Lithe、MapleSQL、SQLiteで作られています。\n\n記事の新規作成・編集・削除を試せます。"],
    #["lean-basics", "Lean 4の基本", "Leanは定理証明支援系であり、関数型プログラミング言語でもあります。\n\nこのサンプルのページとサーバーはLeanで実装されています。"],
    #["sqlite-basics", "SQLiteの基本", "SQLiteはアプリケーションに組み込める軽量なリレーショナルデータベースです。\n\nこのWikiでは記事をSQLiteに保存し、MapleSQLでSQLとパラメーターを分けて操作します。"]]
  let wikiInsert <- renderQuery (.insert "wiki_articles" #["slug", "title", "content"]
    (wikiSeed.map fun row => row.map MapleSQL.Value.text))
  discard <| db.execute wikiInsert
  let insert <- renderQuery SampleData.insertStatement
  discard <| db.execute insert
  return db

end LeanWebStudy
