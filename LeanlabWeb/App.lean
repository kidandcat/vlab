import UVL

/-!
Minimal browser UI. The web shell calls `uvl_web_make` once, then steps the
runtime. The button is a tap target so a headless smoke test can click it.
The chart is drawn by uvl; the server stores notes in cairn separately.
-/

namespace LeanlabWeb.App
open UVL UI

inductive Msg where
  | ping
  deriving BEq, Repr, Inhabited

structure Model where
  pings : Nat := 0
  deriving Repr

def update : Msg → Model → Model
  | .ping, m => { pings := m.pings + 1 }

def view (m : Model) : UI.Widget Msg := ui! pad 20:
  col (gap := 14) (align := .stretch):
    row (gap := 12):
      text "leanlab" (size := 4) (color := Color.hex 0x0D47A1)
      spacer
      chip "cairn + uvl"
    card:
      col (gap := 8) (align := .stretch):
        text "Notas en cairn. Grafica en uvl."
        row (gap := 12):
          button "ping" (onTap := some Msg.ping)
          text ("pings " ++ toString m.pings)
    expanded:
      card:
        lineChart [[1, 3, 2, 6, 4, 8, 7, 9]]

def app : App Model Msg where
  init := {}
  update
  view
  background := Color.hex 0xF4F6F8
  title := "leanlab"

end LeanlabWeb.App

@[export uvl_web_make]
def LeanlabWeb.App.make (w h : UInt32) : UVL.AnyRuntime :=
  .start LeanlabWeb.App.app w h
