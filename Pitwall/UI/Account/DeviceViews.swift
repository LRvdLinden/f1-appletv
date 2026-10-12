import SwiftUI

#if !os(tvOS)
/// Code van een Apple TV goedkeuren (handmatig of via de gescande QR-code).
struct LinkTVSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var code: String
    @State private var busy = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("K7Q-4MX", text: $code)
                        .font(.title2.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    Button {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do {
                                let device = try await model.pitwall.approve(code: code)
                                result = String(localized: "\(device) is nu ingelogd.")
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    } label: {
                        if busy { ProgressView() } else { Label("Koppelen", systemImage: "link") }
                    }
                    .disabled(busy || code.filter { $0.isLetter || $0.isNumber }.count != 6)
                } header: {
                    Text("Vul de code in die op je tv staat")
                } footer: {
                    if let result {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if let error {
                        Text(error).foregroundStyle(.orange)
                    } else {
                        Text("Je Apple TV logt in met je Pitwall-account en krijgt meteen je F1 TV-login, instellingen en setups.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tv koppelen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 320)
        #endif
    }
}
#endif

/// Gekoppelde apparaten: lijst, hernoemen, verwijderen.
struct DevicesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var devices: [AccountDevice] = []
    @State private var limit = 10
    @State private var error: String?
    @State private var renaming: AccountDevice?
    @State private var newName = ""
    @State private var removing: AccountDevice?

    var body: some View {
        List {
            Section {
                ForEach(devices) { device in
                    row(device)
                }
            } header: {
                Text("\(devices.count) van \(limit) apparaten")
            } footer: {
                if let error { Text(error).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Apparaten")
        .task { await load() }
        #if !os(tvOS)
        .refreshable { await load() }
        #endif
        .alert("Naam van het apparaat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Naam", text: $newName)
            Button("Bewaar") {
                guard let device = renaming else { return }
                Task { try? await model.pitwall.renameDevice(device.id, to: newName); await load() }
            }
            Button("Annuleren", role: .cancel) {}
        }
        .confirmationDialog(removing.map { String(localized: "\($0.name) verwijderen? Het apparaat wordt uitgelogd.") } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) {
                guard let device = removing else { return }
                Task { try? await model.pitwall.removeDevice(device.id); await load() }
            }
            Button("Annuleren", role: .cancel) {}
        }
    }

    private func row(_ device: AccountDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: device.symbol).font(.title2).frame(width: 36).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name.isEmpty ? device.platform : device.name).font(.headline)
                    if device.isCurrent { Badge(text: String(localized: "DIT APPARAAT"), color: Theme.accent) }
                }
                Text(device.platform).font(.caption).foregroundStyle(.secondary)
                if let linked = device.signedInAt ?? device.createdAt {
                    Text("Gekoppeld \(linked.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
                Text("Laatst gebruikt \(device.isCurrent ? String(localized: "nu") : Self.relative(device.lastSeenAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { newName = device.name; renaming = device } label: { Label("Hernoemen", systemImage: "pencil") }
                Button(role: .destructive) { removing = device } label: { Label("Verwijderen", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            let result = try await model.pitwall.listDevices()
            devices = result.devices
            limit = result.limit
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 120 { return String(localized: "zojuist") }
        if seconds < 3600 { return String(localized: "\(Int(seconds / 60)) min geleden") }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "gisteren") }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
