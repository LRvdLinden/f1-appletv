import Foundation
import AVFoundation
import Observation

/// One stream (main broadcast, F1 Live, an onboard…) with its own AVPlayer.
@MainActor
@Observable
final class FeedPlayer: Identifiable {
    enum State: Equatable {
        case loading, ready, failed(String)
    }

    struct AudioTrack: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    let feed: Feed
    let player = AVPlayer()
    private(set) var state: State = .loading
    private(set) var audioTracks: [AudioTrack] = []
    private(set) var selectedAudio: Int?
    private(set) var isLive = false
    var id: String { feed.id }

    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue; mutedFlag = newValue }
    }
    /// Mirrors `player.isMuted` so SwiftUI observes changes.
    private(set) var mutedFlag = false

    @ObservationIgnored private var keySession: AVContentKeySession?
    @ObservationIgnored private var keyDelegate: FairPlayKeyDelegate?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var audioOptions: [AVMediaSelectionOption] = []
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?

    init(feed: Feed) {
        self.feed = feed
        player.allowsExternalPlayback = true
        #if os(iOS) || os(tvOS)
        player.preventsDisplaySleepDuringVideoPlayback = true
        #endif
    }

    struct Options {
        var quality: StreamQuality
        var fromBeginning: Bool
        var resumeSeconds: Double?
        var audioCode: String
        var captions: Bool
        var muted: Bool
    }

    func load(service: PlaybackService, options: Options) async {
        state = .loading
        do {
            let entitlement = try await service.entitlement(for: feed)
            let asset = AVURLAsset(url: entitlement.streamURL)

            if entitlement.isFairPlay {
                let certificate = try await service.fairPlayCertificate()
                let delegate = FairPlayKeyDelegate(certificate: certificate) { spc, assetID in
                    try await service.license(spc: spc, assetID: assetID, entitlement: entitlement)
                }
                let session = AVContentKeySession(keySystem: .fairPlayStreaming)
                session.setDelegate(delegate, queue: delegate.queue)
                session.addContentKeyRecipient(asset)
                keySession = session
                keyDelegate = delegate
            }

            let item = AVPlayerItem(asset: asset)
            item.preferredPeakBitRate = options.quality.peakBitRate
            item.preferredMaximumResolution = options.quality.maxSize
            item.preferredForwardBufferDuration = 4
            player.isMuted = options.muted
            mutedFlag = options.muted
            player.replaceCurrentItem(with: item)

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let status = item.status
                let message = item.error?.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    switch status {
                    case .readyToPlay:
                        if self.state != .ready {
                            self.state = .ready
                            await self.prepare(item: item, options: options)
                        }
                    case .failed:
                        self.state = .failed(message ?? String(localized: "Afspelen mislukt."))
                    default:
                        break
                    }
                }
            }
            player.play()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prepare(item: AVPlayerItem, options: Options) async {
        isLive = item.duration.isIndefinite
        if isLive && options.fromBeginning, let start = item.seekableTimeRanges.first?.timeRangeValue.start {
            await player.seek(to: start)
        } else if !isLive, let resume = options.resumeSeconds, resume > 30 {
            await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        await loadAudio(item: item, preferred: options.audioCode)
        await applyCaptions(item: item, enabled: options.captions, language: options.audioCode)
        player.play()
    }

    private func loadAudio(item: AVPlayerItem, preferred: String) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
        audioGroup = group
        audioOptions = group.options
        audioTracks = group.options.enumerated().map { AudioTrack(id: $0.offset, name: Self.name(for: $0.element)) }
        let short = Self.shortCode(preferred)
        if let index = group.options.firstIndex(where: { Self.matches($0, code: preferred, short: short) }) {
            selectAudio(index)
        } else if let current = item.currentMediaSelection.selectedMediaOption(in: group) {
            selectedAudio = group.options.firstIndex(of: current)
        }
    }

    private func applyCaptions(item: AVPlayerItem, enabled: Bool, language: String) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
        guard enabled else { item.select(nil, in: group); return }
        let short = Self.shortCode(language)
        let option = group.options.first { Self.matches($0, code: language, short: short) } ?? group.options.first
        item.select(option, in: group)
    }

    func selectAudio(_ index: Int) {
        guard let group = audioGroup, audioOptions.indices.contains(index) else { return }
        player.currentItem?.select(audioOptions[index], in: group)
        selectedAudio = index
    }

    // MARK: Transport

    var currentTime: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }

    func skip(by seconds: Double) {
        let target = player.currentTime() + CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func goLive() {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        player.seek(to: range.end)
        player.play()
    }

    func seek(toDate date: Date?, orTime time: CMTime) {
        if let date, let item = player.currentItem, item.seek(to: date, completionHandler: nil) { return }
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func startReporting(every seconds: Double, report: @escaping @MainActor (Double) -> Void) {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: seconds, preferredTimescale: 1), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isLive, self.player.rate > 0 else { return }
                report(time.seconds)
            }
        }
    }

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        keySession?.expire()
        keySession = nil
        keyDelegate = nil
    }

    // MARK: Helpers

    private static func shortCode(_ code: String) -> String {
        ["eng": "en", "nld": "nl", "deu": "de", "fra": "fr", "spa": "es", "por": "pt"][code] ?? code
    }

    private static func matches(_ option: AVMediaSelectionOption, code: String, short: String) -> Bool {
        let tag = (option.extendedLanguageTag ?? option.locale?.identifier ?? "").lowercased()
        return tag == code || tag.hasPrefix(short)
    }

    private static func name(for option: AVMediaSelectionOption) -> String {
        let display = option.displayName
        let tag = (option.extendedLanguageTag ?? "").lowercased()
        if tag == "obc" || display.lowercased().contains("fx") { return String(localized: "Teamradio / omgevingsgeluid") }
        return display.isEmpty ? tag.uppercased() : display
    }
}
