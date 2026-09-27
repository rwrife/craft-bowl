#!/usr/bin/env python3
"""Create Craft Bowl labels, milestones and issues on GitHub via the gh CLI (REST only).

Usage:
    gh auth login                       # once
    python3 scripts/create_issues.py --dry-run
    python3 scripts/create_issues.py    # repo defaults to rwrife/craft-bowl
    python3 scripts/create_issues.py --repo owner/name

Idempotent: existing labels, milestones and issues (matched by exact title) are skipped.
Cross references like {{C3}} in bodies are rewritten to #<issue number>.
"""
import argparse, json, re, subprocess, sys

REPO = "rwrife/craft-bowl"
REF = "Visual target: `docs/reference/target.jpg`. Design doc: `docs/PLAN.md`."

LABELS = {
    "type:epic": "5319e7", "type:feature": "1d76db", "type:chore": "c5def5",
    "area:engine": "0e8a16", "area:rendering": "d93f0b", "area:art": "e99695",
    "area:gameplay": "fbca04", "area:ai": "bfd4f2", "area:ui": "f9d0c4",
    "area:audio": "c2e0c6", "area:tools": "bfdadc", "area:qa": "d4c5f9",
    "priority:p0": "b60205", "priority:p1": "ff9f1c", "priority:p2": "cccccc",
}

MILESTONES = [
    ("M0 Foundation", "Project, modules, CI, game loop, input, debug tools"),
    ("M1 Metal 4 Renderer", "Frame graph, lighting, shadows, instancing, post, MetalFX"),
    ("M2 Player Model & Customization", "One rigged model, recolor, numbers, parts, animations"),
    ("M3 Field & Stadium", "Field, stadium, floodlights, crowd, sidelines"),
    ("M4 Core Simulation", "Ratings, locomotion, energy/turbo, ball, contact, rules"),
    ("M5 Lanes & Playbooks", "3+1 lane system, offense/defense plays, resolution, tuning"),
    ("M6 Controls & HUD", "QB/runner/defense controls, touch + controller, HUD, menus — vertical slice gate"),
    ("M7 AI", "Teammate, defensive and coach AI, difficulty"),
    ("M8 Camera, Audio & Feel", "Broadcast camera, VFX juice, audio, haptics"),
    ("M9 Modes & Platform", "Exhibition/practice, teams, saves, Game Center"),
    ("M10 Ship Quality", "Perf, tests, reference match review, TestFlight"),
]


def issue(key, ms, title, labels, summary, tasks, accept, deps=()):
    return dict(key=key, ms=ms, title=title, labels=labels, summary=summary,
                tasks=tasks, accept=accept, deps=list(deps))


I = []  # issues, in creation order
m = lambda n: MILESTONES[n][0]

# ---------------- M0 Foundation ----------------
I += [
 issue("F1", m(0), "Create Xcode 26 workspace, app target and Swift package modules",
   ["type:chore", "area:engine", "priority:p0"],
   "Bootstrap the project on the iOS 26 SDK with Swift 6 strict concurrency and the module layout from PLAN.md §2.",
   ["Xcode 26 workspace `CraftBowl.xcworkspace`, iOS 26 deployment target, landscape-only, ProMotion enabled (`CADisableMinimumFrameDurationOnPhone`)",
    "SwiftUI `App` hosting a `UIViewRepresentable` `MTKView` game view",
    "Local SPM packages: CBCore, CBSim, CBPlays, CBAI, CBRender, CBAssets, CBAnimation, CBInput, CBHUD, CBAudio",
    "CBSim/CBPlays/CBAI must not import UIKit/Metal (enforced by package deps)",
    "Runtime Metal 4 capability check → 'device not supported' screen",
    "README with build instructions"],
   ["App launches to a clear-colored Metal view on device and Simulator", "All packages build and have an empty test target"]),
 issue("F2", m(0), "GitHub Actions CI: build, test, shader compile, lint",
   ["type:chore", "area:tools", "priority:p0"],
   "Continuous integration on macOS runners so every PR proves it builds and passes tests.",
   ["Workflow: `xcodebuild build test` for the app scheme on an iOS Simulator destination",
    "Compile `.metal` sources into `.metallib` as a separate step (fail on warnings)",
    "swift-format lint step", "Cache DerivedData / SPM", "Upload test results + headless sim report (later, see {{L6}})"],
   ["CI green on main", "PRs blocked on failing CI"], ["F1"]),
 issue("F3", m(0), "Fixed-timestep deterministic game loop + ECS-lite world",
   ["type:feature", "area:engine", "priority:p0"],
   "The simulation ticks at a fixed 60 Hz, fully deterministic with a seeded RNG; rendering interpolates between the last two sim states.",
   ["`GameClock` with accumulator, max catch-up steps, pause/slow-mo scale",
    "`World` with dense component arrays (Transform, Kinematics, Player, Ball, AIState, Appearance) and entity IDs",
    "Seeded PCG RNG in CBCore; no `random()` anywhere in sim code (lint rule)",
    "State snapshot + interpolation for renderer", "Record/replay of input stream for bug repro"],
   ["Replaying a recorded input stream reproduces identical positions (unit test)", "Sim runs headless in tests"], ["F1"]),
 issue("F4", m(0), "Debug tooling: debug draw, dev overlay, tuning hot-reload",
   ["type:feature", "area:tools", "priority:p1"],
   "Tools to see what the sim and renderer are doing.",
   ["Metal debug-line/shape renderer (lanes, routes, collision circles, pursuit targets)",
    "Dev overlay (3-finger tap / controller combo): FPS, GPU time, sim tick time, entity inspector",
    "Load `Resources/Tuning/*.json` and hot-reload from a local HTTP/file watch in debug builds",
    "Camera presets incl. `cam.reference` matching the reference framing"],
   ["Can toggle lanes/routes debug draw at runtime", "Editing tuning JSON changes speeds without rebuild in debug"], ["F3"]),
 issue("F5", m(0), "Input abstraction: touch + Game Controller → GameActions",
   ["type:feature", "area:engine", "priority:p0"],
   "Map touch, MFi/Xbox/PlayStation controllers and Simulator keyboard to a single `GameAction` stream consumed by the sim.",
   ["`GameAction` enum: move(vector), passLeft/Center/Right, handoff, turbo, dive, switchPlayer, switchNearest, swat, pause, playSelect(n)",
    "`GCController` connect/disconnect handling, per-controller player assignment (1–2 local players)",
    "Keyboard mapping for Simulator", "Touch layer placeholder (real layout in {{I4}})"],
   ["Actions from all three sources appear identically in the dev overlay"], ["F3"]),
]

# ---------------- M1 Renderer ----------------
I += [
 issue("R1", m(1), "Metal 4 renderer bootstrap (command queue, allocators, argument tables, residency)",
   ["type:feature", "area:rendering", "priority:p0"],
   "Core Metal 4 setup that all passes build on.",
   ["`MTL4CommandQueue`, one `MTL4CommandAllocator` per in-flight frame (3), frame pacing with shared events",
    "Argument tables + residency sets for buffers/textures; bindless material/texture heap",
    "Precompiled `.metallib`, pipeline state cache warmed at load (no hitches in gameplay)",
    "Per-frame uniform ring buffers", "GPU capture scopes named per pass"],
   ["Renders a lit test cube at 60 fps with zero per-frame allocations (Instruments)"], ["F1"]),
 issue("R2", m(1), "Render graph with shadow, depth-prepass, forward+ and post passes",
   ["type:feature", "area:rendering", "priority:p0"],
   "Declarative frame graph (PLAN.md §3) managing transient attachments and pass ordering.",
   ["Passes: GPU cull → cascaded shadows → depth prepass → forward+ (clustered lights) → transparent/particles → post → upscale → HUD",
    "Transient memoryless attachments where possible (TBDR-friendly)",
    "Per-pass GPU timing in dev overlay"],
   ["Passes can be toggled in dev overlay", "GPU frame < 10 ms on iPhone 13 with test scene"], ["R1"]),
 issue("R3", m(1), "Stylized retro-block lighting & materials",
   ["type:feature", "area:rendering", "area:art", "priority:p0"],
   "The core 'AAA retro' look: crisp nearest-sampled pixel textures under modern lighting.",
   ["Nearest-neighbor sampling for albedo, mip-bias tuned to avoid shimmer (+ TAA via MetalFX)",
    "Lighting: wrapped diffuse + subtle rim light, clustered point/spot lights for floodlights",
    "Cascaded shadow maps (3 cascades) with PCF soft edges; contact shadow blobs under players",
    "Baked per-block AO in vertex colors + SSAO",
    "Night sky gradient + stars, exposure tuned for floodlit night"],
   ["Side-by-side of a test player on turf reads like the reference (blocky, crisp, soft-shadowed)"], ["R2"]),
 issue("R4", m(1), "GPU-driven instanced rendering + culling",
   ["type:feature", "area:rendering", "priority:p0"],
   "Draw 18 players, thousands of crowd members and props cheaply.",
   ["Per-instance buffers (transform, appearance, uniform palette index, bone palette offset)",
    "Compute frustum + distance-LOD culling writing indirect draw args",
    "Instanced rigid-bone skinning (bone matrices in a structured buffer)"],
   ["10k crowd instances + 18 players at 60 fps on iPhone 13"], ["R2"]),
 issue("R5", m(1), "Post-processing stack + MetalFX upscaling",
   ["type:feature", "area:rendering", "priority:p1"],
   "Bloom on floodlights, color grade matching the reference, dynamic resolution.",
   ["Bloom (dual-filter) with threshold tuned for light towers and glow VFX",
    "ACES-ish tone map + 3D color-grade LUT authored against the reference (saturated greens, deep blue night)",
    "Vignette, optional subtle chromatic edge off by default",
    "MetalFX temporal upscaler with motion vectors + jitter; frame interpolation on supported Pro devices",
    "Dynamic resolution controller targeting 16.6 ms"],
   ["Toggling LUT on/off in overlay shows reference-like grade", "Stable 60 fps under dynamic resolution"], ["R3"]),
 issue("R6", m(1), "Compute particle system (dust, turf, impact, glow, confetti)",
   ["type:feature", "area:rendering", "priority:p1"],
   "Blocky particles like the dust puff and power glow in the reference.",
   ["GPU particle buffers, emit from sim events (cut, sprint start, tackle, catch, TD)",
    "Cube/quad pixel particles lit by scene lights", "Presets: dust, turf chunks, impact stars, turbo sparkle glow, confetti"],
   ["Dust puff when a runner cuts; yellow sparkle glow on turbo"], ["R4"]),
 issue("R7", m(1), "Thermal & performance scaling",
   ["type:feature", "area:rendering", "priority:p1"],
   "Keep 60 fps on long sessions.",
   ["Observe `ProcessInfo.thermalState`; quality tiers (shadow res, SSAO, crowd density, particle caps, render scale)",
    "Per-device default tier table (A14 → A19 Pro)", "Battery/Low Power Mode respect"],
   ["30-minute soak on iPhone 13 holds ≥ 58 fps median"], ["R5"]),
]

# ---------------- M2 Player model ----------------
I += [
 issue("P1", m(2), "Author the single base player model + rig (Blockbench)",
   ["type:feature", "area:art", "priority:p0"],
   "ONE model for every player. Chunky proportions matching the reference: big cube head/helmet, broad shoulders, cuboid limbs.",
   ["~14 rigid bones (pelvis, spine, chest, head, upper/fore arms, hands, thighs, shins); 1 bone per vertex",
    "Optional parts in the same mesh, grouped for a visibility bitmask: classic helmet, knight-visor helmet, facemask, shoulder armor plates, hair styles (for helmetless look), belt, wrist tape",
    "UV layout reserves fixed rects for numbers (back, front, L/R shoulder, helmet sides)",
    "Export glTF; document rig spec in `docs/art/player-rig.md`"],
   ["Model imports via {{P4}} and renders with correct bones", "All optional parts toggle independently"]),
 issue("P2", m(2), "Mask-based recolor shader: skin tone, primary/secondary/trim, helmet, pants",
   ["type:feature", "area:rendering", "area:art", "priority:p0"],
   "Every player is unique through instance data, not new textures.",
   ["Grayscale-shaded albedo atlas + RGBA mask (R skin, G primary, B secondary, A trim/stripe)",
    "`TeamUniform` palette buffer (primary, secondary, trim, helmet, stripe, pants, numberFill, numberOutline)",
    "~12-tone natural skin palette; per-instance skin index",
    "Face/hair atlas cells selectable per instance"],
   ["Blue/gold and red/black teams from the reference reproduce with one texture set", "Changing a color in the overlay updates live"], ["P1", "R3"]),
 issue("P3", m(2), "Jersey number decals (0–99) in shader",
   ["type:feature", "area:rendering", "priority:p0"],
   "Pixel-font numbers on back, front, shoulders and helmet sides like the '12' in the reference.",
   ["Digit atlas (pixel font) with outline", "Shader maps number UV rects → digit cells from per-instance number; 1- and 2-digit layouts",
    "Uses numberFill / numberOutline from team palette"],
   ["Any number 0–99 renders crisply at all camera distances"], ["P2"]),
 issue("P4", m(2), "Asset pipeline: `cbasset` converter (glTF/PNG → runtime binaries)",
   ["type:feature", "area:tools", "priority:p0"],
   "Swift CLI in `Tools/cbasset` producing fast-loading assets.",
   [".cbmesh (interleaved vertices, bone index, part group id), .cbanim (per-bone keyframes), .cbtex (pixel textures, no mips or manual mips)",
    "Validation: bone count, 1-bone binding, UV number rects present", "Xcode build-phase integration + CI step"],
   ["Model + animations load in < 50 ms on device"], ["F1"]),
 issue("P5", m(2), "Rigid-bone animation system + blend tree",
   ["type:feature", "area:engine", "area:art", "priority:p0"],
   "Drive the one rig from sim state.",
   ["Clips: idle, stance (3-pt/2-pt/QB), run, sprint (turbo lean), backpedal, shuffle, throw, handoff/toss, catch (high/low/dive), block engage/drive, tackle, dive, stumble, fall/get-up, juke, stiff-arm, celebrations ×3",
    "Blend tree driven by speed/turn/state; additive upper-body (throw while moving)",
    "Procedural lean into turns, squash on impact, head look-at ball",
    "Speed-matched run cycles (no foot sliding at 0.72–1.2× speed)"],
   ["All clips play in an animation viewer scene", "Runner visibly slows/leans as energy drops"], ["P4", "R4"]),
 issue("P6", m(2), "Body proportion variation via clamped per-instance bone scales",
   ["type:feature", "area:rendering", "priority:p1"],
   "Linemen look wide and armored, receivers lean — still one model.",
   ["Per-instance scale on chest/shoulders/limbs within limits", "Position presets (OL/DL wide, WR/CB lean, RB compact)",
    "Collision radius derived from scale in sim"],
   ["Lineup screenshot shows clear silhouettes per position"], ["P5"]),
 issue("P7", m(2), "PlayerAppearance/TeamUniform data + roster & name generator",
   ["type:feature", "area:gameplay", "priority:p1"],
   "Data model and generator that produce unique players ('ARMORED ARTHO #12').",
   ["`PlayerAppearance` + `TeamUniform` Codable structs (PLAN.md §4)", "Generator: seeded appearance, unique numbers per team, position-appropriate helmet/armor",
    "Fantasy-flavored name generator (adjective + name), profanity filter"],
   ["Generating 8 teams yields no duplicate numbers within a team"], ["P2", "P3"]),
]

# ---------------- M3 Field & stadium ----------------
I += [
 issue("S1", m(3), "Football field: turf, lines, numbers, end zones, goalposts",
   ["type:feature", "area:art", "area:rendering", "priority:p0"],
   "The field exactly as in the reference.",
   ["100 yd + end zones, correct hash marks and yard lines", "Pixel-font yard numbers with arrows", "Turf: saturated green, pixel noise, mowing stripes",
    "End-zone wordmark, sideline border, pylons, block-style goalposts (yellow)",
    "Line of scrimmage + first-down marker overlays (toggle)"],
   ["Screenshot from `cam.reference` matches field layout of the reference"], ["R3"]),
 issue("S2", m(3), "Stadium environment: bleachers, floodlight towers, banners, tunnel",
   ["type:feature", "area:art", "priority:p0"],
   "Night stadium surrounding the field.",
   ["Tiered voxel bleachers on 3 sides + end-zone stand with tunnel", "Floodlight towers (light banks as emissive blocks + actual spot lights)",
    "Sideline ad boards / banners with FICTIONAL brands only", "Railings, stairs, background trees/skyline silhouettes"],
   ["Scene holds budget in {{R7}} tiers"], ["S1", "R4"]),
 issue("S3", m(3), "Instanced voxel crowd with reactive animation",
   ["type:feature", "area:rendering", "area:art", "priority:p1"],
   "Thousands of blocky fans like the reference.",
   ["Low-poly crowd person (reuse palette mask approach), random colors weighted to home/away team",
    "Vertex-shader idle bob, cheer, stand-up wave driven by excitement value from sim events",
    "LOD: far rows as impostor cards"],
   ["Crowd erupts on TD; 10k fans within budget"], ["S2"]),
 issue("S4", m(3), "Sideline personnel using the player model",
   ["type:feature", "area:art", "priority:p2"],
   "Coaches/benched players on sidelines (reference shows sideline characters).",
   ["Reuse player model with no helmet/cap variants", "Idle/cheer anims, cheap LOD"],
   ["Sidelines populated without additional meshes"], ["S2", "P5"]),
]

# ---------------- M4 Core sim ----------------
I += [
 issue("C1", m(4), "Player ratings: Power, Speed, Endurance (+ derived position traits)",
   ["type:feature", "area:gameplay", "priority:p0"],
   "The three core ratings that make players feel different.",
   ["Ratings 1–99; derived: accel, top speed, turn rate, block/tackle strength, energy drain, turbo capacity, QB arm/accuracy, WR hands",
    "Tuning curves in `Tuning/ratings.json`", "Team overall = weighted rating"],
   ["Unit tests: higher Speed → higher top speed; higher Endurance → slower drain"], ["F3"]),
 issue("C2", m(4), "Locomotion, steering and collision",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Kinematic movement that feels arcade-tight.",
   ["Acceleration/decel, turn rate limited by speed, momentum", "Circle collisions with pushing weighted by Power",
    "Field bounds, out-of-bounds ends play", "Pathing helpers (arrive, pursue, avoid)"],
   ["Players never overlap; OOB detected correctly"], ["C1"]),
 issue("C3", m(4), "Energy drain + Turbo meter for ball carriers and defenders",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Carriers slowly tire and slow down, forcing turbo use (PLAN.md §5.5).",
   ["Energy drains while carrying (faster on cuts), recovers between plays; `v = vmax * lerp(0.72, 1, energy)`",
    "Turbo: separate burst meter, speed multiplier, fast drain, recharge delay; Endurance scales capacity",
    "Defenders get turbo too", "Expose values to HUD overhead bars ({{I5}})"],
   ["Long runs visibly slow without turbo; turbo spent at the right moment breaks a pursuit angle"], ["C2"]),
 issue("C4", m(4), "Ball physics: passes, catches, handoffs, tosses, fumbles",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Ball states and flight.",
   ["States: held, snapped, in-air(pass/toss), loose, dead", "Pass arcs with lead targeting toward lane receiver, arm-based velocity, pressure-based wobble",
    "Catch resolution (hands vs defender contest, swats, INTs)", "Handoff/toss exchange windows", "Rare fumbles on big hits (tunable)"],
   ["Headless tests: open receiver catch rate ≥ 90%, contested ≈ 50% (tunable)"], ["C2"]),
 issue("C5", m(4), "Contact: blocking, tackles, broken tackles, dives",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Physical resolution driven by ratings and momentum.",
   ["Block engagement: power vs power, drive-back, shed timer", "Tackle chance: defender power+momentum vs carrier power+speed*energy+RNG",
    "Broken tackle → stumble/slowdown", "Dive (carrier): lunge for yards, ends play; dive tackle (defender): long reach, whiff recovery",
    "Pile/whistle logic"],
   ["High-Power RB breaks weak-DB tackles more often in harness runs"], ["C3", "C4"]),
 issue("C6", m(4), "Game rules: downs, clock, scoring, kicks, turnovers, OT",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Simplified football rules (PLAN.md §5.6).",
   ["LOS, first-down line, 4 downs, possession changes", "Quarter length config (2–5 min), clock stops on incompletions/OOB/scores, play clock",
    "TD, PAT (kick 1 / lane play for 2), FG timing meter, punt button on 4th, safety",
    "Kickoff with timing meter + return", "Sudden-death OT"],
   ["Full headless game completes with consistent score/clock state"], ["C5"]),
]

# ---------------- M5 Lanes & Playbooks ----------------
I += [
 issue("L1", m(5), "3+1 lane system: Left/Center/Right pass lanes + Backfield run lane",
   ["type:feature", "area:gameplay", "priority:p0"],
   "The core structural idea of Craft Bowl (PLAN.md §5.2).",
   ["Lane corridor geometry relative to LOS and ball spot (handles hash position)",
    "Lane slot occupants (L, C, R, RB); route templates per lane (short, mid, deep, flat, screen)",
    "Per-lane 'openness' metric from separation + defenders in corridor, for UI + AI",
    "Debug draw lanes/openness"],
   ["Openness updates every tick and matches intuition in debug view"], ["C2"]),
 issue("L2", m(5), "Data-driven offensive playbook (lane allocation vs protection)",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Offense chooses which of the 4 lane slots are active and which convert to blockers.",
   ["`OffensivePlay` JSON: per-slot role (target/blocker/lead/fake), route variant, formation, protection",
    "9v9 formation: QB, RB, L/C/R, 4 OL; converted slots add blockers (up to 7)",
    "Starter book: Four Verticals, Spread Pass, Max Protect Deep, Power Run, Toss Sweep L/R, Play-Action Shot, Screen, QB Keeper",
    "Pocket time = f(blockers*power vs rushers)"],
   ["Each play in the book runs correctly in practice mode"], ["L1", "C6"]),
 issue("L3", m(5), "Data-driven defensive playbook (zone/man/blitz/MLB commitment)",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Defense decides coverage and whether the MLB protects the pass or attacks the QB/runner (PLAN.md §5.3).",
   ["9v9 defense: 3 DL, MLB, OLB, 2 CB, 2 S", "`DefensivePlay` JSON: per-defender assignment (zone lane, man target, rush, spy, run-fill)",
    "Starter book: Zone 3, Man, MLB Blitz, Run Stuff, QB Spy, Prevent"],
   ["Each call produces visibly different behavior in debug view"], ["L1", "C6"]),
 issue("L4", m(5), "Play execution: formations, snap, pocket pressure, run holes",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Turn two play cards into a live play.",
   ["Formation placement relative to ball + hash", "Snap sequence, rush timer, pressure → sack",
    "Run holes emerge from blocker assignments vs defensive fills", "QB crossing LOS → runner state; pass caught beyond LOS → runner state"],
   ["Blitz vs Four Verticals yields fast pressure; Run Stuff vs Power Run closes holes"], ["L2", "L3", "C5"]),
 issue("L5", m(5), "Play selection flow (Tecmo-style 4-card grid + full PLAYS book)",
   ["type:feature", "area:ui", "area:gameplay", "priority:p0"],
   "Fast, simultaneous play picking.",
   ["Quick grid of 4 cards (bottom-right cluster in reference) + PLAYS button opens full book",
    "Card art shows lane usage icons (which lanes are live, blockers)", "Simultaneous pick with timer; CPU pick hidden",
    "Controller + touch support"],
   ["Average play-select under 3 s in playtests"], ["L2", "L3", "I4"]),
 issue("L6", m(5), "Headless sim harness + offense×defense matchup balance matrix",
   ["type:feature", "area:tools", "area:qa", "priority:p1"],
   "Keep the rock-paper-scissors balanced.",
   ["`Tools/simharness` runs N plays per matchup with AI-driven users", "Outputs yards/play, completion %, sack %, TD % heatmap (CSV + HTML)",
    "CI job with regression thresholds (no play dominant > X yards/play across all defenses)"],
   ["Matrix report produced in CI on every tuning change"], ["L4", "A1", "A2"]),
]

# ---------------- M6 Controls & HUD ----------------
I += [
 issue("I1", m(6), "QB controls behind the line: Pass L/C/R + Handoff/Toss + scramble",
   ["type:feature", "area:gameplay", "area:ui", "priority:p0"],
   "Easy pass/run options while the QB is behind the LOS.",
   ["Contextual buttons only for lanes the play uses; RB handoff/toss only if RB is a target",
    "Lane openness glow (green/yellow/red) on field", "Stick scrambles; crossing LOS switches to runner controls",
    "Throw auto-leads receiver; pressure adds wobble"],
   ["Never more than 4 action buttons on screen", "Button availability always matches the called play"], ["L4", "F5"]),
 issue("I2", m(6), "Ball-carrier controls: move, Turbo, Dive (+ stiff-arm/juke stretch)",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Runner controls once past the LOS or after a catch beyond it. The offensive user always controls the ball carrier.",
   ["Auto control transfer on handoff/catch", "Turbo (hold), Dive (tap)", "Stretch (P1): stiff-arm (Power), juke (Speed)"],
   ["Control transfers within 1 tick of possession change"], ["I1", "C3", "C5"]),
 issue("I3", m(6), "Defensive controls: switch key defenders, switch-to-nearest, turbo, dive, swat",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Defensive user control options.",
   ["Switch cycles MLB → OLB → CB L → CB R → FS → SS", "Nearest-to-ball button; optional auto-switch setting",
    "Pre-snap: pick which defender to start with", "Turbo, dive tackle, jump/swat when ball in air"],
   ["Switching feels instant; selected defender clearly marked"], ["L4", "F5"]),
 issue("I4", m(6), "Touch control layout + controller mapping + haptic hooks",
   ["type:feature", "area:ui", "priority:p0"],
   "Mobile-first controls matching the reference cluster.",
   ["Left floating virtual stick; right 2×2 action cluster + PLAYS button (reference bottom-right)",
    "Icons change per phase (pre-snap/QB/runner/defense)", "Size, opacity, left-handed mirror options",
    "Controller glyphs for Xbox/PS/MFi"],
   ["Playable one-handed-thumbs on iPhone mini/SE-class widths and Pro Max"], ["F5"]),
 issue("I5", m(6), "In-game HUD: scorebug, down & distance, clock, minimap, name tag, energy bars",
   ["type:feature", "area:ui", "area:rendering", "priority:p0"],
   "Metal-drawn pixel HUD matching the reference layout.",
   ["Center-top scorebug: team-colored banners + score box", "Top-right: down & distance, quarter + clock, possession arrow",
    "Bottom-left minimap with team-colored dots and ball", "Name tag panel on controlled player ('ARMORED ARTHO #12')",
    "Overhead energy/turbo bars on carrier + nearby defenders", "Pixel font with integer scaling; safe-area aware"],
   ["HUD screenshot overlays the reference layout within a few % positioning"], ["C6", "P7"]),
 issue("I6", m(6), "Menus in SwiftUI: title, team select & uniform customizer, settings, pause",
   ["type:feature", "area:ui", "priority:p1"],
   "Pixel-styled front end.",
   ["Title with animated stadium background (render view behind SwiftUI)", "Team select with live 3D player preview + color/number/skin customization",
    "Settings: controls, audio, quality, quarter length, difficulty", "Pause menu"],
   ["Full flow title → team select → game → pause → quit works on controller and touch"], ["P7"]),
]

# ---------------- M7 AI ----------------
I += [
 issue("A1", m(7), "Offensive teammate AI: routes, pass pro, run blocking, RB vision",
   ["type:feature", "area:ai", "priority:p0"],
   "Non-controlled offensive players execute the play convincingly.",
   ["Receivers run lane routes with separation moves, come back to ball", "Blockers pick up rushers by threat; lead blockers kick out",
    "RB follows lead blocker to hole", "CPU QB reads lanes by openness"],
   ["Routes/blocking look correct in 20 recorded plays review"], ["L4"]),
 issue("A2", m(7), "Defensive AI: zone drops, man coverage, blitz, spy, pursuit",
   ["type:feature", "area:ai", "priority:p0"],
   "Defenders execute calls and pursue with good angles.",
   ["Zone lane ownership + hand-offs", "Man trail/undercut based on Speed", "MLB behaviors: drop, blitz path, spy, run-fill",
    "Pursuit with intercept prediction; tackle/dive decision"],
   ["CPU defense stops obvious mismatches in harness at expected rates"], ["L4"]),
 issue("A3", m(7), "CPU coach play-calling with tendency learning",
   ["type:feature", "area:ai", "priority:p1"],
   "CPU calls plays like a smart opponent.",
   ["Situational weights (down, distance, field pos, score, clock)", "Tracks user tendencies (per game) and counters them",
    "Hidden simultaneous pick"],
   ["User spamming one play sees it countered within ~5 calls"], ["A1", "A2"]),
 issue("A4", m(7), "Difficulty levels",
   ["type:feature", "area:ai", "priority:p1"],
   "Easy/Normal/Hard adjust AI, never ratings.",
   ["Reaction delay, pursuit accuracy, QB read quality, coach adaptivity", "Optional light catch-up assist (off by default)"],
   ["Harness shows win-rate spread across difficulties vs scripted user bot"], ["A3"]),
]

# ---------------- M8 Camera/audio/feel ----------------
I += [
 issue("V1", m(8), "Broadcast camera behind the offense",
   ["type:feature", "area:rendering", "area:gameplay", "priority:p0"],
   "Reference framing: elevated, behind QB, looking downfield.",
   ["Follow ball carrier with look-ahead and damping; pull back on passes to show target lane",
    "Hash-aware framing; flips for possession change", "Celebration/replay cams, big-hit shake (setting to reduce)"],
   ["`cam.reference` pre-snap framing matches reference composition"], ["S1"]),
 issue("V2", m(8), "Audio: music, SFX, reactive crowd, announcer stingers",
   ["type:feature", "area:audio", "priority:p1"],
   "Sound that sells the retro-AAA vibe.",
   ["AVAudioEngine buses (music/SFX/crowd/UI) + PHASE spatial crowd", "Chiptune-orchestral hybrid tracks (menu, gameplay, big moment)",
    "SFX: block hits, tackles, catches, whistle, turbo whoosh, dive", "Crowd reacts to excitement value; short announcer stingers"],
   ["Mixing sliders work; no audio hitch on events"], ["C6"]),
 issue("V3", m(8), "Haptics (Core Haptics + controller haptics)",
   ["type:feature", "area:audio", "priority:p2"],
   "Tactile feedback for key moments.",
   ["Patterns: tackle (by force), catch, turbo rumble, TD", "GCController haptics mapping", "Setting to disable"],
   ["Haptics fire on device and supported controllers"], ["V2"]),
 issue("V4", m(8), "Game feel juice: hit-stop, slow-mo, TD celebration, first-down flash",
   ["type:feature", "area:gameplay", "area:rendering", "priority:p1"],
   "Make every play pop.",
   ["Hit-stop frames on tackles scaled by force", "Slow-mo on TD/INT/big play", "Confetti + crowd surge + celebration anims",
    "First-down line flash, 'BIG HIT' pixel text pops"],
   ["Playtest feedback rates feel ≥ 4/5"], ["R6", "V1"]),
]

# ---------------- M9 Modes & platform ----------------
I += [
 issue("G1", m(9), "Game modes: Exhibition vs CPU, local 2P (controllers), Practice",
   ["type:feature", "area:gameplay", "priority:p0"],
   "Playable modes for 1.0.",
   ["Exhibition with quarter length/difficulty", "Local 2-player with two controllers (split input, shared screen)",
    "Practice: pick any offense vs defense play, reset instantly"],
   ["Full exhibition game start→final score"], ["C6", "A3", "I6"]),
 issue("G2", m(9), "Fictional teams & rosters + custom team editor",
   ["type:feature", "area:gameplay", "area:art", "priority:p1"],
   "8 original teams with distinct palettes, names and rating profiles.",
   ["Team data: name, city, palette, helmet style bias, rating profile (power vs speed teams)", "Custom team editor using the customization system",
    "All names/brands original (no real leagues/teams)"],
   ["8 teams selectable; custom team saved and playable"], ["P7", "G3"]),
 issue("G3", m(9), "Persistence with SwiftData (settings, custom teams, stats)",
   ["type:feature", "area:engine", "priority:p1"],
   "Local saves.",
   ["Models: Settings, CustomTeam, GameResult, CareerStats", "Migration plan", "iCloud sync (stretch)"],
   ["Data survives app relaunch and update"], ["F1"]),
 issue("G4", m(9), "Game Center achievements & leaderboards",
   ["type:feature", "area:engine", "priority:p2"],
   "Platform integration.",
   ["Auth flow, achievements (first TD, 100-yd rusher, pick-six…), leaderboards (longest run, margin)", "Access point in menus"],
   ["Achievements unlock in sandbox"], ["G1"]),
]

# ---------------- M10 Ship ----------------
I += [
 issue("Q1", m(10), "Performance pass across device tiers",
   ["type:chore", "area:rendering", "area:qa", "priority:p0"],
   "Hit budgets everywhere.",
   ["Metal System Trace + Instruments on iPhone 12, 13, 15, 17 Pro", "Memory < 900 MB, load < 3 s to kickoff", "Fix hitches (PSO, allocations, asset streaming)"],
   ["60 fps median, 1% lows ≥ 50 fps on iPhone 13"], ["R7", "S3"]),
 issue("Q2", m(10), "Automated tests: sim unit tests, replay determinism, render snapshots",
   ["type:chore", "area:qa", "priority:p1"],
   "Guardrails.",
   ["Unit tests per sim system", "Replay determinism test in CI", "Offscreen render snapshot tests of key scenes with tolerance diff"],
   ["CI runs all suites under 15 min"], ["F2", "L6"]),
 issue("Q3", m(10), "Reference visual match review (docs/reference checklist)",
   ["type:chore", "area:art", "area:qa", "priority:p0"],
   "Iterate until an in-game capture matches the attached reference image.",
   ["Commit reference image to `docs/reference/target.jpg`", "Checklist: night sky + floodlights with bloom; voxel crowd in team colors; fictional sideline banners; yellow goalpost; turf stripes + pixel yard numbers + end-zone wordmark; players with armored/knight helmet variants, bare-head variants, numbers on back+shoulders; overhead energy bars; dust particles; glow sparkle; scorebug, down/distance, clock, possession arrow, minimap, name tag, 2×2 button cluster + PLAYS",
    "Side-by-side capture from `cam.reference` in every milestone review", "Track deltas as follow-up issues"],
   ["All checklist items pass in a signed-off side-by-side"], ["I5", "V1", "S3", "P6"]),
 issue("Q4", m(10), "TestFlight beta + App Store readiness",
   ["type:chore", "area:tools", "priority:p1"],
   "Get it into players' hands.",
   ["Fastlane or Xcode Cloud upload", "App icon, screenshots, privacy manifest, age rating", "Crash reporting + feedback loop"],
   ["External TestFlight build live"], ["Q1", "Q2"]),
]


def gh(args, data=None):
    cmd = ["gh", "api", *args]
    if data is not None:
        cmd += ["--input", "-"]
    r = subprocess.run(cmd, input=json.dumps(data) if data is not None else None,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {r.stderr.strip()}")
    return json.loads(r.stdout) if r.stdout.strip() else None


def paged(path):
    """Yield pages (lists) until an empty page; works on any gh version."""
    pages, p = [], 1
    while True:
        page = gh([f"{path}&page={p}"]) or []
        if not page:
            return pages
        pages.append(page); p += 1


def body_for(it):
    b = [it["summary"], "", REF, "", "### Tasks"]
    b += [f"- [ ] {t}" for t in it["tasks"]]
    b += ["", "### Acceptance criteria"] + [f"- [ ] {a}" for a in it["accept"]]
    if it["deps"]:
        b += ["", "### Depends on", " ".join("{{%s}}" % d for d in it["deps"])]
    return "\n".join(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    R = f"repos/{a.repo}"
    keys = {it["key"] for it in I}
    for it in I:
        for d in it["deps"] + re.findall(r"\{\{(\w+)\}\}", " ".join(it["tasks"])):
            assert d in keys, f"{it['key']} references unknown {d}"
    if a.dry_run:
        for name, _ in MILESTONES:
            print(f"\n## {name}")
            for it in I:
                if it["ms"] == name:
                    print(f"  [{it['key']}] {it['title']}  ({', '.join(it['labels'])})")
        print(f"\n{len(I)} issues + 1 roadmap issue, {len(LABELS)} labels, {len(MILESTONES)} milestones")
        return

    existing = {l["name"] for page in paged(f"{R}/labels?per_page=100") for l in page}
    for n, c in LABELS.items():
        if n not in existing:
            gh([f"{R}/labels", "-X", "POST"], {"name": n, "color": c}); print("label", n)

    ms = {x["title"]: x["number"] for page in paged(f"{R}/milestones?state=all&per_page=100") for x in page}
    for t, d in MILESTONES:
        if t not in ms:
            ms[t] = gh([f"{R}/milestones", "-X", "POST"], {"title": t, "description": d})["number"]; print("milestone", t)

    have = {x["title"]: x["number"] for page in paged(f"{R}/issues?state=all&per_page=100") for x in page}
    num = {}
    for it in I:  # pass 1: create (placeholders unresolved)
        if it["title"] in have:
            num[it["key"]] = have[it["title"]]; continue
        n = gh([f"{R}/issues", "-X", "POST"], {"title": it["title"], "body": body_for(it),
               "labels": it["labels"], "milestone": ms[it["ms"]]})["number"]
        num[it["key"]] = n; print(f"#{n} {it['title']}")
    sub = lambda s: re.sub(r"\{\{(\w+)\}\}", lambda mm: f"#{num[mm.group(1)]}", s)
    for it in I:  # pass 2: resolve cross references
        gh([f"{R}/issues/{num[it['key']]}", "-X", "PATCH"], {"body": sub(body_for(it))})

    title = "Roadmap: Craft Bowl 1.0 (tracking)"
    lines = ["Master tracking issue. See `docs/PLAN.md`. " + REF, ""]
    for t, _ in MILESTONES:
        lines.append(f"### {t}")
        lines += [f"- [ ] #{num[it['key']]} {it['title']}" for it in I if it["ms"] == t]
        lines.append("")
    payload = {"title": title, "body": "\n".join(lines), "labels": ["type:epic", "priority:p0"]}
    if title in have:
        gh([f"{R}/issues/{have[title]}", "-X", "PATCH"], payload)
    else:
        print("#%d %s" % (gh([f"{R}/issues", "-X", "POST"], payload)["number"], title))
    print("done")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        sys.exit(str(e))
