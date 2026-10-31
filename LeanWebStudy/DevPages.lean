import LeanWebStudy.Page

namespace LeanWebStudy

structure DevPages where
  directory : System.FilePath

def DevPages.open (directory : System.FilePath) : IO DevPages := do
  let directory <- IO.FS.realPath directory
  unless (← directory.isDir) do
    throw (IO.userError s!"Page directory is not a directory: {directory}")
  return { directory }

def DevPages.routeParts (path : String) : Option (List String) := do
  if path == "/" then return []
  let parts := path.splitOn "/"
  guard (parts.head? == some "")
  let parts := parts.drop 1
  let parts := if parts.getLast? == some "" then parts.dropLast else parts
  guard (!parts.isEmpty && parts.all fun part =>
    !part.isEmpty && part.toList.all fun c =>
      (c.toNat < 128 && c.isAlphanum) || c == '_' || c == '-')
  return parts

def DevPages.relativePath (path : String) : Option System.FilePath := do
  let parts ← DevPages.routeParts path
  if parts.isEmpty || (path.splitOn "/").getLast? == some "" then
    return System.FilePath.mk (String.intercalate "/" parts ++
      (if parts.isEmpty then "" else "/") ++ "index.lean")
  return System.FilePath.mk (String.intercalate "/" parts ++ ".lean")

def DevPages.find (self : DevPages) (path : String) : IO (Option System.FilePath) := do
  let some relative := DevPages.relativePath path | return none
  let candidate := self.directory / relative
  let candidate ←
    if ← candidate.pathExists then
      pure candidate
    else if (path.splitOn "/").getLast? != some "" then
      let some parts := DevPages.routeParts path | return none
      let index := self.directory / System.FilePath.mk (String.intercalate "/" parts) /
        "index.lean"
      if ← index.pathExists then pure index else return none
    else
      return none
  let resolved <- IO.FS.realPath candidate
  unless self.directory.components.isPrefixOf resolved.components do
    throw (IO.userError s!"Page resolves outside page directory: {candidate}")
  unless (← resolved.metadata).type == .file do return none
  return some resolved

def DevPages.render (source : System.FilePath) (context : Page.Context) : IO String := do
  let result <- IO.Process.output {
    cmd := "lake"
    args := #["env", "lean", "--run", source.toString]
  } (some (Lean.toJson context).compress)
  if result.exitCode != 0 then
    throw (IO.userError
      s!"Page worker failed ({source}, exit {result.exitCode}):\n{result.stdout}{result.stderr}")
  unless result.stderr.isEmpty do IO.eprint result.stderr
  match Lean.Json.parse result.stdout >>= Lean.fromJson? with
  | .ok html => return html
  | .error error =>
    throw (IO.userError s!"Invalid page worker response ({source}): {error}\n{result.stdout}")

end LeanWebStudy
