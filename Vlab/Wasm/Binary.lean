/-
Decoder for the binary subset the fixtures and `wasmtime` use.
It is tested against those bytes. It is not part of the safety theorems.
-/

import Vlab.Wasm.Ast

namespace Vlab.Wasm.Binary

structure R where
  data : ByteArray
  i : Nat

def done (r : R) : Bool :=
  r.i ≥ r.data.size

def byte (r : R) : Option (UInt8 × R) :=
  if h : r.i < r.data.size then
    some (r.data[r.i], { r with i := r.i + 1 })
  else
    none

def uleb (fuel : Nat) (r : R) : Option (Nat × R) :=
  let rec go (fuel shift acc : Nat) (r : R) : Option (Nat × R) :=
    match fuel with
    | 0 => none
    | fuel + 1 => do
      let (b, r) ← byte r
      let acc := acc + (b.toNat &&& 0x7f) <<< shift
      if b.toNat &&& 0x80 == 0 then
        some (acc, r)
      else
        go fuel (shift + 7) acc r
  go fuel 0 0 r

def sleb32 (fuel : Nat) (r : R) : Option (UInt32 × R) :=
  let rec go (fuel shift acc : Nat) (r : R) : Option (UInt32 × R) :=
    match fuel with
    | 0 => none
    | fuel + 1 => do
      let (b, r) ← byte r
      let acc := acc + (b.toNat &&& 0x7f) <<< shift
      let shift := shift + 7
      if b.toNat &&& 0x80 == 0 then
        let signed :=
          if shift < 32 && b.toNat &&& 0x40 != 0 then
            acc + ((0xFFFFFFFF : Nat) <<< shift)
          else
            acc
        some (UInt32.ofNat signed, r)
      else
        go fuel shift acc r
  go fuel 0 0 r

def take (n : Nat) (r : R) : Option (ByteArray × R) :=
  if r.i + n ≤ r.data.size then
    some (r.data.extract r.i (r.i + n), { r with i := r.i + n })
  else
    none

def str (r : R) : Option (String × R) := do
  let (n, r) ← uleb 5 r
  let (bs, r) ← take n r
  let some s := String.fromUTF8? bs | none
  some (s, r)

def hostOp (name : String) : Option HostOp :=
  match name with
  | "fs_read" => some .fsRead
  | "fs_write" => some .fsWrite
  | "net_send" => some .netSend
  | "clock_ms" => some .clock
  | "random" => some .random
  | _ => none

mutual
  partial def parseBlock (r : R) : Option (List Instr × R) := do
    let (is, r, k) ← parseSeq r 4096
    if k == 0x0b then some (is, r) else none

  partial def parseIf (r : R) : Option (List Instr × List Instr × R) := do
    let (th, r, k) ← parseSeq r 4096
    if k == 0x05 then
      let (el, r, k2) ← parseSeq r 4096
      if k2 == 0x0b then some (th, el, r) else none
    else if k == 0x0b then
      some (th, [], r)
    else
      none

  partial def parseSeq (r : R) (fuel : Nat) : Option (List Instr × R × UInt8) :=
    match fuel with
    | 0 => none
    | _ => do
      let (op, r) ← byte r
      match op.toNat with
      | 0x0b => some ([], r, 0x0b)
      | 0x05 => some ([], r, 0x05)
      | 0x00 =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.unreachable :: rest, r, k)
      | 0x01 =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.nop :: rest, r, k)
      | 0x02 =>
        let (bt, r) ← byte r
        if bt != 0x40 then none
        else
          let (body, r) ← parseBlock r
          let (rest, r, k) ← parseSeq r (fuel - 1)
          some (.block body :: rest, r, k)
      | 0x03 =>
        let (bt, r) ← byte r
        if bt != 0x40 then none
        else
          let (body, r) ← parseBlock r
          let (rest, r, k) ← parseSeq r (fuel - 1)
          some (.loop_ body :: rest, r, k)
      | 0x04 =>
        let (bt, r) ← byte r
        if bt != 0x40 then none
        else
          let (th, el, r) ← parseIf r
          let (rest, r, k) ← parseSeq r (fuel - 1)
          some (.if_ th el :: rest, r, k)
      | 0x0c =>
        let (n, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.br n :: rest, r, k)
      | 0x0d =>
        let (n, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.brIf n :: rest, r, k)
      | 0x0f =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.ret :: rest, r, k)
      | 0x10 =>
        let (n, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.call n :: rest, r, k)
      | 0x1a =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.drop :: rest, r, k)
      | 0x20 =>
        let (n, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.localGet n :: rest, r, k)
      | 0x21 =>
        let (n, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.localSet n :: rest, r, k)
      | 0x28 =>
        let (_, r) ← uleb 5 r
        let (_, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.loadI32 :: rest, r, k)
      | 0x2d =>
        let (_, r) ← uleb 5 r
        let (_, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.load8U :: rest, r, k)
      | 0x36 =>
        let (_, r) ← uleb 5 r
        let (_, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.storeI32 :: rest, r, k)
      | 0x3a =>
        let (_, r) ← uleb 5 r
        let (_, r) ← uleb 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.store8 :: rest, r, k)
      | 0x3f =>
        let (z, r) ← byte r
        if z != 0 then none
        else
          let (rest, r, k) ← parseSeq r (fuel - 1)
          some (.memSize :: rest, r, k)
      | 0x40 =>
        let (z, r) ← byte r
        if z != 0 then none
        else
          let (rest, r, k) ← parseSeq r (fuel - 1)
          some (.memGrow :: rest, r, k)
      | 0x41 =>
        let (n, r) ← sleb32 5 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.constI32 n :: rest, r, k)
      | 0x42 =>
        let (n, r) ← sleb32 10 r
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.constI64 n.toUInt64 :: rest, r, k)
      | 0x45 =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.eqzI32 :: rest, r, k)
      | 0x46 =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.eqI32 :: rest, r, k)
      | 0x51 =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.eqI64 :: rest, r, k)
      | 0x6a =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.addI32 :: rest, r, k)
      | 0x6b =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.subI32 :: rest, r, k)
      | 0x6c =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.mulI32 :: rest, r, k)
      | 0x7c =>
        let (rest, r, k) ← parseSeq r (fuel - 1)
        some (.addI64 :: rest, r, k)
      | _ => none
end

def skip (n : Nat) (r : R) : Option R :=
  if r.i + n ≤ r.data.size then some { r with i := r.i + n } else none

structure Draft where
  imports : Array Import := #[]
  typeParams : Array Nat := #[]
  funcTypes : Array Nat := #[]
  codes : Array (List Instr) := #[]
  memPages : Nat := 0
  main : Option Nat := none

def parseType (r : R) : Option (Nat × R) := do
  let (tag, r) ← byte r
  if tag != 0x60 then none
  else
    let (n, r0) ← uleb 5 r
    let mut r := r0
    for _ in [0:n] do
      let (t, r') ← byte r
      if t != 0x7f && t != 0x7e then failure
      r := r'
    let (m, r2) ← uleb 5 r
    r := r2
    for _ in [0:m] do
      let (t, r') ← byte r
      if t != 0x7f && t != 0x7e then failure
      r := r'
    some (n, r)

def parseBody (r : R) : Option (List Instr × R) := do
  let (n, r) ← uleb 5 r
  let (raw, r) ← take n r
  let inner : R := { data := raw, i := 0 }
  let (groups, inner0) ← uleb 5 inner
  let mut inner := inner0
  for _ in [0:groups] do
    let (_, inner') ← uleb 5 inner
    let (_, inner') ← byte inner'
    inner := inner'
  let (is, inner2, k) ← parseSeq inner 4096
  if k != 0x0b || !done inner2 then none else some (is, r)

partial def parseSection (d : Draft) (r : R) : Option (Draft × R) := do
  let (id, r) ← byte r
  let (n, r) ← uleb 5 r
  let (raw, r) ← take n r
  let s : R := { data := raw, i := 0 }
  match id.toNat with
  | 1 =>
    let (count, s) ← uleb 5 s
    let mut s := s
    let mut types : Array Nat := #[]
    for _ in [0:count] do
      let (params, s') ← parseType s
      types := types.push params
      s := s'
    if !done s then none else some ({ d with typeParams := types }, r)
  | 2 =>
    let (count, s) ← uleb 5 s
    let mut s := s
    let mut imps : Array Import := #[]
    for _ in [0:count] do
      let (mod, s1) ← str s
      let (name, s2) ← str s1
      let (kind, s3) ← byte s2
      if kind != 0 then failure
      let (ty, s4) ← uleb 5 s3
      let some params := d.typeParams[ty]? | failure
      imps := imps.push { module := mod, name, op := hostOp name, params }
      s := s4
    if !done s then none else some ({ d with imports := imps }, r)
  | 3 =>
    let (count, s) ← uleb 5 s
    let mut s := s
    let mut ids : Array Nat := #[]
    for _ in [0:count] do
      let (ty, s') ← uleb 5 s
      ids := ids.push ty
      s := s'
    if !done s then none else some ({ d with funcTypes := ids }, r)
  | 5 =>
    let (count, s) ← uleb 5 s
    if count != 1 then none
    else
      let (flags, s) ← byte s
      if flags != 0 then none
      else
        let (pages, s) ← uleb 5 s
        if !done s then none else some ({ d with memPages := pages }, r)
  | 7 =>
    let (count, s) ← uleb 5 s
    let mut s := s
    let mut main := d.main
    for _ in [0:count] do
      let (name, s') ← str s
      let (kind, s') ← byte s'
      let (idx, s') ← uleb 5 s'
      if name == "main" && kind == 0 then main := some idx
      s := s'
    if !done s then none else some ({ d with main }, r)
  | 10 =>
    let (count, s) ← uleb 5 s
    let mut s := s
    let mut codes : Array (List Instr) := #[]
    for _ in [0:count] do
      let (body, s') ← parseBody s
      codes := codes.push body
      s := s'
    if !done s then none else some ({ d with codes }, r)
  | _ =>
    some (d, r)

def decode (bytes : ByteArray) : Option Module := do
  let r : R := { data := bytes, i := 0 }
  let (b0, r) ← byte r
  let (b1, r) ← byte r
  let (b2, r) ← byte r
  let (b3, r) ← byte r
  if b0 != 0 || b1 != 0x61 || b2 != 0x73 || b3 != 0x6d then none
  else
    let (_, r) ← byte r
    let (_, r) ← byte r
    let (_, r) ← byte r
    let (_, r) ← byte r
    let mut d : Draft := {}
    let mut r := r
    let mut guard := 0
    while !done r && guard < 32 do
      let (d', r') ← parseSection d r
      d := d'
      r := r'
      guard := guard + 1
    if !done r then none
    else
      let some main := d.main | none
      if d.codes.size != d.funcTypes.size then none
      else
        let mut funcs : Array Func := #[]
        for i in [0:d.codes.size] do
          let some ty := d.funcTypes[i]? | failure
          let some params := d.typeParams[ty]? | failure
          let some body := d.codes[i]? | failure
          funcs := funcs.push { params, locals := 0, results := 1, body }
        some { imports := d.imports, funcs, memPages := d.memPages, main }

def ofHex (s : String) : Option ByteArray := do
  let rec nib : Char → Option Nat
    | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3 | '4' => some 4
    | '5' => some 5 | '6' => some 6 | '7' => some 7 | '8' => some 8 | '9' => some 9
    | 'a' => some 10 | 'b' => some 11 | 'c' => some 12 | 'd' => some 13 | 'e' => some 14 | 'f' => some 15
    | 'A' => some 10 | 'B' => some 11 | 'C' => some 12 | 'D' => some 13 | 'E' => some 14 | 'F' => some 15
    | _ => none
  let rec go (cs : List Char) (acc : ByteArray) : Option ByteArray :=
    match cs with
    | [] => some acc
    | a :: b :: rest => do
      let x ← nib a
      let y ← nib b
      go rest (acc.push (UInt8.ofNat (x * 16 + y)))
    | _ => none
  go s.toList .empty

end Vlab.Wasm.Binary
