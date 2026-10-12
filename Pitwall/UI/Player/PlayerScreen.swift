import SwiftUI
import AVKit

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    @State private var session: MultiviewSession?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                switch session.state {
                case .loading:
                    LoadingView(title: "Stream voorbereiden…")
                case .failed(let message):
                    VStack(spacing: 20) {
                        ErrorStateView(message: message) { Task { await session.start() } }
                        Button("Sluiten") { dismiss() }
                    }
                case .ready:
                    PlayerContent(session: session, close: close)
                }
            } else {
                LoadingView(title: "Stream voorbereiden…")
            }
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .navigationTitle(session?.title ?? request.title)
        #endif
        .task {
            guard session == nil else { return }
            let newSession = MultiviewSession(request: request, service: model.playback, settings: model.settings)
            session = newSession
            await newSession.start()
        }
        .onDisappear { session?.stop() }
    }

    private func close() {
        session?.stop()
        dismiss()
    }
}

// MARK: - Platform layouts

private struct PlayerContent: View {
    @Bindable var session: MultiviewSession
    let close: () -> Void

    var body: some View {
        #if os(tvOS)
        TVPlayerLayout(session: session, close: close)
        #else
        AdaptivePlayerLayout(session: session, close: close)
        #endif
    }
}

/// The video area: native player for one feed, custom grid for several.
struct VideoArea: View {
    @Bindable var session: MultiviewSession
    var tvMenu: [Any] = []

    var body: some View {
        if !session.isMultiview, let player = session.players.first {
            #if os(tvOS)
            SystemPlayerView(player: player.player, menuItems: tvMenu.compactMap { $0 as? UIMenuElement })
            #else
            SystemPlayerView(player: player.player)
            #endif
        } else {
            MultiviewGrid(session: session)
        }
    }
}

#if os(tvOS)
private struct TVPlayerLayout: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: MultiviewSession
    let close: () -> Void
    @State private var showFeeds = false

    var body: some View {
        Group {
            if session.isMultiview {
                VStack(spacing: 0) {
                    MultiviewGrid(session: session)
                    MultiviewControls(session: session, showFeeds: $showFeeds, close: close)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                        .background(.black)
                }
                .ignoresSafeArea()
                .onPlayPauseCommand { session.togglePlay() }
                .onExitCommand { close() }
            } else {
                VideoArea(session: session, tvMenu: transportMenu)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showFeeds) {
            FeedManagerSheet(session: session)
        }
    }

    /// Extra items in the tvOS transport bar while watching a single feed.
    private var transportMenu: [Any] {
        let feeds = session.feeds.map { feed in
            UIAction(title: feed.displayTitle, image: UIImage(systemName: feed.symbol), state: session.isOpen(feed) ? .on : .off) { _ in
                session.switchTo(feed)
            }
        }
        var items: [UIMenuElement] = [
            UIMenu(title: String(localized: "Feeds"), image: UIImage(systemName: "rectangle.stack"), children: feeds),
            UIAction(title: String(localized: "Multiview"), image: UIImage(systemName: "rectangle.split.2x2")) { _ in showFeeds = true }
        ]
        if let player = session.focused, player.audioTracks.count > 1 {
            let tracks = player.audioTracks.map { track in
                UIAction(title: track.name, state: player.selectedAudio == track.id ? .on : .off) { _ in player.selectAudio(track.id) }
            }
            items.append(UIMenu(title: String(localized: "Commentaar"), image: UIImage(systemName: "waveform"), children: tracks))
        }
        return items
    }
}
#else
private struct AdaptivePlayerLayout: View {
    @Bindable var session: MultiviewSession
    let close: () -> Void
    @State private var showPanel = true
    @State private var showFeeds = false
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var isCompactLandscape: Bool {
        #if os(iOS)
        return verticalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900 && geo.size.width > geo.size.height
            Group {
                if isCompactLandscape {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            VideoArea(session: session)
                            if session.isMultiview {
                                MultiviewControls(session: session, showFeeds: $showFeeds, close: close).padding(8)
                            }
                        }
                        closeButton.padding(12)
                    }
                    .ignoresSafeArea(edges: .horizontal)
                } else if wide {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            topBar
                            VideoArea(session: session)
                            if session.isMultiview {
                                MultiviewControls(session: session, showFeeds: $showFeeds, close: close)
                                    .padding(12)
                            }
                        }
                        if showPanel {
                            Divider()
                            FeedPanel(session: session)
                                .frame(width: 340)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        VideoArea(session: session)
                            .aspectRatio(16 / 9, contentMode: .fit)
                        if session.isMultiview {
                            MultiviewControls(session: session, showFeeds: $showFeeds, close: close)
                                .padding(10)
                        }
                        FeedPanel(session: session)
                    }
                }
            }
        }
        .sheet(isPresented: $showFeeds) { FeedManagerSheet(session: session) }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.headline)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            closeButton
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.headline).lineLimit(1)
                if let race = session.details?.item.race, let name = race.meetingName {
                    Text("\(race.flag ?? "") \(name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { withAnimation { showPanel.toggle() } } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Feeds tonen of verbergen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }
}
#endif

// MARK: - Shared controls

/// Linked transport controls for multiview.
struct MultiviewControls: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: MultiviewSession
    @Binding var showFeeds: Bool
    let close: () -> Void
    @State private var naming = false
    @State private var setupName = ""

    private var hasLive: Bool { session.players.contains { $0.isLive } }

    var body: some View {
        HStack(spacing: controlSpacing) {
            control("gobackward.10", "10 s terug") { session.skip(by: -10) }
                .shortcut("left")
            control(session.isPaused ? "play.fill" : "pause.fill", session.isPaused ? "Afspelen" : "Pauzeren") { session.togglePlay() }
                .shortcut("space")
            control("goforward.10", "10 s vooruit") { session.skip(by: 10) }
                .shortcut("right")
            if hasLive {
                control("dot.radiowaves.left.and.right", "Live") { session.goLive() }
            }
            control("arrow.triangle.2.circlepath", "Synchroniseer") { session.syncAll() }
                .shortcut("s")

            Spacer()

            Menu {
                Picker("Indeling", selection: $session.layout) {
                    ForEach(MultiviewLayout.allCases) { layout in
                        Label(layout.displayName, systemImage: layout.symbol).tag(layout)
                    }
                }
            } label: {
                Label("Indeling", systemImage: session.effectiveLayout.symbol)
            }

            if let focused = session.focused, focused.audioTracks.count > 1 {
                Menu {
                    ForEach(focused.audioTracks) { track in
                        Button {
                            focused.selectAudio(track.id)
                        } label: {
                            if focused.selectedAudio == track.id { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                        }
                    }
                } label: {
                    Label("Commentaar", systemImage: "waveform")
                }
            }

            control("rectangle.stack.badge.plus", "Feeds") { showFeeds = true }
            control("square.and.arrow.down", "Setup opslaan") { setupName = ""; naming = true }
            #if os(tvOS)
            control("xmark", "Sluiten", action: close)
            #endif
        }
        .labelStyle(.iconOnly)
        .font(controlFont)
        .foregroundStyle(.white)
        .alert("Setup opslaan", isPresented: $naming) {
            TextField("Naam", text: $setupName)
            Button("Opslaan") {
                let name = setupName.trimmingCharacters(in: .whitespaces)
                model.saveSetup(session.currentSetup(named: name.isEmpty ? String(localized: "Mijn setup") : name))
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Bewaart de geopende feeds en de indeling, zodat je ze bij een volgende sessie in één keer opent.")
        }
    }

    private var controlSpacing: CGFloat {
        #if os(tvOS)
        return 30
        #else
        return 18
        #endif
    }

    private var controlFont: Font {
        #if os(tvOS)
        return .title3
        #else
        return .title3
        #endif
    }

    private func control(_ symbol: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        .help(title)
        #endif
    }
}

extension View {
    /// Keyboard shortcut on iOS/iPadOS/macOS; a no-op on tvOS.
    @ViewBuilder
    func shortcut(_ key: String) -> some View {
        #if os(tvOS)
        self
        #else
        switch key {
        case "space": self.keyboardShortcut(.space, modifiers: [])
        case "left": self.keyboardShortcut(.leftArrow, modifiers: [])
        case "right": self.keyboardShortcut(.rightArrow, modifiers: [])
        default: self.keyboardShortcut(KeyEquivalent(key.first ?? " "), modifiers: [])
        }
        #endif
    }
}
