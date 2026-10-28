/-
One process, one cairn `ShardSet` on disk.

A single shard (`Epoch.single`). Cross-shard batches are rejected by cairn,
and a note is one key, so it never needs a cross-shard transaction.
Notes are the collection `notes` (versioned compare-and-set, time-ordered ids).
The boot counter is a plain string key. Both go through the same file.

The id generator is seeded from the greatest id already in the collection,
so a restart does not mint an id that sorts before one already stored.
-/

import Cairn
import Std.Time

open Cairn

namespace Vlab.Store

def notesName : String := "notes"

def bootKey : String := "meta:boots"

/-- Ten bytes is 80 bits, the width of a `Ulid` random part, so the value fits. -/
private def random80 : IO Nat := do
  let bytes ← IO.getRandomBytes 10
  let mut n : Nat := 0
  for i in [:bytes.size] do
    n := n * 256 + (bytes[i]!).toNat
  return n

def nowMillis : IO Nat := do
  let ts ← Std.Time.Timestamp.now
  let ms := ts.toMillisecondsSinceUnixEpoch.val
  if ms < 0 then
    return 0
  else
    return ms.toNat

def wallClock : Clock where
  millis := nowMillis
  entropy := random80

structure Store where
  shards : ShardSet
  ids : IdGen
  boots : Nat

/-- Page until the collection ends. The last id seen is the greatest: list order is byte order. -/
private def greatestId (s : ShardSet) : IO (Option Ulid) := do
  let mut after : Option Ulid := none
  let mut last : Option Ulid := none
  for _ in [0:100000] do
    let (rows, next) ← collList s notesName after 64
    for row in rows do
      last := some row.id
    match next with
    | none => return last
    | some id => after := some id
  throw (IO.userError "notes collection has more than 100000 pages; refusing to guess the next id")

def openAt (dir : System.FilePath) : IO Store := do
  IO.FS.createDirAll dir
  let shards ← ShardSet.openFiles dir Epoch.single
  let prevBoots :=
    match ← shards.getStr bootKey with
    | some s => s.toNat?.getD 0
    | none => 0
  let boots := prevBoots + 1
  shards.putStr bootKey (toString boots)
  let ids ← IdGen.new wallClock
  match ← greatestId shards with
  | some id => ids.prev.set (some id)
  | none => pure ()
  return { shards, ids, boots }

def Store.close (s : Store) : IO Unit :=
  s.shards.close

def Store.noteCount (s : Store) : IO Nat := do
  let mut after : Option Ulid := none
  let mut n : Nat := 0
  for _ in [0:100000] do
    let (rows, next) ← collList s.shards notesName after 64
    n := n + rows.length
    match next with
    | none => return n
    | some id => after := some id
  return n

structure Note where
  id : Ulid
  version : UInt64
  text : String
  deriving Repr

def Store.addNote (s : Store) (text : String) : IO Note := do
  if text.isEmpty then
    throw (IO.userError "empty note")
  if text.toList.length > 4000 then
    throw (IO.userError "note longer than 4000 characters")
  let id ← s.ids.next
  let result ← collInsert s.shards notesName id (.str text)
  match result with
  | .ok version => return { id, version, text }
  | .conflict => throw (IO.userError "id already stored")
  | .missing => throw (IO.userError "insert missing")

def Store.listNotes (s : Store) (limit : Nat) : IO (List Note) := do
  let (rows, _) ← collList s.shards notesName none limit
  let mut out : List Note := []
  for row in rows do
    match row.val with
    | .str text => out := out ++ [{ id := row.id, version := row.version, text }]
    | _ => pure ()
  return out

def Store.getNote (s : Store) (id : Ulid) : IO (Option Note) := do
  match ← collGet s.shards notesName id with
  | some (version, .str text) => return some { id, version, text }
  | some _ => return none
  | none => return none

end Vlab.Store
