namespace LeanWebStudy.IRT

structure Item where
  id : Nat
  aMilli : Nat
  bMilli : Int
  cMilli : Nat
  deriving BEq, Repr

structure Response where
  itemId : Nat
  correct : Bool
  deriving BEq, Repr

def itemPool : Array Item := #[
  { id := 1, aMilli := 800, bMilli := -2600, cMilli := 150 },
  { id := 2, aMilli := 1100, bMilli := -2400, cMilli := 200 },
  { id := 3, aMilli := 1400, bMilli := -2200, cMilli := 180 },
  { id := 4, aMilli := 900, bMilli := -2000, cMilli := 250 },
  { id := 5, aMilli := 1200, bMilli := -1800, cMilli := 160 },
  { id := 6, aMilli := 1600, bMilli := -1600, cMilli := 220 },
  { id := 7, aMilli := 1000, bMilli := -1400, cMilli := 200 },
  { id := 8, aMilli := 1300, bMilli := -1200, cMilli := 150 },
  { id := 9, aMilli := 1700, bMilli := -1000, cMilli := 240 },
  { id := 10, aMilli := 900, bMilli := -800, cMilli := 180 },
  { id := 11, aMilli := 1200, bMilli := -600, cMilli := 210 },
  { id := 12, aMilli := 1500, bMilli := -400, cMilli := 170 },
  { id := 13, aMilli := 1000, bMilli := -200, cMilli := 250 },
  { id := 14, aMilli := 1800, bMilli := 0, cMilli := 200 },
  { id := 15, aMilli := 1300, bMilli := 200, cMilli := 150 },
  { id := 16, aMilli := 900, bMilli := 400, cMilli := 220 },
  { id := 17, aMilli := 1500, bMilli := 600, cMilli := 180 },
  { id := 18, aMilli := 1100, bMilli := 800, cMilli := 250 },
  { id := 19, aMilli := 1700, bMilli := 1000, cMilli := 160 },
  { id := 20, aMilli := 1000, bMilli := 1200, cMilli := 200 },
  { id := 21, aMilli := 1400, bMilli := 1400, cMilli := 230 },
  { id := 22, aMilli := 1900, bMilli := 1600, cMilli := 150 },
  { id := 23, aMilli := 1100, bMilli := 1800, cMilli := 190 },
  { id := 24, aMilli := 1600, bMilli := 2000, cMilli := 250 },
  { id := 25, aMilli := 900, bMilli := 2200, cMilli := 170 },
  { id := 26, aMilli := 1300, bMilli := 2400, cMilli := 210 },
  { id := 27, aMilli := 1800, bMilli := 2600, cMilli := 180 },
  { id := 28, aMilli := 1200, bMilli := -1500, cMilli := 230 },
  { id := 29, aMilli := 1500, bMilli := 500, cMilli := 160 },
  { id := 30, aMilli := 1000, bMilli := 2100, cMilli := 200 }
]

def difficultyConstant : Float := 1.7

def probabilityCorrect (item : Item) (theta : Float) : Float :=
  let a := Float.ofNat item.aMilli / 1000.0
  let b := Float.ofInt item.bMilli / 1000.0
  let c := Float.ofNat item.cMilli / 1000.0
  let logistic := 1.0 / (1.0 + Float.exp (-(difficultyConstant * a * (theta - b))))
  c + (1.0 - c) * logistic

def posteriorAbility (items : Array Item) (responses : Array Response) : Float := Id.run do
  let mut weightedAbility := 0.0
  let mut totalWeight := 0.0
  for step in [:161] do
    let theta := -4.0 + Float.ofNat step / 20.0
    let mut weight := Float.exp (-(theta * theta) / 2.0)
    for response in responses do
      match items.find? (·.id == response.itemId) with
      | none => pure ()
      | some item =>
        let probability := probabilityCorrect item theta
        weight := weight * (if response.correct then probability else 1.0 - probability)
    totalWeight := totalWeight + weight
    weightedAbility := weightedAbility + theta * weight
  if totalWeight == 0.0 then return 0.0
  return weightedAbility / totalWeight

def abilityMilli (theta : Float) : Int :=
  Int.ofNat (((5.0 + theta) * 1000.0 + 0.5).toUInt64.toNat) - 5000

def information (item : Item) (theta : Float) : Float :=
  let a := Float.ofNat item.aMilli / 1000.0
  let b := Float.ofInt item.bMilli / 1000.0
  let c := Float.ofNat item.cMilli / 1000.0
  let logistic := 1.0 / (1.0 + Float.exp (-(difficultyConstant * a * (theta - b))))
  let probability := c + (1.0 - c) * logistic
  (difficultyConstant * difficultyConstant * a * a * (1.0 - c) *
    logistic * logistic * (1.0 - logistic)) / probability

def nextItem (items : Array Item) (responses : Array Response) : Option Item := do
  let theta := posteriorAbility items responses
  let mut best : Option (Item × Float) := none
  for item in items do
    if responses.all (·.itemId != item.id) then
      let score := information item theta
      match best with
      | none => best := some (item, score)
      | some (_, currentScore) =>
        if score > currentScore then best := some (item, score)
  (best.map Prod.fst)

end LeanWebStudy.IRT
