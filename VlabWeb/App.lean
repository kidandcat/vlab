import UVL
import Vlab.Sandbox.Host
import Vlab.Wasm.Ast
import Vlab.Wasm.Eval

/-!
Browser view of the sandbox. The buttons run the same pure interpreter the
server runs. The HTML panel next to the canvas talks to the multi-sandbox API.
-/

namespace VlabWeb.App
open UVL UI
open Vlab.Sandbox.Host
open Vlab.Wasm

inductive Msg where
  | oob
  | loop
  | deny
  deriving BEq, Repr, Inhabited

structure Model where
  line : String := "pick an escape"
  deriving Repr

def env (grants : List Cap) : HostEnv := {
  grants
  vfs := []
  clock := 0
  entropy := #[]
  entropyAt := 0
  calls := 0
  callQuota := 4
  vfsQuota := 1024
  audit := []
}

def oobMod : Module := {
  imports := #[]
  funcs := #[{
    params := 0
    locals := 0
    results := 1
    body := [.constI32 65536, .loadI32, .drop, .constI32 0]
  }]
  memPages := 1
  main := 0
}

def loopMod : Module := {
  imports := #[]
  funcs := #[{
    params := 0
    locals := 0
    results := 1
    body := [.loop_ [.br 0], .constI32 0]
  }]
  memPages := 0
  main := 0
}

def denyMod : Module := {
  imports := #[{ module := "vlab", name := "fs_read", op := some .fsRead, params := 4 }]
  funcs := #[{
    params := 0
    locals := 0
    results := 1
    body := [.constI32 0, .constI32 0, .constI32 0, .constI32 0, .call 0]
  }]
  memPages := 0
  main := 1
}

def describe : Halt → String
  | .trap .bounds _ => "trap bounds · load?_inRange"
  | .trap .outOfFuel _ => "trap outOfFuel · evalList_zero"
  | .trap .escape _ => "trap escape · normalize_safe"
  | .ok st | .ret st =>
    match st.host.audit with
    | line :: _ => line
    | [] =>
      match st.stack with
      | .i32 n :: _ => "value " ++ toString n.toNat
      | _ => "ok"
  | .trap _ _ => "trap"
  | .br _ _ => "br"

def update : Msg → Model → Model
  | .oob, _ => { line := describe (runModule 20 oobMod (env []) (65536 * 2)) }
  | .loop, _ => { line := describe (runModule 30 loopMod (env []) 0) }
  | .deny, _ => { line := describe (runModule 20 denyMod (env []) 0) }

def view (m : Model) : UI.Widget Msg := ui! pad 16:
  col (gap := 10) (align := .stretch):
    row:
      text "vlab" (size := 4) (color := Color.hex 0x0D47A1)
      spacer
      chip "sandbox"
    card:
      col (gap := 6) (align := .stretch):
        text "Fuel, memory, capabilities."
        text m.line
        row (gap := 8):
          button "oob" (onTap := some Msg.oob)
          button "loop" (onTap := some Msg.loop)
          button "deny" (onTap := some Msg.deny)
    card:
      col (gap := 4) (align := .stretch):
        text "load?_inRange"
        text "normalize_safe"
        text "fsReadOk_grant"
        text "evalList_zero"

def app : App Model Msg where
  init := {}
  update
  view
  background := Color.hex 0xF4F6F8
  title := "vlab"

end VlabWeb.App

@[export uvl_web_make]
def VlabWeb.App.make (w h : UInt32) : UVL.AnyRuntime :=
  .start VlabWeb.App.app w h
