/-
Theorem names an audit line is allowed to cite. `tag_known` says every
constructor prints one of `knownTags`. The test file `#check`s each of
those declarations, so a renamed or missing theorem fails elaboration.
-/

namespace Vlab.Sandbox.Cited

inductive Cited where
  | fsReadOk_grant
  | fsWriteOk_grant
  | netOk_grant
  | clockOk_grant
  | randomOk_grant
  | normalize_safe
  | load_inRange
  | store_size
  | grow_le
  | deny_keeps
  | note_keeps
  | evalList_zero
  deriving DecidableEq, Repr

def tag : Cited → String
  | .fsReadOk_grant => "fsReadOk_grant"
  | .fsWriteOk_grant => "fsWriteOk_grant"
  | .netOk_grant => "netOk_grant"
  | .clockOk_grant => "clockOk_grant"
  | .randomOk_grant => "randomOk_grant"
  | .normalize_safe => "normalize_safe"
  | .load_inRange => "load?_inRange"
  | .store_size => "store?_size"
  | .grow_le => "grow_le"
  | .deny_keeps => "deny_keeps"
  | .note_keeps => "note_keeps"
  | .evalList_zero => "evalList_zero"

def knownTags : List String := [
  "fsReadOk_grant",
  "fsWriteOk_grant",
  "netOk_grant",
  "clockOk_grant",
  "randomOk_grant",
  "normalize_safe",
  "load?_inRange",
  "store?_size",
  "grow_le",
  "deny_keeps",
  "note_keeps",
  "evalList_zero"
]

theorem tag_known (c : Cited) : tag c ∈ knownTags := by
  cases c <;> decide

def withTheorem (msg : String) (c : Cited) : String :=
  msg ++ " theorem=" ++ tag c

def citedName (line : String) : Option String :=
  match line.splitOn "theorem=" with
  | [_, name] => some name
  | _ => none

def namesKnown (lines : List String) : Bool :=
  lines.all fun line =>
    match citedName line with
    | none => true
    | some name => name ∈ knownTags

end Vlab.Sandbox.Cited
