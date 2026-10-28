/-
Host calls. Effects stay in this function. A denial does not change the
virtual filesystem or the scripted network table. An admission has the
capability in the grant list: the branch that builds `.allow` checks it.
-/

import Vlab.Sandbox.Cited
import Vlab.Sandbox.Path
import Vlab.Wasm.Ast
import Vlab.Wasm.Mem

open Vlab.Sandbox.Cited
open Vlab.Wasm
open Vlab.Wasm.Mem

namespace Vlab.Sandbox.Host

inductive Cap where
  | fsRead (pre : List String)
  | fsWrite (pre : List String)
  | net (host : String) (port : Nat) (body : Array UInt8)
  | clock
  | random
  deriving Repr, BEq

structure HostEnv where
  grants : List Cap
  vfs : List (List String × Array UInt8)
  clock : UInt64
  entropy : Array UInt8
  entropyAt : Nat
  calls : Nat
  callQuota : Nat
  vfsQuota : Nat
  audit : List String
  deriving Repr

inductive HostOut where
  | allow (env : HostEnv) (mem : Array UInt8) (v : Val)
  | deny (env : HostEnv)
  | trap (t : Trap) (env : HostEnv)
  deriving Repr

def vfsBytes : List (List String × Array UInt8) → Nat
  | [] => 0
  | (_, v) :: rest => v.size + vfsBytes rest

def readVfs (vfs : List (List String × Array UInt8)) (path : List String) :
    Option (Array UInt8) :=
  match vfs with
  | [] => none
  | (p, v) :: rest => if p == path then some v else readVfs rest path

def writeVfs (vfs : List (List String × Array UInt8)) (path : List String)
    (data : Array UInt8) : List (List String × Array UInt8) :=
  match vfs with
  | [] => [(path, data)]
  | (p, v) :: rest =>
    if p == path then (path, data) :: rest else (p, v) :: writeVfs rest path data

def fsReadOk : List Cap → List String → Bool
  | [], _ => false
  | .fsRead p :: rest, path => Path.under p path || fsReadOk rest path
  | _ :: rest, path => fsReadOk rest path

def fsWriteOk : List Cap → List String → Bool
  | [], _ => false
  | .fsWrite p :: rest, path => Path.under p path || fsWriteOk rest path
  | _ :: rest, path => fsWriteOk rest path

def netOk : List Cap → String → Nat → Bool
  | [], _, _ => false
  | .net h p _ :: rest, host, port => (h == host && p == port) || netOk rest host port
  | _ :: rest, host, port => netOk rest host port

def clockOk : List Cap → Bool
  | [] => false
  | .clock :: _ => true
  | _ :: rest => clockOk rest

def randomOk : List Cap → Bool
  | [] => false
  | .random :: _ => true
  | _ :: rest => randomOk rest

def netBody (grants : List Cap) (host : String) (port : Nat) : Array UInt8 :=
  match grants.findSome? fun
    | .net h p b => if h == host && p == port then some b else none
    | _ => none with
  | some b => b
  | none => #[]

private def u32? : Val → Option Nat
  | .i32 n => some n.toNat
  | _ => none

private def takeU32 : List Val → Option (Nat × List Val)
  | .i32 n :: rest => some (n.toNat, rest)
  | _ => none

private def four (args : List Val) : Option (Nat × Nat × Nat × Nat) := do
  let (a, r) ← takeU32 args
  let (b, r) ← takeU32 r
  let (c, r) ← takeU32 r
  let (d, r) ← takeU32 r
  if r.isEmpty then some (a, b, c, d) else none

private def pathOf (mem : Array UInt8) (addr len : Nat) : Except Trap (List String) := do
  let some bs := load? mem addr len | throw .bounds
  let some s := String.fromUTF8? (ByteArray.mk bs.toArray) | throw .typeError
  match Path.normalize s with
  | some segs => pure segs
  | none => throw .escape

private def note (env : HostEnv) (line : String) : HostEnv :=
  { env with audit := line :: env.audit }

private def deny (env : HostEnv) (line : String) : HostOut :=
  .deny (note env line)

def perform (env : HostEnv) (op : HostOp) (args : List Val) (mem : Array UInt8) : HostOut :=
  if env.calls ≥ env.callQuota then
    .trap .hostQuota env
  else
    let env := { env with calls := env.calls + 1 }
    match op with
    | .clock =>
      if clockOk env.grants then
        .allow (note env (withTheorem "allow clock" .clockOk_grant)) mem (.i64 env.clock)
      else
        deny env (withTheorem "deny clock" .clockOk_grant)
    | .random =>
      match four args with
      | none => .trap .typeError env
      | some (_, _, buf, len) =>
        if randomOk env.grants then
          let n := min len 256
          let avail := env.entropy.size - env.entropyAt
          let n := min n avail
          match load? mem buf 0 with
          | none => .trap .bounds env
          | some _ =>
            let bs := (List.range n).map fun i =>
              env.entropy[env.entropyAt + i]?.getD 0
            match store? mem buf bs with
            | none => .trap .bounds env
            | some mem =>
              let env := { env with entropyAt := env.entropyAt + n }
              .allow (note env (withTheorem "allow random" .randomOk_grant)) mem
                (.i32 (UInt32.ofNat n))
        else
          deny env (withTheorem "deny random" .randomOk_grant)
    | .fsRead =>
      match four args with
      | none => .trap .typeError env
      | some (paddr, plen, buf, blen) =>
        match pathOf mem paddr plen with
        | .error .bounds => .trap .bounds env
        | .error .escape => .trap .escape (note env (withTheorem "escape fs_read" .normalize_safe))
        | .error t => .trap t env
        | .ok segs =>
          if fsReadOk env.grants segs then
            let data := (readVfs env.vfs segs).getD #[]
            let n := min blen data.size
            let bs := (List.range n).map fun i => data[i]?.getD 0
            match store? mem buf bs with
            | none => .trap .bounds env
            | some mem =>
              .allow (note env (withTheorem "allow fs_read" .fsReadOk_grant)) mem
                (.i32 (UInt32.ofNat n))
          else
            deny env (withTheorem "deny fs_read" .fsReadOk_grant)
    | .fsWrite =>
      match four args with
      | none => .trap .typeError env
      | some (paddr, plen, buf, blen) =>
        match pathOf mem paddr plen with
        | .error .bounds => .trap .bounds env
        | .error .escape => .trap .escape (note env (withTheorem "escape fs_write" .normalize_safe))
        | .error t => .trap t env
        | .ok segs =>
          if fsWriteOk env.grants segs then
            match load? mem buf blen with
            | none => .trap .bounds env
            | some bs =>
              let data := Array.mk bs
              let old := vfsBytes env.vfs
              let prev := (readVfs env.vfs segs).map (·.size) |>.getD 0
              let next := old - prev + data.size
              if next ≤ env.vfsQuota then
                let env := { env with vfs := writeVfs env.vfs segs data }
                .allow (note env (withTheorem "allow fs_write" .fsWriteOk_grant)) mem
                  (.i32 (UInt32.ofNat data.size))
              else
                deny env "deny fs_write quota"
          else
            deny env (withTheorem "deny fs_write" .fsWriteOk_grant)
    | .netSend =>
      match four args with
      | none => .trap .typeError env
      | some (haddr, hlen, port, buf) =>
        -- args are hostPtr, hostLen, port, bufPtr. The fifth (len) is not in `four`.
        -- net uses host, port and ignores the payload length beyond the pointer.
        match pathOf mem haddr hlen with
        | .error .bounds => .trap .bounds env
        | .error .escape => .trap .escape (note env (withTheorem "escape net" .normalize_safe))
        | .error t => .trap t env
        | .ok segs =>
          let host := String.intercalate "." segs
          if netOk env.grants host port then
            let body := netBody env.grants host port
            let n := min body.size 256
            let bs := (List.range n).map fun i => body[i]?.getD 0
            match store? mem buf bs with
            | none => .trap .bounds env
            | some mem =>
              .allow (note env (withTheorem s!"allow net {host}:{port}" .netOk_grant)) mem
                (.i32 (UInt32.ofNat n))
          else
            deny env (withTheorem s!"deny net {host}:{port}" .netOk_grant)

theorem note_keeps (env : HostEnv) (line : String) :
    (note env line).vfs = env.vfs ∧ (note env line).entropyAt = env.entropyAt ∧
      (note env line).grants = env.grants := by
  simp [note]

theorem deny_keeps (env : HostEnv) (line : String) :
    match deny env line with
    | .deny env' => env'.vfs = env.vfs ∧ env'.entropyAt = env.entropyAt ∧ env'.grants = env.grants
    | _ => False := by
  simp [deny, note]

private theorem bool_not_true {b : Bool} (h : ¬ b = true) : b = false := by
  cases b <;> simp_all

theorem fsReadOk_grant (grants : List Cap) (path : List String)
    (h : fsReadOk grants path = true) :
    ∃ p, .fsRead p ∈ grants ∧ Path.under p path = true := by
  induction grants with
  | nil => simp [fsReadOk] at h
  | cons c rest ih =>
    cases c with
    | fsRead p =>
      by_cases hu : Path.under p path = true
      · exact ⟨p, List.Mem.head _, hu⟩
      · have hf : Path.under p path = false := bool_not_true hu
        simp [fsReadOk, hf] at h
        rcases ih h with ⟨p', hm, hu'⟩
        exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | fsWrite p =>
      simp [fsReadOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | net host port body =>
      simp [fsReadOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | clock =>
      simp [fsReadOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | random =>
      simp [fsReadOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩

theorem fsWriteOk_grant (grants : List Cap) (path : List String)
    (h : fsWriteOk grants path = true) :
    ∃ p, .fsWrite p ∈ grants ∧ Path.under p path = true := by
  induction grants with
  | nil => simp [fsWriteOk] at h
  | cons c rest ih =>
    cases c with
    | fsWrite p =>
      by_cases hu : Path.under p path = true
      · exact ⟨p, List.Mem.head _, hu⟩
      · have hf : Path.under p path = false := bool_not_true hu
        simp [fsWriteOk, hf] at h
        rcases ih h with ⟨p', hm, hu'⟩
        exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | fsRead p =>
      simp [fsWriteOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | net host port body =>
      simp [fsWriteOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | clock =>
      simp [fsWriteOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩
    | random =>
      simp [fsWriteOk] at h
      rcases ih h with ⟨p', hm, hu'⟩
      exact ⟨p', List.Mem.tail _ hm, hu'⟩

theorem clockOk_grant (grants : List Cap) (h : clockOk grants = true) : .clock ∈ grants := by
  induction grants with
  | nil => simp [clockOk] at h
  | cons c rest ih =>
    cases c with
    | clock => exact List.Mem.head _
    | fsRead p =>
      simp [clockOk] at h
      exact List.Mem.tail _ (ih h)
    | fsWrite p =>
      simp [clockOk] at h
      exact List.Mem.tail _ (ih h)
    | net host port body =>
      simp [clockOk] at h
      exact List.Mem.tail _ (ih h)
    | random =>
      simp [clockOk] at h
      exact List.Mem.tail _ (ih h)

theorem randomOk_grant (grants : List Cap) (h : randomOk grants = true) : .random ∈ grants := by
  induction grants with
  | nil => simp [randomOk] at h
  | cons c rest ih =>
    cases c with
    | random => exact List.Mem.head _
    | clock =>
      simp [randomOk] at h
      exact List.Mem.tail _ (ih h)
    | fsRead p =>
      simp [randomOk] at h
      exact List.Mem.tail _ (ih h)
    | fsWrite p =>
      simp [randomOk] at h
      exact List.Mem.tail _ (ih h)
    | net host port body =>
      simp [randomOk] at h
      exact List.Mem.tail _ (ih h)

theorem netOk_grant (grants : List Cap) (host : String) (port : Nat)
    (h : netOk grants host port = true) :
    ∃ body, .net host port body ∈ grants := by
  induction grants with
  | nil => simp [netOk] at h
  | cons c rest ih =>
    cases c with
    | net hst p body =>
      by_cases hh : hst == host
      · by_cases hp : p == port
        · have hh' : hst = host := by simpa using hh
          have hp' : p = port := by simpa using hp
          subst hh'
          subst hp'
          exact ⟨body, List.Mem.head _⟩
        · have hp' : (p == port) = false := bool_not_true hp
          simp [netOk, hh, hp'] at h
          rcases ih h with ⟨b, hm⟩
          exact ⟨b, List.Mem.tail _ hm⟩
      · have hh' : (hst == host) = false := bool_not_true hh
        simp [netOk, hh'] at h
        rcases ih h with ⟨b, hm⟩
        exact ⟨b, List.Mem.tail _ hm⟩
    | fsRead p =>
      simp [netOk] at h
      rcases ih h with ⟨b, hm⟩
      exact ⟨b, List.Mem.tail _ hm⟩
    | fsWrite p =>
      simp [netOk] at h
      rcases ih h with ⟨b, hm⟩
      exact ⟨b, List.Mem.tail _ hm⟩
    | clock =>
      simp [netOk] at h
      rcases ih h with ⟨b, hm⟩
      exact ⟨b, List.Mem.tail _ hm⟩
    | random =>
      simp [netOk] at h
      rcases ih h with ⟨b, hm⟩
      exact ⟨b, List.Mem.tail _ hm⟩

end Vlab.Sandbox.Host
