namespace LeanWebStudy.OrderBook

inductive Side where
  | buy
  | sell
  deriving BEq, Repr, Inhabited

structure Order where
  id : Nat
  side : Side
  price : Nat
  remaining : Nat
  deriving BEq, Repr, Inhabited

structure Trade where
  id : Nat
  makerOrderId : Nat
  takerOrderId : Nat
  price : Nat
  quantity : Nat
  deriving BEq, Repr

structure Book where
  orders : Array Order
  trades : Array Trade
  nextOrderId : Nat
  nextTradeId : Nat
  deriving BEq, Repr

structure Submission where
  book : Book
  orderId : Nat
  remaining : Nat
  trades : Array Trade
  deriving BEq, Repr

def initial : Book := {
  orders := #[
    { id := 1, side := .buy, price := 10000, remaining := 5 },
    { id := 2, side := .buy, price := 9950, remaining := 8 },
    { id := 3, side := .sell, price := 10100, remaining := 4 },
    { id := 4, side := .sell, price := 10150, remaining := 7 }]
  trades := #[]
  nextOrderId := 5
  nextTradeId := 1
}

def bestMatchIndex (book : Book) (side : Side) (price : Nat) : Option Nat := Id.run do
  let mut best : Option Nat := none
  for index in [:book.orders.size] do
    let order := book.orders[index]!
    let eligible := match side, order.side with
      | .buy, .sell => decide (order.price <= price)
      | .sell, .buy => decide (order.price >= price)
      | _, _ => false
    if eligible then
      match best with
      | none => best := some index
      | some bestIndex =>
        let currentBest := book.orders[bestIndex]!
        let better := match side with
          | .buy => decide (order.price < currentBest.price)
          | .sell => decide (order.price > currentBest.price)
        if better || (order.price == currentBest.price && order.id < currentBest.id) then
          best := some index
  return best

def removeOrReduce (orders : Array Order) (index : Nat) (quantity : Nat) :
    Array Order := Id.run do
  let mut result := #[]
  for currentIndex in [:orders.size] do
    let order := orders[currentIndex]!
    if currentIndex == index then
      if order.remaining > quantity then
        result := result.push { order with remaining := order.remaining - quantity }
    else
      result := result.push order
  return result

def submit (book : Book) (side : Side) (price quantity : Nat) : Submission := Id.run do
  let orderId := book.nextOrderId
  let mut nextBook := book
  let mut remaining := quantity
  let mut fills := #[]
  while remaining > 0 do
    match bestMatchIndex nextBook side price with
    | none => break
    | some index =>
      let maker := nextBook.orders[index]!
      let filled := min remaining maker.remaining
      let trade : Trade := {
        id := nextBook.nextTradeId
        makerOrderId := maker.id
        takerOrderId := orderId
        price := maker.price
        quantity := filled
      }
      nextBook := {
        nextBook with
        orders := removeOrReduce nextBook.orders index filled
        trades := nextBook.trades.push trade
        nextTradeId := nextBook.nextTradeId + 1
      }
      fills := fills.push trade
      remaining := remaining - filled
  if remaining > 0 then
    nextBook := {
      nextBook with
      orders := nextBook.orders.push { id := orderId, side, price, remaining }
    }
  if nextBook.trades.size > 20 then
    nextBook := { nextBook with trades := nextBook.trades.extract (nextBook.trades.size - 20) nextBook.trades.size }
  nextBook := { nextBook with nextOrderId := orderId + 1 }
  return { book := nextBook, orderId, remaining, trades := fills }

def parsePrice (input : String) : Option Nat := do
  let parts := input.splitOn "."
  match parts with
  | [whole] =>
    let dollars ← whole.toNat?
    if dollars == 0 then none else some (dollars * 100)
  | [whole, fraction] =>
    let dollars ← whole.toNat?
    if fraction.length == 1 then
      let cents ← fraction.toNat?
      if dollars == 0 && cents == 0 then none else some (dollars * 100 + cents * 10)
    else if fraction.length == 2 then
      let cents ← fraction.toNat?
      if dollars == 0 && cents == 0 then none else some (dollars * 100 + cents)
    else
      none
  | _ => none

def formatPrice (price : Nat) : String :=
  let whole := toString (price / 100)
  let fraction := toString (price % 100)
  whole ++ "." ++ (if fraction.length == 1 then "0" else "") ++ fraction

end LeanWebStudy.OrderBook
