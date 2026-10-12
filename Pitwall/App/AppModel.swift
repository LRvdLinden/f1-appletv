import Foundation
import Observation

/// App-wide state shared by every scene.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let account: AccountStore

    private(set) var menu: [PageRef] = []
    private(set) var menuError: String?
    private(set) var isLoadingMenu = false

    /// Set to start playback; iOS/tvOS present it full screen, macOS opens a window.
    var activePlayback: PlaybackRequest?
    /// Shown when the user tries to play without being signed in.
    var showLogin = false
    var savedSetups: [SavedSetup] = SetupStore.load() {
        didSet { SetupStore.save(savedSetups) }
    }

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.account = AccountStore(language: settings.catalogLanguage.rawValue)
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

    func saveSetup(_ setup: SavedSetup) {
        savedSetups.removeAll { $0.name.caseInsensitiveCompare(setup.name) == .orderedSame }
        savedSetups.append(setup)
    }
}
