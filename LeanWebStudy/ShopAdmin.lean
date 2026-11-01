import Html
import LeanWebStudy.Page

open Html

namespace LeanWebStudy.ShopAdmin

private def styles : String := r#"
:root{font-family:Inter,"Noto Sans JP",system-ui,sans-serif;color:#18211c;background:#f3f5f2}*{box-sizing:border-box}body{margin:0}a{color:inherit}
.header{background:#173c2d;color:#fff}.header-inner{max-width:1200px;margin:auto;padding:0 24px;min-height:68px;display:flex;align-items:center;justify-content:space-between;gap:24px}
.brand{font-family:Georgia,serif;font-size:23px;font-weight:700;text-decoration:none}.brand span{color:#a8c58e}.header nav{display:flex;gap:20px;align-items:center}.header nav a{font-size:13px;text-decoration:none;color:#dbe7df}
.store-link{border:1px solid #668477;border-radius:999px;padding:8px 13px}.page{max-width:1200px;margin:auto;padding:38px 24px 80px}.eyebrow{font-size:11px;letter-spacing:.15em;color:#62776c;font-weight:800}
h1{font-family:Georgia,"Noto Serif JP",serif;font-size:38px;font-weight:500;margin:7px 0 12px}h2{font-size:18px;margin:0 0 16px}h3{font-size:15px;margin:0}.muted{color:#6d7972;line-height:1.7}
.notice{background:#fff6d8;border:1px solid #eadb9f;color:#675b2d;padding:13px 16px;border-radius:5px;font-size:12px;margin:20px 0 28px}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:15px;margin:28px 0}.stat{background:#fff;border:1px solid #dde3de;border-radius:7px;padding:21px}.stat strong{display:block;font-size:28px;margin-top:8px}.stat span{font-size:12px;color:#6d7972}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.panel{background:#fff;border:1px solid #dde3de;border-radius:7px;padding:22px}.panel-link{text-decoration:none}.panel-link:hover{border-color:#8ca394}.panel p{margin-bottom:0}
.section-head{display:flex;align-items:end;justify-content:space-between;gap:16px;margin:32px 0 16px}.section-head a{font-size:13px;color:#496456}
.inventory{display:grid;gap:10px}.inventory-row{display:grid;grid-template-columns:54px minmax(180px,1fr) 210px;gap:16px;align-items:center;background:#fff;border:1px solid #dde3de;border-radius:6px;padding:12px 15px}
.art{width:48px;height:48px;display:grid;place-items:center;border-radius:5px;background:#eef0e9;font-size:25px}.meta{font-size:11px;color:#77817b;margin-top:4px}.stock-form{display:flex;gap:8px;align-items:center}.stock-form input{width:90px;padding:9px;border:1px solid #ccd5ce;border-radius:4px;font:inherit}
.button{border:0;background:#275c45;color:#fff;padding:10px 14px;border-radius:4px;font-weight:700;font-size:12px;cursor:pointer}.button:hover{background:#194733}.button.secondary{background:#e8eee9;color:#294b3b}.button.shipping{background:#355f7b}.button.delivered{background:#5c536f}
.badge{display:inline-flex;padding:5px 8px;border-radius:999px;font-size:10px;font-weight:800;letter-spacing:.04em}.pending{background:#fff0c2;color:#795d00}.paid{background:#dcefe1;color:#275b35}.new{background:#e4ecf3;color:#355b75}.shipped{background:#e5e0ef;color:#574a70}.delivered{background:#e2e5e3;color:#59615c}
.orders{display:grid;gap:16px}.order{background:#fff;border:1px solid #dde3de;border-radius:7px;padding:22px}.order-head{display:flex;justify-content:space-between;gap:18px;align-items:start;border-bottom:1px solid #e7ebe8;padding-bottom:15px;margin-bottom:15px}.order-head strong{font-family:monospace;font-size:16px}.badges{display:flex;gap:7px;flex-wrap:wrap}
.order-body{display:grid;grid-template-columns:1fr 1fr;gap:24px}.items{list-style:none;padding:0;margin:0}.items li{display:flex;justify-content:space-between;gap:12px;font-size:13px;padding:6px 0}.customer{font-size:13px;line-height:1.8;color:#59645d}.order-foot{display:flex;justify-content:space-between;align-items:center;gap:15px;border-top:1px solid #e7ebe8;margin-top:16px;padding-top:16px}.actions{display:flex;gap:8px;flex-wrap:wrap}.empty{text-align:center;padding:60px 20px;background:#fff;border:1px solid #dde3de;border-radius:7px}
@media(max-width:760px){.header-inner{align-items:flex-start;padding-top:18px;padding-bottom:18px;flex-direction:column}.header nav{flex-wrap:wrap}.stats{grid-template-columns:repeat(2,1fr)}.grid{grid-template-columns:1fr}.inventory-row{grid-template-columns:48px 1fr}.stock-form{grid-column:1/-1}.order-body{grid-template-columns:1fr}.order-foot{align-items:flex-start;flex-direction:column}}
"#

private def yen (amount : Int) : String :=
  let text := toString amount
  if text.length <= 3 then s!"¥{text}" else
    let split := text.length - 3
    s!"¥{text.take split},{text.drop split}"

private def paymentLabel (status : String) : String :=
  if status == "paid" then "入金確認済み" else "入金待ち"

private def fulfillmentLabel (status : String) : String :=
  match status with
  | "shipped" => "発送済み"
  | "delivered" => "配達完了"
  | _ => "未発送"

private def statusBadge (label kind : String) : Node .phrasing :=
  span [label] { class_ := s!"badge {kind}" }

private def actionForm (orderId : Int) (action label className : String) : Node .flow :=
  form [
    input { type := "hidden", name := "orderId", value := toString orderId },
    input { type := "hidden", name := "action", value := action },
    button [label] { type := "submit", class_ := s!"button {className}" }
  ] { action := "/shop/admin/orders/status", method := "post" }

private def orderCard (order : Page.ShopOrder) : Node .flow :=
  let itemNodes : List (Node .listItem) := order.items.toList.map fun item =>
    li [
      span [s!"{item.productName} × {item.quantity}"],
      span [yen (item.unitPrice * Int.ofNat item.quantity)]
    ]
  let actionNodes : List (Node .flow) :=
    (if order.paymentStatus == "pending" then
      [actionForm order.id "confirm-payment" "入金を確認" "secondary"] else []) ++
    (if order.fulfillmentStatus == "new" then
      [actionForm order.id "mark-shipped" "発送済みにする" "shipping"] else []) ++
    (if order.fulfillmentStatus == "shipped" then
      [actionForm order.id "mark-delivered" "配達完了にする" "delivered"] else [])
  article [
    div [
      div [
        strong [s!"ORDER-{order.id}"],
        p [s!"{order.customerName} 様"] { class_ := "meta" }
      ],
      div [
        statusBadge (paymentLabel order.paymentStatus) order.paymentStatus,
        statusBadge (fulfillmentLabel order.fulfillmentStatus) order.fulfillmentStatus
      ] { class_ := "badges" }
    ] { class_ := "order-head" },
    div [
      div [h3 ["注文商品"], ul itemNodes { class_ := "items" }],
      div [
        h3 ["お届け先"],
        p [s!"〒{order.postalCode}", br, order.address, br, order.phone]
          { class_ := "customer" }
      ]
    ] { class_ := "order-body" },
    div [
      strong [s!"合計 {yen order.total}"],
      div actionNodes { class_ := "actions" }
    ] { class_ := "order-foot" }
  ] { class_ := "order" }

private def intro (eyebrow title description : String) : List (Node .flow) :=
  [p [eyebrow] { class_ := "eyebrow" }, h1 [title], p [description] { class_ := "muted" },
   p ["この管理画面はローカル学習用で、認証・権限管理はありません。外部公開しないでください。"]
     { class_ := "notice" }]

private def dashboard (context : Page.Context) : List (Node .flow) :=
  let current := context.shopOrders.filter (·.fulfillmentStatus == "new")
  let processed := context.shopOrders.filter (·.fulfillmentStatus != "new")
  let unpaid := context.shopOrders.filter (·.paymentStatus == "pending")
  let lowStock := context.shopInventory.filter (·.stock <= 5)
  intro "STORE ADMIN" "店舗管理" "オンライン店舗と同じSQLiteデータを確認・更新できます。" ++
  [div [
    div [span ["現在の注文"], strong [toString current.size]] { class_ := "stat" },
    div [span ["入金待ち"], strong [toString unpaid.size]] { class_ := "stat" },
    div [span ["処理済み"], strong [toString processed.size]] { class_ := "stat" },
    div [span ["在庫僅少"], strong [toString lowStock.size]] { class_ := "stat" }
  ] { class_ := "stats" },
  div [
    a { href := "/shop/admin/inventory/", class_ := "panel panel-link" } [
      h2 ["在庫管理"], p ["8商品の在庫数を確認し、入荷や棚卸しを反映します。"] { class_ := "muted" }
    ],
    a { href := "/shop/admin/orders/", class_ := "panel panel-link" } [
      h2 ["現在の注文"], p ["入金確認と発送処理が必要な注文を表示します。"] { class_ := "muted" }
    ],
    a { href := "/shop/admin/orders/processed/", class_ := "panel panel-link" } [
      h2 ["処理した注文"], p ["発送済み・配達完了の注文履歴を確認します。"] { class_ := "muted" }
    ]
  ] { class_ := "grid" }]

private def inventoryPage (context : Page.Context) : List (Node .flow) :=
  let rows : List (Node .flow) := context.shopInventory.toList.map fun item =>
    div [
      div [item.product.art] { class_ := "art" },
      div [h3 [item.product.name], p [item.product.slug] { class_ := "meta" }],
      form [
        label ["在庫数"] { for_ := s!"stock-{item.product.slug}" },
        input { type := "number", name := "stock", value := toString item.stock, required := true }
          [("id", s!"stock-{item.product.slug}"), ("min", "0"), ("max", "1000000")],
        input { type := "hidden", name := "productSlug", value := item.product.slug },
        button ["更新"] { type := "submit", class_ := "button" }
      ] { action := "/shop/admin/inventory/update", method := "post", class_ := "stock-form" }
    ] { class_ := "inventory-row" }
  intro "INVENTORY" "在庫管理" "注文確定時に在庫が減り、ここで更新した値はオンライン店舗の注文処理に使われます。" ++
  [div rows { class_ := "inventory" }]

private def ordersPage (context : Page.Context) (processed : Bool) : List (Node .flow) :=
  let orders := context.shopOrders.filter fun order =>
    if processed then order.fulfillmentStatus != "new" else order.fulfillmentStatus == "new"
  let title := if processed then "処理した注文" else "現在の注文"
  let description := if processed then
    "発送済みと配達完了の注文です。発送済みの注文を配達完了へ更新できます。"
  else
    "入金確認と発送処理を行います。入金確認後にのみ発送済みへ更新できます。"
  intro "ORDER MANAGEMENT" title description ++
  [div [
    a { href := "/shop/admin/orders/" } ["現在の注文"],
    "　/　",
    a { href := "/shop/admin/orders/processed/" } ["処理した注文"]
  ] { class_ := "section-head" },
  if orders.isEmpty then
    div ["該当する注文はありません。"] { class_ := "empty" }
  else
    div (orders.toList.map orderCard) { class_ := "orders" }]

private def content (context : Page.Context) : String × List (Node .flow) :=
  match context.path with
  | "/shop/admin" | "/shop/admin/" => ("店舗管理", dashboard context)
  | "/shop/admin/inventory" | "/shop/admin/inventory/" =>
      ("在庫管理", inventoryPage context)
  | "/shop/admin/orders/processed" | "/shop/admin/orders/processed/" =>
      ("処理した注文", ordersPage context true)
  | _ => ("現在の注文", ordersPage context false)

def render (context : Page.Context) : String :=
  let (pageTitle, pageContent) := content context
  document
    (head (title s!"{pageTitle} - niwa admin") [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
      meta_ [("name", "theme-color"), ("content", "#173c2d")],
      Node.unsafeRaw ("<style>" ++ styles ++ "</style>")
    ])
    (body [
      header [
        div [
          a { href := "/shop/admin/", class_ := "brand" } ["niwa", span [" admin"]],
          nav [
            a { href := "/shop/admin/inventory/" } ["在庫"],
            a { href := "/shop/admin/orders/" } ["現在の注文"],
            a { href := "/shop/admin/orders/processed/" } ["処理済み"],
            a { href := "/shop/", class_ := "store-link" } ["店舗を見る"]
          ]
        ] { class_ := "header-inner" }
      ] { class_ := "header" },
      main pageContent { class_ := "page" }
    ])
    (lang := "ja") (pretty := true)

end LeanWebStudy.ShopAdmin
