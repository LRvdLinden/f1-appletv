import Foundation
import Observation

/// App-wide state shared by every scene.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    /// F1 TV-sessie (streams).
    let account: AccountStore
    /// Pitwall-account (Supabase): verplicht inloggen, tv-koppeling, apparaten, sync.
    let pitwall: AccountService
    @ObservationIgnored let sync = SyncCoordinator()

    /// Code uit een gescande QR (pitwall://link?code=…) die nog bevestigd moet worden.
    var pendingLinkCode: String?
    /// Herstellink uit de e-mail (pitwall://reset#access_token=…).
    var recovery: RecoveryLink?
    /// Korte melding bovenin (bv. na het bevestigen van je e-mailadres).
    var banner: String?

    private(set) var menu: [PageRef] = []
    private(set) var menuError: String?
    private(set) var isLoadingMenu = false

    /// Set to start playback; iOS/tvOS present it full screen, macOS opens a window.
    var activePlayback: PlaybackRequest?
    /// Shown when the user tries to play without being signed in.
    var showLogin = false
    var savedSetups: [SavedSetup] = SetupStore.load() {
        didSet {
            SetupStore.save(savedSetups)
            sync.localChanged(.setups)
        }
    }

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.account = AccountStore(language: settings.catalogLanguage.rawValue)
        self.pitwall = AccountService()
        wireSync()
    }

    private func wireSync() {
        sync.account = pitwall
        sync.export = { [unowned self] section in
            switch section {
            case .f1tv: return account.session.map { SyncCoordinator.jsonObject($0) } ?? NSNull()
            case .settings: return settings.snapshot
            case .setups: return SyncCoordinator.jsonObject(savedSetups)
            }
        }
        sync.apply = { [unowned self] section, value in
            switch section {
            case .f1tv:
                if let session = SyncCoordinator.decodeObject(F1Session.self, from: value) {
                    if session != account.session { account.signIn(session) }
                } else if account.session != nil {
                    account.signOut()
                }
            case .settings:
                if let values = value as? [String: Any] { settings.apply(values) }
            case .setups:
                savedSetups = SyncCoordinator.decodeObject([SavedSetup].self, from: value) ?? []
            }
        }
        account.onSessionChange = { [unowned self] in sync.localChanged(.f1tv) }
        settings.onChange = { [unowned self] in sync.localChanged(.settings) }
        pitwall.onSignedIn = { [unowned self] in await sync.pullFromServer() }
        pitwall.onHeartbeat = { [unowned self] in await sync.pullFromServer() }
        sync.start()
    }

    /// Bij het starten en bij terugkeer naar de voorgrond.
    func resume() async {
        sync.pullFromCloud()
        await pitwall.resume()
        await account.refreshIfNeeded()
    }

    // MARK: Deeplinks

    func handle(_ url: URL) {
        guard url.scheme == "pitwall" else { return }
        switch url.host {
        case "link":
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
            pendingLinkCode = code
        case "reset":
            let fragment = URLComponents(string: "x://x?" + (url.fragment ?? ""))?.queryItems ?? []
            let value = { (name: String) in fragment.first { $0.name == name }?.value }
            if let token = value("access_token") {
                recovery = RecoveryLink(accessToken: token, refreshToken: value("refresh_token"))
            }
        case "confirmed":
            banner = String(localized: "Je e-mailadres is bevestigd. Je kunt nu inloggen.")
        default:
            break
        }
    }

    var catalog: CatalogService { CatalogService(endpoints: F1Endpoints(language: settings.catalogLanguage.rawValue)) }
    var playback: PlaybackService { PlaybackService(account: account) }

    func loadMenu(force: Bool = false) async {
        guard force || menu.isEmpty else { return }
        isLoadingMenu = true
        menuError = nil
        do {
            menu = try await catalog.menu()
        } catch {
            menuError = error.localizedDescription
        }
        isLoadingMenu = false
    }

    func languageChanged() async {
        account.language = settings.catalogLanguage.rawValue
        await loadMenu(force: true)
    }

    func play(_ request: PlaybackRequest) {
        guard account.isSignedIn else { showLogin = true; return }
        activePlayback = request
    }

    func play(_ item: CatalogItem, fromBeginning: Bool = false) {
        guard case .play(let target) = item.action else { return }
        var request = PlaybackRequest(contentID: target.contentID, title: item.title, fromBeginning: fromBeginning)
        if let channel = target.channelURI { request.feedTargets = [channel] }
        play(request)
    }

    func deleteSetup(_ setup: SavedSetup) {
        savedSetups.removeAll { $0.id == setup.id }
    }

    func saveSetup(_ setup: SavedSetup) {
        savedSetups.removeAll { $0.name.caseInsensitiveCompare(setup.name) == .orderedSame }
        savedSetups.append(setup)
    }
}

struct RecoveryLink: Identifiable {
    let accessToken: String
    let refreshToken: String?
    var id: String { accessToken }
}
