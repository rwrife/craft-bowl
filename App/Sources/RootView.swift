import CBAssets
import CBCore
import CBRender
import CBSim
import Metal
import SwiftUI

struct PlayerProfile: Identifiable, Hashable, Sendable {
    let id: Position
    let name: String
    let number: Int
    let ratings: Ratings
}

struct TeamDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let city: String
    let nickname: String
    let abbreviation: String
    let uniform: TeamUniform
    let roster: [PlayerProfile]

    var name: String { "\(city) \(nickname)" }
    var primaryColor: Color {
        Color(red: Double(uniform.primary.r), green: Double(uniform.primary.g), blue: Double(uniform.primary.b))
    }
    var secondaryColor: Color {
        Color(red: Double(uniform.secondary.r), green: Double(uniform.secondary.g), blue: Double(uniform.secondary.b))
    }
    var overall: Int {
        TeamRating.overall(roster.map(\.ratings))
    }

    func gameRoster(for side: Side) -> [Position: (ratings: Ratings, number: Int)] {
        Dictionary(
            uniqueKeysWithValues: roster.filter { $0.id.side == side }.map {
                ($0.id, (ratings: $0.ratings, number: $0.number))
            })
    }
}

enum TeamCatalog {
    static let teams: [TeamDefinition] = {
        let teams = [
            make(
                "austin", "Austin", "Armadillos", "AUS", 0x2457D6, 0xF5B82E, 11, 0,
                specialNames: [.qb: "Ryan", .rb: "Hunter", .laneCenter: "Jaison"]),
            make("brooklyn", "Brooklyn", "Bolts", "BRK", 0x121820, 0x22C8F2, 23, 18),
            make("miami", "Miami", "Waves", "MIA", 0x00A6A6, 0xFF6B35, 37, 36),
            make("chicago", "Chicago", "Foundry", "CHI", 0xA51C30, 0xD7DCE2, 41, 54),
            make("seattle", "Seattle", "Sasquatch", "SEA", 0x173F35, 0x9EDB4D, 59, 72),
            make("phoenix", "Phoenix", "Firebirds", "PHX", 0x7A1D5D, 0xFF9E1B, 71, 90),
            make("nashville", "Nashville", "Notes", "NSH", 0x3A1C71, 0xF4D35E, 83, 108),
            make("boston", "Boston", "Minutemen", "BOS", 0x16324F, 0xC73737, 97, 126),
            make("san-diego", "San Diego", "Surf", "SD", 0x176B87, 0xF2E8CF, 109, 144),
        ]
        let names = teams.flatMap(\.roster).map(\.name)
        precondition(Set(names).count == names.count, "Team catalog player names must be unique")
        return teams
    }()

    private static let firstNames = [
        "Andre", "Beck", "Caleb", "Dante", "Eli", "Finn", "Gabe", "Isaiah", "Jett", "Kai", "Leo", "Malik",
        "Nico", "Owen", "Quinn", "Rafael", "Sam", "Trey", "Victor", "Wes", "Zane",
    ]
    private static let lastNames = [
        "Banks", "Cole", "Cross", "Davis", "Ellis", "Frost", "Grant", "Hayes", "Irons", "Jones", "Knox",
        "Lane", "Miles", "North", "Price", "Reed", "Stone", "Turner", "Vale", "West", "Young",
    ]

    private static func make(
        _ id: String, _ city: String, _ nickname: String, _ abbreviation: String,
        _ primary: UInt32, _ secondary: UInt32, _ seed: UInt64, _ rosterOffset: Int,
        specialNames: [Position: String] = [:]
    ) -> TeamDefinition {
        var rng = CatalogRNG(seed: seed)
        let positions = Position.allCases
        let usedNumbers = positions.enumerated().map { index, _ in 1 + ((index * 11 + Int(seed)) % 98) }
        let roster = positions.enumerated().map { index, position in
            let combination = ((rosterOffset + index) * 179 + 73) % (firstNames.count * lastNames.count)
            let first = firstNames[combination / lastNames.count]
            let last = lastNames[combination % lastNames.count]
            let name = specialNames[position].map { "\($0) \(last)" } ?? "\(first) \(last)"
            return PlayerProfile(
                id: position,
                name: name,
                number: usedNumbers[index],
                ratings: ratings(for: position, rng: &rng))
        }
        let primaryRGB = RGB(hex: primary)
        let secondaryRGB = RGB(hex: secondary)
        let dark = RGB(primaryRGB.r * 0.38, primaryRGB.g * 0.38, primaryRGB.b * 0.38)
        let uniform = TeamUniform(
            primary: primaryRGB, secondary: secondaryRGB, trim: dark,
            helmet: primaryRGB, helmetStripe: secondaryRGB, pants: dark,
            numberFill: secondaryRGB, numberOutline: dark)
        return TeamDefinition(
            id: id, city: city, nickname: nickname, abbreviation: abbreviation,
            uniform: uniform, roster: roster)
    }

    private static func ratings(for position: Position, rng: inout CatalogRNG) -> Ratings {
        let base: (Int, Int, Int, Int) =
            switch position {
            case .qb: (58, 70, 72, 84)
            case .rb: (74, 86, 76, 68)
            case .laneLeft, .laneRight: (54, 88, 70, 76)
            case .laneCenter: (62, 82, 80, 84)
            case .lt, .lg, .rg, .rt: (88, 48, 82, 45)
            case .deL, .nt, .deR: (86, 58, 78, 52)
            case .mlb, .olb: (76, 76, 78, 65)
            case .cbL, .cbR: (54, 89, 74, 72)
            case .fs, .ss: (65, 84, 76, 74)
            }
        func varied(_ value: Int) -> Int { value + rng.next(13) - 6 }
        return Ratings(power: varied(base.0), speed: varied(base.1), endurance: varied(base.2), ability: varied(base.3))
    }
}

private struct CatalogRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

private enum AppScreen: Hashable {
    case title, teamSelect, manageTeams, settings, intro, game
}

struct RootView: View {
    @State private var session = GameSession()
    @State private var screen: AppScreen = .title
    @State private var selectedTeam = TeamCatalog.teams[0]
    @State private var opponentTeam = TeamCatalog.teams[1]
    @State private var managedTeam = TeamCatalog.teams[0]
    @State private var handledAutoStart = false
    private let supported = Renderer.isSupported(MTLCreateSystemDefaultDevice())

    var body: some View {
        if !supported {
            UnsupportedDeviceView()
        } else {
            ZStack {
                GameView(session: session)

                switch screen {
                case .title:
                    TitleView(
                        play: { screen = .teamSelect },
                        manage: { screen = .manageTeams },
                        settings: { screen = .settings })
                case .teamSelect:
                    TeamSelectView(back: { screen = .title }) { team in
                        selectedTeam = team
                        opponentTeam =
                            TeamCatalog.teams.filter { $0.id != team.id }.randomElement() ?? TeamCatalog.teams[1]
                        session.startGame(home: selectedTeam, away: opponentTeam)
                        screen = .intro
                    }
                case .manageTeams:
                    TeamManagementView(selected: $managedTeam, back: { screen = .title })
                case .settings:
                    SettingsView(session: session, back: { screen = .title })
                case .intro:
                    MatchupIntroView(home: selectedTeam, away: opponentTeam, spotlightHome: session.introSpotlightHome)
                case .game:
                    HUDView(session: session)
                    TouchControls(session: session)
                    Button("MENU") {
                        session.enterAttractMode()
                        screen = .title
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.75))
                    .overlay(Rectangle().stroke(.white.opacity(0.6), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 72)
                    .padding(.top, 12)
                }

                if session.showDevOverlay {
                    DevOverlay(session: session)
                }
            }
            .task(id: screen) {
                guard screen == .intro else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, screen == .intro else { return }
                session.beginGameplay()
                screen = .game
            }
            .onAppear {
                guard !handledAutoStart else { return }
                handledAutoStart = true
                #if DEBUG
                    switch UserDefaults.standard.string(forKey: "CBStoreScreen") {
                    case "teams":
                        screen = .teamSelect
                        return
                    case "roster":
                        screen = .manageTeams
                        return
                    case "plays":
                        session.startGame(home: selectedTeam, away: opponentTeam, seed: 2026, showIntro: false)
                        session.paused = true
                        screen = .game
                        return
                    case "action":
                        session.startGame(home: selectedTeam, away: opponentTeam, seed: 2026, showIntro: false)
                        session.autopilot = true
                        screen = .game
                        return
                    default:
                        break
                    }
                #endif
                if UserDefaults.standard.bool(forKey: "CBAutoStart") {
                    session.startGame(home: selectedTeam, away: opponentTeam, showIntro: false)
                    screen = .game
                }
            }
        }
    }
}

private struct MenuBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.78), .black.opacity(0.25), .black.opacity(0.82)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct TitleView: View {
    let play: () -> Void
    let manage: () -> Void
    let settings: () -> Void

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 14) {
                Image("BlockBowlTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 760, maxHeight: 190)
                    .accessibilityLabel("Block Bowl")
                MenuButton("KICKOFF", color: .blue, width: 480, action: play)
                HStack(spacing: 14) {
                    MenuButton("MANAGE TEAMS", color: .orange, width: 233, action: manage)
                    MenuButton("SETTINGS", color: .gray, width: 233, action: settings)
                }
            }
        }
    }
}

private struct MenuButton: View {
    let title: String
    let color: Color
    let width: CGFloat
    let action: () -> Void

    init(_ title: String, color: Color, width: CGFloat = 300, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .frame(width: width)
                .padding(.vertical, 11)
                .background(color.opacity(0.86))
                .overlay(Rectangle().stroke(.yellow, lineWidth: 2))
                .foregroundStyle(.white)
        }
    }
}

private struct TeamSelectView: View {
    let back: () -> Void
    let select: (TeamDefinition) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 14) {
                MenuHeader(title: "CHOOSE YOUR TEAM", back: back)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TeamCatalog.teams) { team in
                        Button {
                            select(team)
                        } label: {
                            TeamTile(team: team)
                        }
                    }
                }
                .padding(.horizontal, 90)
            }
            .padding(.vertical, 24)
        }
    }
}

private struct TeamTile: View {
    let team: TeamDefinition

    var body: some View {
        VStack(spacing: 5) {
            Text(team.abbreviation)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(team.secondaryColor)
            Text(team.name.uppercased())
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("OVR \(team.overall)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, minHeight: 94)
        .background(team.primaryColor.opacity(0.9))
        .overlay(Rectangle().stroke(team.secondaryColor, lineWidth: 3))
    }
}

private struct TeamManagementView: View {
    @Binding var selected: TeamDefinition
    let back: () -> Void

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 12) {
                MenuHeader(title: "MANAGE TEAMS", back: back)
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(TeamCatalog.teams) { team in
                                Button {
                                    selected = team
                                } label: {
                                    HStack {
                                        Text(team.abbreviation).font(
                                            .system(size: 16, weight: .black, design: .monospaced))
                                        Text(team.name).font(.system(size: 12, weight: .bold, design: .monospaced))
                                        Spacer()
                                        Text("\(team.overall)").font(
                                            .system(size: 12, weight: .black, design: .monospaced))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(team.id == selected.id ? team.primaryColor : .black.opacity(0.55))
                                    .overlay(
                                        Rectangle().stroke(
                                            team.secondaryColor.opacity(team.id == selected.id ? 1 : 0.35)))
                                }
                            }
                        }
                    }
                    .frame(width: 230)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(selected.name.uppercased())
                                .font(.system(size: 24, weight: .black, design: .monospaced))
                            Spacer()
                            Text("OVR \(selected.overall)")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                        RosterHeader()
                        ScrollView {
                            ForEach(selected.roster) { player in
                                RosterRow(player: player)
                            }
                        }
                    }
                    .padding(14)
                    .background(selected.primaryColor.opacity(0.65))
                    .overlay(Rectangle().stroke(selected.secondaryColor, lineWidth: 3))
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, 80)
            }
            .padding(.vertical, 22)
        }
    }
}

private struct RosterHeader: View {
    var body: some View {
        HStack {
            Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
            Text("PWR").frame(width: 42)
            Text("SPD").frame(width: 42)
            Text("END").frame(width: 42)
            Text("ABL").frame(width: 42)
        }
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .foregroundStyle(.yellow)
    }
}

private struct RosterRow: View {
    let player: PlayerProfile

    var body: some View {
        HStack {
            Text("#\(player.number) \(positionName(player.id))  \(player.name)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(player.ratings.power)").frame(width: 42)
            Text("\(player.ratings.speed)").frame(width: 42)
            Text("\(player.ratings.endurance)").frame(width: 42)
            Text("\(player.ratings.ability)").frame(width: 42)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider().background(.white.opacity(0.2)) }
    }

    private func positionName(_ position: Position) -> String {
        switch position {
        case .laneLeft, .laneCenter, .laneRight: "WR"
        case .deL, .deR: "DE"
        case .cbL, .cbR: "CB"
        default: position.rawValue.uppercased()
        }
    }
}

private struct SettingsView: View {
    @Bindable var session: GameSession
    let back: () -> Void
    @AppStorage("CBMasterVolume") private var masterVolume = 0.85
    @AppStorage("CBMusicVolume") private var musicVolume = 0.7
    @AppStorage("CBSFXVolume") private var sfxVolume = 0.9
    @AppStorage("CBCrowdVolume") private var crowdVolume = 0.8
    @AppStorage("CBShadows") private var shadows = true
    @AppStorage("CBBloom") private var bloom = true
    @AppStorage("CBDynamicResolution") private var dynamicResolution = true

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 10) {
                MenuHeader(title: "SETTINGS", back: back)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AUDIO").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(
                            .yellow)
                        VolumeRow("MASTER", value: $masterVolume)
                        VolumeRow("MUSIC", value: $musicVolume)
                        VolumeRow("SFX", value: $sfxVolume)
                        VolumeRow("CROWD", value: $crowdVolume)
                        if !session.audioError.isEmpty {
                            Text("AUDIO UNAVAILABLE: \(session.audioError)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                        Divider().background(.white.opacity(0.4))
                        Text("VIDEO").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(
                            .yellow)
                        Toggle("SHADOWS", isOn: $shadows)
                        Toggle("BLOOM", isOn: $bloom)
                        Toggle("DYNAMIC RESOLUTION", isOn: $dynamicResolution)
                    }
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(18)
                    .frame(width: 440)
                    .background(.black.opacity(0.72))
                    .overlay(Rectangle().stroke(.white.opacity(0.45), lineWidth: 2))
                }
                .scrollIndicators(.visible)
            }
            .padding(.vertical, 14)
        }
        .onAppear {
            applyAudio()
            applyVideo()
        }
        .onChange(of: masterVolume) { _, _ in applyAudio() }
        .onChange(of: musicVolume) { _, _ in applyAudio() }
        .onChange(of: sfxVolume) { _, _ in applyAudio() }
        .onChange(of: crowdVolume) { _, _ in applyAudio() }
        .onChange(of: shadows) { _, _ in applyVideo() }
        .onChange(of: bloom) { _, _ in applyVideo() }
        .onChange(of: dynamicResolution) { _, _ in applyVideo() }
    }

    private func applyAudio() {
        session.setAudio(
            master: Float(masterVolume), music: Float(musicVolume),
            sfx: Float(sfxVolume), crowd: Float(crowdVolume))
    }

    private func applyVideo() {
        session.settings.shadows = shadows
        session.settings.bloom = bloom
        session.settings.dynamicResolution = dynamicResolution
    }
}

private struct VolumeRow: View {
    let title: String
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text("\(Int(value * 100))").frame(width: 38, alignment: .trailing)
        }
    }
}

private struct MenuHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            Button("‹ BACK", action: back)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Text(title)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(.yellow)
            Spacer()
            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, 36)
    }
}

private struct MatchupIntroView: View {
    let home: TeamDefinition
    let away: TeamDefinition
    let spotlightHome: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.8)],
                startPoint: .top, endPoint: .bottom)
            VStack {
                Text("TONIGHT'S MATCHUP")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .padding(.top, 26)
                Spacer()
                HStack(spacing: 30) {
                    IntroTeam(team: home, active: spotlightHome)
                    Text("VS")
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundStyle(.yellow)
                    IntroTeam(team: away, active: !spotlightHome)
                }
                Spacer()
                Text("\(spotlightHome ? home.name : away.name) WARMING UP")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct IntroTeam: View {
    let team: TeamDefinition
    let active: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(team.abbreviation)
                .font(.system(size: 48, weight: .black, design: .monospaced))
                .foregroundStyle(team.secondaryColor)
            Text(team.name.uppercased())
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(team.primaryColor.opacity(active ? 0.92 : 0.45))
        .overlay(Rectangle().stroke(team.secondaryColor, lineWidth: active ? 4 : 1))
        .scaleEffect(active ? 1.08 : 0.94)
        .animation(.easeInOut(duration: 0.35), value: active)
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
