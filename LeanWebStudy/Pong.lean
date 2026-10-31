import Lean.Data.Json

namespace LeanWebStudy.Pong

private def errorResponse (message : String) : Bool × String :=
  (false, (Lean.Json.mkObj [
    ("type", Lean.toJson ("error" : String)),
    ("message", Lean.toJson message)]).compress)

private def decode (bytes : ByteArray) : Except String String := do
  let some text := String.fromUTF8? bytes
    | throw "UTF-8 のテキストを送信してください。"
  let json ← Lean.Json.parse text
  let kind ← json.getObjValAs? String "type"
  if kind == "paddle" then
    let y ← json.getObjValAs? Nat "y"
    unless y <= 370 do throw "パドル位置が範囲外です。"
    return (Lean.Json.mkObj [
      ("type", Lean.toJson ("paddle" : String)),
      ("y", Lean.toJson y)]).compress
  if kind == "ball" then
    let x ← json.getObjValAs? Nat "x"
    let y ← json.getObjValAs? Nat "y"
    let left ← json.getObjValAs? Nat "left"
    let right ← json.getObjValAs? Nat "right"
    unless x <= 800 && y <= 450 && left <= 7 && right <= 7 do
      throw "ボールまたはスコアが範囲外です。"
    return (Lean.Json.mkObj [
      ("type", Lean.toJson ("ball" : String)),
      ("x", Lean.toJson x), ("y", Lean.toJson y),
      ("left", Lean.toJson left), ("right", Lean.toJson right)]).compress
  throw "type は paddle または ball を指定してください。"

def response (_id : UInt64) (bytes : ByteArray) : Bool × String :=
  match decode bytes with
  | .ok event => (true, event)
  | .error error => errorResponse error

end LeanWebStudy.Pong
