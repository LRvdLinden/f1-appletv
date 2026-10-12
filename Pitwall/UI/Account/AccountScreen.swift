import SwiftUI

struct AccountScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showF1Login = false
    @State private var showSendToTV = false
    @State private var showLinkTV = false
    @State private var confirmF1SignOut = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    pitwallSection
                    f1Section
                    disclaimer
                }
                .padding(Theme.horizontalPadding)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .navigationTitle("Account")
            .navigationDestination(for: String.self) { route in
                if route == "devices" { DevicesScreen() }
            }
        }
        #if !os(tvOS)
        .sheet(isPresented: $showF1Login) { WebLoginSheet() }
        .sheet(isPresented: $showSendToTV) { SendToTVSheet() }
        .sheet(isPresented: $showLinkTV) { LinkTVSheet(code: "") }
        #endif
    }

    // MARK: Pitwall-account

    @ViewBuilder private var pitwallSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pitwall-account").font(.title2.bold())
            if let session = model.pitwall.session {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingelogd als \(session.email)").font(.headline)
                        Label(iCloudStatus, systemImage: "icloud").font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    #if !os(tvOS)
                    Button { showLinkTV = true } label: { Label("Tv koppelen", systemImage: "appletv") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    #endif
                    NavigationLink(value: "devices") { Label("Apparaten", systemImage: "laptopcomputer.and.iphone") }
                    HStack(spacing: 16) {
                        Button { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Account verwijderen", systemImage: "trash") }
                    }
                    if let deleteError { Text(deleteError).foregroundStyle(.orange).font(.callout) }
                }
                .confirmationDialog("Uitloggen bij Pitwall op dit apparaat?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Uitloggen", role: .destructive) { Task { await model.pitwall.signOut() } }
                    Button("Annuleren", role: .cancel) {}
                }
                .confirmationDialog("Je Pitwall-account verwijderen? Dit kan niet ongedaan worden gemaakt.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Account verwijderen", role: .destructive) {
                        Task {
                            do { try await model.pitwall.deleteAccount() }
                            catch { deleteError = error.localizedDescription }
                        }
                    }
                    Button("Annuleren", role: .cancel) {}
                }
            } else {
                Text("Zonder account: instellingen en F1 TV-login gaan alleen via iCloud mee.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iCloudStatus: String {
        FileManager.default.ubiquityIdentityToken != nil
            ? String(localized: "iCloud-sync staat aan")
            : String(localized: "iCloud niet beschikbaar; sync loopt via je account")
    }

    // MARK: F1 TV

    @ViewBuilder private var f1Section: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("F1 TV").font(.title2.bold())
            if let session = model.account.session {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("Naam", session.displayName)
                    if let email = session.email { infoRow("E-mail", email) }
                    infoRow("Abonnement", session.subscriptionTier ?? session.subscriptionStatus ?? "—")
                    if let country = session.country { infoRow("Land", country) }
                    if let expiry = session.tokenExpiry { infoRow("Sessie geldig tot", expiry.formatted(date: .abbreviated, time: .shortened)) }
                }
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if model.account.sessionExpired {
                    Label("F1 TV heeft je sessie beëindigd. Log opnieuw in.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 16) {
                    #if !os(tvOS)
                    if model.account.sessionExpired {
                        Button { showF1Login = true } label: { Label("Opnieuw inloggen", systemImage: "person.crop.circle.badge.checkmark") }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    Button { showSendToTV = true } label: { Label("Naar Apple TV in dit netwerk", systemImage: "wifi") }
                    #endif
                    Button { Task { try? await model.account.refresh() } } label: { Label("Sessie vernieuwen", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confirmF1SignOut = true } label: { Label("Uitloggen bij F1 TV", systemImage: "rectangle.portrait.and.arrow.right") }
                }
                .confirmationDialog("Uitloggen bij F1 TV? Dit geldt voor al je gekoppelde apparaten.", isPresented: $confirmF1SignOut, titleVisibility: .visible) {
                    Button("Uitloggen", role: .destructive) { model.account.signOut() }
                    Button("Annuleren", role: .cancel) {}
                }
            } else {
                Text("Pitwall gebruikt je eigen F1 TV-abonnement. Log één keer in; via je account en iCloud zijn je andere apparaten daarna ook ingelogd.")
                    .foregroundStyle(.secondary)
                #if os(tvOS)
                Text("Log in op je iPhone, iPad of Mac met hetzelfde Pitwall-account; deze Apple TV neemt de F1 TV-login dan vanzelf over. Of koppel via je netwerk:")
                    .foregroundStyle(.secondary)
                TVPairingView()
                #else
                Button { showF1Login = true } label: {
                    Label("Inloggen met F1 TV", systemImage: "person.crop.circle.badge.checkmark").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                Text("Je logt in op de officiële F1-pagina. Pitwall bewaart alleen de sessie, nooit je wachtwoord.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
    }

    private var disclaimer: some View {
        Text("Pitwall is een onofficiële app en is niet verbonden aan de Formula 1-bedrijven. F1, FORMULA ONE, FORMULA 1 en verwante merken zijn handelsmerken van Formula One Licensing B.V.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}
