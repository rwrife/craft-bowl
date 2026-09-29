# Daily maintenance state

## Latest run

- Timestamp: `2026-09-29T08:23:41Z`
- Repository: `rwrife/craft-bowl`
- Base snapshot: `origin/main` at `66007cbb91cf78d34912c5716b9789760b5f07fb`
- Result head: `origin/main` at `ad952cc0379b02b6724202c5c81dcc8d34de16da`
- Open PR snapshot (start of run): none
- Open issue snapshot (start of run): 58 issues (`#2`–`#59`)
- Selected issue: [#2 — GitHub Actions CI: build, test, shader compile, lint](https://github.com/rwrife/craft-bowl/issues/2) → CLOSED this run
- Implementation branch: `feat/issue-2-ci-hardening` (merged, remote ref deleted)
- Implementation PR: [#63](https://github.com/rwrife/craft-bowl/pull/63) — squash-merged at `2026-09-29T07:54:13Z`, merge SHA `ad952cc0379b02b6724202c5c81dcc8d34de16da`, body used `Advances #2` (no premature auto-close)
- Issue closure: closed by criterion-by-criterion audit comment after merged-main CI evidence — [comment](https://github.com/rwrife/craft-bowl/issues/2#issuecomment-5886211999)
- Branch protection (issue acceptance "PRs blocked on failing CI"): `main` now strictly requires the Actions check `build`, strict up-to-date branches, conversation resolution, force-push and deletion disabled
- Actions: preflight passed; no open PRs to triage; closure audit of #1 confirmed landed; implemented issue #2 slice (workflow hardening + app test target + artifact upload), opened PR, waited for green, merged, enabled protection, closed issue with evidence
- Verification executed (this run, real output):
  - `actionlint` on `.github/workflows/ci.yml` — PASS (rc 0)
  - YAML `safe_load` of `.github/workflows/ci.yml` + `project.yml` — PASS
  - `swift-format lint --strict --configuration .swift-format Tests/CraftBowlTests/AppSmokeTests.swift` in `swift:6.2` Docker — PASS (rc 0)
  - `git diff --cached --check` — PASS
  - Independent read-only review of the complete staged diff (4 rounds, fail-closed) — final verdict `passed: true`, no blockers
  - Hosted CI PR run [36538354433](https://github.com/rwrife/craft-bowl/actions/runs/36538354433) — SUCCESS (`build`, 9m37s), incl. package tests, metallib, strict lint, app-scheme simulator test, upload
  - Hosted CI push run on merged main [36539418761](https://github.com/rwrife/craft-bowl/actions/runs/36539418761) — SUCCESS at `ad952cc…`
- Evidence tiers: Linux host provided lint/actionlint/YAML/review evidence only. `swift test` on Linux fails on `CBRender` (`no such module 'simd'`) — pre-existing Apple-only constraint, not a regression; package + app builds/tests are hosted-macOS CI evidence, not local evidence. No local Xcode/simulator run was possible.
- Remaining gaps for issue #2: none outstanding (headless sim report is explicitly deferred to #35)
- Blockers: none open
- Next-queue note: `#3`…`#59` remain open; `#1` and `#2` are closed.
