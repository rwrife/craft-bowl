# Daily maintenance state

## Latest run

- Timestamp: `2026-10-06T06:37:19Z`
- Repository: `rwrife/craft-bowl`; base: `975453e17f6be0bc441c7361618ce68225a9620b` (`origin/main`). Repo NFS mounted on Halo; access preflight passed.
- Open PR snapshot: none; no PRs to triage or merge.
- Open issue snapshot: #4–#59 (56 open issues). #58 is the roadmap tracker.
- Closure audit: #4/#5 require authorized interactive runtime evidence, so remain closure-audit candidates rather than implementation tasks. #24's weighted overall, speed/endurance curves and bundled JSON are landed; missing tunable QB arm speed and turn-rate derivation prevent full closure. Current main CI [37312527557](https://github.com/rwrife/craft-bowl/actions/runs/37312527557) is successful.
- Selected issue: [#24 — Player ratings](https://github.com/rwrife/craft-bowl/issues/24), dependency #3 closed. Scope: tunable Power-derived QB pass velocity used by both receiver leading and ball flight, with direct package and production-path tests. Partial slice; issue stays open.
- Branch/worktree: `feat/issue-24-qb-arm-speed` at `/home/rwrife/repos/craft-bowl/.worktrees/issue-24-qb-arm-speed`. No interrupted matching worktree/branch found.
- Actions taken: preflight, queue snapshot, acceptance audit and dedicated worktree creation completed. Implemented Power-derived QB arm speed (18–26 yd/s) in bundled ratings tuning; both receiver lead and actual flight use the same speed. Bad tunings fall back to safe defaults; older JSON remains decodable. Added five package tests, including live `Match.step` passes for moving-receiver lead and hostile tuning. Issue remains open for remaining rating derivatives and comprehensive acceptance.
- Local verification: Docker `swift:6.0` transitive-only SwiftPM mirror (CBCore/CBSim/CBPlays/CBAI/CBGame) RED against hard-coded flight speed; GREEN after implementation; final Swift 6 language mode `swift test -Xswiftc -warnings-as-errors`: 12 XCTest PASS (1 ScaffoldTests, 3 TeamRatingTests, 3 ReplayDeterminismTests, 5 QuarterbackArmTests). `bash scripts/check-sim-rng.sh`: PASS (19 files). Docker Swift 6.0 `swift-format lint --strict` on 3 changed Swift files: PASS after full-file mechanical format in `Match.swift`. The canonical full package is Apple-gated (`CBRender` imports `simd` on Linux); its CI run and iOS app build pending this PR.
- Review/freeze: independent read-only review PASS on complete staged diff (tree `37f28cfd55d35e47fcdb7db8cd98acceea52157e`, patch SHA-256 `741cc012f9fd4fb05d5c1d4e2cc03020dd959c0dec8e3e0f5f28f541f7e49c1d`). Working tree contains local `.verify` SwiftPM mirror/build cache, intentionally excluded from the PR.
- Blockers: local Linux cannot run Xcode/iOS simulator, Metal compilation or interactive device acceptance. Native checks will remain hosted-CI evidence only.
