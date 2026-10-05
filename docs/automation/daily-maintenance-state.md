# Daily maintenance state

## Latest run (in progress)

- Timestamp: `2026-10-05T12:24:19Z`
- Repository: `rwrife/craft-bowl`; base: `de57bbd4d905ace532be43053565100ee35047b6` (`origin/main`)
- Open PR snapshot: none; PR-first pass: nothing to triage or merge.
- Open issue snapshot: #4–#59 (56 open issues). #4 and #5 have code landed but require interactive runtime evidence before closure; see previous run's notes. #58 is the roadmap tracker. Other issues are dependency-gated or later milestones.
- Selected issue: [#24 — Player ratings](https://github.com/rwrife/craft-bowl/issues/24), dependency #3 closed. Existing speed/endurance curves and JSON are implemented; team overall in `App/Sources/RootView.swift` is currently an unweighted average. Scope for this run: weighted team overall with direct package tests and UI consumption; #24 remains open for missing derived traits/complete acceptance audit.
- Branch/worktree: `feat/issue-24-weighted-overall` at `.worktrees/issue-24-weighted-overall`. No prior issue branch or worktree found.
- Actions taken: preflight and queue audit passed; dedicated worktree created. Implemented 3/3/2/2 weighted team overall in `CBSim.TeamRating`, wired the title/team-selection UI's OVR to it, added package and app smoke tests. The issue stays open because not all derived ratings have been audited/implemented.
- Local verification: Docker `swift:6.2` focused TDD RED showed missing `TeamRating`, then GREEN passed; mirrored all three `ScaffoldTests` files through a local transitive-only SwiftPM probe (7/7 XCTest PASS), `bash scripts/check-sim-rng.sh` PASS (19 files), `swiftc -parse` on changed app files PASS, and Swift 6.2 `swift-format lint --strict --configuration .swift-format` on changed Swift files PASS after formatting the pre-existing style drift in `RootView.swift`. Direct Linux `swift test --package-path Packages/CraftBowlKit` failed on existing Apple-only `CBRender/Meshes.swift` import of `simd`; this is not a test-result pass.
- Pending: clean staged diff/review, commit, push, open PR; macOS package/app CI not yet observed.
- Blockers: no GitHub access blocker. Linux cannot execute Xcode/iOS simulator or verify interactive runtime criteria.
