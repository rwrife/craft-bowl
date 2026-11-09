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

## Portable Godot game

The Godot 4.4.1 project at the repository root is a cross-platform runtime for the game. It reuses the
shipping playbooks, rating curves, team catalog, logo, and audio while implementing the menus, match
simulation, stadium, HUD, touch controls, keyboard, and gamepad in GDScript and Godot's renderer. The
stadium uses a dark, fogged night environment with a dim voxel crowd, field-focused floodlights with fake volumetric light shafts, height fog, drifting haze motes, low mist, warm accent lights, a screen vignette, bloom,
subtle translucent turbo trails, turf kick-up on tackles, and touchdown confetti, pyro jets, fireworks, and a team-color light show over the bowl.
Game-day touches include lens flares on the light banks, crowd camera flashes that build with excitement, a follow-spot on the ball carrier,
light pooling on the turf, contact shadows, striped officials, a chain crew with down box, a sideline TV camera operator, kicking nets and carts,
cheerleaders at each end-zone corner, and a film-style post pass with color grade, chromatic fringe, and grain.
The title logo slams onto the screen with squash, camera shake, a flash, block dust, and a thud.
Surfaces use pixel-noise block textures, and ad boards use pixelated lettering. Its stacked bowl has a 52-row double deck
with a slight upper-deck overhang, aisles, vomitories, stair rails, a lit glass suite level, roof-mounted light banks, a single home tunnel in an end-zone
corner, LED ribbon boards, a padded lower barrier with team names, sponsor ads, and live game clocks, and a
hanging jumbo tron with the live score. The field has painted team end zones, a midfield logo, yard numbers,
a wide white border, pylons, yard-number arrows, and an on-field down-and-distance marker, viewed from a raised broadcast camera with a
bottom score bug. Players have padded helmets, shoulder pads, belts, knee pads, socks, and shoulder numbers; road teams wear white. The wider sidelines include benches,
coaches, and 32 loosely scattered players per team between the 20-yard lines; they sway subtly and jump
to cheer during live plays.
Crowd characters face the field in team-heavy colors. Nearer rows use detailed Minecraft-style
models with faces, hair or caps, arm poses, and foam fingers; middle rows use lighter block models; farther
rows use pixel billboards, with each fan's detail tier randomly dithered across row boundaries. Block fans bounce in a GPU shader as plays heat up. The Swift/iOS app remains available in `App/`
and `Packages/`.

Open `project.godot` in Godot 4.4.1 or later and run the project. The Godot project uses the
Compatibility renderer and a 1280×720 landscape viewport. On desktop, the game starts centered on its
current display in the largest exact 16:9 window that fits within 75% of both the display's width and
height (1440×810 on a 1920×1080 display). Mobile, headless, and fullscreen launches are unchanged.
To run the deterministic gameplay tests:

```sh
godot --headless --path . --script res://godot/tests/test_simulation.gd
godot --headless --path . --script res://godot/tests/test_app_replay.gd
```

In-game controls: WASD/arrows or the left stick to move; J/K/L or X/A/B to select/pass; H or Y to
handoff; Space or the right trigger to turbo; U or the right shoulder to dive/tackle; I or Y on defense
to jump and block a pass; P/Escape or Menu to
pause. The developer overlay is on `~`, a three-finger tap, or the controller Back/Select button and
includes pause, slow-motion, autopilot, video toggles, and deterministic record/replay/verification.
Touch devices use the on-screen stick and contextual action buttons.

### Godot match flow

Before kickoff, a five-second warm-up pans across the home team and then the opponent, with
players jumping in two rows and a compact matchup banner highlighting the team on camera.
Games begin with **Ready to receive** and a playable kickoff return from your own 10-yard line.
An animated kick arcs toward the returner before the catch; movement and the game clock start
when the ball is caught.
After a touchdown (seven points, including the automatic extra point) or made field goal, a series
recap shows plays, yards, passing, rushing, first downs, possession time, and points. **Ready to kick**
or **Ready to receive** starts the next kickoff. The CPU receives to open the second half.

Opponent possessions are played live, not fast-forwarded. Select **Rush the QB**, **Man to Man**, or
**Zone Defense** before the CPU snap. You control the middle linebacker at the snap, switch to the
defender nearest the projected receiver on a pass, and switch to the nearest teammate when the ball
changes hands. Defense has turbo, dive/tackle, and jump/block. Interceptions and recovered fumbles
can be returned, including for touchdowns; the return's final spot sets the next possession.
Once the ball leaves the CPU quarterback or possession changes, defensive control keeps tracking
the teammate nearest the ball, with at least one second between automatic switches.
After an automatic switch on defense, the newly active player follows AI pursuit for one second
before stick/keyboard direction takes over. Turbo, dive/tackle, and jump remain available during
that transition; other defenders continue their coverage and pursuit.
The user-controlled defender has 10% faster turbo and 15% more dive travel; CPU defenders and
offensive movement are unchanged. Diving immediately transfers defensive control to the next
closest available teammate, bypassing the switch delay and excluding players already diving.

On fourth down at the **opponent's 40 or closer**, **Kick field goal** (F / controller X) displays
distance and success chance. Distance includes 17 yards for the snap and end zone; longer kicks
have lower seeded success probability. A miss gives the opponent the ball at the kicking spot.
Farther out, **Punt** (G / controller B) advances the ball 50 yards, capped at the opponent's 10.
You can still select and run an offensive play instead of kicking. The CPU uses the same fourth-down
kicking rules. Touch kicking buttons appear alongside the play cards. Block-kick formations are
reserved for a later update.

To package for another platform, install the matching Godot export template, add a preset for the
target in **Project → Export**, then export the project. The scene and input implementation are not
tied to Apple frameworks; platform-specific signing, store metadata, and export templates remain the
responsibility of the target platform.

Microsoft Store artwork, listing descriptions, and Windows screenshots are in
[`WindowsStore/`](WindowsStore/README.md), with scripts to rebuild the assets and recapture the game.

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

## Playing (Swift/iOS sandbox)

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

A subtle whistle sounds once when each on-field play ends, alongside cheers for big moments. It follows the
master and SFX volume controls and stays silent in the title-screen attract demo.

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
