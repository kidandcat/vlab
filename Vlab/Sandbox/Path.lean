/-
Virtual paths. `normalize` drops `.` and rejects a `..` that would leave the root.
The result is a list of segments. The host turns that list into a relative
file path. It does not interpret the guest string again.
-/

namespace Vlab.Sandbox.Path

def go (fuel : Nat) (acc segs : List String) : Option (List String) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    match segs with
    | [] => some acc.reverse
    | "." :: rest => go fuel acc rest
    | ".." :: rest =>
      match acc with
      | [] => none
      | _ :: acc => go fuel acc rest
    | s :: rest =>
      if s = "" then none else go fuel (s :: acc) rest

def segments (path : String) : List String :=
  path.splitOn "/" |>.filter (· ≠ "")

def normalize (path : String) : Option (List String) :=
  let segs := segments path
  go (segs.length + 1) [] segs

def under (pre path : List String) : Bool :=
  pre.isPrefixOf path

def safeSeg (s : String) : Prop :=
  s ≠ ".." ∧ s ≠ "." ∧ s ≠ ""

private theorem safe_of_cons {s : String} {acc : List String}
    (hs : safeSeg s) (hacc : ∀ t, t ∈ acc → safeSeg t) :
    ∀ t, t ∈ s :: acc → safeSeg t := by
  intro t ht
  cases ht with
  | head => exact hs
  | tail _ hmem => exact hacc t hmem

private theorem safe_of_tail {a : String} {acc : List String}
    (hacc : ∀ t, t ∈ a :: acc → safeSeg t) :
    ∀ t, t ∈ acc → safeSeg t := by
  intro t ht
  exact hacc t (List.Mem.tail _ ht)

theorem go_safe (fuel : Nat) (acc segs out : List String)
    (hacc : ∀ s, s ∈ acc → safeSeg s)
    (h : go fuel acc segs = some out) :
    ∀ s, s ∈ out → safeSeg s := by
  induction fuel generalizing acc segs out with
  | zero =>
    simp [go] at h
  | succ fuel ih =>
    cases segs with
    | nil =>
      simp [go] at h
      subst h
      intro s hs
      exact hacc s (List.mem_reverse.mp hs)
    | cons hd tl =>
      by_cases hdot : hd = "."
      · simp [go, hdot] at h
        exact ih acc tl out hacc h
      · by_cases hup : hd = ".."
        · cases acc with
          | nil =>
            simp [go, hdot, hup] at h
          | cons a acc' =>
            simp [go, hdot, hup] at h
            exact ih acc' tl out (safe_of_tail hacc) h
        · by_cases hem : hd = ""
          · simp [go, hem] at h
          · simp [go, hem] at h
            exact ih (hd :: acc) tl out (safe_of_cons ⟨hup, hdot, hem⟩ hacc) h

theorem normalize_safe (path : String) (out : List String)
    (h : normalize path = some out) :
    ∀ s, s ∈ out → safeSeg s := by
  unfold normalize segments at h
  exact go_safe (segments path).length.succ [] (segments path) out (by intro s hs; cases hs) h

end Vlab.Sandbox.Path
