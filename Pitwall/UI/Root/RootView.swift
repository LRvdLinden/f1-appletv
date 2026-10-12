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
                await model.account.refreshIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await model.account.refreshIfNeeded() } }
            }
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
                    ScrollView { TVPairingView().padding(60) }
                }
                .onChange(of: model.account.isSignedIn) {
                    if model.account.isSignedIn { model.showLogin = false }
                }
                #else
                WebLoginSheet()
                #endif
            }
            #endif
    }

    @ViewBuilder private var content: some View {
        if model.menu.isEmpty {
            if let error = model.menuError {
                ErrorStateView(message: error) { Task { await model.loadMenu(force: true) } }
                    .background(Theme.background)
            } else {
                LoadingView(title: "F1 TV laden…")
                    .background(Theme.background)
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

    var body: some View {
        TabView {
            ForEach(model.menu) { ref in
                BrowseStack(root: ref)
                    .tabItem { Label(ref.title, systemImage: MenuIcon.symbol(for: ref.title)) }
                    .tag(ref.uri)
            }
            AccountScreen()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag("account")
            SettingsScreen()
                .tabItem { Label("Instellingen", systemImage: "gearshape") }
                .tag("settings")
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
