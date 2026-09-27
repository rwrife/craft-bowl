import CBCore
import CBGame
import CBInput
import CBPlays
import CBRender
import SwiftUI

private extension Font {
    static func pixel(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private let homeBlue = Color(red: 0.16, green: 0.36, blue: 0.84)
private let awayRed = Color(red: 0.7, green: 0.15, blue: 0.17)
private let panel = Color(red: 0.05, green: 0.07, blue: 0.14).opacity(0.85)

/// Minimal Tecmo-style scorebug + down & distance + play prompts (full HUD lands in #35–#38).
struct HUDView: View {
    let session: GameSession

    var body: some View {
        let h = session.hud
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Spacer()
                HStack(spacing: 0) {
                    Text("BLUE").font(.pixel(15)).padding(.horizontal, 12).frame(height: 34).background(homeBlue)
                    Text("\(h.homeScore)").font(.pixel(22)).frame(width: 46, height: 34).background(panel)
                    VStack(spacing: 0) {
                        Text("Q\(h.quarter)").font(.pixel(10))
                        Text(h.clock).font(.pixel(14))
                    }
                    .frame(width: 64, height: 34).background(.black.opacity(0.9))
                    Text("\(h.awayScore)").font(.pixel(22)).frame(width: 46, height: 34).background(panel)
                    Text("RED").font(.pixel(15)).padding(.horizontal, 12).frame(height: 34).background(awayRed)
                }
                .foregroundStyle(.white)
                .overlay(Rectangle().stroke(.black, lineWidth: 2))
                Spacer()
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(h.downDistance).font(.pixel(16)).foregroundStyle(.yellow)
                    Text(h.ballOn).font(.pixel(11)).foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(panel)
                .padding(.trailing, 60)
            }
            .padding(.top, 10)

            if !h.message.isEmpty && h.message != "SELECT PLAY" {
                Text(h.message)
                    .font(.pixel(h.message.count > 12 ? 28 : 40, .black))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 0, x: 3, y: 3)
                    .padding(.top, 28)
            }
            Spacer()
            if h.phase == .preSnap {
                VStack(spacing: 4) {
                    Text("◀  \(h.playName)  ▶").font(.pixel(18)).foregroundStyle(.white)
                    Text("vs \(h.defenseName)").font(.pixel(10)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(panel)
                .padding(.bottom, 24)
            } else if h.phase == .live {
                HStack(spacing: 6) {
                    Text("TURBO").font(.pixel(10)).foregroundStyle(.yellow)
                    MeterBar(value: h.turbo, color: .yellow)
                    Text("STAMINA").font(.pixel(10)).foregroundStyle(.green)
                    MeterBar(value: h.energy, color: .green)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(panel)
                .padding(.bottom, 20)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MeterBar: View {
    let value: Float
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.6))
            Rectangle().fill(color).frame(width: 80 * CGFloat(clamp(value, 0, 1)))
        }
        .frame(width: 80, height: 8)
        .overlay(Rectangle().stroke(.white.opacity(0.5), lineWidth: 1))
    }
}

/// On-screen controls: virtual stick (left) and a context-sensitive action cluster (right).
struct TouchControls: View {
    let session: GameSession

    private func send(_ a: GameAction) { session.input.send(a, from: .touch) }

    var body: some View {
        let h = session.hud
        HStack(alignment: .bottom) {
            VirtualStick { send(.move($0)) }
                .padding(.leading, 40)
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                switch h.phase {
                case .preSnap:
                    HStack(spacing: 10) {
                        ActionButton(label: "◀", color: .gray) { send(.previousPlay) }
                        ActionButton(label: "▶", color: .gray) { send(.nextPlay) }
                    }
                    ActionButton(label: "SNAP", color: homeBlue, size: 84) { send(.snap) }
                case .live:
                    if !h.qbActions.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(h.qbActions, id: \.self) { action in
                                ActionButton(label: label(action), color: color(action)) { send(gameAction(action)) }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            ActionButton(label: "DIVE", color: awayRed) { send(.dive) }
                            HoldButton(label: "TURBO", color: .orange) { send(.turbo($0)) }
                        }
                    }
                case .dead:
                    EmptyView()
                }
            }
            .padding(.trailing, 40)
        }
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func label(_ a: QBAction) -> String {
        switch a {
        case .passLeft: "PASS\nL"
        case .passCenter: "PASS\nC"
        case .passRight: "PASS\nR"
        case .handoff: "HAND\nOFF"
        case .toss: "TOSS"
        }
    }

    private func color(_ a: QBAction) -> Color {
        switch a {
        case .passLeft: Color(red: 0.1, green: 0.6, blue: 0.85)
        case .passCenter: Color(red: 0.8, green: 0.65, blue: 0.1)
        case .passRight: Color(red: 0.8, green: 0.25, blue: 0.6)
        case .handoff, .toss: Color(red: 0.2, green: 0.6, blue: 0.3)
        }
    }

    private func gameAction(_ a: QBAction) -> GameAction {
        switch a {
        case .passLeft: .passLeft
        case .passCenter: .passCenter
        case .passRight: .passRight
        case .handoff, .toss: .handoff
        }
    }
}

private struct ActionButton: View {
    let label: String
    let color: Color
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Text(label)
            .font(.pixel(label.count > 5 ? 12 : 16))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.opacity(0.85), in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

private struct HoldButton: View {
    let label: String
    let color: Color
    let onChange: (Bool) -> Void
    @State private var held = false

    var body: some View {
        Text(label)
            .font(.pixel(13))
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(color.opacity(held ? 1 : 0.75), in: .circle)
            .overlay(Circle().stroke(.white.opacity(held ? 1 : 0.6), lineWidth: 2))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !held { held = true; onChange(true) }
                }
                .onEnded { _ in
                    held = false
                    onChange(false)
                })
    }
}

private struct VirtualStick: View {
    let onMove: (Vec2) -> Void
    @State private var knob: CGSize = .zero
    private let size: CGFloat = 150
    private let travel: CGFloat = 55

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.25)).overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
            Circle().fill(.white.opacity(0.55)).frame(width: 58, height: 58).offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                var dx = v.location.x - size / 2, dy = v.location.y - size / 2
                let len = (dx * dx + dy * dy).squareRoot()
                if len > travel { dx *= travel / len; dy *= travel / len }
                knob = CGSize(width: dx, height: dy)
                onMove(Vec2(Float(dx / travel), Float(-dy / travel)))
            }
            .onEnded { _ in
                knob = .zero
                onMove(.zero)
            })
    }
}

/// Dev overlay (issue #4): perf, pass toggles, camera presets, time controls, record/replay, inspector.
struct DevOverlay: View {
    @Bindable var session: GameSession

    var body: some View {
        let d = session.dev
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "%.0f FPS  cpu %.2fms  sim %.3fms", d.fps, d.cpuMs, d.simMs))
                Text(String(format: "gpu cull+shadow %.2f  scene %.2f  post %.2f ms",
                            d.gpuCullShadow, d.gpuScene, d.gpuPost))
                Text(String(format: "scale %.2f  %@", d.renderScale, d.renderSize))
                Text("crowd \(d.crowd)  players \(d.players)  draws \(d.drawCalls)")
                Text("MetalFX \(d.metalFX ? "on" : "off")  residency \(d.residency ? "on" : "off")")
                Text("tick \(d.tick)  checksum \(d.checksum)")
                Divider().background(.white)
                ForEach(d.inspector, id: \.self) { Text($0) }
                Divider().background(.white)
                Text("INPUT  \(d.controllers.isEmpty ? "no controller" : d.controllers.joined(separator: ", "))")
                ForEach(Array(d.inputLog.enumerated()), id: \.offset) { Text($0.element).opacity(0.8) }
            }
            .font(.pixel(10, .semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.7))
            .allowsHitTesting(false)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Group {
                    toggle("Shadows", $session.settings.shadows)
                    toggle("Bloom", $session.settings.bloom)
                    toggle("Grade LUT", $session.settings.colorGrade)
                    toggle("MetalFX", $session.settings.metalFX)
                    toggle("Pixel noise", $session.settings.pixelNoise)
                    toggle("Crowd", $session.settings.crowd)
                    toggle("Glows", $session.settings.glows)
                    toggle("GPU cull", $session.settings.gpuCulling)
                    toggle("Dyn res", $session.settings.dynamicResolution)
                    toggle("Debug draw", $session.settings.debugDraw)
                }
                Picker("Camera", selection: $session.cameraPreset) {
                    ForEach(Camera.Preset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                HStack(spacing: 4) {
                    small(session.paused ? "Resume" : "Pause") { session.paused.toggle() }
                    small(session.slowMotion ? "1×" : "¼×") { session.slowMotion.toggle() }
                    small(session.autopilot ? "Auto ✓" : "Auto") { session.autopilot.toggle() }
                }
                HStack(spacing: 4) {
                    small("● Rec") { session.startRecording() }
                    small("■") { session.stopRecording() }
                    small("▶ Replay") { session.playRecording() }
                    small("Verify") { session.verifyRecording() }
                }
                Text(replayText).font(.pixel(10)).foregroundStyle(replayColor)
            }
            .padding(8)
            .background(.black.opacity(0.7))
        }
        .padding(.top, 54)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
        } label: {
            Text("\(binding.wrappedValue ? "■" : "□") \(title)")
                .font(.pixel(11, .semibold))
                .foregroundStyle(binding.wrappedValue ? .yellow : .white.opacity(0.6))
        }
    }

    private func small(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.pixel(10)).padding(.horizontal, 6).padding(.vertical, 4)
                .background(.white.opacity(0.15), in: .rect(cornerRadius: 3))
                .foregroundStyle(.white)
        }
    }

    private var replayText: String {
        switch session.replay {
        case .idle: "replay: idle"
        case .recording(let t): "REC \(t) ticks"
        case .recorded(let t): "recorded \(t) ticks"
        case .playing(let t, let n): "replaying \(t)/\(n)"
        case .verified(let ok, let t): ok ? "MATCH ✓ \(t) ticks" : "MISMATCH ✗ \(t) ticks"
        }
    }

    private var replayColor: Color {
        if case .verified(let ok, _) = session.replay { return ok ? .green : .red }
        if case .recording = session.replay { return .red }
        return .white
    }
}
