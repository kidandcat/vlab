import Vlab.Sandbox.Cited
import Vlab.Sandbox.Host
import Vlab.Sandbox.Path
import Vlab.Wasm.Eval
import Vlab.Wasm.Mem

-- Elaborating this file prints the kernel axioms of the sandbox theorems.
-- `scripts/check-axioms.sh` rejects `sorryAx` and anything outside
-- `propext`, `Classical.choice`, and `Quot.sound`.
#print axioms Vlab.Sandbox.Path.normalize_safe
#print axioms Vlab.Wasm.Mem.load?_inRange
#print axioms Vlab.Wasm.Mem.store?_size
#print axioms Vlab.Wasm.Mem.grow_le
#print axioms Vlab.Sandbox.Host.fsReadOk_grant
#print axioms Vlab.Sandbox.Host.fsWriteOk_grant
#print axioms Vlab.Sandbox.Host.netOk_grant
#print axioms Vlab.Sandbox.Host.clockOk_grant
#print axioms Vlab.Sandbox.Host.randomOk_grant
#print axioms Vlab.Sandbox.Host.deny_keeps
#print axioms Vlab.Sandbox.Host.note_keeps
#print axioms Vlab.Wasm.evalList_zero
#print axioms Vlab.Sandbox.Cited.tag_known
