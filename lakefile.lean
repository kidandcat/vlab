import Lake
open Lake DSL

package vlab where
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
lean_lib Vlab

@[default_target]
lean_exe «vlab-server» where
  root := `VlabServer

/-- Browser UI. Built to WebAssembly by `web/build.sh`; not a native default. -/
lean_lib VlabWeb where
  globs := #[.one `VlabWeb.App]

@[test_driver]
lean_exe «vlab-tests» where
  root := `Tests.Main
