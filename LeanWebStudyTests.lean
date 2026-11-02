import LeanWebStudy
import LeanWebStudy.LifecycleTests

open LeanWebStudy

def queryMatches (requestId : Nat) : Bool :=
  match sampleQuery requestId with
  | .ok formatted =>
    formatted.sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" &&
      formatted.params == #[.integer (Int.ofNat requestId)]
  | .error _ => false

#guard queryMatches 7
#guard queryMatches 8
#guard queryMatches 0

#guard match queryJson 7 with
  | .ok json => json == Lean.Json.mkObj [
      ("requestId", Lean.toJson (7 : Nat)),
      ("sql", Lean.toJson ("SELECT * FROM \"users\" WHERE \"id\" > ?" : String)),
      ("params", .arr #[Lean.toJson (7 : Int)])]
  | .error _ => false

#guard valueJson (.text "\"<user>") == Lean.toJson ("\"<user>" : String)

#guard escapeHtml "<script>&\"'" == "&lt;script&gt;&amp;&quot;&#39;"

#guard (Chat.response 1
  "{\"type\":\"message\",\"requestId\":\"test\",\"author\":\" Ada \",\"message\":\"Hi\"}".toUTF8).1
#guard !(Chat.response 1 "{}".toUTF8).1
#guard !(Chat.response 1
  "{\"type\":\"message\",\"requestId\":\"test\",\"author\":\" \",\"message\":\"Hi\"}".toUTF8).1
#guard (Pong.response 1 "{\"type\":\"paddle\",\"y\":120}".toUTF8).1
#guard !(Pong.response 1 "{\"type\":\"paddle\",\"y\":371}".toUTF8).1
#guard (Pong.response 1
  "{\"type\":\"ball\",\"x\":400,\"y\":225,\"left\":0,\"right\":0}".toUTF8).1
#guard !(Pong.response 1
  "{\"type\":\"ball\",\"x\":801,\"y\":225,\"left\":0,\"right\":0}".toUTF8).1

#guard OrderBook.parsePrice "101" == some 10100
#guard OrderBook.parsePrice "101.5" == some 10150
#guard OrderBook.parsePrice "101.05" == some 10105
#guard OrderBook.parsePrice "0.00" == none
#guard OrderBook.parsePrice "1.001" == none
#guard OrderBook.formatPrice 10105 == "101.05"

def partialOrderMatchWorks : Bool := Id.run do
  let result := OrderBook.submit OrderBook.initial .buy 10100 7
  return result.trades == #[{
      id := 1, makerOrderId := 3, takerOrderId := 5, price := 10100, quantity := 4 }] &&
    result.remaining == 3 &&
    result.book.orders.any (fun order =>
      order.id == 5 && order.side == .buy && order.price == 10100 && order.remaining == 3)

def multipleOrderMatchWorks : Bool := Id.run do
  let result := OrderBook.submit OrderBook.initial .sell 9950 13
  return result.trades == #[
      { id := 1, makerOrderId := 1, takerOrderId := 5, price := 10000, quantity := 5 },
      { id := 2, makerOrderId := 2, takerOrderId := 5, price := 9950, quantity := 8 }] &&
    result.remaining == 0 &&
    result.book.orders.all (fun order => order.side == .sell)

def timePriorityMatchWorks : Bool := Id.run do
  let book := { OrderBook.initial with
    orders := #[
      { id := 2, side := .sell, price := 10200, remaining := 2 },
      { id := 1, side := .sell, price := 10200, remaining := 5 }]
    nextOrderId := 3 }
  let result := OrderBook.submit book .buy 10200 4
  return result.trades == #[{
      id := 1, makerOrderId := 1, takerOrderId := 3, price := 10200, quantity := 4 }] &&
    result.book.orders.size == 2 &&
    result.book.orders[0]!.id == 2 &&
    result.book.orders[1]!.id == 1 &&
    result.book.orders[1]!.remaining == 1

#guard partialOrderMatchWorks
#guard multipleOrderMatchWorks
#guard timePriorityMatchWorks

#guard DevPages.relativePath "/" == some (System.FilePath.mk "index.lean")
#guard DevPages.relativePath "/hello" == some (System.FilePath.mk "hello.lean")
#guard DevPages.relativePath "/sqlite/" ==
  some (System.FilePath.mk "sqlite/index.lean")
#guard DevPages.relativePath "/blog/new-page_2" ==
  some (System.FilePath.mk "blog/new-page_2.lean")
#guard DevPages.relativePath "/../Main" == none
#guard DevPages.relativePath "/%2e%2e/Main" == none
#guard DevPages.relativePath "/hello/" ==
  some (System.FilePath.mk "hello/index.lean")
#guard DevPages.relativePath "//hello" == none
#guard DevPages.relativePath "/hello\\world" == none
#guard DevPages.relativePath "hello" == none

#guard rowsJson #[#[.integer 4, .text "Dave"]] ==
  Lean.Json.arr #[Lean.Json.arr #[Lean.toJson (4 : Int), Lean.toJson ("Dave" : String)]]

section WebSocketTests

open Std.Http
open Std.Http.WebSocket

private def hexOf (bytes : ByteArray) : String := Id.run do
  let digits := "0123456789abcdef".toList.toArray
  let mut out := ""
  for i in [0:bytes.size] do
    let b := bytes[i]!
    out := out.push digits[b.toNat >>> 4]!
    out := out.push digits[b.toNat &&& 15]!
  return out

-- FIPS 180-4 / RFC 3174 test vectors (including a multi-chunk input).
#guard hexOf (Internal.sha1 "abc".toUTF8) == "a9993e364706816aba3e25717850c26c9cd0d89d"
#guard hexOf (Internal.sha1 "".toUTF8) == "da39a3ee5e6b4b0d3255bfef95601890afd80709"
#guard hexOf (Internal.sha1 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".toUTF8) ==
  "84983e441c3bd26ebaae4aa1f95129e5e54670f1"

-- RFC 4648 §10 test vectors.
#guard Internal.base64Encode ByteArray.empty == ""
#guard Internal.base64Encode "f".toUTF8 == "Zg=="
#guard Internal.base64Encode "fo".toUTF8 == "Zm8="
#guard Internal.base64Encode "foo".toUTF8 == "Zm9v"
#guard Internal.base64Encode "foob".toUTF8 == "Zm9vYg=="
#guard Internal.base64Encode "fooba".toUTF8 == "Zm9vYmE="
#guard Internal.base64Encode "foobar".toUTF8 == "Zm9vYmFy"

-- RFC 6455 §1.3 handshake example.
#guard acceptKey "dGhlIHNhbXBsZSBub25jZQ==" == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

-- RFC 6455 §5.7: a masked "Hello" text frame from the client.
private def rfcMaskedHello : Bool :=
  let bytes : ByteArray :=
    ⟨#[0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]⟩
  match Frame.decode? bytes true 1024 with
  | .ok (some (frame, consumed)) =>
    frame.fin && frame.opcode == .text && frame.payload == "Hello".toUTF8 &&
      consumed == bytes.size
  | _ => false

#guard rfcMaskedHello

-- Masked encode followed by server-side decode restores the payload.
private def maskedRoundTrip : Bool :=
  let payload := "Hello, WebSocket!".toUTF8
  let key : ByteArray := ⟨#[0x37, 0xfa, 0x21, 0x3d]⟩
  let bytes := Frame.encode { opcode := .binary, payload } (maskKey := some key)
  match Frame.decode? bytes true 1024 with
  | .ok (some (frame, consumed)) =>
    frame.fin && frame.opcode == .binary && frame.payload == payload &&
      consumed == bytes.size
  | _ => false

#guard maskedRoundTrip

-- Server-to-client frames are unmasked and use the 16-bit extended length.
private def serverLongFrame : Bool := Id.run do
  let mut payload := ByteArray.empty
  for i in [0:300] do
    payload := payload.push i.toUInt8
  let bytes := Frame.encode { opcode := .binary, payload }
  match Frame.decode? bytes false 1024 with
  | .ok (some (frame, consumed)) =>
    return frame.payload == payload && consumed == bytes.size
  | _ => return false

#guard serverLongFrame

-- Incomplete input requests more bytes instead of failing.
#guard match Frame.decode? ⟨#[0x81]⟩ true 1024 with
  | .ok none => true
  | _ => false
#guard match Frame.decode? ⟨#[0x81, 0x85, 0x37, 0xfa]⟩ true 1024 with
  | .ok none => true
  | _ => false

-- Per-frame protocol violations.
private def decodesToError (bytes : ByteArray) (expected : ProtocolError) : Bool :=
  match Frame.decode? bytes true 1024 with
  | .error error => error == expected
  | _ => false

#guard decodesToError ⟨#[0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]⟩ .unmaskedFrame
#guard decodesToError ⟨#[0xC1, 0x80, 0, 0, 0, 0]⟩ .reservedBitsSet
#guard decodesToError ⟨#[0x83, 0x80, 0, 0, 0, 0]⟩ (.unknownOpcode 3)
#guard decodesToError ⟨#[0x09, 0x80, 0, 0, 0, 0]⟩ .fragmentedControl
#guard decodesToError ⟨#[0x89, 0xFE, 0, 126, 0, 0, 0, 0]⟩ .controlTooLarge
#guard decodesToError ⟨#[0x82, 0xFE, 0, 5, 0, 0, 0, 0]⟩ .nonMinimalLength
#guard decodesToError ⟨#[0x82, 0xFE, 0xFF, 0xFF, 0, 0, 0, 0]⟩ (.payloadTooLarge 65535)

#guard validCloseCode 1000 && validCloseCode 1011 && validCloseCode 3000 &&
  validCloseCode 4999
#guard !validCloseCode 999 && !validCloseCode 1004 && !validCloseCode 1005 &&
  !validCloseCode 1006 && !validCloseCode 1015 && !validCloseCode 2999 &&
  !validCloseCode 5000

private def wsRequest (headers : List (String × String)) (method : Method := .get) :
    Request.Head := {
  method
  version := .v11
  headers := headers.foldl (fun acc (name, value) => acc.insert! name value) Headers.empty
}

private def validHandshakeHeaders : List (String × String) := [
  ("Host", "127.0.0.1"),
  ("Upgrade", "websocket"),
  ("Connection", "keep-alive, Upgrade"),
  ("Sec-WebSocket-Version", "13"),
  ("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")]

private def handshakeOk (result : Except HandshakeError String) (key : String) : Bool :=
  match result with
  | .ok value => value == key
  | .error _ => false

private def handshakeFails (result : Except HandshakeError String)
    (expected : HandshakeError) : Bool :=
  match result with
  | .error error => error == expected
  | .ok _ => false

#guard handshakeOk (checkHandshake (wsRequest validHandshakeHeaders))
  "dGhlIHNhbXBsZSBub25jZQ=="
#guard handshakeFails (checkHandshake (wsRequest validHandshakeHeaders (method := .post)))
  .methodNotAllowed
#guard handshakeFails
  (checkHandshake (wsRequest (validHandshakeHeaders.filter (·.1 != "Upgrade"))))
  .missingUpgrade
#guard handshakeFails
  (checkHandshake (wsRequest (("Connection", "keep-alive") ::
    validHandshakeHeaders.filter (·.1 != "Connection"))))
  .missingConnectionUpgrade
#guard handshakeFails
  (checkHandshake (wsRequest (("Sec-WebSocket-Version", "8") ::
    validHandshakeHeaders.filter (·.1 != "Sec-WebSocket-Version"))))
  .unsupportedVersion
#guard handshakeFails
  (checkHandshake (wsRequest (validHandshakeHeaders.filter (·.1 != "Sec-WebSocket-Key"))))
  .invalidKey
#guard handshakeFails
  (checkHandshake (wsRequest (("Sec-WebSocket-Key", "short") ::
    validHandshakeHeaders.filter (·.1 != "Sec-WebSocket-Key"))))
  .invalidKey
#guard handshakeFails
  (checkHandshake (wsRequest validHandshakeHeaders)
    (checkOrigin := fun origin => origin.isSome))
  .originRejected
#guard handshakeOk
  (checkHandshake
    (wsRequest (("Origin", "http://127.0.0.1:8080") :: validHandshakeHeaders))
    (checkOrigin := (· == some "http://127.0.0.1:8080")))
  "dGhlIHNhbXBsZSBub25jZQ=="

-- The switching head carries the computed accept key.
#guard (switchingProtocolsHead "dGhlIHNhbXBsZSBub25jZQ==").status == .switchingProtocols
#guard ((switchingProtocolsHead "dGhlIHNhbXBsZSBub25jZQ==").headers.get?
  (Header.Name.ofString! "sec-websocket-accept")).map toString ==
  some "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

private def checkCloseReason (reason expected : String) : IO Unit := do
  let (client, server) ← Std.Http.Internal.Mock.new
  try
    Std.Async.Async.block do
      let upgraded ← Server.Upgraded.ofTransport server ByteArray.empty
      let socket ← WebSocket.ofUpgraded upgraded
      socket.close 1000 reason
      let some bytes ← client.tryRecv?
        | throw (IO.userError "Expected a close frame")
      let .ok (some (frame, consumed)) := Frame.decode? bytes false 125
        | throw (IO.userError "Expected a valid unmasked control frame of at most 125 bytes")
      unless frame.fin && frame.opcode == .close && consumed == bytes.size do
        throw (IO.userError "Expected exactly one complete close frame")
      unless frame.payload.size ≥ 2 &&
          frame.payload[0]! == 0x03 && frame.payload[1]! == 0xE8 do
        throw (IO.userError "Close frame must preserve status code 1000")
      let reasonBytes := frame.payload.extract 2 frame.payload.size
      unless String.fromUTF8? reasonBytes == some expected do
        throw (IO.userError s!"Close reason must be valid UTF-8 and equal {repr expected}")
      socket.close 1000 "second close"
      unless (← client.tryRecv?).isNone do
        throw (IO.userError "Repeated close must not send another frame")
  finally
    client.close

private def testCloseReasons : IO Unit := do
  let ascii (n : Nat) := String.ofList (List.replicate n 'a')
  checkCloseReason "" ""
  checkCloseReason "short reason" "short reason"
  checkCloseReason (ascii 123) (ascii 123)
  checkCloseReason (ascii 124) (ascii 123)
  checkCloseReason (ascii 10000) (ascii 123)
  for char in [Char.ofNat 0xE9, Char.ofNat 0x3042, Char.ofNat 0x1F600] do
    let symbol := String.singleton char
    let width := symbol.toUTF8.size
    checkCloseReason symbol symbol
    let exact := ascii (123 - width) ++ symbol
    checkCloseReason exact exact
    checkCloseReason (exact ++ "x") exact
    for prefixLength in [119:124] do
      let leading := ascii prefixLength
      let expected :=
        if prefixLength + width ≤ 123 then
          leading ++ symbol ++ ascii (123 - prefixLength - width)
        else leading
      checkCloseReason (leading ++ symbol ++ ascii 200) expected
  IO.println "PASS: WebSocket close reasons preserve UTF-8 boundaries and the 125-byte limit"

end WebSocketTests

def expectFailure (action : IO α) (message : String) : IO Unit := do
  let error <- try
    discard action
    pure none
  catch error =>
    pure (some error.toString)
  match error with
  | some error =>
    unless (error.splitOn message).length > 1 do
      throw (IO.userError s!"Expected error containing '{message}', got '{error}'")
  | none => throw (IO.userError s!"Expected failure: {message}")

def main : IO Unit := do
  LifecycleTests.test
  testCloseReasons
  let testProduct : Page.ShopProduct := {
    slug := "test", name := "Test", category := "Demo", price := 100,
    art := "x", kind := "test", badge := "NEW", description := "Description",
    details := "Details" }
  let context : Page.Context := {
    requestId := 7, path := "/hello", usersHtml := "<ul></ul>", sqliteDemoHtml := "<pre>demo</pre>",
    boardPosts := #[{ id := 3, author := "Ada", message := "Hello" }],
    wikiArticles := #[{ slug := "hello", title := "Hello", content := "Wiki text" }],
    shopProducts := #[testProduct],
    shopCart := #[{ product := testProduct, quantity := 2 }],
    shopLatestOrderId := some 4,
    shopInventory := #[{ product := testProduct, stock := 7 }],
    shopOrders := #[{
      id := 4, customerName := "Test User", postalCode := "000-0000",
      address := "Test Address", phone := "000-0000-0000", total := 200,
      paymentStatus := "paid", fulfillmentStatus := "shipped",
      items := #[{
        productSlug := "test", productName := "Test", quantity := 2, unitPrice := 100 }] }],
    chatPort := 12345 }
  match (Lean.fromJson? (Lean.toJson context) : Except String Page.Context) with
  | .ok decoded =>
    unless decoded.requestId == context.requestId && decoded.path == context.path &&
        decoded.usersHtml == context.usersHtml && decoded.sqliteDemoHtml == context.sqliteDemoHtml &&
        decoded.boardPosts == context.boardPosts && decoded.wikiArticles == context.wikiArticles &&
        decoded.shopProducts == context.shopProducts && decoded.shopCart == context.shopCart &&
        decoded.shopLatestOrderId == context.shopLatestOrderId &&
        decoded.shopInventory == context.shopInventory && decoded.shopOrders == context.shopOrders &&
        decoded.chatPort == context.chatPort do
      throw (IO.userError "Page context must preserve every field through JSON")
  | .error error => throw (IO.userError s!"Page context decoding failed: {error}")
  let legacyContext := Lean.Json.mkObj [
    ("requestId", Lean.toJson (1 : Nat)), ("path", Lean.toJson ("/" : String)),
    ("usersHtml", Lean.toJson ("<ul></ul>" : String))]
  match (Lean.fromJson? legacyContext : Except String Page.Context) with
  | .ok decoded =>
    unless decoded.sqliteDemoHtml.isEmpty && decoded.boardPosts.isEmpty &&
        decoded.wikiArticles.isEmpty && decoded.shopProducts.isEmpty &&
        decoded.shopCart.isEmpty && decoded.shopLatestOrderId.isNone &&
        decoded.shopInventory.isEmpty && decoded.shopOrders.isEmpty && decoded.chatPort == 0 do
      throw (IO.userError "Legacy page context must default optional fields")
  | .error error => throw (IO.userError s!"Legacy page context decoding failed: {error}")
  let invalidContext := Lean.Json.mkObj [
    ("requestId", Lean.toJson (1 : Nat)), ("path", Lean.toJson ("/" : String)),
    ("usersHtml", Lean.toJson ("<ul></ul>" : String)), ("sqliteDemoHtml", .null)]
  match (Lean.fromJson? invalidContext : Except String Page.Context) with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Present but invalid demo HTML must not be silently defaulted")
  let db <- Database.seededMemory
  unless IRT.itemPool.size == 30 do
    throw (IO.userError "CAT item pool must contain exactly thirty items")
  let catItems ← db.execute {
    sql := "SELECT item_id, a_milli, b_milli, c_milli FROM cat_items ORDER BY item_id"
    params := #[] }
  unless catItems.size == 30 && catItems[0]? ==
      some #[.integer 1, .integer 800, .integer (-2600), .integer 150] do
    throw (IO.userError "CAT item parameters must be seeded in SQLite")
  let catResponses ← db.execute { sql := "SELECT * FROM cat_responses", params := #[] }
  unless catResponses.isEmpty do
    throw (IO.userError "A new CAT run must have no saved responses")
  let startingAbility := IRT.posteriorAbility IRT.itemPool #[]
  let correctAbility := IRT.posteriorAbility IRT.itemPool
    #[{ itemId := 14, correct := true }]
  let incorrectAbility := IRT.posteriorAbility IRT.itemPool
    #[{ itemId := 14, correct := false }]
  unless correctAbility > startingAbility && incorrectAbility < startingAbility do
    throw (IO.userError "CAT EAP ability estimates must respond to correctness")
  let some firstItem := IRT.nextItem IRT.itemPool #[] |
    throw (IO.userError "CAT must select an initial item")
  unless IRT.nextItem IRT.itemPool #[{ itemId := firstItem.id, correct := true }] !=
      some firstItem do
    throw (IO.userError "CAT must not select an item more than once")
  let query <- match sampleQuery 3 with
    | .ok query => pure query
    | .error error => throw (IO.userError error)
  let expected := SampleData.users.extract 3 10
  unless (← db.execute query) == expected do
    throw (IO.userError "Parameterized query returned incorrect rows")
  let all <- renderQuery (.select #[.all] "users" none)
  unless SampleData.users.size == 10 && (← db.execute all) == SampleData.users do
    throw (IO.userError "Seeded database must contain exactly the ten synthetic source users")
  unless (← db.execute {
      sql := "SELECT sql FROM sqlite_master WHERE name = ?"
      params := #[.text "users"] }) == #[#[.text SampleData.sqliteSchema]] do
    throw (IO.userError "Displayed schema must match the actual database schema")
  let boardSelect <- renderQuery (.select #[.all] "posts" none)
  unless (← db.execute boardSelect).isEmpty do
    throw (IO.userError "A newly seeded bulletin board must have no posts")
  let boardInsert <- renderQuery (.insert "posts" #["author", "message"]
    #[#[.text "Ada", .text "Hello from SQLite"]])
  let _ ← db.execute boardInsert
  unless (← db.execute boardSelect) ==
      #[#[.integer 1, .text "Ada", .text "Hello from SQLite"]] do
    throw (IO.userError "MapleSQL post insertion and retrieval must use the shared SQLite database")
  let productSelect <- renderQuery (.select #[.all] "shop_products" none)
  unless (← db.execute productSelect).size == 8 do
    throw (IO.userError "A newly seeded shop must contain eight products")
  let inventorySelect <- renderQuery (.select #[.all] "shop_inventory" none)
  let inventoryRows ← db.execute inventorySelect
  unless inventoryRows.size == 8 &&
      inventoryRows.all (fun row => row[1]? == some (.integer 20)) do
    throw (IO.userError "A newly seeded shop must have inventory for every product")
  let cartInsert <- renderQuery (.insert "shop_cart_items" #["product_slug", "quantity"]
    #[#[.text "canvas-tote", .integer 2]])
  discard <| db.execute cartInsert
  let cartSelect <- renderQuery (.select #[.all] "shop_cart_items" none)
  unless (← db.execute cartSelect) == #[#[.text "canvas-tote", .integer 2]] do
    throw (IO.userError "MapleSQL cart insertion must persist in the shared SQLite database")
  let orderInsert <- renderQuery (.insert "shop_orders"
    #["customer_name", "postal_code", "address", "phone", "total",
      "payment_status", "fulfillment_status"]
    #[#[.text "Test User", .text "000-0000", .text "Test Address",
      .text "000-0000-0000", .integer 8250, .text "pending", .text "new"]])
  discard <| db.execute orderInsert
  let orderSelect <- renderQuery (.select #[.all] "shop_orders" none)
  unless (← db.execute orderSelect) ==
      #[#[.integer 1, .text "Test User", .text "000-0000", .text "Test Address",
        .text "000-0000-0000", .integer 8250, .text "pending", .text "new"]] do
    throw (IO.userError "MapleSQL order insertion must persist in the shared SQLite database")
  let wikiSelect <- renderQuery (.select #[.all] "wiki_articles" none)
  unless (← db.execute wikiSelect).size == 3 do
    throw (IO.userError "A newly seeded wiki must contain three starter articles")
  for row in SampleData.users do
    match row.toList with
    | [.integer id, .text _, .text email] =>
      unless email == s!"user-{id}@example.invalid" do
        throw (IO.userError "Dummy emails must use the reserved invalid domain")
    | _ => throw (IO.userError "Dummy users must have id, name and email")
  let emailQuery <- renderQuery (SampleData.emailsByNameStatement SampleData.duplicateName)
  unless emailQuery.sql == "SELECT \"email\" FROM \"users\" WHERE \"name\" = ?" &&
      emailQuery.params == #[.text SampleData.duplicateName] do
    throw (IO.userError "Email projection must bind the name separately")
  let expectedEmails := #[#[.text "user-1@example.invalid"], #[.text "user-2@example.invalid"]]
  let emails <- db.execute emailQuery
  unless emails == expectedEmails do
    throw (IO.userError "Same-name SELECT must return exactly two email-only rows")
  let missingName <- renderQuery (SampleData.emailsByNameStatement "No such dummy user")
  unless (← db.execute missingName).isEmpty do
    throw (IO.userError "Unmatched names must return no emails")
  let demo <- sqliteDemoHtml query (← db.execute query) emailQuery emails
  for text in #[SampleData.sourceUrl, SampleData.licenseUrl, SampleData.generatorUrl,
      escapeHtml SampleData.sourceSchema, escapeHtml SampleData.sqliteSchema,
      escapeHtml query.sql, escapeHtml (rowsJson expected).compress,
      escapeHtml (reprStr (sampleStatement 3)), escapeHtml emailQuery.sql,
      escapeHtml (Lean.Json.arr (emailQuery.params.map valueJson)).compress,
      escapeHtml (rowsJson expectedEmails).compress] do
    unless (demo.splitOn text).length > 1 do
      throw (IO.userError s!"Demo must display actual source, schema, and query output: {text}")
  let emptyQuery <- renderQuery (sampleStatement 10)
  unless (← db.execute emptyQuery).isEmpty do
    throw (IO.userError "IDs at or above ten must return empty results")

  let name := "'; DROP TABLE users; -- <script>&\""
  let email := "<script>&\"'@example.invalid"
  let insert <- renderQuery (.insert "users" #["id", "name", "email"]
    #[#[.integer 11, .text name, .text email]])
  unless (← db.execute insert).isEmpty do
    throw (IO.userError "INSERT should not return rows")
  let byName <- renderQuery (.select #[.all] "users"
    (some (.equal (.column "name") (.parameter (.text name)))))
  unless (← db.execute byName) == #[#[.integer 11, .text name, .text email]] do
    throw (IO.userError "Text parameters must round-trip without SQL interpolation")
  let injectedNameQuery <- renderQuery (SampleData.emailsByNameStatement name)
  unless (← db.execute injectedNameQuery) == #[#[.text email]] do
    throw (IO.userError "Email SELECT must bind SQL-like names without interpolation")
  unless (← usersHtml #[#[.integer 11, .text name, .text email]]) ==
      ("<ul><li>11: &#39;; DROP TABLE users; -- &lt;script&gt;&amp;&quot;" ++
        " <span>(&lt;script&gt;&amp;&quot;&#39;@example.invalid)</span></li></ul>") do
    throw (IO.userError "Database content must be HTML-escaped")

  let min : Int := -9223372036854775808
  let max : Int := 9223372036854775807
  unless (← db.execute { sql := "SELECT ?, ?", params := #[.integer min, .integer max] }) ==
      #[#[.integer min, .integer max]] do
    throw (IO.userError "SQLite integer boundaries must round-trip")
  let nulText := "before" ++ String.singleton (Char.ofNat 0) ++ "after"
  unless (← db.execute { sql := "SELECT ?", params := #[.text nulText] }) ==
      #[#[.text nulText]] do
    throw (IO.userError "SQLite text parameters must preserve embedded NUL bytes")

  expectFailure (db.execute { sql := "SELECT ?", params := #[.integer (max + 1)] })
    "signed 64-bit"
  expectFailure (db.execute { sql := "SELECT ?", params := #[.integer (min - 1)] })
    "signed 64-bit"
  expectFailure (db.execute { sql := "SELECT ?", params := #[] }) "parameter count mismatch"
  expectFailure (db.execute { sql := "SELECT 1", params := #[.integer 1] })
    "parameter count mismatch"
  expectFailure (db.execute { sql := "SELECT 1; DROP TABLE users", params := #[] })
    "one SQL statement"
  expectFailure (db.execute { sql := "", params := #[] }) "one statement"
  expectFailure (db.execute {
    sql := "SELECT 1" ++ String.singleton (Char.ofNat 0), params := #[] }) "NUL bytes"
  expectFailure (db.execute { sql := "SELECT * FROM missing", params := #[] })
    "no such table"
  expectFailure (db.execute { sql := "SELECT NULL", params := #[] }) "Unsupported"
  expectFailure (db.execute { sql := "SELECT 1.5", params := #[] }) "Unsupported"
  expectFailure (db.execute { sql := "SELECT x'00'", params := #[] }) "Unsupported"
  expectFailure (db.execute insert) "UNIQUE constraint"
  let repeatedEmail <- renderQuery (.insert "users" #["id", "name", "email"]
    #[#[.integer 12, .text "Another dummy", .text "user-1@example.invalid"]])
  expectFailure (db.execute repeatedEmail) "UNIQUE constraint"
  let missingEmail <- renderQuery (.insert "users" #["id", "name"]
    #[#[.integer 12, .text "Another dummy"]])
  expectFailure (db.execute missingEmail) "NOT NULL constraint"
  unless (← db.execute all).size == 11 do
    throw (IO.userError "Data should persist on the shared connection after query failures")
  let fresh <- Database.seededMemory
  unless (← fresh.execute all) == SampleData.users do
    throw (IO.userError "In-memory databases must be isolated per connection")
  IO.println "PASS: SQLite execution, binding, result types, error recovery, memory isolation"
