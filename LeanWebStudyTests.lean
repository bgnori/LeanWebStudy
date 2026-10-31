import LeanWebStudy

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
