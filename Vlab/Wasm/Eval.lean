/-
Interpreter. Recursion is on the fuel argument, so a run stops.
Memory changes go through `Mem.store?` and `Mem.grow`. Host effects go
through `Host.perform`. Fuel 0 traps before an instruction runs.
-/

import Vlab.Sandbox.Host
import Vlab.Wasm.Ast
import Vlab.Wasm.Mem

open Vlab.Sandbox.Host
open Vlab.Wasm.Mem

namespace Vlab.Wasm

structure St where
  mem : Array UInt8
  quota : Nat
  stack : List Val
  locals : Array Val
  host : HostEnv

inductive Halt where
  | ok (st : St)
  | br (n : Nat) (st : St)
  | ret (st : St)
  | trap (t : Trap) (st : St)

def zeros (n : Nat) : Array Val :=
  Array.replicate n (.i32 0)

def u32le : List UInt8 → UInt32
  | [a, b, c, d] =>
    a.toUInt32 + b.toUInt32 <<< 8 + c.toUInt32 <<< 16 + d.toUInt32 <<< 24
  | _ => 0

def leU32 (n : UInt32) : List UInt8 :=
  [n.toUInt8, (n >>> 8).toUInt8, (n >>> 16).toUInt8, (n >>> 24).toUInt8]

def pop (st : St) : Option (Val × St) :=
  match st.stack with
  | v :: rest => some (v, { st with stack := rest })
  | [] => none

def popI32 (st : St) : Option (UInt32 × St) :=
  match pop st with
  | some (.i32 n, st) => some (n, st)
  | _ => none

def push (st : St) (v : Val) : St :=
  { st with stack := v :: st.stack }

def evalList (fuel : Nat) (mod : Module) (is : List Instr) (st : St) : Halt :=
  match fuel with
  | 0 => .trap .outOfFuel st
  | fuel + 1 =>
    match is with
    | [] => .ok st
    | .nop :: rest => evalList fuel mod rest st
    | .unreachable :: _ => .trap .unreachable st
    | .drop :: rest =>
      match pop st with
      | some (_, st) => evalList fuel mod rest st
      | none => .trap .stack st
    | .constI32 n :: rest => evalList fuel mod rest (push st (.i32 n))
    | .constI64 n :: rest => evalList fuel mod rest (push st (.i64 n))
    | .addI32 :: rest => binI32 fuel mod rest st (· + ·)
    | .subI32 :: rest => binI32 fuel mod rest st (· - ·)
    | .mulI32 :: rest => binI32 fuel mod rest st (· * ·)
    | .eqI32 :: rest =>
      binI32 fuel mod rest st fun a b => if a == b then 1 else 0
    | .eqzI32 :: rest =>
      match popI32 st with
      | some (a, st) =>
        evalList fuel mod rest (push st (.i32 (if a == 0 then 1 else 0)))
      | none => .trap .stack st
    | .addI64 :: rest =>
      match pop64 st with
      | some (b, a, st) => evalList fuel mod rest (push st (.i64 (a + b)))
      | none => .trap .stack st
    | .eqI64 :: rest =>
      match pop64 st with
      | some (b, a, st) =>
        evalList fuel mod rest (push st (.i32 (if a == b then 1 else 0)))
      | none => .trap .stack st
    | .localGet i :: rest =>
      match st.locals[i]? with
      | some v => evalList fuel mod rest (push st v)
      | none => .trap .typeError st
    | .localSet i :: rest =>
      match pop st with
      | some (v, st) =>
        if h : i < st.locals.size then
          evalList fuel mod rest { st with locals := st.locals.set i v h }
        else
          .trap .typeError st
      | none => .trap .stack st
    | .loadI32 :: rest =>
      match popI32 st with
      | some (addr, st) =>
        match load? st.mem addr.toNat 4 with
        | some bs => evalList fuel mod rest (push st (.i32 (u32le bs)))
        | none => .trap .bounds st
      | none => .trap .stack st
    | .load8U :: rest =>
      match popI32 st with
      | some (addr, st) =>
        match load? st.mem addr.toNat 1 with
        | some [b] => evalList fuel mod rest (push st (.i32 b.toUInt32))
        | _ => .trap .bounds st
      | none => .trap .stack st
    | .storeI32 :: rest =>
      match popI32 st with
      | some (v, st) =>
        match popI32 st with
        | some (addr, st) =>
          match store? st.mem addr.toNat (leU32 v) with
          | some mem => evalList fuel mod rest { st with mem }
          | none => .trap .bounds st
        | none => .trap .stack st
      | none => .trap .stack st
    | .store8 :: rest =>
      match popI32 st with
      | some (v, st) =>
        match popI32 st with
        | some (addr, st) =>
          match store? st.mem addr.toNat [v.toUInt8] with
          | some mem => evalList fuel mod rest { st with mem }
          | none => .trap .bounds st
        | none => .trap .stack st
      | none => .trap .stack st
    | .memSize :: rest =>
      let pages := st.mem.size / page
      evalList fuel mod rest (push st (.i32 (UInt32.ofNat pages)))
    | .memGrow :: rest =>
      match popI32 st with
      | some (delta, st) =>
        let extra := delta.toNat * page
        let old := st.mem.size / page
        match grow st.mem extra st.quota with
        | some mem => evalList fuel mod rest (push { st with mem } (.i32 (UInt32.ofNat old)))
        | none => evalList fuel mod rest (push st (.i32 0xFFFFFFFF))
      | none => .trap .stack st
    | .block body :: rest =>
      match evalList fuel mod body st with
      | .ok st => evalList fuel mod rest st
      | .br 0 st => evalList fuel mod rest st
      | .br (n + 1) st => .br n st
      | .ret st => .ret st
      | .trap t st => .trap t st
    | .loop_ body :: rest =>
      evalLoop fuel mod body rest st
    | .if_ th el :: rest =>
      match popI32 st with
      | some (c, st) =>
        let arm := if c == 0 then el else th
        match evalList fuel mod arm st with
        | .ok st => evalList fuel mod rest st
        | .br 0 st => evalList fuel mod rest st
        | .br (n + 1) st => .br n st
        | .ret st => .ret st
        | .trap t st => .trap t st
      | none => .trap .stack st
    | .br n :: _ => .br n st
    | .brIf n :: rest =>
      match popI32 st with
      | some (c, st) =>
        if c == 0 then evalList fuel mod rest st else .br n st
      | none => .trap .stack st
    | .ret :: _ => .ret st
    | .call f :: rest =>
      evalCall fuel mod f rest st
where
  pop64 (st : St) : Option (UInt64 × UInt64 × St) :=
    match pop st with
    | some (.i64 b, st) =>
      match pop st with
      | some (.i64 a, st) => some (b, a, st)
      | _ => none
    | _ => none
  binI32 (fuel : Nat) (mod : Module) (rest : List Instr) (st : St)
      (f : UInt32 → UInt32 → UInt32) : Halt :=
    match popI32 st with
    | some (b, st) =>
      match popI32 st with
      | some (a, st) => evalList fuel mod rest (push st (.i32 (f a b)))
      | none => .trap .stack st
    | none => .trap .stack st
  evalLoop (fuel : Nat) (mod : Module) (body rest : List Instr) (st : St) : Halt :=
    match fuel with
    | 0 => .trap .outOfFuel st
    | fuel + 1 =>
      match evalList fuel mod body st with
      | .ok st => evalList fuel mod rest st
      | .br 0 st => evalLoop fuel mod body rest st
      | .br (n + 1) st => .br n st
      | .ret st => .ret st
      | .trap t st => .trap t st
  take (n : Nat) (acc : List Val) (st : St) : Option (List Val × St) :=
    match n with
    | 0 => some (acc, st)
    | n + 1 =>
      match pop st with
      | some (v, st) => take n (v :: acc) st
      | none => none
  evalCall (fuel : Nat) (mod : Module) (f : Nat) (rest : List Instr) (st : St) : Halt :=
    if h : f < mod.imports.size then
      let imp := mod.imports[f]
      match take imp.params [] st with
      | none => .trap .stack st
      | some (args, st) =>
        match imp.op with
        | none => .trap .badModule st
        | some op =>
          match perform st.host op args st.mem with
          | .allow env mem v =>
            evalList fuel mod rest (push { st with host := env, mem } v)
          | .deny env =>
            evalList fuel mod rest (push { st with host := env } (.i32 0xFFFFFFFF))
          | .trap t env => .trap t { st with host := env }
    else
      let idx := f - mod.imports.size
      if h : idx < mod.funcs.size then
        let fn := mod.funcs[idx]
        match take fn.params [] st with
        | none => .trap .stack st
        | some (args, st) =>
          let locals := args.toArray ++ zeros fn.locals
          let inner : St := { st with stack := [], locals }
          match evalList fuel mod fn.body inner with
          | .ok st' | .ret st' =>
            if fn.results = 0 then
              evalList fuel mod rest { st with mem := st'.mem, host := st'.host }
            else
              match st'.stack with
              | v :: _ =>
                evalList fuel mod rest (push { st with mem := st'.mem, host := st'.host } v)
              | [] => .trap .stack st
          | .br _ st' => .trap .typeError { st with mem := st'.mem, host := st'.host }
          | .trap t st' => .trap t { st with mem := st'.mem, host := st'.host }
      else
        .trap .badModule st

theorem evalList_zero (mod : Module) (is : List Instr) (st : St) :
    evalList 0 mod is st = .trap .outOfFuel st := by
  simp [evalList]

def runModule (fuel : Nat) (mod : Module) (env : HostEnv) (quota : Nat) : Halt :=
  let bytes := mod.memPages * page
  let base : St := {
    mem := Array.replicate bytes 0
    quota
    stack := []
    locals := #[]
    host := env
  }
  if bytes ≤ quota then
    evalList fuel mod [.call mod.main] base
  else
    .trap .memQuota base

end Vlab.Wasm
