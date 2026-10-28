/-
Linear memory. A successful read or write stays inside the array.
`grow` does not pass the quota when the memory already fit in it.
-/

namespace Vlab.Wasm.Mem

def load? (mem : Array UInt8) (addr len : Nat) : Option (List UInt8) :=
  if h : addr + len ≤ mem.size then
    some <| (List.finRange len).map fun i =>
      mem[addr + i.val]'(by
        have hi : i.val < len := i.isLt
        omega)
  else
    none

theorem load?_inRange {mem : Array UInt8} {addr len : Nat} {bs : List UInt8}
    (h : load? mem addr len = some bs) : addr + len ≤ mem.size := by
  unfold load? at h
  split at h
  · assumption
  · simp at h

def poke (mem : Array UInt8) (addr : Nat) (bs : List UInt8) : Array UInt8 :=
  match bs with
  | [] => mem
  | b :: rest =>
    let mem := if h : addr < mem.size then mem.set addr b h else mem
    poke mem (addr + 1) rest

theorem poke_size (mem : Array UInt8) (addr : Nat) (bs : List UInt8) :
    (poke mem addr bs).size = mem.size := by
  induction bs generalizing mem addr with
  | nil => simp [poke]
  | cons b rest ih =>
    unfold poke
    split
    · rw [ih (mem.set addr b ‹_›) (addr + 1)]
      simp
    · simpa using ih mem (addr + 1)

def store? (mem : Array UInt8) (addr : Nat) (bs : List UInt8) : Option (Array UInt8) :=
  if addr + bs.length ≤ mem.size then
    some (poke mem addr bs)
  else
    none

theorem store?_size {mem m : Array UInt8} {addr : Nat} {bs : List UInt8}
    (h : store? mem addr bs = some m) : m.size = mem.size := by
  unfold store? at h
  split at h
  · simp at h
    simpa [h] using poke_size mem addr bs
  · simp at h

def grow (mem : Array UInt8) (extra quota : Nat) : Option (Array UInt8) :=
  if mem.size + extra ≤ quota then
    some (mem ++ Array.replicate extra 0)
  else
    none

theorem grow_le {mem m : Array UInt8} {extra quota : Nat}
    (h : grow mem extra quota = some m) : m.size ≤ quota := by
  unfold grow at h
  split at h
  · simp at h
    subst h
    have : (mem ++ Array.replicate extra 0).size = mem.size + extra := by
      simp [Array.size_append, Array.size_replicate]
    omega
  · simp at h

def page : Nat := 65536

end Vlab.Wasm.Mem
