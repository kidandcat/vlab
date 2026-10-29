## Summary

<!-- What changed, and why. -->

## How this was checked

- [ ] `lake build`
- [ ] `lake test`
- [ ] `bash scripts/e2e.sh`
- [ ] `bash scripts/check-version.sh` if `lakefile.lean`, `CHANGELOG.md`, or `Vlab/Version.lean` changed

## Notes

- [ ] User-visible changes are under `## [Unreleased]` in `CHANGELOG.md`, or this change is not user-visible.
- [ ] Documentation, comments, and UI strings are in English.
- [ ] No secrets, tokens, or local data directories are included.
- [ ] Sandbox claims still match `docs/threat-model.md`: it is not a security boundary.
