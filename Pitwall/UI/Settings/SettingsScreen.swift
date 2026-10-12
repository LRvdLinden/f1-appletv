import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Taal catalogus", selection: $settings.catalogLanguage) {
                        ForEach(CatalogLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Commentaar", selection: $settings.audioLanguage) {
                        ForEach(CatalogLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Ondertitels", isOn: $settings.showCaptions)
                } header: {
                    Text("Taal")
                } footer: {
                    Text("Commentaar in je taal wordt gekozen als F1 TV het voor die sessie aanbiedt.")
                }

                Section("Afspelen") {
                    Picker("Live-sessies starten", selection: $settings.liveStart) {
                        ForEach(LiveStart.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Standaardfeed", selection: $settings.defaultFeed) {
                        ForEach(DefaultFeed.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Kwaliteit", selection: $settings.quality) {
                        ForEach(StreamQuality.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Kwaliteit in multiview", selection: $settings.multiviewQuality) {
                        ForEach(StreamQuality.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Kijkvoortgang bijhouden bij F1 TV", isOn: $settings.reportProgress)
                }

                Section {
                    if model.savedSetups.isEmpty {
                        Text("Nog geen setups. Sla er een op vanuit de multiview-bediening.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.savedSetups) { setup in
                        HStack {
                            Label(setup.name, systemImage: "square.stack.3d.up")
                            Spacer()
                            Text("\(setup.feedKeys.count) feeds · \(setup.layout.displayName)")
                                .foregroundStyle(.secondary)
                            #if os(tvOS) || os(macOS)
                            Button(role: .destructive) {
                                model.deleteSetup(setup)
                            } label: {
                                Image(systemName: "trash")
                            }
                            #endif
                        }
                    }
                    #if os(iOS)
                    .onDelete { model.savedSetups.remove(atOffsets: $0) }
                    #endif
                } header: {
                    Text("Multiview-setups")
                }

                Section("Over") {
                    LabeledContent("Versie", value: Self.version)
                    Link(destination: URL(string: "https://github.com/LRvdLinden/f1-appletv")!) {
                        Label("Broncode en changelog", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Pitwall is onofficieel en niet verbonden aan de Formula 1-bedrijven. Je hebt een eigen F1 TV-abonnement nodig.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Instellingen")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
