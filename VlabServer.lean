/-
`vlab-server`: HTTP/1.1 in front of one cairn directory.

    vlab-server --data DIR --host 127.0.0.1 --port 8080 --static web/dist

The default host is the loopback. Each note is one synced cairn commit
before the response is sent.
-/

import Vlab.Http
import Vlab.Store
import Std.Http.Server
import Std.Net

open Std.Http.Server
open Std.Async
open Std.Net
open Vlab.Http
open Vlab.Store

def usage : String :=
  "vlab-server [--data DIR] [--host 127.0.0.1] [--port 8080] [--static web/dist]\n"

structure Flags where
  data : System.FilePath := "data"
  host : String := "127.0.0.1"
  port : Nat := 8080
  static : System.FilePath := "web/dist"
  deriving Repr

private def parseIPv4 (s : String) : Option (UInt8 × UInt8 × UInt8 × UInt8) := do
  let parts := s.splitOn "."
  match parts with
  | [a, b, c, d] =>
      let some an := a.toNat? | failure
      let some bn := b.toNat? | failure
      let some cn := c.toNat? | failure
      let some dn := d.toNat? | failure
      if an < 256 && bn < 256 && cn < 256 && dn < 256 then
        some (UInt8.ofNat an, UInt8.ofNat bn, UInt8.ofNat cn, UInt8.ofNat dn)
      else
        none
  | _ => none

private def takeFlag (name value : String) (f : Flags) : Except String Flags :=
  match name with
  | "--data" => pure { f with data := value }
  | "--host" => pure { f with host := value }
  | "--port" =>
      match value.toNat? with
      | some n =>
          if n ≤ 65535 then pure { f with port := n }
          else throw "port out of range"
      | none => throw "port is not a number"
  | "--static" => pure { f with static := value }
  | other => throw s!"unknown flag {other}"

private def parseArgs (args : List String) : Except String Flags := do
  let mut f : Flags := {}
  let mut rest := args
  while true do
    match rest with
    | [] => break
    | "--help" :: _ => throw usage
    | "-h" :: _ => throw usage
    | name :: value :: tail =>
        if name.startsWith "--" then
          f ← takeFlag name value f
          rest := tail
        else
          throw s!"unexpected argument {name}"
    | name :: _ =>
        throw s!"flag {name} needs a value"
  return f

def main (args : List String) : IO UInt32 := do
  let flags ←
    match parseArgs args with
    | .ok f => pure f
    | .error msg =>
        IO.eprintln msg
        return 1
  let some (a, b, c, d) := parseIPv4 flags.host
    | IO.eprintln s!"host must be an IPv4 address, got {flags.host}"
      return 1
  let store ← openAt flags.data
  let static ← Static.load flags.static
  let sandboxRoot := flags.data / "sandboxes"
  IO.FS.createDirAll sandboxRoot
  let boxes ← IO.mkRef (← reloadBoxes store sandboxRoot)
  let app : App := { store, static, boxes, sandboxRoot }
  let addr : SocketAddress := .v4 {
    addr := .ofParts a b c d
    port := UInt16.ofNat flags.port
  }
  IO.println s!"vlab-server toolchain v{toolchain} data={flags.data} static={flags.static} assets={static.files.length}"
  IO.println s!"boots={store.boots}"
  let server ← (Std.Http.Server.serve addr (handler app) config).block
  match server.localAddr with
  | some bound => IO.println s!"listening {bound}"
  | none => IO.println "listening"
  server.waitShutdown.block
  store.close
  return 0
