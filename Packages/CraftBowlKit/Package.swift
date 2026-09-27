// swift-tools-version: 6.0
// CraftBowlKit — engine, simulation and rendering modules for Craft Bowl.
// CBCore / CBSim / CBPlays / CBAI / CBAnimation / CBAssets are platform-neutral (no UIKit/Metal)
// so the deterministic simulation can be unit-tested and run headless (see docs/PLAN.md §2).
import PackageDescription

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "CraftBowlKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "CBCore", targets: ["CBCore"]),
        .library(name: "CBSim", targets: ["CBSim"]),
        .library(name: "CBPlays", targets: ["CBPlays"]),
        .library(name: "CBAI", targets: ["CBAI"]),
        .library(name: "CBAnimation", targets: ["CBAnimation"]),
        .library(name: "CBAssets", targets: ["CBAssets"]),
        .library(name: "CBInput", targets: ["CBInput"]),
        .library(name: "CBRender", targets: ["CBRender"]),
        .library(name: "CBHUD", targets: ["CBHUD"]),
        .library(name: "CBAudio", targets: ["CBAudio"]),
    ],
    targets: [
        // Platform-neutral core
        .target(name: "CBCore", swiftSettings: strict),
        .target(name: "CBSim", dependencies: ["CBCore"],
                resources: [.process("Resources")], swiftSettings: strict),
        .target(name: "CBPlays", dependencies: ["CBCore", "CBSim"],
                resources: [.process("Resources")], swiftSettings: strict),
        .target(name: "CBAI", dependencies: ["CBCore", "CBSim", "CBPlays"], swiftSettings: strict),
        .target(name: "CBAnimation", dependencies: ["CBCore"], swiftSettings: strict),
        .target(name: "CBAssets", dependencies: ["CBCore"], swiftSettings: strict),

        // Apple-platform modules (guarded with canImport so the package still resolves elsewhere)
        .target(name: "CBInput", dependencies: ["CBCore"], swiftSettings: strict),
        .target(name: "CBRender", dependencies: ["CBCore", "CBAssets", "CBSim"], swiftSettings: strict),
        .target(name: "CBHUD", dependencies: ["CBCore", "CBSim"], swiftSettings: strict),
        .target(name: "CBAudio", dependencies: ["CBCore"], swiftSettings: strict),
    ]
)
