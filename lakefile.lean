import Lake
open Lake DSL

package leanlab where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩
  ]

/-!
Pinned to the same commits this workspace was read against.
`lake-manifest.json` records the resolved revisions.
-/
require cairn from git "https://github.com/kidandcat/cairn.git" @ "543684716dde412bb803702efdf6e6406f435c9d"
require uvl from git "https://github.com/kidandcat/uvl.git" @ "ff2f323df25f2e260c19a28d220c3bf507b033df"

@[default_target]
lean_lib Leanlab

@[default_target]
lean_exe «leanlab-server» where
  root := `LeanlabServer

/-- Browser UI. Built to WebAssembly by `web/build.sh`; not a native default. -/
lean_lib LeanlabWeb where
  globs := #[.one `LeanlabWeb.App]

@[test_driver]
lean_exe «leanlab-tests» where
  root := `Tests.Main
