import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Verplicht inlogscherm (na de splash, zonder geldige sessie).
struct AuthScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AuthBackdrop()
            #if os(tvOS)
            TVAuthLayout()
            #else
            ScrollView {
                VStack(spacing: 28) {
                    PitwallWordmark()
                        .padding(.top, 40)
                    EmailAuthCard()
                        .frame(maxWidth: 440)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }
}

/// Gedimde, vervaagde collage van F1 TV-artwork achter het inlogscherm.
struct AuthBackdrop: View {
    @Environment(AppModel.self) private var model
    @State private var pictures: [String] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                let columns = max(3, Int(geo.size.width / 260))
                let width = geo.size.width / CGFloat(columns)
                let height = width * 9 / 16
                let rows = Int(geo.size.height / height) + 1
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if pictures.isEmpty {
                                    Rectangle().fill(index % 3 == 0 ? Theme.accent.opacity(0.35) : Theme.surface)
                                        .frame(width: width, height: height)
                                } else {
                                    ArtworkImage(pictureID: pictures[index % pictures.count], width: width, height: height)
                                }
                            }
                        }
                    }
                }
                .rotationEffect(.degrees(-8))
                .scaleEffect(1.25)
                .blur(radius: 3)
                .opacity(0.45)
                LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.55), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .task(id: model.menu.count) {
            guard pictures.isEmpty, let home = model.menu.first,
                  let page = try? await model.catalog.page(home) else { return }
            pictures = page.sections.flatMap(\.items).compactMap(\.pictureID).prefix(40).map { $0 }
        }
    }
}

struct PitwallWordmark: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("Logo").resizable().scaledToFit().frame(height: 54)
            Text("Pitwall").font(.system(size: 40, weight: .heavy, design: .rounded))
        }
    }
}

/// E-mail en wachtwoord: inloggen, account maken, wachtwoord vergeten.
struct EmailAuthCard: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var showReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.pitwall.isConfigured {
                notConfigured
            } else {
                Text(creating ? "Account maken" : "Inloggen").font(.largeTitle.bold())

                if let banner = model.banner {
                    Label(banner, systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.callout)
                }

                TextField("E-mail", text: $email)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .authField()

                HStack {
                    Group {
                        if showPassword { TextField("Wachtwoord", text: $password) }
                        else { SecureField("Wachtwoord", text: $password) }
                    }
                    .textContentType(creating ? .newPassword : .password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    #if !os(tvOS)
                    Button(showPassword ? "Verberg" : "Toon") { showPassword.toggle() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    #endif
                }
                .authField()

                if let error {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                if let info {
                    Text(info).font(.callout).foregroundStyle(.green)
                }

                Button(action: submit) {
                    ZStack {
                        Text(creating ? "Account maken" : "Inloggen").opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(.white) }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(busy)

                if !creating {
                    Button("Wachtwoord vergeten?") { showReset = true }
                        #if !os(tvOS)
                        .buttonStyle(.plain)
                        #endif
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(creating ? "Heb je al een account?" : "Nieuw bij Pitwall?").foregroundStyle(.secondary)
                    Button(creating ? "Log in." : "Maak een account.") {
                        creating.toggle(); error = nil; info = nil
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                    .fontWeight(.semibold)
                }
                .font(.callout)
            }
        }
        .padding(32)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showReset) { ForgotPasswordSheet(email: email) }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accounts zijn niet ingesteld in deze build.").font(.headline)
            Text("Vul de Supabase-URL en publishable key in AccountConfig.swift in om inloggen te activeren.")
                .foregroundStyle(.secondary)
            Button("Doorgaan zonder account") { model.pitwall.continuedWithoutAccount = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }

    private func submit() {
        error = nil; info = nil; busy = true
        Task {
            defer { busy = false }
            do {
                if creating {
                    let signedIn = try await model.pitwall.signUp(email: email, password: password)
                    if !signedIn {
                        info = String(localized: "Kijk in je inbox om je e-mailadres te bevestigen en log daarna in.")
                        creating = false
                    }
                } else {
                    try await model.pitwall.signIn(email: email, password: password)
                }
                model.banner = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private extension View {
    func authField() -> some View {
        self
            #if !os(tvOS)
            .textFieldStyle(.plain)
            .padding(14)
            .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 8))
            #endif
    }
}

struct ForgotPasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-mail", text: $email)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Herstellink versturen") {
                        Task {
                            do { try await model.pitwall.recover(email: email); sent = true; error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                } footer: {
                    if sent {
                        Text("Als er een account bestaat, ontvang je een e-mail om je wachtwoord opnieuw in te stellen.")
                    } else if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Wachtwoord herstellen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluiten") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 440, height: 300)
        #endif
    }
}

/// Nieuw wachtwoord na de herstellink in de e-mail.
struct ResetPasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: RecoveryLink
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Nieuw wachtwoord", text: $password)
                        .textContentType(.newPassword)
                    Button("Opslaan") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                try await model.pitwall.updatePassword(password, recoveryAccessToken: link.accessToken, refreshToken: link.refreshToken)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(busy || password.count < 6)
                } footer: {
                    if let error { Text(error).foregroundStyle(.orange) }
                    else { Text("Minstens 6 tekens. Daarna ben je op alle andere apparaten uitgelogd.") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nieuw wachtwoord")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 440, height: 280)
        #endif
    }
}

// MARK: - Apple TV

#if os(tvOS)
/// Links QR en code, rechts inloggen met e-mail (zoals Netflix).
private struct TVAuthLayout: View {
    @Environment(AppModel.self) private var model
    @State private var code: AccountService.TVCode?
    @State private var error: String?
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 40) {
            PitwallWordmark()
            if !model.pitwall.isConfigured {
                EmailAuthCard().frame(maxWidth: 800)
            } else {
                HStack(alignment: .center, spacing: 80) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Inloggen met je telefoon").font(.title2.bold())
                        Text("Scan de QR-code met de camera van je telefoon").foregroundStyle(.secondary)
                        HStack(alignment: .center, spacing: 40) {
                            QRCodeView(text: code?.url ?? "")
                                .frame(width: 300, height: 300)
                                .padding(16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                .redacted(reason: code == nil ? .placeholder : [])
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Of open Pitwall op je iPhone, iPad of Mac › Account › Tv koppelen en vul deze code in:")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 440, alignment: .leading)
                                Text(code?.display ?? "··· ···")
                                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(error ?? String(localized: "Wachten op bevestiging…")).foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 20) {
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 2, height: 160)
                        Text("OF").font(.headline).foregroundStyle(.secondary)
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 2, height: 160)
                    }

                    Button { showEmail = true } label: {
                        Label("Inloggen met e-mail", systemImage: "envelope")
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(60)
        .task(id: model.pitwall.isConfigured) { await pollLoop() }
        .sheet(isPresented: $showEmail) {
            ScrollView { EmailAuthCard().frame(maxWidth: 900).padding(60) }
        }
    }

    private func pollLoop() async {
        guard model.pitwall.isConfigured else { return }
        while !Task.isCancelled && !model.pitwall.isSignedIn {
            do {
                let current = try await model.pitwall.startTVCode()
                code = current
                error = nil
                let deadline = Date().addingTimeInterval(TimeInterval(current.expiresIn))
                while Date() < deadline && !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(max(current.interval, 2)) * 1_000_000_000)
                    switch try await model.pitwall.poll(current) {
                    case .signedIn: return
                    case .expired: break
                    case .pending: continue
                    }
                    break
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
#endif

/// Witte QR-code via Core Image.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Color.white
        }
    }

    static func make(_ text: String) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - Apparatenlimiet

struct DeviceLimitScreen: View {
    @Environment(AppModel.self) private var model
    let limit: Int
    let devices: [AccountDevice]
    @State private var busy: String?

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Te veel apparaten").font(.largeTitle.bold())
                    Text("Je account kan op maximaal \(limit) apparaten tegelijk worden gebruikt. Verwijder een apparaat om op dit apparaat in te loggen.")
                        .foregroundStyle(.secondary)
                    ForEach(devices) { device in
                        HStack(spacing: 16) {
                            Image(systemName: device.symbol).font(.title2).frame(width: 40)
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline)
                                Text(device.platform).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                busy = device.id
                                Task { try? await model.pitwall.removeDevice(device.id); busy = nil }
                            } label: {
                                if busy == device.id { ProgressView() } else { Text("Verwijderen") }
                            }
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button("Annuleren") { Task { await model.pitwall.signOut() } }
                }
                .padding(40)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
