/-
The Wasm subset the interpreter runs: i32/i64, structured control,
one linear memory, direct calls. No floats, SIMD, or indirect calls.
-/

namespace Vlab.Wasm

inductive Ty where
  | i32
  | i64
  deriving Repr, BEq, DecidableEq

inductive Val where
  | i32 (n : UInt32)
  | i64 (n : UInt64)
  deriving Repr, BEq

inductive Trap where
  | outOfFuel
  | bounds
  | stack
  | typeError
  | denied
  | hostQuota
  | memQuota
  | unreachable
  | escape
  | badModule
  deriving Repr, BEq

inductive Instr where
  | nop
  | unreachable
  | drop
  | constI32 (n : UInt32)
  | constI64 (n : UInt64)
  | addI32
  | subI32
  | mulI32
  | eqI32
  | eqzI32
  | addI64
  | eqI64
  | localGet (i : Nat)
  | localSet (i : Nat)
  | loadI32
  | storeI32
  | load8U
  | store8
  | memSize
  | memGrow
  | block (body : List Instr)
  | loop_ (body : List Instr)
  | if_ (th el : List Instr)
  | br (n : Nat)
  | brIf (n : Nat)
  | call (f : Nat)
  | ret
  deriving Repr, BEq

inductive HostOp where
  | fsRead
  | fsWrite
  | netSend
  | clock
  | random
  deriving Repr, BEq, DecidableEq

structure Import where
  module : String
  name : String
  op : Option HostOp
  params : Nat
  deriving Repr

structure Func where
  params : Nat
  locals : Nat
  results : Nat
  body : List Instr
  deriving Repr

structure Module where
  imports : Array Import
  funcs : Array Func
  memPages : Nat
  main : Nat
  deriving Repr

def tyOf : Val → Ty
  | .i32 _ => .i32
  | .i64 _ => .i64

end Vlab.Wasm
