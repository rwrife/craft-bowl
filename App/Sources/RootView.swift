import CBRender
import Metal
import SwiftUI

/// Title (attract mode plays behind it) → game.
struct RootView: View {
    @State private var session = GameSession()
    @State private var inGame = UserDefaults.standard.bool(forKey: "CBAutoStart")
    private let supported = Renderer.isSupported(MTLCreateSystemDefaultDevice())

    var body: some View {
        if !supported {
            UnsupportedDeviceView()
        } else {
            ZStack {
                GameView(session: session)
                if inGame {
                    HUDView(session: session)
                    TouchControls(session: session)
                } else {
                    TitleView {
                        session.kickoff()
                        inGame = true
                    }
                }
                if session.showDevOverlay {
                    DevOverlay(session: session)
                }
            }
            .onAppear {
                if inGame { session.kickoff(seed: 1) }
            }
        }
    }
}

struct TitleView: View {
    let start: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.55)], startPoint: .top,
                           endPoint: .bottom)
            VStack(spacing: 18) {
                Text("BLOCK BOWL")
                    .font(.system(size: 72, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 0, x: 5, y: 5)
                Text("BLOCKY ARCADE FOOTBALL")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                Spacer().frame(height: 12)
                Button(action: start) {
                    Text("KICKOFF")
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 36).padding(.vertical, 12)
                        .background(Color(red: 0.16, green: 0.36, blue: 0.84), in: .rect(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.yellow, lineWidth: 3))
                        .foregroundStyle(.white)
                }
                Text("KEYBOARD: WASD MOVE · SPACE TURBO · J/K/L PASS · H HANDOFF · U DIVE · RETURN SNAP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .ignoresSafeArea()
    }
}

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("BLOCK BOWL").font(.system(size: 40, weight: .black, design: .monospaced))
            Text("This device's GPU isn't supported. Block Bowl needs an A14 Bionic chip or newer.")
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }
}
