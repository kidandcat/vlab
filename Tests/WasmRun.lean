import Vlab.Sandbox.Host
import Vlab.Sandbox.Service
import Vlab.Wasm.Ast
import Vlab.Wasm.Binary
import Vlab.Wasm.Eval

open Vlab.Sandbox.Host
open Vlab.Wasm
open Vlab.Wasm.Binary

private def expect (name : String) (ok : Bool) : IO Unit := do
  unless ok do
    throw (IO.userError name)

def emptyEnv : HostEnv := {
  grants := []
  vfs := []
  clock := 0
  entropy := #[]
  entropyAt := 0
  calls := 0
  callQuota := 4
  vfsQuota := 1024
  audit := []
}

def resultI32 : Halt → Option UInt32
  | .ok st | .ret st =>
    match st.stack with
    | .i32 n :: _ => some n
    | _ => none
  | _ => none

def trapOf : Halt → Option Trap
  | .trap t _ => some t
  | _ => none

def addHex : String :=
  "0061736d010000000105016000017f03020100070801046d61696e00000a09010700412841026a0b"

def oobHex : String :=
  "0061736d010000000105016000017f030201000503010001070801046d61696e00000a0e010c00418080042802001a41000b"

def loopHex : String :=
  "0061736d010000000105016000017f03020100070801046d61696e00000a0b01090003400c000b41000b"

def hostHex : String :=
  "0061736d01000000010d0260047f7f7f7f017f6000017f02100104766c61620766735f72656164000003020101070801046d61696e00010a0e010c00410041004100410010000b"

def decodeHex (s : String) : IO Module := do
  let some bytes := ofHex s | throw (IO.userError "hex")
  match decode bytes with
  | some m => return m
  | none => throw (IO.userError s!"decode failed {s.length}")

def testArith : IO Unit := do
  let m ← decodeHex addHex
  match resultI32 (runModule 20 m emptyEnv 0) with
  | some 42 => pure ()
  | other => throw (IO.userError s!"add {other}")

def testOob : IO Unit := do
  let m ← decodeHex oobHex
  expect "oob" (trapOf (runModule 20 m emptyEnv (65536 * 2)) == some .bounds)

def testLoop : IO Unit := do
  let m ← decodeHex loopHex
  expect "loop" (trapOf (runModule 30 m emptyEnv 0) == some .outOfFuel)

def testDeny : IO Unit := do
  let m ← decodeHex hostHex
  let h := runModule 20 m emptyEnv 0
  expect "deny trap" (trapOf h == none)
  match h with
  | .ok st | .ret st =>
    expect "deny value" (resultI32 h == some 0xFFFFFFFF)
    expect "deny audit" (st.host.audit.any (·.startsWith "deny fs_read"))
    expect "vfs untouched" st.host.vfs.isEmpty
  | .trap t _ => throw (IO.userError s!"deny trap {repr t}")
  | .br _ _ => throw (IO.userError "deny br")

def testAllowFs : IO Unit := do
  let m ← decodeHex hostHex
  let env := { emptyEnv with grants := [.fsRead [], .fsWrite []] }
  -- host fixture only calls fs_read. Grant read, empty file, returns 0.
  match resultI32 (runModule 20 m env 0) with
  | some 0 => pure ()
  | other => throw (IO.userError s!"allow read {other}")

def testEscape : IO Unit := do
  -- i32 path pointer 0, length 2, bytes are ".." written by stores, then call fs_read.
  -- Built as AST: store ".." at 0 and call import 0. Memory one byte page is heavy;
  -- use a tiny custom module with memPages 1 and body that stores 0x2e 0x2e then calls.
  let body : List Instr := [
    .constI32 0, .constI32 0x2e, .store8,
    .constI32 1, .constI32 0x2e, .store8,
    .constI32 0, .constI32 2, .constI32 0, .constI32 0, .call 0
  ]
  let m : Module := {
    imports := #[{ module := "vlab", name := "fs_read", op := some .fsRead, params := 4 }]
    funcs := #[{ params := 0, locals := 0, results := 1, body }]
    memPages := 1
    main := 1
  }
  let env := { emptyEnv with grants := [.fsRead []] }
  let h := runModule 40 m env (65536 * 2)
  unless trapOf h == some .escape do
    throw (IO.userError s!"escape got {repr (trapOf h)} audit={match h with | .trap _ st => st.host.audit | .ok st | .ret st => st.host.audit | .br _ st => st.host.audit}")

def testNormalize : IO Unit := do
  expect "dotdot" (Vlab.Sandbox.Path.normalize "../x" == none)
  expect "stay" (Vlab.Sandbox.Path.normalize "a/../b" == some ["b"])
  expect "root" (Vlab.Sandbox.Path.normalize "/" == some [])

private def wasmtime (bytes : ByteArray) (name : String) : IO (Bool × String) := do
  let path : System.FilePath := s!"/tmp/vlab-{name}-{← IO.monoNanosNow}.wasm"
  IO.FS.writeBinFile path bytes
  let r ← IO.Process.output { cmd := "wasmtime", args := #["--invoke", "main", path.toString] }
  return (r.exitCode == 0, r.stdout.trimAscii.toString)

def testDiff : IO Unit := do
  let some addB := ofHex addHex | throw (IO.userError "add hex")
  let (ok, out) ← wasmtime addB "add"
  expect "wasmtime add" (ok && out == "42")
  let some oobB := ofHex oobHex | throw (IO.userError "oob hex")
  let (ok2, _) ← wasmtime oobB "oob"
  expect "wasmtime oob traps" (!ok2)

def testSpec : IO Unit := do
  match Vlab.Sandbox.Service.parseSpec "fuel 20\nmemory 65536\nfs-read\nnet example.test 80 ok\n" with
  | .ok s =>
    expect "fuel" (s.fuel == 20)
    expect "net" (s.netHost == "example.test")
    expect "grant" (s.grants.any fun c => match c with | .net _ _ _ => true | _ => false)
  | .error e => throw (IO.userError e)
  match Vlab.Sandbox.Service.parseSpec "fuel 0\n" with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "fuel 0 accepted")

def testWasm : IO Unit := do
  testNormalize
  testSpec
  testArith
  testOob
  testLoop
  testDeny
  testAllowFs
  testEscape
  testDiff
