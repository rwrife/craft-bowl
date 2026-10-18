import SceneKit
import SwiftUI
import UIKit

/// The Block Bowl shield on the title screen, rendered as a real 3D mesh (`BlockBowlLogo.obj`, vertex-colored).
/// It flies in from deep in the stadium spinning, slams into place with a flash and a camera shake, then idles
/// with a slow ±15° twist and a ±5° tilt.
struct TitleLogo3D: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        view.scene = TitleLogoScene.make()
        view.isPlaying = true
        view.accessibilityLabel = "Block Bowl"
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}

@MainActor
private enum TitleLogoScene {
    static let twistAngle = Float(15 * Double.pi / 180)
    static let tiltAngle = Float(5 * Double.pi / 180)

    static func make() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let camera = SCNCamera()
        camera.fieldOfView = 24
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3.6)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 820
        key.eulerAngles = SCNVector3(-0.45, -0.35, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 350
        rim.eulerAngles = SCNVector3(-0.2, 2.6, 0)
        scene.rootNode.addChildNode(rim)

        // Hierarchy: entrance (fly-in) → twist (yaw) → tilt (pitch) → mesh.
        let entrance = SCNNode()
        let twistNode = SCNNode()
        let tiltNode = SCNNode()
        scene.rootNode.addChildNode(entrance)
        entrance.addChildNode(twistNode)
        twistNode.addChildNode(tiltNode)
        if let geometry = TitleLogoMesh.geometry {
            tiltNode.addChildNode(SCNNode(geometry: geometry))
        }

        animateEntrance(entrance, camera: cameraNode, key: key, twist: twistNode, tilt: tiltNode)
        return scene
    }

    private static func animateEntrance(
        _ node: SCNNode, camera: SCNNode, key: SCNNode, twist: SCNNode, tilt: SCNNode
    ) {
        node.position = SCNVector3(0, -0.6, -22)
        node.eulerAngles = SCNVector3(0.6, -Float.pi * 4, 0.25)
        node.scale = SCNVector3(0.35, 0.35, 0.35)
        node.opacity = 0

        func eased(_ action: SCNAction, _ mode: SCNActionTimingMode) -> SCNAction {
            action.timingMode = mode
            return action
        }

        // Fly in spinning, overshoot toward the camera, then slam back into place.
        let flyIn = SCNAction.group([
            eased(.move(to: SCNVector3(0, 0, 0.45), duration: 1.15), .easeOut),
            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 1.15, usesShortestUnitArc: false), .easeOut),
            eased(.scale(to: 1.12, duration: 1.15), .easeOut),
            .fadeIn(duration: 0.35),
        ])
        let slam = SCNAction.group([
            eased(.move(to: SCNVector3(0, 0, 0), duration: 0.14), .easeIn),
            eased(.scale(to: 0.94, duration: 0.14), .easeIn),
        ])
        let settle = eased(.scale(to: 1, duration: 0.3), .easeOut)
        let delay = 0.2
        node.runAction(.sequence([.wait(duration: delay), flyIn, slam, settle]))

        // Everything else keys off the moment the logo slams home.
        let impact = delay + flyIn.duration + slam.duration
        key.runAction(.sequence([.wait(duration: impact), flash(key.light?.intensity ?? 820)]))
        camera.runAction(.sequence([.wait(duration: impact), shake(from: camera.position)]))
        startIdle(twist: twist, tilt: tilt, after: impact)
    }

    /// Light spike that decays back to `base` intensity.
    private static func flash(_ base: CGFloat) -> SCNAction {
        let duration: CGFloat = 0.7
        return .customAction(duration: duration) { node, elapsed in
            let t = 1 - elapsed / duration
            node.light?.intensity = base * (1 + 2.2 * t * t)
        }
    }

    private static func shake(from home: SCNVector3) -> SCNAction {
        let offsets: [(Float, Float)] = [(0.05, -0.03), (-0.04, 0.035), (0.025, -0.02), (-0.012, 0.01), (0, 0)]
        return .sequence(
            offsets.map { dx, dy in
                SCNAction.move(to: SCNVector3(home.x + dx, home.y + dy, home.z), duration: 0.045)
            })
    }

    /// Slow twist (yaw ±15°) and tilt (pitch ±5°) on different periods so the motion never looks mechanical.
    private static func startIdle(twist: SCNNode, tilt: SCNNode, after delay: TimeInterval) {
        func swing(_ node: SCNNode, axis: SIMD3<Float>, amplitude: Float, halfPeriod: TimeInterval, key: String) {
            func to(_ angle: Float, _ duration: TimeInterval) -> SCNAction {
                let a = SCNAction.rotateTo(
                    x: CGFloat(axis.x * angle), y: CGFloat(axis.y * angle), z: CGFloat(axis.z * angle),
                    duration: duration, usesShortestUnitArc: true)
                a.timingMode = .easeInEaseOut
                return a
            }
            let loop = SCNAction.repeatForever(.sequence([to(-amplitude, halfPeriod), to(amplitude, halfPeriod)]))
            node.runAction(.sequence([.wait(duration: delay), to(amplitude, halfPeriod / 2), loop]), forKey: key)
        }
        swing(twist, axis: SIMD3(0, 1, 0), amplitude: twistAngle, halfPeriod: 3.2, key: "twist")
        swing(tilt, axis: SIMD3(1, 0, 0), amplitude: tiltAngle, halfPeriod: 2.3, key: "tilt")
    }
}

/// Parses the bundled OBJ (positions + `v x y z r g b` vertex colors, triangles) into a flat-shaded,
/// vertex-colored SceneKit geometry centered on the origin and scaled to 1 unit tall.
@MainActor
enum TitleLogoMesh {
    static let geometry: SCNGeometry? = load()

    private static func load() -> SCNGeometry? {
        guard let url = Bundle.main.url(forResource: "BlockBowlLogo", withExtension: "obj"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        var triangles: [SIMD3<Int>] = []
        positions.reserveCapacity(6_000)
        colors.reserveCapacity(6_000)
        triangles.reserveCapacity(11_000)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let tag = parts.first else { continue }
            if tag == "v", parts.count >= 4 {
                let p = SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0)
                positions.append(p)
                if parts.count >= 7 {
                    colors.append(SIMD3(Float(parts[4]) ?? 1, Float(parts[5]) ?? 1, Float(parts[6]) ?? 1))
                } else {
                    colors.append(SIMD3(1, 1, 1))
                }
            } else if tag == "f", parts.count >= 4 {
                // "f a b c" or "f a/t/n ..." — only the position index is used; fan-triangulate polygons.
                let idx = parts.dropFirst().compactMap { Int($0.split(separator: "/").first ?? "") }.map { $0 - 1 }
                guard idx.count >= 3 else { continue }
                for k in 1..<(idx.count - 1) { triangles.append(SIMD3(idx[0], idx[k], idx[k + 1])) }
            }
        }
        guard !positions.isEmpty, !triangles.isEmpty else { return nil }

        let lo = positions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let hi = positions.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        let center = (lo + hi) / 2
        let scale = 1 / max(hi.y - lo.y, 1e-4)

        // Un-indexed so every triangle gets its own flat normal: crisp, blocky facets.
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var vertexColors: [SIMD3<Float>] = []
        let count = triangles.count * 3
        vertices.reserveCapacity(count)
        normals.reserveCapacity(count)
        vertexColors.reserveCapacity(count)
        for t in triangles {
            guard t.x < positions.count, t.y < positions.count, t.z < positions.count else { continue }
            let a = (positions[t.x] - center) * scale
            let b = (positions[t.y] - center) * scale
            let c = (positions[t.z] - center) * scale
            let n = simd_normalize(simd_cross(b - a, c - a))
            let normal = n.x.isFinite ? SCNVector3(n.x, n.y, n.z) : SCNVector3(0, 0, 1)
            for (p, i) in [(a, t.x), (b, t.y), (c, t.z)] {
                vertices.append(SCNVector3(p.x, p.y, p.z))
                normals.append(normal)
                // OBJ colors are sRGB; SceneKit shades in linear space.
                vertexColors.append(linear(colors[i]))
            }
        }

        let colorData = vertexColors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: vertexColors.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let element = SCNGeometryElement(indices: Array(0..<UInt32(vertices.count)), primitiveType: .triangles)
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
            elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = UIColor.white
        material.specular.contents = UIColor(white: 0.45, alpha: 1)
        material.shininess = 0.35
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    private static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func channel(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
        return SIMD3(channel(c.x), channel(c.y), channel(c.z))
    }
}
