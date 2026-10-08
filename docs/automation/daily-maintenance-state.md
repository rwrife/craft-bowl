# Daily maintenance state

## Latest run

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
