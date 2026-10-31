import Lake
open Lake DSL

-- Use the system library directory for SQLite and its matching libc dependencies.
private def sqliteLinkArgs : Array String := run_io do
  let result <- IO.Process.output { cmd := "cc", args := #["-print-file-name=libsqlite3.so"] }
  let path := result.stdout.trimAscii.toString
  if result.exitCode != 0 || path == "libsqlite3.so" || path.isEmpty then
    throw (IO.userError "SQLite development library not found; install libsqlite3-dev and a C compiler")
  let library <- IO.FS.realPath path
  let some directory := library.parent
    | throw (IO.userError "SQLite library has no parent directory")
  return #["-B", directory.toString, "-L", directory.toString, "-lsqlite3"]

package LeanWebStudy where
  version := v!"0.1.0"
  moreLinkArgs := sqliteLinkArgs

require maplesql from git
  "https://github.com/bgnori/MapleSQL.git" @ "2c6cd91028888defd2c9f678386efe069a6d78fc"

require html from git
  "https://github.com/paulbutcher/lean-html" @ "573ae2609ceef7afd509d0fcce533ddc913e990f"

require lithe from git
  "https://github.com/JoshuaPurtell/lithe" @ "v0.1.0"

lean_lib LeanWebStudy

target sqlite.o pkg : System.FilePath := do
  let src <- inputFile (pkg.dir / "native" / "sqlite.c") true
  buildO (pkg.buildDir / "native" / "sqlite.o") src
    #["-I", (← getLeanIncludeDir).toString] #["-fPIC", "-Wall", "-Wextra", "-Werror"]

extern_lib sqlite pkg := do
  let obj <- sqlite.o.fetch
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "sqlite") #[obj]

@[test_driver]
lean_exe LeanWebStudyTests where
  root := `LeanWebStudyTests

@[default_target]
lean_exe leanwebstudy where
  root := `Main
