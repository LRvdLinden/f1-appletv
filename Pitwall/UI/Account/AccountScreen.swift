import SwiftUI

struct AccountScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showLogin = false
    @State private var showSendToTV = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let session = model.account.session {
                        signedIn(session)
                    } else {
                        signedOut
                    }
                    disclaimer
                }
                .padding(Theme.horizontalPadding)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .navigationTitle("Account")
        }
        #if !os(tvOS)
        .sheet(isPresented: $showLogin) { WebLoginSheet() }
        .sheet(isPresented: $showSendToTV) { SendToTVSheet() }
        #endif
    }

    @ViewBuilder
    private func signedIn(_ session: F1Session) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName).font(.title2.bold())
                if let email = session.email { Text(email).foregroundStyle(.secondary) }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            infoRow("Abonnement", session.subscriptionTier ?? session.subscriptionStatus ?? "—")
            if let status = session.subscriptionStatus { infoRow("Status", status.capitalized) }
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
            Button { showSendToTV = true } label: {
                Label("Apple TV koppelen", systemImage: "appletv")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            #endif
            Button { Task { try? await model.account.refresh() } } label: {
                Label("Sessie vernieuwen", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) { confirmSignOut = true } label: {
                Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .confirmationDialog("Uitloggen bij F1 TV?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { model.account.signOut() }
            Button("Annuleren", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log in met F1 TV").font(.title.bold())
            Text("Pitwall gebruikt je eigen F1 TV-abonnement. Welke streams, onboards en kwaliteit je ziet hangt af van dat abonnement.")
                .foregroundStyle(.secondary)
        }
        #if os(tvOS)
        TVPairingView()
        #else
        Button { showLogin = true } label: {
            Label("Inloggen met F1 TV", systemImage: "person.crop.circle.badge.checkmark")
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        Text("Je logt in op de officiële F1-pagina. Pitwall slaat alleen de sessie op in je sleutelhanger, nooit je wachtwoord.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        #endif
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
