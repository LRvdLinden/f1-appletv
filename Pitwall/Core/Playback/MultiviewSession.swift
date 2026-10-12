import Foundation
import AVFoundation
import Observation

/// What to play. Codable so macOS can open it in its own window.
struct PlaybackRequest: Codable, Hashable, Identifiable {
    var contentID: String
    var title: String
    /// Feed targets to open; empty means "the default feed".
    var feedTargets: [String] = []
    var fromBeginning = false
    var id: String { contentID + feedTargets.joined(separator: ",") + (fromBeginning ? "-start" : "") }
}

/// A playback session with one or more feeds that share transport controls.
@MainActor
@Observable
final class MultiviewSession {
    enum State: Equatable { case loading, ready, failed(String) }

    private(set) var state: State = .loading
    private(set) var details: VideoDetails?
    private(set) var players: [FeedPlayer] = []
    var layout: MultiviewLayout = .auto
    private(set) var focusedID: String?
    private(set) var isPaused = false

    let request: PlaybackRequest
    @ObservationIgnored private let service: PlaybackService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastReport = Date.distantPast

    init(request: PlaybackRequest, service: PlaybackService, settings: AppSettings) {
        self.request = request
        self.service = service
        self.settings = settings
    }

    var title: String { details?.item.title ?? request.title }
    var feeds: [Feed] { details?.feeds ?? [] }
    var focused: FeedPlayer? { players.first { $0.id == focusedID } ?? players.first }
    var isMultiview: Bool { players.count > 1 }
    var effectiveLayout: MultiviewLayout {
        guard layout == .auto else { return layout }
        switch players.count {
        case 0, 1: return .single
        case 2: return .sideBySide
        case 3, 4: return .grid2x2
        default: return .grid3x3
        }
    }

    func start() async {
        state = .loading
        do {
            let details = try await service.details(contentID: request.contentID)
            self.details = details
            var initial: [Feed] = request.feedTargets.compactMap { target in details.feeds.first { $0.target == target } }
            if initial.isEmpty {
                let preferLive = settings.defaultFeed == .f1Live
                let live = details.feeds.first { $0.kind == .additional && $0.title.uppercased().contains("F1 LIVE") }
                initial = [preferLive ? (live ?? details.feeds[0]) : details.feeds[0]]
            }
            state = .ready
            for feed in initial { add(feed) }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Feeds

    func isOpen(_ feed: Feed) -> Bool { players.contains { $0.id == feed.id } }

    func add(_ feed: Feed) {
        if let existing = players.first(where: { $0.id == feed.id }) { focus(existing.id); return }
        guard players.count < 9 else { return }
        let player = FeedPlayer(feed: feed)
        let first = players.isEmpty
        players.append(player)
        if first { focusedID = player.id }
        if layout != .auto && players.count > layout.capacity { layout = .auto }
        let quality = players.count > 1 ? settings.multiviewQuality : settings.quality
        let options = FeedPlayer.Options(
            quality: quality,
            fromBeginning: request.fromBeginning,
            resumeSeconds: feed.kind == .main ? details?.item.resumeSeconds : nil,
            audioCode: settings.audioLanguage.audioCode,
            captions: settings.showCaptions,
            muted: !first
        )
        Task {
            await player.load(service: service, options: options)
            if !first { syncToFocused(player) }
        }
        if feed.kind == .main && settings.reportProgress {
            let service = self.service
            let contentID = request.contentID
            let subtype = details?.item.contentSubtype ?? "REPLAY"
            player.startReporting(every: 30) { position in
                Task { await service.report(contentID: contentID, subtype: subtype, position: position) }
            }
        }
        if players.count > 1 { applyMultiviewQuality() }
    }

    func remove(_ id: String) {
        guard players.count > 1, let index = players.firstIndex(where: { $0.id == id }) else { return }
        players[index].stop()
        players.remove(at: index)
        if focusedID == id { focus(players[0].id) }
    }

    /// Replaces the only/main feed (single view feed switching).
    func switchTo(_ feed: Feed) {
        guard let current = focused else { add(feed); return }
        if current.id == feed.id { return }
        if isOpen(feed) { focus(feed.id); return }
        let index = players.firstIndex { $0.id == current.id } ?? 0
        current.stop()
        players.remove(at: index)
        add(feed)
        if let added = players.last, index < players.count - 1 {
            players.removeLast()
            players.insert(added, at: index)
        }
        focus(feed.id)
    }

    func makeMain(_ id: String) {
        guard let index = players.firstIndex(where: { $0.id == id }), index > 0 else { focus(id); return }
        let player = players.remove(at: index)
        players.insert(player, at: 0)
        focus(id)
    }

    /// The focused feed plays sound; the others are muted.
    func focus(_ id: String) {
        focusedID = id
        for player in players { player.isMuted = player.id != id }
    }

    private func applyMultiviewQuality() {
        for player in players {
            player.player.currentItem?.preferredPeakBitRate = settings.multiviewQuality.peakBitRate
            player.player.currentItem?.preferredMaximumResolution = settings.multiviewQuality.maxSize
        }
    }

    // MARK: Linked transport

    func togglePlay() {
        isPaused.toggle()
        for player in players { isPaused ? player.player.pause() : player.player.play() }
    }

    func skip(by seconds: Double) {
        for player in players { player.skip(by: seconds) }
    }

    func goLive() {
        isPaused = false
        for player in players { player.goLive() }
    }

    /// Lines every feed up with the focused one, using program date-time when available.
    func syncAll() {
        for player in players where player.id != focused?.id { syncToFocused(player) }
    }

    private func syncToFocused(_ player: FeedPlayer) {
        guard let reference = focused, reference.id != player.id, let item = reference.player.currentItem else { return }
        player.seek(toDate: item.currentDate(), orTime: reference.player.currentTime())
        if isPaused { player.player.pause() }
    }

    // MARK: Setups

    func currentSetup(named name: String) -> SavedSetup {
        SavedSetup(name: name, layout: layout, feedKeys: players.map(\.feed.setupKey))
    }

    func apply(_ setup: SavedSetup) {
        let wanted = setup.feedKeys.compactMap { key in feeds.first { $0.setupKey == key } }
        guard !wanted.isEmpty else { return }
        for player in players where !wanted.contains(where: { $0.id == player.id }) {
            if players.count > 1 { remove(player.id) }
        }
        for feed in wanted { add(feed) }
        if players.count > wanted.count, let extra = players.first(where: { p in !wanted.contains { $0.id == p.id } }) {
            remove(extra.id)
        }
        layout = setup.layout
    }

    func stop() {
        for player in players { player.stop() }
        players.removeAll()
    }
}
