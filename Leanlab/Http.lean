/-
HTTP routes for the skeleton.

`Std.Http.Server` (HTTP/1.1, keep-alive, chunked bodies) is the listener.
This module only decides the response. Static files are a fixed whitelist
loaded at startup: there is no path join, so a request cannot escape the list.
-/

import Leanlab.Json
import Leanlab.Store
import Std.Async
import Std.Http.Server

open Std.Async
open Std.Http
open Std.Http.Server
open Leanlab.Store

namespace Leanlab.Http

def maxBodyBytes : UInt64 := 65536

def toolchain : String := "4.35.0"

def noteTextLimit : Nat := 4000

inductive Route where
  | health
  | listNotes
  | createNote
  | getNote (id : String)
  | static (name : String)
  | methodNotAllowed
  | notFound
  deriving Repr, BEq

def pathOf (uri : String) : String :=
  match uri.splitOn "?" with
  | p :: _ => p
  | [] => uri

def segments (path : String) : List String :=
  path.splitOn "/" |>.filter (· != "")

/-- Classify a method and an origin-form URI. `method` is the HTTP token (`GET`, `POST`, …). -/
def classify (method path : String) : Route :=
  let path := pathOf path
  match method, segments path with
  | "GET", [] => .static "index.html"
  | "GET", ["health"] => .health
  | "GET", ["api", "notes"] => .listNotes
  | "POST", ["api", "notes"] => .createNote
  | "GET", ["api", "notes", id] => .getNote id
  | "POST", ["api", "notes", _] => .methodNotAllowed
  | "POST", [] => .methodNotAllowed
  | "POST", ["health"] => .methodNotAllowed
  | "GET", [name] =>
      if name == "index.html" || name == "uvl.js" || name == "uvl.wasm" || name == "uvl-web.js" then
        .static name
      else
        .notFound
  | _, _ => .notFound

structure StaticFile where
  contentType : String
  bytes : ByteArray

structure Static where
  files : List (String × StaticFile)

def contentTypeOf (name : String) : String :=
  match name with
  | "index.html" => "text/html; charset=utf-8"
  | "uvl.js" => "text/javascript; charset=utf-8"
  | "uvl-web.js" => "text/javascript; charset=utf-8"
  | "uvl.wasm" => "application/wasm"
  | _ => "application/octet-stream"

def Static.load (dir : System.FilePath) : IO Static := do
  let names := ["index.html", "uvl.js", "uvl.wasm", "uvl-web.js"]
  let mut files : List (String × StaticFile) := []
  for name in names do
    let path := dir / name
    if ← path.pathExists then
      let bytes ← IO.FS.readBinFile path
      files := files ++ [(name, { contentType := contentTypeOf name, bytes })]
  return { files }

def Static.find? (s : Static) (name : String) : Option StaticFile :=
  match s.files.find? (fun pair => pair.1 == name) with
  | some (_, file) => some file
  | none => none

def hexDigit (n : Nat) : Char :=
  let chars := "0123456789abcdef".toList
  chars[n % 16]?.getD '0'

private def digits (n : Nat) : List Char :=
  go 64 n []
where
  go (fuel n : Nat) (acc : List Char) : List Char :=
    match fuel with
    | 0 => acc
    | fuel + 1 =>
      if n == 0 then acc
      else go fuel (n / 16) (hexDigit (n % 16) :: acc)

def toHex (id : Cairn.Ulid) : String :=
  pad 12 id.time ++ pad 20 id.rand
where
  pad (width n : Nat) : String :=
    let ds := digits n
    let zeros := if ds.length ≥ width then [] else List.replicate (width - ds.length) '0'
    String.ofList (zeros ++ ds)

private def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private def fromHex (cs : List Char) : Option Nat := do
  let mut n : Nat := 0
  if cs.isEmpty then
    failure
  for c in cs do
    let some v := hexVal c | failure
    n := n * 16 + v
  return n

def ofHex? (s : String) : Option Cairn.Ulid := do
  let cs := s.toList
  if cs.length != 32 then
    failure
  let t ← fromHex (cs.take 12)
  let r ← fromHex (cs.drop 12)
  if ht : t < 2 ^ 48 then
    if hr : r < 2 ^ 80 then
      some ⟨t, r, ht, hr⟩
    else
      none
  else
    none

def noteJson (n : Note) (tookNs : Option Nat := none) : String :=
  let took :=
    match tookNs with
    | some ns => ",\"tookNs\":" ++ toString ns
    | none => ""
  "{\"id\":" ++ Json.str (toHex n.id) ++ ",\"version\":" ++ toString n.version ++
    ",\"text\":" ++ Json.str n.text ++ took ++ "}"

def errorJson (msg : String) : String :=
  "{\"error\":" ++ Json.str msg ++ "}"

structure App where
  store : Store
  static : Static

private def json (status : Status) (body : String) : ContextAsync (Response Body.Any) :=
  Response.withStatus status |>.json body

private def respondBytes (contentType : String) (body : ByteArray) : ContextAsync (Response Body.Any) :=
  Response.ok
    |>.header! "Content-Type" contentType
    |>.fromBytes body

def dispatch (app : App) (method uri body : String) : IO (Status × String × Option (String × ByteArray)) := do
  match classify method uri with
  | .health =>
      let notes ← app.store.noteCount
      let payload :=
        "{\"ok\":true,\"toolchain\":" ++ Json.str toolchain ++
        ",\"boots\":" ++ toString app.store.boots ++
        ",\"notes\":" ++ toString notes ++
        ",\"http\":\"std\"}"
      return (.ok, payload, none)
  | .listNotes =>
      let notes ← app.store.listNotes 50
      let items := ", ".intercalate (notes.map fun n => noteJson n)
      return (.ok, "{\"notes\":[" ++ items ++ "]}", none)
  | .createNote =>
      match Json.parseTextField body with
      | .error msg => return (.badRequest, errorJson msg, none)
      | .ok text =>
          try
            let t0 ← IO.monoNanosNow
            let note ← app.store.addNote text
            let t1 ← IO.monoNanosNow
            return (.ok, noteJson note (some (t1 - t0)), none)
          catch e =>
            return (.badRequest, errorJson (toString e), none)
  | .getNote id =>
      match ofHex? id with
      | none => return (.badRequest, errorJson "bad id", none)
      | some ulid =>
          match ← app.store.getNote ulid with
          | none => return (.notFound, errorJson "not found", none)
          | some note => return (.ok, noteJson note, none)
  | .static name =>
      match app.static.find? name with
      | some file => return (.ok, "", some (file.contentType, file.bytes))
      | none =>
          if name == "index.html" then
            return (.ok, "leanlab: el front todavía no está compilado. Ejecuta web/build.sh.\n", none)
          else
            return (.notFound, errorJson "front asset missing", none)
  | .methodNotAllowed =>
      return (.methodNotAllowed, errorJson "method not allowed", none)
  | .notFound =>
      return (.notFound, errorJson "not found", none)

def handle (app : App) (req : Request Body.Stream) : ContextAsync (Response Body.Any) := do
  let body : String ← req.body.readAll (some maxBodyBytes)
  let method := toString req.line.method
  let uri := toString req.line.uri
  let (status, payload, file) ← dispatch app method uri body
  match file with
  | some (contentType, raw) =>
      respondBytes contentType raw
  | none =>
      if status == .ok && (classify method uri == .static "index.html") &&
          !(app.static.find? "index.html").isSome then
        Response.ok |>.text payload
      else
        json status payload

def handler (app : App) : StatelessHandler :=
  Handler.ofFn (handle app)

def config : Config := {
  serverName := some (Header.Value.ofString! "leanlab")
  maxBodySize := maxBodyBytes.toNat
  maxConnections := 64
}

end Leanlab.Http
