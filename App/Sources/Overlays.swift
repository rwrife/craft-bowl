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
        let homeName = session.homeTeam?.abbreviation ?? "BLUE"
        let awayName = session.awayTeam?.abbreviation ?? "RED"
        let homeColor = session.homeTeam?.primaryColor ?? homeBlue
        let awayColor = session.awayTeam?.primaryColor ?? awayRed
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Spacer()
                HStack(spacing: 0) {
                    Text(homeName).font(.pixel(15)).padding(.horizontal, 12).frame(height: 34).background(homeColor)
                    Text("\(h.homeScore)").font(.pixel(22)).frame(width: 46, height: 34).background(panel)
                    VStack(spacing: 0) {
                        Text("Q\(h.quarter)").font(.pixel(10))
                        Text(h.clock).font(.pixel(14))
                    }
                    .frame(width: 64, height: 34).background(.black.opacity(0.9))
                    Text("\(h.awayScore)").font(.pixel(22)).frame(width: 46, height: 34).background(panel)
                    Text(awayName).font(.pixel(15)).padding(.horizontal, 12).frame(height: 34).background(awayColor)
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

            if !h.message.isEmpty && h.message != "SELECT PLAY" && !h.showDriveRecap {
                Text(h.message)
                    .font(.pixel(h.message.count > 12 ? 28 : 40, .black))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 0, x: 3, y: 3)
                    .padding(.top, 28)
            }
            Spacer()
            if h.phase == .live {
                HStack(spacing: 6) {
                    Text("TURBO").font(.pixel(10)).foregroundStyle(.yellow)
                    MeterBar(value: h.turbo, color: .yellow)
                    Text("HEALTH").font(.pixel(10)).foregroundStyle(.green)
                    MeterBar(value: h.health, color: .green)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(panel)
                .padding(.bottom, 20)
            }
        }
        .opacity(h.gameOver == nil ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// Modal recap of a simulated opposing possession: a translucent card over the opponent's sideline dance with
/// how the drive ended, the passing / rushing box score, the last few snaps and where the user gets the ball.
struct DriveRecapDialog: View {
    let session: GameSession
    @State private var appeared = false

    var body: some View {
        let h = session.hud
        if h.showDriveRecap, let drive = h.opponentDrive {
            let teamColor = session.awayTeam?.primaryColor ?? awayRed
            let homeName = session.homeTeam?.abbreviation ?? "BLUE"
            let awayName = session.awayTeam?.abbreviation ?? "RED"
            ZStack {
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                card(drive, teamColor: teamColor, score: "\(homeName) \(h.homeScore)  ·  \(awayName) \(h.awayScore)")
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 44)
            }
            .contentShape(Rectangle())
            .onTapGesture { session.input.send(.snap, from: .touch) }
            .onAppear { withAnimation(.spring(duration: 0.35)) { appeared = true } }
            .onDisappear { appeared = false }
        }
    }

    private func card(_ drive: OpponentDrive, teamColor: Color, score: String) -> some View {
        let s = drive.stats
        let accent: Color = drive.points > 0 ? .yellow : (drive.ending.isStop ? .green : .white)
        return VStack(spacing: 8) {
            HStack {
                Text(drive.headline).font(.pixel(13)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Text(drive.trigger.text).font(.pixel(9, .bold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(teamColor.opacity(0.85), in: .rect(cornerRadius: 10))

            VStack(spacing: 2) {
                Text(drive.resultText).font(.pixel(26, .black)).foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.7), radius: 0, x: 2, y: 2)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("\(drive.fieldPositionText)   ·   \(score)")
                    .font(.pixel(10, .bold)).foregroundStyle(.white.opacity(0.8))
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    StatRow(title: "PASSING", items: [
                        ("C/ATT", "\(s.completions)/\(s.passAttempts)"), ("YDS", "\(s.passYards)"),
                        ("TD", "\(s.passTouchdowns)"), ("INT", "\(s.interceptions)"),
                    ])
                    StatRow(title: "RUSHING", items: [
                        ("ATT", "\(s.rushAttempts)"), ("YDS", "\(s.rushYards)"),
                        ("AVG", String(format: "%.1f", s.rushAverage)), ("TD", "\(s.rushTouchdowns)"),
                    ])
                    StatRow(title: "DRIVE", items: [
                        ("PLAYS", "\(drive.plays)"), ("NET", "\(s.netYards)"),
                        ("1ST", "\(s.firstDowns)"), ("TOP", drive.timeOfPossession),
                    ])
                }
                .frame(width: 270)

                VStack(alignment: .leading, spacing: 3) {
                    Text("PLAY BY PLAY").font(.pixel(9, .bold)).foregroundStyle(.white.opacity(0.6))
                    let recent = drive.playByPlay.suffix(6)
                    if drive.playByPlay.count > recent.count {
                        Text("…\(drive.playByPlay.count - recent.count) EARLIER").font(.pixel(8)).foregroundStyle(.white.opacity(0.45))
                    }
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.pixel(9, .semibold)).foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 270, alignment: .leading)
                .padding(8)
                .background(.black.opacity(0.25), in: .rect(cornerRadius: 8))
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(drive.resumeText).font(.pixel(13)).foregroundStyle(.yellow)
                Spacer()
                Text("TAP OR PRESS ANY BUTTON").font(.pixel(9, .bold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 590)
        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 16))
        .background(panel.opacity(0.35), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(teamColor.opacity(0.9), lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

/// Final whistle: a translucent card beside the winners' celebration with the final score, who won and a
/// side-by-side team box score. REMATCH goes through the sim's input (any button works on a controller);
/// MAIN MENU leaves the game.
struct GameOverDialog: View {
    let session: GameSession
    let mainMenu: () -> Void
    @State private var appeared = false

    var body: some View {
        if let g = session.hud.gameOver {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea()
                card(g)
                    .padding(.trailing, 40)
                    .offset(x: appeared ? 0 : 80)
                    .opacity(appeared ? 1 : 0)
            }
            .onAppear { withAnimation(.spring(duration: 0.5).delay(0.4)) { appeared = true } }
            .onDisappear { appeared = false }
        }
    }

    private func card(_ g: GameSummary) -> some View {
        let homeName = session.homeTeam?.abbreviation ?? "BLUE"
        let awayName = session.awayTeam?.abbreviation ?? "RED"
        let homeColor = session.homeTeam?.primaryColor ?? homeBlue
        let awayColor = session.awayTeam?.primaryColor ?? awayRed
        let headline: String
        let accent: Color
        switch g.winner {
        case .home:
            headline = "\(session.homeTeam?.name.uppercased() ?? homeName) WIN!"
            accent = homeColor
        case .away:
            headline = "\(session.awayTeam?.name.uppercased() ?? awayName) WIN!"
            accent = awayColor
        case .tie:
            headline = "TIE GAME"
            accent = .white.opacity(0.7)
        }
        let h = g.home, a = g.away
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("FINAL").font(.pixel(11, .bold)).foregroundStyle(.white.opacity(0.7))
                Text(headline).font(.pixel(22, .black)).foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.7), radius: 0, x: 2, y: 2)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }

            HStack(spacing: 0) {
                scoreSide(homeName, g.homeScore, homeColor, won: g.winner == .home)
                Text("–").font(.pixel(22, .black)).foregroundStyle(.white.opacity(0.6)).frame(width: 30)
                scoreSide(awayName, g.awayScore, awayColor, won: g.winner == .away, trailing: true)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(homeName).foregroundStyle(homeColor.mix(with: .white, by: 0.35))
                    Spacer()
                    Text("TEAM STATS").foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(awayName).foregroundStyle(awayColor.mix(with: .white, by: 0.35))
                }
                .font(.pixel(9, .bold))
                .padding(.bottom, 4)
                compare("TOTAL YARDS", h.stats.netYards, a.stats.netYards)
                compare("PASSING", "\(h.stats.completions)/\(h.stats.passAttempts)  \(h.stats.passYards)",
                        "\(a.stats.completions)/\(a.stats.passAttempts)  \(a.stats.passYards)",
                        better: winnerOf(h.stats.passYards, a.stats.passYards))
                compare("RUSHING", "\(h.stats.rushAttempts)–\(h.stats.rushYards)",
                        "\(a.stats.rushAttempts)–\(a.stats.rushYards)",
                        better: winnerOf(h.stats.rushYards, a.stats.rushYards))
                compare("TOUCHDOWNS", h.stats.passTouchdowns + h.stats.rushTouchdowns,
                        a.stats.passTouchdowns + a.stats.rushTouchdowns)
                compare("FIRST DOWNS", h.stats.firstDowns, a.stats.firstDowns)
                compare("TURNOVERS", h.turnovers, a.turnovers, lowerIsBetter: true)
                compare("SACKED", h.stats.sacks, a.stats.sacks, lowerIsBetter: true)
                compare("LONGEST PLAY", h.stats.longestPlay, a.stats.longestPlay)
                compare("POSSESSION", h.timeOfPossession, a.timeOfPossession,
                        better: winnerOf(Int(h.seconds), Int(a.seconds)))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.black.opacity(0.25), in: .rect(cornerRadius: 8))

            HStack(spacing: 10) {
                Button { session.input.send(.snap, from: .touch) } label: {
                    Text("REMATCH").font(.pixel(13, .black)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(homeColor, in: .rect(cornerRadius: 8))
                }
                Button(action: mainMenu) {
                    Text("MAIN MENU").font(.pixel(13, .black)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(.white.opacity(0.15), in: .rect(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 380)
        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 16))
        .background(panel.opacity(0.35), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.9), lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private func scoreSide(_ name: String, _ score: Int, _ color: Color, won: Bool, trailing: Bool = false)
        -> some View
    {
        HStack(spacing: 8) {
            if trailing { Text("\(score)").font(.pixel(34, .black)).foregroundStyle(won ? .yellow : .white) }
            Text(name).font(.pixel(14, .black)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(color, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(won ? .yellow : .clear, lineWidth: 2))
            if !trailing { Text("\(score)").font(.pixel(34, .black)).foregroundStyle(won ? .yellow : .white) }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .leading : .trailing)
    }

    /// -1 home better, 1 away better, 0 even.
    private func winnerOf(_ home: Int, _ away: Int, lowerIsBetter: Bool = false) -> Int {
        home == away ? 0 : ((home > away) != lowerIsBetter ? -1 : 1)
    }

    private func compare(_ label: String, _ home: Int, _ away: Int, lowerIsBetter: Bool = false) -> some View {
        compare(label, "\(home)", "\(away)", better: winnerOf(home, away, lowerIsBetter: lowerIsBetter))
    }

    private func compare(_ label: String, _ home: String, _ away: String, better: Int) -> some View {
        HStack {
            Text(home).font(.pixel(12, better < 0 ? .black : .semibold))
                .foregroundStyle(better < 0 ? .yellow : .white.opacity(0.85))
                .frame(width: 90, alignment: .leading)
            Spacer(minLength: 0)
            Text(label).font(.pixel(9, .bold)).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Text(away).font(.pixel(12, better > 0 ? .black : .semibold))
                .foregroundStyle(better > 0 ? .yellow : .white.opacity(0.85))
                .frame(width: 90, alignment: .trailing)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.vertical, 2.5)
    }
}

private struct StatRow: View {
    let title: String
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.pixel(9, .bold)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    StatChip(label: item.0, value: item.1)
                }
            }
            .padding(.vertical, 4)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 6))
        }
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.pixel(8, .bold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.pixel(14, .black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
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

private extension Color {
    init(_ v: SIMD3<Float>) { self.init(red: Double(v.x), green: Double(v.y), blue: Double(v.z)) }
}

/// Pre-snap play selection: the 3 plays dealt this down as chalkboard X's-and-O's cards.
struct PlayCardsView: View {
    let session: GameSession

    var body: some View {
        let h = session.hud
        VStack(spacing: 6) {
            StatLegend()
            HStack(spacing: 10) {
                ForEach(Array(h.playCards.enumerated()), id: \.offset) { i, card in
                    PlayCard(diagram: card, slot: i, selected: h.chosenCard == i,
                             dimmed: h.chosenCard != nil && h.chosenCard != i)
                        .onTapGesture { session.input.send(.playSelect(i), from: .touch) }
                }
            }
        }
    }
}

/// Explains the stacked bar drawn over key players: each color is a rating, shrinking as health drains.
private struct StatLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            item("SPD", StatBar.speedColor)
            item("END", StatBar.enduranceColor)
            item("ABL", StatBar.abilityColor)
            Text("× HEALTH").font(.pixel(9)).foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(panel)
    }

    private func item(_ label: String, _ c: SIMD3<Float>) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(Color(c)).frame(width: 10, height: 6).overlay(Rectangle().stroke(.black, lineWidth: 1))
            Text(label).font(.pixel(9)).foregroundStyle(.white)
        }
    }
}

private struct PlayCard: View {
    let diagram: PlayDiagram
    let slot: Int
    let selected: Bool
    let dimmed: Bool

    private static let chalk = Color(red: 0.06, green: 0.17, blue: 0.11)
    private static let keys = ["1", "2", "3"]

    var body: some View {
        VStack(spacing: 3) {
            Canvas { ctx, size in draw(&ctx, size) }
                .frame(width: 124, height: 60)
                .background(PlayCard.chalk)
                .overlay(alignment: .topLeading) {
                    Text(PlayCard.keys[min(slot, 2)]).font(.pixel(9)).foregroundStyle(.black)
                        .frame(width: 13, height: 13).background(.yellow.opacity(0.9)).padding(3)
                }
            Text(diagram.name.uppercased()).font(.pixel(10)).foregroundStyle(.white).lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(diagram.kindLabel).font(.pixel(8)).foregroundStyle(.white.opacity(0.65))
        }
        .frame(width: 124)
        .padding(4)
        .background(panel)
        .overlay(Rectangle().stroke(selected ? .yellow : .white.opacity(0.35), lineWidth: selected ? 3 : 1))
        .scaleEffect(selected ? 1.06 : 1)
        .opacity(dimmed ? 0.6 : 1)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(Rectangle())
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        func pt(_ v: Vec2) -> CGPoint {
            CGPoint(x: CGFloat((v.x - PlayDiagram.minX) / (PlayDiagram.maxX - PlayDiagram.minX)) * size.width,
                    y: size.height - CGFloat((v.y - PlayDiagram.minY) / (PlayDiagram.maxY - PlayDiagram.minY)) * size.height)
        }
        let losY = pt(Vec2(0, 0)).y
        var los = Path()
        los.move(to: CGPoint(x: 0, y: losY))
        los.addLine(to: CGPoint(x: size.width, y: losY))
        ctx.stroke(los, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        let yellow = Color(red: 1, green: 0.85, blue: 0.2)
        for stroke in diagram.strokes where stroke.points.count > 1 {
            var path = Path()
            path.move(to: pt(stroke.points[0]))
            for p in stroke.points.dropFirst() { path.addLine(to: pt(p)) }
            let end = pt(stroke.points[stroke.points.count - 1])
            let prev = pt(stroke.points[stroke.points.count - 2])
            let angle = atan2(end.y - prev.y, end.x - prev.x)
            switch stroke.style {
            case .route, .run:
                let w: CGFloat = stroke.style == .run ? 2.4 : 1.5
                let c = stroke.style == .run ? Color(red: 1, green: 0.55, blue: 0.2) : yellow
                ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                var head = Path()
                let len: CGFloat = 5
                head.move(to: end)
                head.addLine(to: CGPoint(x: end.x - len * cos(angle - 0.5), y: end.y - len * sin(angle - 0.5)))
                head.addLine(to: CGPoint(x: end.x - len * cos(angle + 0.5), y: end.y - len * sin(angle + 0.5)))
                head.closeSubpath()
                ctx.fill(head, with: .color(c))
            case .pitch:
                ctx.stroke(path, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            case .block:
                ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
                var t = Path()
                let n = CGPoint(x: -sin(angle) * 3, y: cos(angle) * 3)
                t.move(to: CGPoint(x: end.x - n.x, y: end.y - n.y))
                t.addLine(to: CGPoint(x: end.x + n.x, y: end.y + n.y))
                ctx.stroke(t, with: .color(.white.opacity(0.8)), lineWidth: 1.6)
            }
        }
        let r: CGFloat = 3.2
        for o in diagram.offense {
            let c = pt(o)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(red: 0.55, green: 0.75, blue: 1)), lineWidth: 1.5)
        }
        let q = pt(diagram.qb)
        ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(yellow))
        for d in diagram.defense {
            let c = pt(d)
            var x = Path()
            x.move(to: CGPoint(x: c.x - r, y: c.y - r)); x.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            x.move(to: CGPoint(x: c.x + r, y: c.y - r)); x.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
            ctx.stroke(x, with: .color(Color(red: 1, green: 0.35, blue: 0.3)), lineWidth: 1.5)
        }
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
                .opacity(h.showDriveRecap || h.gameOver != nil ? 0 : 1)
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                switch h.phase {
                case .preSnap:
                    if h.chosenCard != nil && !h.showDriveRecap {
                        ActionButton(label: "SNAP", color: homeBlue, size: 84) { send(.snap) }
                    }
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
        .overlay(alignment: .bottom) {
            if h.phase == .preSnap && !h.playCards.isEmpty && !h.showDriveRecap {
                PlayCardsView(session: session).padding(.bottom, 40)
            }
        }
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
