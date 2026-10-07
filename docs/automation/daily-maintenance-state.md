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
- PR: pending push/review.
- Blockers: no PR blockers; Linux cannot verify iOS runtime or device performance. Prior merged worktree `.worktrees/issue-24-qb-arm-speed` retains untracked `.verify` scratch; destructive cleanup was denied by cron approval policy, so it was not modified.
