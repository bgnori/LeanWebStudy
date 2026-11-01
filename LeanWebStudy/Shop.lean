import Html
import LeanWebStudy.Page

open Html

namespace LeanWebStudy.Shop

private def styles : String := r#"
:root{font-family:Inter,"Noto Sans JP",ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#252b25;background:#f8f8f3;font-synthesis:none;text-rendering:optimizeLegibility}
*{box-sizing:border-box}body{margin:0}a{color:inherit}.shell{max-width:1180px;margin:auto;padding:0 28px}
.topline{background:#263b32;color:#f6f5eb;text-align:center;padding:9px 16px;font-size:12px;letter-spacing:.08em}
.header{background:#f8f8f3;border-bottom:1px solid #e8e9df}.nav{min-height:76px;display:flex;align-items:center;justify-content:space-between;gap:26px}
.brand{font-family:Georgia,serif;font-size:26px;font-weight:700;letter-spacing:-.06em;text-decoration:none}.brand span{color:#7b8f5b}
.navlinks{display:flex;align-items:center;gap:30px}.navlinks a,.cart-link{font-size:13px;text-decoration:none;color:#596057}
.navlinks a:hover,.text-link:hover{color:#68794c}.cart-link{border:1px solid #dfe1d7;padding:10px 15px;border-radius:999px}
.page{padding:42px 0 84px;min-height:68vh}.crumb{font-size:12px;color:#7a8077;margin:0 0 26px}.crumb a{color:inherit;text-decoration:none}
.eyebrow{font-size:11px;letter-spacing:.17em;font-weight:700;color:#76865a;text-transform:uppercase}h1,h2,h3,p{margin-top:0}
h1{font-family:Georgia,"Noto Serif JP",serif;font-size:clamp(34px,5vw,58px);line-height:1.13;letter-spacing:-.04em;font-weight:500;margin-bottom:20px}
h2{font-family:Georgia,"Noto Serif JP",serif;font-size:32px;font-weight:500;letter-spacing:-.03em;margin-bottom:12px}h3{font-size:15px;margin-bottom:7px}
.muted{color:#70776e;line-height:1.8}.hero{display:grid;grid-template-columns:1fr 1fr;min-height:440px;background:#e8ebde;border-radius:8px;overflow:hidden}
.hero-copy{padding:clamp(30px,6vw,76px);align-self:center}.hero-copy p{max-width:390px}
.hero-art{position:relative;display:grid;place-items:center;min-height:300px;background:radial-gradient(ellipse at 50% 58%,#d1d8be 0 23%,transparent 23.5%),linear-gradient(145deg,#e1e6d5,#c5cfb6)}
.hero-art:before,.hero-art:after{content:"";position:absolute;border:1px solid #84946f;border-radius:50%;width:260px;height:260px}.hero-art:after{width:205px;height:205px}
.hero-art span{position:relative;z-index:1;font-size:104px;filter:drop-shadow(0 18px 14px #64735040)}
.button{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:0 22px;background:#334a3c;color:#fff;text-decoration:none;border:0;border-radius:3px;font-size:13px;font-weight:650;letter-spacing:.03em;cursor:pointer}
.button:hover{background:#263b32}.section-head{display:flex;align-items:end;justify-content:space-between;gap:20px;margin:68px 0 24px}.section-head h2{margin-bottom:0}
.text-link{font-size:13px;text-decoration:none;color:#596057}.product-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px}.product-card{text-decoration:none}
.product-visual{height:285px;position:relative;display:grid;place-items:center;overflow:hidden;border-radius:5px}.product-visual.tote{background:#e8e4d7}.product-visual.shirt{background:#e4e8e3}.product-visual.scarf{background:#ede5dc}.product-visual.shoes{background:#e3e7e0}.product-visual.pen{background:#e8e1d5}.product-visual.box-small,.product-visual.box-medium,.product-visual.box-large{background:#e7e0d3}.product-visual.box-small .art{font-size:70px}.product-visual.box-medium .art{font-size:88px}.product-visual.box-large .art{font-size:108px}
.product-visual .art{font-size:96px;filter:drop-shadow(0 14px 12px #454b3520);transition:transform .25s}.product-card:hover .art{transform:translateY(-5px) rotate(-3deg)}
.tag{position:absolute;top:14px;left:14px;padding:6px 9px;background:#f8f8f3;border-radius:2px;font-size:10px;letter-spacing:.05em}
.product-info{display:flex;justify-content:space-between;gap:12px;padding:15px 2px}.product-info p{margin:0;color:#7a8077;font-size:12px}.price{white-space:nowrap;font-size:13px}
.intro{max-width:650px;margin-bottom:36px}.detail{display:grid;grid-template-columns:1fr 1fr;gap:64px;align-items:center}.detail .product-visual{height:500px}
.detail-copy h1{font-size:clamp(34px,4vw,48px)}.detail-copy .price{font-size:19px;font-weight:650;margin:22px 0}.detail-copy .button{margin:12px 0 20px}
.detail-list{white-space:pre-line;border-top:1px solid #e1e3d9;margin-top:24px;padding-top:18px;font-size:13px;line-height:2;color:#697067}
.panel{background:#fff;border:1px solid #e7e8df;border-radius:5px;padding:26px}.cart-layout{display:grid;grid-template-columns:1.5fr .8fr;gap:26px;align-items:start}
.cart-row{display:grid;grid-template-columns:100px 1fr auto;gap:18px;align-items:center;padding:14px 0;border-bottom:1px solid #e9eae3}.cart-row .product-visual{width:100px;height:100px}.cart-row .art{font-size:42px}.cart-row p{font-size:12px;color:#747b70;margin:0}
.summary-line{display:flex;justify-content:space-between;padding:11px 0;font-size:13px}.summary-line.total{border-top:1px solid #e2e4da;margin-top:8px;padding-top:18px;font-weight:700}
.full{width:100%;margin-top:14px}.steps{display:flex;gap:9px;align-items:center;color:#8b9086;font-size:11px;margin:0 0 32px}.steps .current{color:#334a3c;font-weight:700}.steps span+span:before{content:"/";margin-right:9px;color:#b8bcb2}
.checkout-grid{display:grid;grid-template-columns:1.2fr .8fr;gap:28px;align-items:start}.checkout-panel h2{font-family:inherit;font-size:16px;font-weight:700;margin-bottom:14px}.checkout-panel+.checkout-panel{margin-top:16px}
.field{display:grid;gap:6px;margin-bottom:16px}.field label{font-size:12px;font-weight:700}.field input{width:100%;padding:12px;border:1px solid #d8dbd1;border-radius:3px;background:#fff;font:inherit}
.notice{padding:14px 17px;background:#eff1e9;color:#5d6753;font-size:12px;line-height:1.7;border-radius:3px}.empty{text-align:center;padding:48px 20px}
.complete{text-align:center;max-width:650px;margin:42px auto;padding:52px 30px}.checkmark{width:62px;height:62px;margin:0 auto 24px;display:grid;place-items:center;border-radius:50%;background:#e5eadc;color:#41573d;font-size:28px}
.order-number{font-family:monospace;font-size:14px;letter-spacing:.08em;background:#f2f3ed;padding:12px 18px;display:inline-block;margin:12px 0 25px}
.footer{background:#263b32;color:#e7e8dc;padding:34px 0;font-size:12px}.footer-inner{display:flex;justify-content:space-between;gap:20px;align-items:center}.footer a{color:inherit;text-decoration:none}
@media(max-width:760px){.shell{padding:0 18px}.nav{min-height:66px}.navlinks{gap:14px}.navlinks a:nth-child(2){display:none}.brand{font-size:23px}.hero,.detail,.cart-layout,.checkout-grid{grid-template-columns:1fr}.hero-art{min-height:260px;grid-row:1}.hero-copy{padding:32px 26px}.hero-art span{font-size:82px}.product-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:13px}.product-visual{height:220px}.product-visual .art{font-size:76px}.detail{gap:28px}.detail .product-visual{height:360px}.section-head{margin-top:50px}.page{padding-top:30px}.footer-inner{align-items:flex-start;flex-direction:column}}
@media(max-width:420px){.product-grid{grid-template-columns:1fr}.product-visual{height:290px}.navlinks{gap:10px}.cart-link{padding:8px 11px}.cart-row{grid-template-columns:72px 1fr auto;gap:12px}.cart-row .product-visual{width:72px;height:80px}}
"#

private def yen (amount : Int) : String :=
  match amount with
  | 2750 => "¥2,750"
  | 990 => "¥990"
  | 1800 => "¥1,800"
  | 2400 => "¥2,400"
  | 3200 => "¥3,200"
  | 3850 => "¥3,850"
  | 4400 => "¥4,400"
  | 550 => "¥550"
  | 8800 => "¥8,800"
  | 13200 => "¥13,200"
  | 0 => "無料"
  | amount => s!"¥{amount}"

private def cartCount (context : Page.Context) : Nat :=
  context.shopCart.foldl (fun total item => total + item.quantity) 0

private def productVisual (product : Page.ShopProduct) (compact := false) : Node .flow :=
  div [
    if compact then span [] else span [product.badge] { class_ := "tag" },
    span [product.art] { class_ := "art" } [("aria-hidden", "true")]
  ] { class_ := s!"product-visual {product.kind}" }

private def productCard (product : Page.ShopProduct) : Node .flow :=
  article [
    a { href := s!"/shop/products/{product.slug}", class_ := "product-card" } [
      productVisual product,
      div [
        div [h3 [product.name], p [product.category]],
        span [yen product.price] { class_ := "price" }
      ] { class_ := "product-info" }
    ]
  ]

private def crumb (parts : List (Node .phrasing)) : Node .flow :=
  p parts { class_ := "crumb" }

private def summaryLine (label value : String) (total := false) : Node .flow :=
  div [span [label], span [value]]
    { class_ := if total then "summary-line total" else "summary-line" }

private def totals (cart : Array Page.ShopCartItem) : Int × Int × Int :=
  let subtotal := cart.foldl
    (fun total item => total + item.product.price * Int.ofNat item.quantity) 0
  let shipping := if subtotal >= 8000 then 0 else 550
  (subtotal, shipping, subtotal + shipping)

private def homeContent (context : Page.Context) : List (Node .flow) :=
  [section_ [
    div [
      p ["A LITTLE MORE NATURAL"] { class_ := "eyebrow" },
      h1 ["いつもの暮らしに、", br, "ちょうどいい余白。"],
      p ["素材の表情を楽しみながら、毎日気持ちよく使えるものを。niwaが選んだ、長く寄りそう日用品をお届けします。"]
        { class_ := "muted" },
      a { href := "/shop/products/", class_ := "button" } ["商品を見にいく　→"]
    ] { class_ := "hero-copy" },
    div [span ["🧺"] {} [("aria-hidden", "true")]]
      { class_ := "hero-art" } [("aria-label", "自然素材のかごと枝のイラスト")]
  ] { class_ := "hero" },
  section_ [
    div [
      div [p ["OUR FAVORITES"] { class_ := "eyebrow" }, h2 ["今週のおすすめ"]],
      a { href := "/shop/products/", class_ := "text-link" } ["すべての商品を見る →"]
    ] { class_ := "section-head" },
    div ((context.shopProducts.toList.take 3).map productCard) { class_ := "product-grid" }
  ],
  section_ [
    div [
      p ["OUR PROMISE"] { class_ := "eyebrow" },
      h2 ["つくり手と、使い手のあいだに。"],
      p ["素材を選ぶところから、毎日の手ざわりまで。小さなこだわりを重ねた品を、ひとつずつ紹介しています。"]
        { class_ := "muted" }
    ]
  ] { id := "about", class_ := "section-head" }]

private def productsContent (context : Page.Context) : List (Node .flow) :=
  [crumb [a { href := "/shop/" } ["ホーム"], "　/　商品一覧"],
   section_ [
     p ["THE COLLECTION"] { class_ := "eyebrow" },
     h1 ["暮らしの道具"],
     p ["素材の心地よさと、使うほどになじむかたち。niwaの定番と新作をご紹介します。"]
       { class_ := "muted" }
   ] { class_ := "intro" },
   div (context.shopProducts.toList.map productCard) { class_ := "product-grid" }]

private def productContent (product : Page.ShopProduct) : List (Node .flow) :=
  [crumb [a { href := "/shop/" } ["ホーム"], "　/　",
    a { href := "/shop/products/" } ["商品一覧"], "　/　商品詳細"],
   section_ [
     productVisual product,
     div [
       p [product.category] { class_ := "eyebrow" },
       h1 [product.name],
       p [yen product.price, "（税込）"] { class_ := "price" },
       p [product.description] { class_ := "muted" },
       form [
         input { type := "hidden", name := "productSlug", value := product.slug },
         button ["カートに入れる　→"] { type := "submit", class_ := "button" }
       ] { action := "/shop/cart/add", method := "post" },
       p ["カートの内容はメモリー上のSQLiteに保存され、サーバー再起動時に消去されます。"]
         { class_ := "muted", style := "font-size:12px" },
       div [product.details, "\nお届け目安：ご注文から3〜5営業日"] { class_ := "detail-list" }
     ] { class_ := "detail-copy" }
   ] { class_ := "detail" }]

private def cartRow (item : Page.ShopCartItem) : Node .flow :=
  div [
    productVisual item.product true,
    div [
      h3 [item.product.name],
      p [s!"{item.product.category} · {item.quantity}点"],
      p [a { href := s!"/shop/products/{item.product.slug}", class_ := "text-link" } ["商品詳細"]]
        { style := "margin-top:8px" }
    ],
    strong [yen (item.product.price * Int.ofNat item.quantity)] { class_ := "price" }
  ] { class_ := "cart-row" }

private def cartContent (context : Page.Context) : List (Node .flow) :=
  let (subtotal, shipping, total) := totals context.shopCart
  let rows : List (Node .flow) := context.shopCart.toList.map cartRow
  let cartFooter : List (Node .flow) :=
    [p ["カートはメモリー上のSQLiteに保存されています。"]
       { class_ := "notice", style := "margin-top:20px" },
     p [a { href := "/shop/products/", class_ := "text-link" } ["← 買い物を続ける"]]
       { style := "margin:20px 0 0" }]
  [crumb [a { href := "/shop/" } ["ホーム"], "　/　カート"],
   p ["YOUR BAG"] { class_ := "eyebrow" },
   h1 ["ショッピングカート"],
   if context.shopCart.isEmpty then
     section_ [
       h2 ["カートは空です"],
       p ["商品詳細ページから商品を追加してください。"] { class_ := "muted" },
       a { href := "/shop/products/", class_ := "button" } ["商品を見る"]
     ] { class_ := "panel empty" }
   else
     div [
       section_ (
         rows ++ cartFooter
       ) { class_ := "panel" },
       aside [
         h2 ["ご注文金額"] { style := "font-family:inherit;font-size:16px;font-weight:700" },
         summaryLine "小計" (yen subtotal),
         summaryLine "送料" (yen shipping),
         summaryLine "合計（税込）" (yen total) true,
         a { href := "/shop/checkout/", class_ := "button full" } ["レジに進む　→"]
       ] { class_ := "panel" }
     ] { class_ := "cart-layout" }]

private def field (id labelText name value : String) (attrs : List (String × String) := []) :
    Node .flow :=
  div [
    label [labelText] { for_ := id },
    input { name, value, required := true } (("id", id) :: attrs)
  ] { class_ := "field" }

private def checkoutContent (context : Page.Context) : List (Node .flow) :=
  let (subtotal, shipping, total) := totals context.shopCart
  let rows : List (Node .flow) := context.shopCart.toList.map cartRow
  let orderSummary : List (Node .flow) :=
    [summaryLine "小計" (yen subtotal),
     summaryLine "送料" (yen shipping),
     summaryLine "合計（税込）" (yen total) true,
     p ["注文と注文明細はメモリー上のSQLiteに保存されます。決済・メール送信は行いません。"]
       { class_ := "notice" },
     button ["注文を確定する　→"] { type := "submit", class_ := "button full" },
     p [a { href := "/shop/cart/", class_ := "text-link" } ["カートに戻る"]]
       { style := "text-align:center;margin:15px 0 0" }]
  [crumb [a { href := "/shop/" } ["ホーム"], "　/　",
    a { href := "/shop/cart/" } ["カート"], "　/　ご注文確認"],
   div [span ["カート"], span ["ご注文確認"] { class_ := "current" }, span ["注文完了"]]
     { class_ := "steps" },
   p ["CHECKOUT"] { class_ := "eyebrow" },
   h1 ["お届け先とご注文内容"],
   if context.shopCart.isEmpty then
     section_ [
       h2 ["カートは空です"],
       a { href := "/shop/products/", class_ := "button" } ["商品を見る"]
     ] { class_ := "panel empty" }
   else
     form [
       div [
         section_ [
           h2 ["お届け先"],
           field "customer-name" "お名前" "customerName" "山田 花子"
             [("maxlength", "80"), ("autocomplete", "name")],
           field "postal-code" "郵便番号" "postalCode" "150-0001"
             [("maxlength", "16"), ("autocomplete", "postal-code")],
           field "address" "住所" "address" "東京都渋谷区神宮前 1-2-3"
             [("maxlength", "200"), ("autocomplete", "street-address")],
           field "phone" "電話番号" "phone" "000-0000-0000"
             [("maxlength", "32"), ("autocomplete", "tel")]
         ] { class_ := "panel checkout-panel" }
       ],
       aside (
         ([h2 ["ご注文商品"]
           { style := "font-family:inherit;font-size:16px;font-weight:700" }] :
           List (Node .flow)) ++ rows ++ orderSummary
       ) { class_ := "panel" }
     ] { action := "/shop/orders", method := "post", class_ := "checkout-grid" }]

private def completeContent (context : Page.Context) : List (Node .flow) :=
  [crumb [a { href := "/shop/" } ["ホーム"], "　/　注文完了"],
   section_ [
     div ["✓"] { class_ := "checkmark" } [("aria-hidden", "true")],
     p ["ORDER COMPLETE"] { class_ := "eyebrow" },
     h1 ["ご注文ありがとうございます"] { style := "font-size:42px" },
     p ["注文と注文明細をSQLiteに保存しました。デモのため、決済・発送・メール送信は行われません。"]
       { class_ := "muted" },
     p [match context.shopLatestOrderId with
       | some id => s!"ORDER-{id}"
       | none => "注文番号なし"] { class_ := "order-number" },
     br,
     a { href := "/shop/products/", class_ := "button" } ["商品一覧に戻る"]
   ] { class_ := "panel complete" }]

private def pageContent (context : Page.Context) : String × List (Node .flow) :=
  match context.path with
  | "/shop" | "/shop/" => ("ホーム", homeContent context)
  | "/shop/products" | "/shop/products/" => ("商品一覧", productsContent context)
  | "/shop/cart" | "/shop/cart/" => ("カート", cartContent context)
  | "/shop/checkout" | "/shop/checkout/" => ("ご注文確認", checkoutContent context)
  | "/shop/order-complete" | "/shop/order-complete/" =>
      ("注文完了", completeContent context)
  | path =>
      let slug := (path.splitOn "/").getLast?.getD ""
      match context.shopProducts.find? (·.slug == slug) with
      | some product => (product.name, productContent product)
      | none => ("商品が見つかりません",
          [section_ [h1 ["商品が見つかりません"], a { href := "/shop/products/" } ["商品一覧へ"]]])

def render (context : Page.Context) : String :=
  let (pageTitle, content) := pageContent context
  document
    (head (title s!"{pageTitle} - niwa store") [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
      meta_ [("name", "theme-color"), ("content", "#f8f8f3")],
      Node.unsafeRaw ("<style>" ++ styles ++ "</style>")
    ])
    (body [
      div ["送料無料 · 8,000円以上のお買い上げ"] { class_ := "topline" },
      header [
        div [
          a { href := "/shop/", class_ := "brand" } ["niwa", span ["."]],
          nav [
            a { href := "/shop/products/" } ["商品を見る"],
            a { href := "/shop/#about" } ["niwaについて"],
            a { href := "/shop/cart/", class_ := "cart-link" }
              [s!"カート ({cartCount context})"]
          ] { class_ := "navlinks" } [("aria-label", "メインナビゲーション")]
        ] { class_ := "shell nav" }
      ] { class_ := "header" },
      main content { class_ := "shell page" },
      footer [
        div [
          a { href := "/shop/", class_ := "brand" } ["niwa", span ["."]],
          span ["暮らしに、長く寄りそうもの。 · ECサイトのページ遷移デモ"],
          a { href := "/shop/admin/" } ["店舗管理"],
          a { href := "/" } ["LeanWebStudy"]
        ] { class_ := "shell footer-inner" }
      ] { class_ := "footer" }
    ])
    (lang := "ja") (pretty := true)

end LeanWebStudy.Shop
