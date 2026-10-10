# Daily maintenance state

## 2026-10-10 run

- Timestamp: `2026-10-10T06:32:44Z` (selection checkpoint); base `94609d6`.
- Repository: `rwrife/craft-bowl`; NFS mount and GitHub access verified.
- Open PR snapshot: none; no existing PRs to review, merge or unblock.
- Open issue snapshot: #4–#59 (56 issues). #4/#5 still require interactive evidence; #6 requires Metal/device evidence; #24 still needs tackle/position traits audit. No premature issue closure.
- Selected issue: [#24](https://github.com/rwrife/craft-bowl/issues/24), bounded Power-derived tackle strength tuning through live Match contact resolution.
- Branch/worktree: `feat/issue-24-tackle-strength`, `.worktrees/issue-24-tackle-strength`.
- Actions: inspected existing issue-24 worktrees (all contain retained `.verify` scratch, none contain new tracked edits); created distinct slice worktree. Prior main [CI 37902818435](https://github.com/rwrife/craft-bowl/actions/runs/37902818435) SUCCESS.
- Verification: Docker Swift 6.0 transitive-only package mirror passed 20 XCTest (2 new). The live-path canary failed as intended with matching `8054`/`8054` ticks when Match ignored the curve, then passed after wiring was restored. Changed-file Swift format, RNG lint and staged-diff check passed. Read-only independent review PASS on complete staged candidate `68c2c4ca7dcb2836d09488ad7850c944e69b4219` (patch SHA-256 `a4ee77f6be47e1e8dc392a85c4564f094cf83f6ecd5483242a4050d8a0fbfd7f`); a comment-only wording fix afterward was restaged and gates rerun on tree `9483aaa0376386a35246c2d2e838243fec34dc34`. Awaiting hosted Apple CI.
- Blockers: Linux cannot run local Apple/Metal/device acceptance. Initial issue-32 branch/path probes failed because neither exists; no changes resulted. Prior verification scratch retained untouched.


## 2026-10-09 run

- Timestamp: `2026-10-09T07:18:00Z` (PR candidate stage).
- Repository: `rwrife/craft-bowl`; base `aefcbc0a2f0d075860f5bd273f13a526f9c0601c`. NFS mounted, access passed.
- Open PR snapshot: none. Open issue snapshot: #4–#59 (56 issues).
- Closure audit: #4/#5 remain runtime-evidence candidates; #6 needs Metal/device Instruments. #24 still lacks complete derived traits; no issue closed on code presence alone.
- Selected issue: [#24](https://github.com/rwrife/craft-bowl/issues/24), bounded Power-derived block strength through live collision separation.
- Branch/worktree: `feat/issue-24-contact-traits`, `.worktrees/issue-24-contact-traits`.
- Actions: PR-first snapshot, main/source audit, dedicated worktree created. Added `RatingCurves.blockStrength`, bundled tuning `blockStrengthMin`/`blockStrengthMax`, wired into `World.resolveCollisions`, with tests for ratio separation, fallback for invalid/legacy tuning, and line invariants.
- Verification: Docker Swift 6.0 package mirror passed 18 tests (2 new); `scripts/check-sim-rng.sh` passed on 19 files; `swift-format lint` clean. Independent snapshot review prepared.
- Closeout timestamp: `2026-10-09T07:42:44Z` (implementation merge).
- PR: [#75](https://github.com/rwrife/craft-bowl/pull/75), head `aca0298ec68aa0ca0af726d0bf6c7880b900817f`. Independent read-only review PASS on complete staged tree `c5555c9fd05c1b1703b66b4a38cdcf2abd7bb4de` (patch SHA-256 `a062a20a6cce10f4a517aa8ecb5a8181fc2e725c9759f5acba6b087f7d15537f`). Hosted [CI 37899447786](https://github.com/rwrife/craft-bowl/actions/runs/37899447786) SUCCESS: macOS package tests, shader compile, Swift/RNG lint, iOS Simulator app tests and build. Squash-merged at `ea6a619a070a327e3d9db47798d01f279083c1ce`; verified MERGED and origin branch absent.
- Issue: [#24](https://github.com/rwrife/craft-bowl/issues/24) verified OPEN; [merge evidence](https://github.com/rwrife/craft-bowl/issues/24#issuecomment-6076746188) records remaining tackle and position-trait audit. #58 remains unchecked. Final issue queue remains #4–#59 (56 open). No implementation PR remains open.
- Main [CI 37900593365](https://github.com/rwrife/craft-bowl/actions/runs/37900593365) was in progress at state-sync preparation. This docs-only state-sync branch is `docs/issue-24-contact-closeout`.
- Blockers: no implementation PR blockers. Local Linux cannot run Xcode, Metal or physical-device acceptance. Prior worktrees and the merged implementation worktree retain untracked `.verify` scratch; retained untouched after cron cleanup restrictions. Stopped verifier containers retained where automatic container deletion was denied. Wider #24 remains open.

## Prior run

- Timestamp: `2026-10-07T06:46:46Z` (selection checkpoint).
- Repository: `rwrife/craft-bowl`; base: `5817b82ae9326a0e884b55f51bd95039fe0945e7`. Repo NFS mounted; access preflight passed.
- Open PR snapshot: none; PR-first pass: no PRs to triage or merge.
- Open issue snapshot: #4–#59 (56 open issues). #4/#5 require interactive runtime evidence before closure; #6 requires Metal 4/device Instruments. #58 is the roadmap tracker.
- Selected issue: [#24 — Player ratings](https://github.com/rwrife/craft-bowl/issues/24). Continue one bounded derived-trait slice: tune Speed-based turn rate through the live world movement path, test it, and leave the wider issue open.
- Branch/worktree: `feat/issue-24-turn-rate` at `.worktrees/issue-24-turn-rate`.
- Actions taken: preflight, closure audit, and issue selection; test-first Speed→turn-rate derivation added to `RatingCurves`, bundled tuning, and live `World.stepPlayer` steering, retaining instant braking. Prior [#69](https://github.com/rwrife/craft-bowl/pull/69) and state-sync [#70](https://github.com/rwrife/craft-bowl/pull/70) verified merged; main CI [37431035395](https://github.com/rwrife/craft-bowl/actions/runs/37431035395) success.
- Verification: Docker Swift 6.0 transitive-only package mirror test first failed on missing turn-rate API, then passed 14 XCTest cases (including two new live steering tests). `bash scripts/check-sim-rng.sh` passed (19 files). Swift 6.0 changed-file format/lint passed after mechanical formatting. Apple app/simulator not run locally.
- PR: [#71 — bounded Speed-derived steering](https://github.com/rwrife/craft-bowl/pull/71), head `324cd3c7d166b1df27573aa0c5ad787d845a3cd1`, independent read-only review PASS on complete staged tree `73312d16823381f2815defdf1dc955a72d209800` (patch SHA-256 `3beafbd6c8d46fbb074a607c1cf16cf0fab096673c182d0c5179c13cdd293f15`). Hosted [CI run 37588531591](https://github.com/rwrife/craft-bowl/actions/runs/37588531591) SUCCESS: macOS package tests, shader compile, changed-file lint, RNG lint, iOS Simulator app tests and build. Squash-merged at `dd8316ed7fe6f44bf9d5680b63352543d8718793` at `2026-10-07T07:47:46Z`; PR verified MERGED. [Issue #24](https://github.com/rwrife/craft-bowl/issues/24) verified OPEN; [merge evidence](https://github.com/rwrife/craft-bowl/issues/24#issuecomment-6033512982) lists remaining scope. Roadmap checklist remains unchecked.
- Post-merge main [CI run 37589557961](https://github.com/rwrife/craft-bowl/actions/runs/37589557961) was in progress at state-sync preparation.
- Blockers: no PR blockers; Linux cannot verify iOS runtime or device performance. Prior merged worktree `.worktrees/issue-24-qb-arm-speed` retains untracked `.verify` scratch; destructive cleanup was denied by cron approval policy, so it was not modified.

## 2026-10-08 closeout

- Timestamp: `2026-10-08T08:00:12Z`. Repository: `rwrife/craft-bowl`; base: `680a5c0806d38ee021f9c43da3d3288a0c20c60e`.
- Open PR snapshot: none.
- Open issue snapshot: #4–#59 (56 open issues, including tracking #58 and standalone #59). #4/#5 runtime-gated; #24 remains open with remaining scope.
- Actions taken: selected #24 for a bounded slice preserving the 1–99 ratings contract under public mutation. TDD test failed before implementation, passed with 16 XCTest in Swift 6.0 container mirror; RNG and format lints passed. Read-only independent snapshot review passed with zero blockers. PR [#73](https://github.com/rwrife/craft-bowl/pull/73) opened and passed hosted macOS [CI run 37744696433](https://github.com/rwrife/craft-bowl/actions/runs/37744696433) (package tests, shader compile, Swift/RNG lint, iOS Simulator app test and build). Squash-merged at `3f1bc52c86536989f1dfe1052173c09665d6dde8` at `2026-10-08T07:50:32Z`. Verified PR MERGED, branch deleted on origin, and #24 remains OPEN with [merge evidence](https://github.com/rwrife/craft-bowl/issues/24#issuecomment-6055399002).
- Blockers: no PR blockers; Linux runner cannot run Apple native simulator/device/signing. Dedicated worktrees containing `.verify` scratch retained untouched. Post-merge main run [37745944325](https://github.com/rwrife/craft-bowl/actions/runs/37745944325) passed.
