# Craft Bowl — Build Plan

A modern-retro, blocky, AAA-looking American football game for iOS. It looks like a blocky dungeon-crawler and plays like simplified Tecmo Bowl. The target look is `docs/reference/target.jpg`, a night stadium with floodlights, a voxel crowd, a broadcast camera behind the QB, and chunky rigged players with overhead energy bars.

---

## 1. Pillars

1. **Readable in one glance.** It takes 3 seconds to pick a play and about 6 seconds to run one. Every decision is lane-based and shown on screen.
2. **One model, infinite players.** A single rigged player mesh. Skin, uniform colors, number, helmet style, armor pieces and body proportions are all instance data.
3. **Commitment gameplay.** Every play call trades something away. On offense it's more lanes or more protection. On defense it's cover the pass or send the middle linebacker.
4. **Stamina drives the drama.** Ball carriers tire and slow down. Turbo and dive are the answer, and endurance and power ratings make each player feel different.
5. **AAA retro.** Low-resolution pixel textures with high-quality modern lighting: shadows, bloom, AO, particles and temporal upscaling at 60 fps.

## 2. Platform & Tech Stack

| Area | Choice |
|---|---|
| Toolchain | Xcode 26, **iOS 26 SDK**, Swift 6 (strict concurrency) |
| Min device | A14 Bionic or later (Metal 4 GPU family). Unsupported devices get a friendly message screen |
| Graphics | **Metal 4** (`MTL4CommandQueue`, `MTL4CommandAllocator`, argument tables, residency sets), precompiled `.metallib`, **MetalFX** temporal upscaling (+ frame interpolation on Pro devices) |
| App shell | SwiftUI (menus, settings) hosting an `MTKView`-based game view; in-game HUD rendered in Metal for pixel-perfect scaling |
| Input | Touch virtual controls + **Game Controller** framework (MFi/Xbox/PlayStation), keyboard in Simulator |
| Audio | AVAudioEngine (music/SFX buses) + PHASE for spatial crowd |
| Haptics | Core Haptics (device) + GCController haptics |
| Persistence | SwiftData (rosters, settings, stats) |
| Platform | Game Center (achievements, leaderboards). Online multiplayer is post-1.0 |
| Art tools | Blockbench (model + rig + animation) → glTF → custom `cbasset` converter |
| CI | GitHub Actions macOS runner: build, unit tests, headless sim harness, shader compile |

### Module layout (Swift packages inside one Xcode workspace)

```
CraftBowl.xcworkspace
├─ App/                 SwiftUI app, scene, lifecycle, menus
├─ Packages/
│  ├─ CBCore            math, RNG (seeded), logging, config/tuning loading
│  ├─ CBSim             deterministic 60 Hz football simulation (no UIKit/Metal imports)
│  ├─ CBPlays           lane model, playbooks (data-driven JSON), play resolution
│  ├─ CBAI              teammate/opponent/coach AI
│  ├─ CBRender          Metal 4 renderer, render graph, materials, particles, post
│  ├─ CBAssets          runtime asset loading (.cbmesh/.cbanim/.cbtex)
│  ├─ CBAnimation       rigid-bone animation, blend trees
│  ├─ CBInput           touch + controller abstraction → GameActions
│  ├─ CBHUD             Metal-drawn HUD (scorebug, minimap, name tags, bars)
│  └─ CBAudio           music, SFX, crowd, haptics
└─ Tools/
   ├─ cbasset           glTF/PNG → runtime binary converter (Swift CLI)
   └─ simharness        headless play simulator for balance tuning
```

The simulation is **pure Swift and deterministic**: fixed 60 Hz tick with a seeded RNG, and rendering interpolates between ticks. That gives us unit-testable gameplay, headless balance runs, replays, and a path to online play later.

## 3. Rendering Plan (hitting the reference image)

**Frame graph:** GPU culling (compute) → cascaded shadow maps → depth prepass → forward+ clustered lighting (dozens of floodlight/stadium lights) → transparent/particles → post (SSAO composite, bloom, tone map, color-grade LUT, vignette) → MetalFX upscale → HUD.

**Look rules taken from the reference:**
- **Nearest-neighbor pixel textures** (16–32 texels per block face) on crisp cuboid geometry. No blurry filtering.
- Saturated turf green with pixel-noise and mowing stripes. White yard lines, hash marks and pixel-font yard numbers. End-zone wordmark.
- Night sky, **floodlight towers** with bloom glare, soft shadows under every player, and baked per-block AO plus SSAO.
- **Voxel crowd** in tiered bleachers. Thousands of GPU-instanced block people, palette-randomized with a bias toward team colors, bobbing and cheering on events.
- Sideline banners and ad boards with **fictional** brands, a tunnel, and a goalpost at the far end.
- VFX: dust puffs from cuts and sprints, turf chunks, impact sparks, and a yellow "power glow" sparkle on turbo or big hits (like #61 in the reference).

**Performance budget:** 60 fps locked at 1080p-class output via dynamic resolution + MetalFX, and under 900 MB memory. It watches `ProcessInfo.thermalState` and scales resolution and effects down under heat.

## 4. The One Player Model

A single Blockbench model with roughly 14 rigid bones (pelvis, spine, chest, head, 2×upper arm, 2×forearm, 2×hand, 2×thigh, 2×shin). Each vertex is bound to exactly one bone, so skinning costs about the same as instanced rigid transforms.

**Optional parts are part of the same mesh** and switched per instance with a visibility bitmask: classic helmet, knight-visor helmet (armored linemen in the reference), facemask, shoulder armor plates, hair styles for helmetless players, belt, wrist tape.

**Per-instance appearance data (GPU instance buffer):**

```swift
struct PlayerAppearance {
  var skinTone: UInt8          // index into ~12-tone natural palette
  var faceID: UInt8            // eyes/brows/facial hair atlas cell
  var hairID: UInt8
  var helmetStyle: HelmetStyle // none / classic / knight
  var partMask: UInt32         // visible optional parts
  var number: UInt8            // 0–99
  var bodyScale: SIMD3<Float>  // clamped: linemen wide, receivers lean
}
struct TeamUniform {
  var primary, secondary, trim, helmet, helmetStripe, pants, numberFill, numberOutline: SIMD3<Float>
}
```

**Shader recolor:** the albedo atlas is authored in grayscale shading plus a **mask texture** (R = skin, G = primary, B = secondary, A = trim/stripe). The fragment shader multiplies the shading by the palette color picked by the mask. **Numbers** come from a pixel-digit atlas mapped into fixed UV rectangles (back, front, both shoulders, helmet sides). That's how the reference shows "12" on the back and shoulders.

**Animations:** idle, stance (3-point/2-point/QB), run, sprint (turbo lean), backpedal, shuffle, throw, handoff/toss, catch (high/low/diving), block engage/drive, tackle, dive, stumble/fall/get-up, juke, stiff-arm, and celebrations. They blend in a small blend tree with procedural lean into turns and squash/stretch on impact.

## 5. Gameplay Design

### 5.1 Format

The format is **9-on-9**. It's smaller than 11, so it stays readable on a phone and Tecmo-simple, but it's big enough for real line play. It's defined in data (`Tuning/format.json`), but 9v9 is the shipped default.
- **Offense (9):** QB, RB, 3 lane players (Left / Center / Right), 4 offensive linemen (LT, LG, RG, RT).
- **Defense (9):** 3 DL (DE, NT, DE), **MLB** (middle linebacker, the key decision-maker), 1 OLB, 2 CB, 2 S (FS, SS).
- A lane player or the RB who is converted to a blocker joins the 4 linemen, for up to 7 blockers in Max Protect.

### 5.2 The 3+1 Lane System

The field ahead of the LOS is split into three **passing lanes**: **Left, Center, Right**. The **+1 lane** is the **Backfield/Run lane**, which belongs to the RB.

Every offensive play decides, for each of the 4 lane slots, whether that player is an **active target** or a **blocker**:

| Play (example) | L | C | R | RB | Extra blockers | Pocket time | Notes |
|---|---|---|---|---|---|---|---|
| Four Verticals | ✔ | ✔ | ✔ | ✔ (flat) | 0 | Short | All 4 options, weakest protection |
| Spread Pass | ✔ | ✔ | ✔ | block | 1 | Medium | Classic 3-lane pass |
| Max Protect Deep | ✔ | block | ✔ | block | 2 | Long | Two deep shots, QB is safe |
| Power Run | block | ✔ (TE-style) | block | ✔ | 2 lead | — | Run-first, fake one pass |
| Toss Sweep L/R | ✔ | block | block | ✔ toss | 2 | — | Outside run, pitch |
| Play-Action Shot | ✔ | ✔ | block | fake | 1 | Medium | Freezes a run-committed MLB |
| Screen | block | block | ✔ | ✔ (screen) | 2 | Short | Beats blitz |
| QB Keeper | ✔ | ✔ | ✔ | block | 1 | — | Scramble-friendly |

Pocket time comes from `blockers × power` versus the rushers the defense commits. Converting a lane player into a blocker **removes that pass/handoff button** for the play, adds protection or a lead blocker, and reveals less to the defense.

### 5.3 Defensive Calls

The defense chooses **how to cover the lanes** and **what the MLB does**:

| Call | Coverage | MLB | Strong vs | Weak vs |
|---|---|---|---|---|
| Zone 3 | Each defender owns a lane, S deep | Drops to center zone | 3-lane passing | Runs, 4-verts flat |
| Man | Each lane player shadowed | Free: reads RB | Short passes | Deep/crossers with speed |
| MLB Blitz | Man outside | **Rushes QB** | Pass (fast pressure) | Center lane open, screens |
| Run Stuff | Soft zone | **Fills backfield** | Runs/tosses | Play-action, deep pass |
| QB Spy | Zone | Shadows QB | Scrambles/keepers | Deep outside |
| Prevent | Deep zones | Middle deep | Long passes | Everything underneath |

The core read is: **does the MLB stay home to protect the pass, or commit to the QB or runner?**

### 5.4 Play Flow & Controls

1. **Play select.** Tecmo-style 4-card quick grid (bottom-right in the reference) plus a full PLAYS book. Both sides pick at the same time, with a short timer.
2. **Snap → QB phase (behind the LOS).** Contextual big buttons: **Pass L / Pass C / Pass R / Hand off (or Toss)**. A button only appears if the play uses that lane. Lanes glow by openness (green/yellow/red). The left stick scrambles. Throws auto-lead the target, and stat-based accuracy wobble adds risk under pressure.
3. **Runner phase.** Once the ball carrier crosses the LOS, or the ball is caught beyond it, controls switch to **Stick + Turbo + Dive** (Stiff-arm/Juke as a P1 stretch).
4. **The offensive user always controls the ball carrier.** Control transfers automatically on handoff or catch.
5. **Defensive user:** **Switch** cycles through the key defenders (MLB → OLB → CB L → CB R → FS → SS), **Nearest** jumps to the defender closest to the ball, with an optional auto-switch setting. Actions are Turbo, Dive Tackle, and Jump/Swat while the ball is in the air.

### 5.5 Energy, Turbo & Ratings

- **Ratings (1–99):** **Power** (break tackles, win blocks, tackle strength), **Speed** (top speed, acceleration), **Endurance** (energy drain and turbo capacity). Position modifiers derive QB arm/accuracy and WR hands.
- **Energy:** the ball carrier's energy drains over time (faster when cutting, slower for high endurance). Top speed scales with energy: `v = vmax × lerp(0.72, 1.0, energy)`.
- **Turbo:** a separate burst meter that temporarily lifts speed above normal and drains fast, recharging when not in use. Tired runners **must** turbo to break away, which makes timing matter. Defenders have turbo too.
- **Dive:** ends the carrier's play with a lunge for extra yards (distance scales with speed). A defender's dive tackle has long reach but whiffs cost recovery time.
- **Contact:** tackle success weighs `defender.power + momentum` against `carrier.power + speed×energy + small RNG`. Broken tackles cause a stumble and slow the carrier.
- Overhead **energy bars** (reference) show on the carrier and nearby defenders.

### 5.6 Rules (simplified)

Downs & distance, 4 quarters (2–5 min, configurable), play clock, TD (6) + PAT choice (auto kick 1 / go-for-2 from lane play), FG via a simple timing meter, punt on 4th down via one button, kickoffs with a timing meter and returns, safeties, interceptions and fumbles (rare), sudden-death OT. No penalties in v1.

## 6. AI

- **Teammates:** receivers run lane route templates with separation logic, blockers pick up rushers by threat, RB follows the lead blocker to the hole, and pursuit angles use intercept prediction.
- **Defense:** zone drops with lane ownership, man trail and undercut, MLB blitz/spy/run-fill behaviors, tackle decisions based on reach and power.
- **CPU coach:** play-calling from down, distance, field position, score, clock and learned user tendencies (per-difficulty memory). Three difficulty levels change reaction time, accuracy and play-call quality, never ratings.

## 7. Camera, HUD & Feel

- **Broadcast camera:** elevated, behind the offense, looking downfield (the reference framing). It follows the ball carrier with look-ahead, pulls back on passes, and has celebration and replay angles plus camera shake on big hits.
- **HUD** (pixel font, Metal-drawn): center-top scorebug (team color banners and score), down & distance plus quarter/clock at top-right with a possession arrow, **minimap** at bottom-left, **name tag** on the controlled player ("ARMORED ARTHO #12"), overhead energy bars, and the action-button cluster at bottom-right.
- **Juice:** hit-stop frames on tackles, slow-motion on TD and interception, confetti and crowd surge, first-down line flash, and haptics for catches, hits and turbo.
- **Audio:** chip-tune plus orchestral hybrid score, reactive crowd (PHASE), crunchy block-impact SFX, whistles, and short announcer stingers.

## 8. Milestones

| # | Milestone | Outcome |
|---|---|---|
| M0 | Foundation | Project, modules, CI, game loop, input, debug tools |
| M1 | Metal 4 Renderer | Frame graph, lighting, shadows, instancing, post, MetalFX |
| M2 | Player Model & Customization | One rigged model, recolor, numbers, parts, animations |
| M3 | Field & Stadium | Field, stadium, floodlights, crowd, sidelines |
| M4 | Core Simulation | Ratings, locomotion, energy/turbo, ball, contact, rules |
| M5 | Lanes & Playbooks | Lane system, offense/defense plays, resolution, tuning harness |
| M6 | Controls & HUD | QB/runner/defense controls, touch + controller, HUD, menus |
| M7 | AI | Teammate, defensive and coach AI, difficulty |
| M8 | Camera, Audio & Feel | Broadcast camera, VFX juice, audio, haptics |
| M9 | Modes & Platform | Exhibition/practice, teams, saves, Game Center |
| M10 | Ship Quality | Perf, tests, reference-match review, TestFlight |

**Vertical-slice gate (after M6):** one full drive, 9v9, on a lit field with recolored players, lane passing and runs, energy/turbo/dive, and the HUD. It must read like the reference image in a side-by-side screenshot.

**Definition of done (overall):** a side-by-side capture with the reference passes the `docs/reference` visual checklist (see the "Reference visual match review" issue), it holds 60 fps on iPhone 13 and up, and a full exhibition game plays start to finish against the CPU.

## 9. Key Risks

| Risk | Mitigation |
|---|---|
| Metal 4 API maturity / device floor | Keep the render graph abstract; decide on a Metal 3 fallback at the M1 review |
| "AAA retro" is subjective | Lock the reference image and a color LUT early, and hold a weekly screenshot review against the checklist |
| Lane gameplay becomes solvable | Headless sim harness with a 10k-play matchup matrix, and CPU coach tendency learning |
| Touch controls feel cramped | Contextual buttons only (≤4 at once), size and handedness options, full controller support |
| Crowd/particles blow the thermal budget | GPU-driven instancing, LODs, and thermal-state scaling |

## 10. Working Agreement

- Every issue carries a milestone, an `area:*` label and a priority.
- Gameplay numbers live in `Resources/Tuning/*.json`, never hard-coded.
- Any PR that changes visuals attaches a before/after screenshot captured from the same debug camera preset (`cam.reference`).
