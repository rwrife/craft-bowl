# Craft Bowl

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
make open        # generates CraftBowl.xcodeproj from project.yml and opens it
```

The `.xcodeproj` is generated and git-ignored. Edit `project.yml` instead.

## Layout

```
App/                      SwiftUI app shell + Metal shaders (App/Shaders)
Packages/CraftBowlKit/    engine modules (Swift package)
  CBCore       RNG (PCG32), fixed-step GameClock, math, tuning loader
  CBSim        9v9 positions, Power/Speed/Endurance ratings, energy + turbo, World
  CBPlays      3+1 lanes, data-driven offense/defense playbooks (Resources/*.json)
  CBAI         player/coach brain protocols
  CBAnimation  rig bones + clip IDs for the single player model
  CBAssets     PlayerAppearance / TeamUniform (one model, many looks)
  CBInput      GameAction stream, touch + Game Controller
  CBRender     Metal renderer (bootstrap)
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
