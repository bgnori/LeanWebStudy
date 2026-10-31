import Lean

namespace LeanWebStudy.Page

structure Context where
  requestId : Nat
  path : String
  usersHtml : String
  deriving Lean.ToJson, Lean.FromJson

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
