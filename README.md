# Block Bowl

A modern-retro, blocky American football game for iOS. It looks like a blocky dungeon crawler and plays like simplified Tecmo Bowl: 9-on-9, a 3+1 lane play system, and stamina/turbo running.

- **Design & roadmap:** [`docs/PLAN.md`](docs/PLAN.md)
- **Visual target:** [`docs/reference/target.jpg`](docs/reference/target.jpg)
- **Backlog:** GitHub Issues, grouped by milestones M0–M10 (created by `scripts/create_issues.py`)

## Requirements

- Xcode 26 / iOS 26 SDK, Swift 6
- A device with an A14 Bionic or newer (Metal 4 GPU family)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`make bootstrap`)

## Getting started

```sh
make bootstrap   # installs xcodegen + swift-format via Homebrew
make open        # generates CraftBowl.xcodeproj and opens CraftBowl.xcworkspace
```

The `.xcodeproj` is generated and git-ignored; the committed workspace references it and the local
Swift package. Run `make open` after a fresh checkout. Edit `project.yml` instead of the generated project.

If `xcodebuild` reports the Command Line Tools instead of Xcode, run `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## CI status

`main` PR/push CI now enforces all issue-#2 core gates on hosted macOS runners:

- Swift package tests (`swift test`) with xUnit output at `TestResults/CraftBowlKit.xml`
- Metal shader compile with `-Werror` plus explicit `metallib` link
- Strict `swift-format` lint on changed Swift files in pull requests
- App-scheme simulator tests via `xcodebuild test`
- Test artifact upload (`xUnit` + `.xcresult`) for every run

`swift-format` is intentionally scoped to changed Swift files in PRs while legacy formatting debt is burned down.

### Command-line run (Simulator)

```sh
xcodegen generate
xcodebuild -project CraftBowl.xcodeproj -scheme CraftBowl \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/dd/Build/Products/Debug-iphonesimulator/CraftBowl.app
xcrun simctl launch booted com.infinityball.craftbowl -CBAutoStart YES -CBDevOverlay YES
```

Launch arguments (UserDefaults): `-CBAutoStart YES` skips the title screen, `-CBAutopilot YES` lets the CPU play offense, and `-CBDevOverlay YES` opens the dev overlay.

The Simulator has no MetalFX, so upscaling falls back to a bilinear blit there. On the Simulator the GPU-family check is skipped; on devices an A14 or newer is required.

## Playing (current sandbox)

You play offense (blue) against CPU defense (red). A turnover, touchdown, or safety restarts the drive.

| Action | Touch | Keyboard | Controller |
|---|---|---|---|
| Move | left stick | WASD / arrows | left stick / d-pad |
| Pick play (1 of 3 cards) | tap a card | 1 2 3 or J K L | X A B |
| Snap (after picking) | SNAP | Return (or any pass key) | any face button |
| Pass L / C / R | lane buttons | J K L | X A B |
| Handoff | HAND | H | Y |
| Turbo | hold TURBO | hold Space | right trigger |
| Dive | DIVE | U | right shoulder |
| Pause | — | P / Esc | Menu |
| Dev overlay | 3-finger tap | ` | Options, or L3+R3 |

Before each snap you get 3 random play cards with X's-and-O's diagrams. The play auto-snaps after 10 seconds.

Every player has **health**. It drains quickly while the player is involved in a play (faster when carrying, cutting, or using turbo) and regenerates otherwise. Low health reduces speed and ability (catching, diving, QB accuracy). Stacked stat bars (speed / endurance / ability × health) float over the key players before the snap. During the play they show only over the ball carrier. Invisible walls keep players on the field and out of the stands.

The dev overlay shows FPS, CPU/GPU pass timings, draw counts, the controlled-player inspector, and the input log. It has toggles for every render pass, camera presets, pause, ¼× speed, autopilot, and deterministic Record / Replay / Verify (replay confirms the world checksum). In Debug builds, edits to `ratings.json` hot-reload once per second.

## Layout

```
App/                      SwiftUI app shell + Metal shaders (App/Shaders)
Packages/CraftBowlKit/    engine modules (Swift package)
  CBCore       RNG (PCG32), fixed-step GameClock, math, tuning loader
  CBSim        9v9 positions, Power/Speed/Endurance/Ability ratings, health + turbo, World
  CBPlays      3+1 lanes, data-driven offense/defense playbooks (Resources/*.json)
  CBAI         player/coach brain protocols
  CBAnimation  rig bones + clip IDs for the single player model
  CBAssets     PlayerAppearance / TeamUniform (one model, many looks)
  CBInput      GameAction stream: touch, hardware keyboard, Game Controller
  CBGame       match rules (downs, clock, scoring), GameSimulation, record/replay
  CBRender     Metal renderer: instanced players, GPU-culled crowd, shadows,
               floodlights, bloom, tonemap + color-grade LUT, MetalFX upscaling
  CBHUD        HUD layout matching the reference
  CBAudio      audio buses
docs/                     plan + reference art
scripts/create_issues.py  creates labels, milestones and issues via `gh`
```

CBCore, CBSim, CBPlays, CBAI, CBAnimation and CBAssets must stay platform-neutral (no UIKit or Metal), so the simulation stays deterministic and can run headless.

## Tuning

Gameplay numbers live in JSON resources, not code:
- `Packages/CraftBowlKit/Sources/CBSim/Resources/ratings.json`
- `Packages/CraftBowlKit/Sources/CBPlays/Resources/{format,offense,defense}.json`
