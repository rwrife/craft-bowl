# Daily maintenance state

## Latest run

- Timestamp: `2026-10-06T06:37:19Z`
- Repository: `rwrife/craft-bowl`; base: `975453e17f6be0bc441c7361618ce68225a9620b` (`origin/main` at selection). Repo NFS mounted on Halo; access preflight passed.
- Open PR snapshot: none; PR-first pass: nothing to triage or merge.
- Open issue snapshot: #4–#59 (56 open issues). #4 and #5 require authorized interactive runtime evidence and remain closure-audit candidates; #58 is the roadmap tracker.
- Selected issue: [#24 — Player ratings](https://github.com/rwrife/craft-bowl/issues/24), dependency #3 closed. Scope: tunable Power-derived QB throw speed (18–26 yd/s) used for receiver lead prediction and ball flight, with hostile-tuning defense and 5 focused tests. Partial slice; issue stays open.
- Branch/worktree: `feat/issue-24-qb-arm-speed` at `.worktrees/issue-24-qb-arm-speed`.
- Actions taken: preflight and backlog audit passed; dedicated worktree created. Implemented `QuarterbackArmCurve` in `CBSim.Ratings`, bundled `qbArm` in `ratings.json`, wired `Match.pass` lead and throw velocity to `quarterbackPassSpeed`, and added 5 tests in `QuarterbackArmTests`. Mechanical full-file formatting applied to `Match.swift` for CI changed-file lint compliance.
- Local verification: Docker `swift:6.0` transitive-only SwiftPM mirror (CBCore/CBSim/CBPlays/CBAI/CBGame) TDD RED on fixed 22 yd/s flight speed and NaN hostile curve, then GREEN; final language mode `swift test -Xswiftc -warnings-as-errors`: 12 XCTest PASS (1 ScaffoldTests, 3 TeamRatingTests, 3 ReplayDeterminismTests, 5 QuarterbackArmTests). `bash scripts/check-sim-rng.sh`: PASS (19 files). Docker Swift 6.0 `swift-format lint --strict` on 3 changed Swift files: PASS.
- Review/freeze: independent read-only review round 1 identified hostile tiny-curve bug; patched and regression-tested. Round 2 PASS on complete staged diff (tree `37f28cfd55d35e47fcdb7db8cd98acceea52157e`, patch SHA-256 `741cc012f9fd4fb05d5c1d4e2cc03020dd959c0dec8e3e0f5f28f541f7e49c1d`). Pushed commit `4c4f14921c6c4d91e0bdcca84fee00371b9087e8`.
- PR: [#69 — derive QB pass velocity from Power ratings](https://github.com/rwrife/craft-bowl/pull/69). Hosted [CI run 37428725106](https://github.com/rwrife/craft-bowl/actions/runs/37428725106) SUCCESS across all steps (package tests, Metal shader compile, changed-file lint, RNG lint, iOS Simulator app test and build). Squash-merged at `6d9d7488330173379f5dec78011c4c702483d137` on `2026-10-06T07:25:06Z`; post-merge PR state verified `MERGED`.
- Issue #24 remains OPEN, as intended for a partial slice; [merge-evidence comment](https://github.com/rwrife/craft-bowl/issues/24#issuecomment-6011539978) records completed scope, CI provenance and remaining derived-trait gaps. The tracking checklist for #24 stays unchecked.
- Post-merge main CI at `6d9d748` in progress at closeout-state preparation: [run 37429534273](https://github.com/rwrife/craft-bowl/actions/runs/37429534273).
- Blockers: no PR blockers. Linux cannot run local Xcode/iOS simulator or verify #4/#5 interactive runtime acceptance. State-sync docs PR to finalize this record follows the feature merge.
