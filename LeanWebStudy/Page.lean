import Lean

namespace LeanWebStudy.Page

structure BoardPost where
  id : Int
  author : String
  message : String
  deriving Lean.ToJson, Lean.FromJson, BEq

structure WikiArticle where
  slug : String
  title : String
  content : String
  deriving Lean.ToJson, Lean.FromJson, BEq

structure ShopProduct where
  slug : String
  name : String
  category : String
  price : Int
  art : String
  kind : String
  badge : String
  description : String
  details : String
  deriving Lean.ToJson, Lean.FromJson, BEq

structure ShopCartItem where
  product : ShopProduct
  quantity : Nat
  deriving Lean.ToJson, Lean.FromJson, BEq

structure ShopInventoryItem where
  product : ShopProduct
  stock : Nat
  deriving Lean.ToJson, Lean.FromJson, BEq

structure ShopOrderItem where
  productSlug : String
  productName : String
  quantity : Nat
  unitPrice : Int
  deriving Lean.ToJson, Lean.FromJson, BEq

structure ShopOrder where
  id : Int
  customerName : String
  postalCode : String
  address : String
  phone : String
  total : Int
  paymentStatus : String
  fulfillmentStatus : String
  items : Array ShopOrderItem
  deriving Lean.ToJson, Lean.FromJson, BEq

structure Context where
  requestId : Nat
  path : String
  usersHtml : String
  sqliteDemoHtml : String := ""
  boardPosts : Array BoardPost := #[]
  wikiArticles : Array WikiArticle := #[]
  shopProducts : Array ShopProduct := #[]
  shopCart : Array ShopCartItem := #[]
  shopLatestOrderId : Option Int := none
  shopInventory : Array ShopInventoryItem := #[]
  shopOrders : Array ShopOrder := #[]
  chatPort : Nat := 0
  deriving Lean.ToJson

instance : Lean.FromJson Context where
  fromJson? json := do
    let fields <- json.getObj?
    let sqliteDemoHtml <- match fields.get? "sqliteDemoHtml" with
      | some value => value.getStr?
      | none => pure ""
    let boardPosts <- match fields.get? "boardPosts" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let wikiArticles <- match fields.get? "wikiArticles" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let shopProducts <- match fields.get? "shopProducts" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let shopCart <- match fields.get? "shopCart" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let shopLatestOrderId <- match fields.get? "shopLatestOrderId" with
      | some value => Lean.fromJson? value
      | none => pure none
    let shopInventory <- match fields.get? "shopInventory" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let shopOrders <- match fields.get? "shopOrders" with
      | some value => Lean.fromJson? value
      | none => pure #[]
    let chatPort <- match fields.get? "chatPort" with
      | some value => do
        let port ← value.getNat?
        unless port <= 65535 do throw "chatPort must be at most 65535"
        pure port
      | none => pure 0
    return {
      requestId := ← json.getObjValAs? Nat "requestId"
      path := ← json.getObjValAs? String "path"
      usersHtml := ← json.getObjValAs? String "usersHtml"
      sqliteDemoHtml
      boardPosts
      wikiArticles
      shopProducts
      shopCart
      shopLatestOrderId
      shopInventory
      shopOrders
      chatPort }

def escapeHtml (text : String) : String :=
  text.replace "&" "&amp;" |>.replace "<" "&lt;" |>.replace ">" "&gt;"
    |>.replace "\"" "&quot;" |>.replace "'" "&#39;"

-- stdout is reserved for the JSON response; page diagnostics belong on stderr.
def run (render : Context -> IO String) : IO Unit := do
  let input <- (← IO.getStdin).readToEnd
  let context <- match Lean.Json.parse input >>= Lean.fromJson? with
    | .ok context => pure context
    | .error error => throw (IO.userError s!"Invalid page context: {error}")
  let html <- render context
  (← IO.getStdout).putStr (Lean.toJson html).compress

end LeanWebStudy.Page
