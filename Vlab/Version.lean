/-
Package version printed by `vlab-server` and returned by `GET /health`.

`scripts/check-version.sh` requires this string, `version := v!"X.Y.Z"` in
`lakefile.lean`, and the newest `## [X.Y.Z]` heading in `CHANGELOG.md`
to be the same number.
-/

namespace Vlab

def version : String := "0.1.0"

end Vlab
