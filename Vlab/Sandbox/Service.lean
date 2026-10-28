/-
One sandbox is one directory, one grant list and one quota.
Each execution starts with a zeroed linear memory, a full fuel tank and a
zero host-call count. The virtual directory survives across executions of
the same sandbox and disappears on destroy. The cairn audit does not.
-/

import Vlab.Sandbox.Host
import Vlab.Store
import Vlab.Wasm.Ast
import Vlab.Wasm.Binary
import Vlab.Wasm.Eval

open Vlab.Sandbox.Host
open Vlab.Wasm
open Vlab.Wasm.Binary

namespace Vlab.Sandbox.Service

def maxFuel : Nat := 100000
def maxMemory : Nat := 1024 * 1024
def maxCalls : Nat := 1000
def maxModuleHex : Nat := 32768
def maxLive : Nat := 32
def vfsQuota : Nat := 262144

structure Spec where
  fuel : Nat := 1000
  memoryBytes : Nat := 65536
  maxHostCalls : Nat := 8
  fsRead : Bool := false
  fsWrite : Bool := false
  clock : Bool := false
  random : Bool := false
  netHost : String := ""
  netPort : Nat := 0
  netBody : String := ""
  deriving Repr

def Spec.grants (s : Spec) : List Cap :=
  let fs : List Cap :=
    (if s.fsRead then [.fsRead []] else []) ++
    (if s.fsWrite then [.fsWrite []] else [])
  let clk : List Cap := if s.clock then [.clock] else []
  let rnd : List Cap := if s.random then [.random] else []
  let net : List Cap :=
    if s.netHost.isEmpty then []
    else [.net s.netHost s.netPort s.netBody.toUTF8.data]
  fs ++ clk ++ rnd ++ net

def Spec.check (s : Spec) : Except String Spec := do
  if s.fuel = 0 || s.fuel > maxFuel then throw "fuel out of range"
  if s.memoryBytes > maxMemory then throw "memory out of range"
  if s.maxHostCalls > maxCalls then throw "host calls out of range"
  pure s

def parseSpec (text : String) : Except String Spec := do
  let mut spec : Spec := {}
  for raw in text.splitOn "\n" do
    let line := raw.trimAscii.toString
    if line.isEmpty then continue
    let p := line.splitOn " " |>.filter (· ≠ "")
    match p with
    | ["fuel", n] =>
      let some k := n.toNat? | throw "fuel"
      spec := { spec with fuel := k }
    | ["memory", n] =>
      let some k := n.toNat? | throw "memory"
      spec := { spec with memoryBytes := k }
    | ["calls", n] =>
      let some k := n.toNat? | throw "calls"
      spec := { spec with maxHostCalls := k }
    | ["fs-read"] => spec := { spec with fsRead := true }
    | ["fs-write"] => spec := { spec with fsWrite := true }
    | ["clock"] => spec := { spec with clock := true }
    | ["random"] => spec := { spec with random := true }
    | ["net", host, port, body] =>
      let some k := port.toNat? | throw "port"
      spec := { spec with netHost := host, netPort := k, netBody := body }
    | _ => throw s!"bad spec line {line}"
  Spec.check spec

def addHex : String :=
  "0061736d010000000105016000017f03020100070801046d61696e00000a09010700412841026a0b"

def oobHex : String :=
  "0061736d010000000105016000017f030201000503010001070801046d61696e00000a0e010c00418080042802001a41000b"

def loopHex : String :=
  "0061736d010000000105016000017f03020100070801046d61696e00000a0b01090003400c000b41000b"

def hostHex : String :=
  "0061736d01000000010d0260047f7f7f7f017f6000017f02100104766c61620766735f72656164000003020101070801046d61696e00010a0e010c00410041004100410010000b"

def exampleHex : String → Option String
  | "add" => some addHex
  | "oob" => some oobHex
  | "loop" => some loopHex
  | "host" => some hostHex
  | _ => none

def parseExec (text : String) : Except String ByteArray := do
  let line := text.trimAscii.toString
  let p := line.splitOn " " |>.filter (· ≠ "")
  match p with
  | ["example", name] =>
    let some hex := exampleHex name | throw "unknown example"
    let some b := ofHex hex | throw "example hex"
    pure b
  | ["wasm", hex] =>
    if hex.length > maxModuleHex then throw "module too big"
    let some b := ofHex hex | throw "wasm hex"
    pure b
  | _ => throw "exec wants `example NAME` or `wasm HEX`"

structure Box where
  id : String
  spec : Spec
  dir : System.FilePath
  alive : Bool

def auditName (id : String) : String :=
  "aud-" ++ id

def boxJson (b : Box) : String :=
  let g := b.spec.grants
  let names := ", ".intercalate (g.map fun
    | .fsRead _ => "\"fs-read\""
    | .fsWrite _ => "\"fs-write\""
    | .clock => "\"clock\""
    | .random => "\"random\""
    | .net h p _ => "\"net " ++ h ++ ":" ++ toString p ++ "\"")
  "{\"id\":\"" ++ b.id ++ "\",\"alive\":" ++ (if b.alive then "true" else "false") ++
    ",\"fuel\":" ++ toString b.spec.fuel ++
    ",\"memoryBytes\":" ++ toString b.spec.memoryBytes ++
    ",\"maxHostCalls\":" ++ toString b.spec.maxHostCalls ++
    ",\"grants\":[" ++ names ++ "]}"

def loadVfs (dir : System.FilePath) : IO (List (List String × Array UInt8)) := do
  if !(← dir.pathExists) then return []
  let entries ← dir.readDir
  let mut out : List (List String × Array UInt8) := []
  for e in entries do
    let info ← e.path.metadata
    if info.type == .file then
      let bytes ← IO.FS.readBinFile e.path
      out := out ++ [([e.fileName], bytes.data)]
  return out

def saveVfs (dir : System.FilePath) (vfs : List (List String × Array UInt8)) : IO Unit := do
  IO.FS.createDirAll dir
  for (segs, data) in vfs do
    let mut p := dir
    for s in segs do
      p := p / s
    IO.FS.createDirAll (p.parent.getD dir)
    IO.FS.writeBinFile p ⟨data⟩

def runBytes (spec : Spec) (env0 : HostEnv) (bytes : ByteArray) : Except String Halt := do
  let some m := decode bytes | throw "decode"
  if m.memPages * Vlab.Wasm.Mem.page > spec.memoryBytes then
    throw "module memory exceeds quota"
  pure (runModule spec.fuel m env0 spec.memoryBytes)

private def trapName : Trap → String
  | .outOfFuel => "outOfFuel"
  | .bounds => "bounds"
  | .stack => "stack"
  | .typeError => "typeError"
  | .denied => "denied"
  | .hostQuota => "hostQuota"
  | .memQuota => "memQuota"
  | .unreachable => "unreachable"
  | .escape => "escape"
  | .badModule => "badModule"

private def jsonString (s : String) : String :=
  let s := s.replace "\"" "\\\""
  let s := s.replace "\n" "\\n"
  "\"" ++ s ++ "\""

def summarize (h : Halt) : String :=
  match h with
  | .ok st | .ret st =>
    let v := match st.stack with
      | .i32 n :: _ => toString n.toNat
      | .i64 n :: _ => toString n.toNat
      | _ => ""
    let lines := "\n".intercalate st.host.audit.reverse
    "{\"trap\":null,\"value\":\"" ++ v ++ "\",\"calls\":" ++ toString st.host.calls ++
      ",\"audit\":" ++ jsonString lines ++ "}"
  | .trap t st =>
    let lines := "\n".intercalate st.host.audit.reverse
    "{\"trap\":\"" ++ trapName t ++ "\",\"value\":\"\",\"calls\":" ++ toString st.host.calls ++
      ",\"audit\":" ++ jsonString lines ++ "}"
  | .br _ st =>
    "{\"trap\":\"br\",\"value\":\"\",\"calls\":" ++ toString st.host.calls ++ ",\"audit\":\"\"}"

end Vlab.Sandbox.Service
