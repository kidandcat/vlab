import Tests.WasmRun
import Vlab.Http
import Vlab.Json
import Vlab.Store

open Vlab.Http
open Vlab.Json
open Vlab.Store

private def expect (name : String) (ok : Bool) : IO Unit := do
  unless ok do
    throw (IO.userError name)

private def testJson : IO Unit := do
  match parseTextField "{\"text\":\"hola\"}" with
  | .ok "hola" => pure ()
  | other => throw (IO.userError s!"plain {repr other}")
  match parseTextField "  { \"text\" : \"a\\\"b\\\\c\\n\" }\n" with
  | .ok "a\"b\\c\n" => pure ()
  | other => throw (IO.userError s!"escapes {repr other}")
  match parseTextField "{\"text\":\"á\"}" with
  | .ok "á" => pure ()
  | other => throw (IO.userError s!"utf8 {repr other}")
  match parseTextField "{\"text\":\"\\u00e1\"}" with
  | .ok "á" => pure ()
  | other => throw (IO.userError s!"unicode {repr other}")
  match parseTextField "{\"no\":1}" with
  | .error _ => pure ()
  | .ok v => throw (IO.userError s!"accepted {v}")
  expect "escape quote" ((str "a\"b") == "\"a\\\"b\"")
  expect "roundtrip escape" <|
    match parseTextField ("{\"text\":" ++ str "línea\n\"x\"" ++ "}") with
    | .ok "línea\n\"x\"" => true
    | _ => false

private def testRoutes : IO Unit := do
  expect "health" (classify "GET" "/health" == .health)
  expect "health query" (classify "GET" "/health?x=1" == .health)
  expect "list" (classify "GET" "/api/notes" == .listNotes)
  expect "create" (classify "POST" "/api/notes" == .createNote)
  expect "root" (classify "GET" "/" == .static "index.html")
  expect "wasm" (classify "GET" "/uvl.wasm" == .static "uvl.wasm")
  expect "traversal" (classify "GET" "/../secret" == .notFound)
  expect "dot" (classify "GET" "/index.html/../../etc" == .notFound)
  expect "post root" (classify "POST" "/" == .methodNotAllowed)
  expect "missing" (classify "GET" "/nope" == .notFound)

private def testIds : IO Unit := do
  let zero : Cairn.Ulid := ⟨0, 0, by decide, by decide⟩
  let max : Cairn.Ulid := ⟨2 ^ 48 - 1, 2 ^ 80 - 1, by decide, by decide⟩
  expect "zero hex" (ofHex? (toHex zero) == some zero)
  expect "max hex" (ofHex? (toHex max) == some max)
  expect "short" (ofHex? "abc" == none)
  expect "width" ((toHex zero).length == 32)

private def testStore : IO Unit := do
  let dir : System.FilePath := s!"/tmp/vlab-test-{← IO.monoNanosNow}"
  try
    let s ← openAt dir
    expect "boot 1" (s.boots == 1)
    let n ← s.addNote "hola \"mundo\""
    let listed ← s.listNotes 10
    expect "one note" (listed.length == 1)
    expect "text" (listed.head?.map (·.text) == some "hola \"mundo\"")
    let again ← s.getNote n.id
    expect "get" (again.map (·.version) == some n.version)
    s.close
    let s2 ← openAt dir
    expect "boot 2" (s2.boots == 2)
    let listed2 ← s2.listNotes 10
    expect "persisted" (listed2.map (·.text) == ["hola \"mundo\""])
    let n2 ← s2.addNote "segunda"
    expect "order" ((toHex n.id).toList < (toHex n2.id).toList)
    try
      discard <| s2.addNote ""
      throw (IO.userError "EMPTY_STORED")
    catch e =>
      let msg := toString e
      if msg.contains "EMPTY_STORED" then
        throw e
      unless msg.contains "empty note" do
        throw e
    s2.close
  finally
    IO.FS.removeDirAll dir

def main : IO UInt32 := do
  try
    testJson
    testRoutes
    testIds
    testStore
    testWasm
    IO.println "vlab tests ok"
    return 0
  catch e =>
    IO.eprintln s!"vlab tests failed: {e}"
    return 1
