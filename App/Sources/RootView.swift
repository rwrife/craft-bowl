import CBRender
import Metal
import SwiftUI

/// Title → game flow placeholder. Menus land in issue I6.
struct RootView: View {
    @State private var inGame = false
    private let supported = Renderer.isSupported(MTLCreateSystemDefaultDevice())

    var body: some View {
        if !supported {
            UnsupportedDeviceView()
        } else {
            ZStack {
                GameView()
                if !inGame {
                    VStack(spacing: 24) {
                        Text("CRAFT BOWL")
                            .font(.system(size: 64, weight: .black, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black, radius: 0, x: 4, y: 4)
                        Button("KICKOFF") { inGame = true }
                            .font(.system(size: 28, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 32).padding(.vertical, 12)
                            .background(Color.blue, in: .rect(cornerRadius: 4))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("CRAFT BOWL").font(.system(size: 40, weight: .black, design: .monospaced))
            Text("This device's GPU isn't supported. Craft Bowl needs an A14 Bionic chip or newer.")
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }
}
