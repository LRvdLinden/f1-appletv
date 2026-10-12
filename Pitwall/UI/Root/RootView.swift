import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        content
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .task {
                await model.loadMenu()
                await model.resume()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await model.resume() } }
            }
            .onChange(of: model.settings.catalogLanguage) {
                Task { await model.languageChanged() }
            }
            .onOpenURL { model.handle($0) }
            #if os(macOS)
            .onChange(of: model.activePlayback) {
                if let request = model.activePlayback {
                    openWindow(value: request)
                    model.activePlayback = nil
                }
            }
            .sheet(isPresented: $model.showLogin) { WebLoginSheet() }
            #else
            .fullScreenCover(item: $model.activePlayback) { request in
                PlayerScreen(request: request)
                    .environment(model)
            }
            .sheet(isPresented: $model.showLogin) {
                #if os(tvOS)
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            Text("Log in bij F1 TV op je iPhone, iPad of Mac met hetzelfde Pitwall-account; deze Apple TV neemt de login vanzelf over. Of koppel via je netwerk:")
                                .foregroundStyle(.secondary)
                            TVPairingView()
                        }
                        .padding(60)
                    }
                }
                .onChange(of: model.account.isSignedIn) {
                    if model.account.isSignedIn { model.showLogin = false }
                }
                #else
                WebLoginSheet()
                #endif
            }
            #endif
            #if !os(tvOS)
            .sheet(item: $model.recovery) { link in
                ResetPasswordSheet(link: link).environment(model)
            }
            .sheet(isPresented: Binding(
                get: { model.pendingLinkCode != nil && model.pitwall.phase == .signedIn },
                set: { if !$0 { model.pendingLinkCode = nil } }
            )) {
                LinkTVSheet(code: model.pendingLinkCode ?? "").environment(model)
            }
            #endif
    }

    @ViewBuilder private var content: some View {
        if model.menu.isEmpty && model.menuError == nil && model.isLoadingMenu {
            SplashView()
        } else if !model.pitwall.mayUseApp {
            if case .deviceLimit(let limit, let devices) = model.pitwall.phase {
                DeviceLimitScreen(limit: limit, devices: devices)
            } else {
                AuthScreen()
            }
        } else if model.menu.isEmpty {
            if let error = model.menuError {
                ErrorStateView(message: error) { Task { await model.loadMenu(force: true) } }
                    .background(Theme.background)
            } else {
                SplashView()
            }
        } else {
            #if os(macOS)
            MacSidebarLayout()
            #else
            TabLayout()
            #endif
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                PitwallWordmark()
                ProgressView()
            }
        }
    }
}

enum MenuIcon {
    static func symbol(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("home") || lower.contains("start") { return "house" }
        if lower.contains("live") { return "dot.radiowaves.left.and.right" }
        if lower.contains("archive") || lower.contains("archief") || lower.contains("archiv") { return "archivebox" }
        if lower.contains("show") { return "sparkles.tv" }
        if lower.contains("doc") { return "film" }
        if lower.contains("f2") || lower.contains("f3") || lower.contains("academy") || lower.contains("porsche") { return "car.2" }
        if lower.range(of: #"\d{4}"#, options: .regularExpression) != nil || lower.contains("season") || lower.contains("seizoen") { return "flag.checkered" }
        return "play.rectangle"
    }
}

#if !os(macOS)
private struct TabLayout: View {
    @Environment(AppModel.self) private var model
    /// Launch argument `-initialTab account|settings` (used for screenshots).
    @State private var selection = UserDefaults.standard.string(forKey: "initialTab") ?? ""

    /// tvOS has room for a handful of tabs; the rest goes under "Meer".
    private var visibleCount: Int {
        #if os(tvOS)
        return model.menu.count > 4 ? 3 : model.menu.count
        #else
        return model.menu.count
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(model.menu.prefix(visibleCount)) { ref in
                BrowseStack(root: ref)
                    .tabItem { Label(ref.title, systemImage: MenuIcon.symbol(for: ref.title)) }
                    .tag(ref.uri)
            }
            if visibleCount < model.menu.count {
                MoreScreen(pages: Array(model.menu.dropFirst(visibleCount)))
                    .tabItem { Label("Meer", systemImage: "ellipsis.circle") }
                    .tag("more")
            }
            AccountScreen()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag("account")
            SettingsScreen()
                .tabItem { Label("Instellingen", systemImage: "gearshape") }
                .tag("settings")
        }
        .onAppear {
            if selection.isEmpty { selection = model.menu.first?.uri ?? "account" }
        }
    }
}

/// Remaining catalog sections (tvOS).
private struct MoreScreen: View {
    let pages: [PageRef]

    var body: some View {
        NavigationStack {
            List(pages) { ref in
                NavigationLink(value: ref) {
                    Label(ref.title, systemImage: MenuIcon.symbol(for: ref.title))
                }
            }
            .navigationTitle("Meer")
            .navigationDestination(for: PageRef.self) { PageScreen(ref: $0) }
            .navigationDestination(for: CatalogItem.self) { VideoDetailScreen(item: $0) }
        }
    }
}
#else
private struct MacSidebarLayout: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("F1 TV") {
                    ForEach(model.menu) { ref in
                        Label(ref.title, systemImage: MenuIcon.symbol(for: ref.title)).tag(Optional(ref.uri))
                    }
                }
                Section {
                    Label("Account", systemImage: "person.crop.circle").tag(Optional("account"))
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if selection == "account" {
                AccountScreen()
            } else if let ref = model.menu.first(where: { $0.uri == selection }) ?? model.menu.first {
                BrowseStack(root: ref).id(ref.uri)
            }
        }
        .onAppear { if selection == nil { selection = model.menu.first?.uri } }
    }
}
#endif
