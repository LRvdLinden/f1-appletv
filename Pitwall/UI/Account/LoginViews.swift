import SwiftUI

#if !os(tvOS)
import WebKit

#if os(macOS)
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

/// Official F1 sign-in page; closes itself once the session is found.
struct WebLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var login = WebLogin()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebViewContainer(webView: login.webView)
                if login.isLoading {
                    ProgressView().padding(.top, 24)
                }
                if let message = login.errorMessage {
                    HStack {
                        Text(message).font(.callout)
                        Spacer()
                        Button("Opnieuw") { login.reload() }
                    }
                    .padding(12)
                    .background(.thinMaterial)
                }
            }
            .navigationTitle("Inloggen bij F1")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { login.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        #if os(macOS)
        .frame(width: 720, height: 720)
        #endif
        .task {
            if let session = await login.signIn() {
                model.account.signIn(session)
                login.clear()
                dismiss()
            }
        }
    }
}

/// Sends this device's session to an Apple TV that shows a pairing code.
struct SendToTVSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var browser = PairingBrowser()
    @State private var selected: PairingBrowser.Device?
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Open Pitwall op je Apple TV en ga naar Account. Kies hieronder de Apple TV en vul de code in die op je tv staat.")
                        .foregroundStyle(.secondary)
                }

                Section("Apple TV's in dit netwerk") {
                    if browser.devices.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Zoeken…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(browser.devices) { device in
                        Button {
                            selected = device
                            browser.reset()
                        } label: {
                            HStack {
                                Label(device.name, systemImage: "appletv")
                                Spacer()
                                if selected == device { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selected {
                    Section("Code op je tv") {
                        TextField("123456", text: $code)
                            .font(.title2.monospacedDigit())
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Button {
                            guard let session = model.account.session else { return }
                            browser.send(session, to: selected, code: code)
                        } label: {
                            Label("Koppelen", systemImage: "link")
                        }
                        .disabled(code.filter(\.isNumber).count != 6 || browser.sendState == .sending)
                    }
                }

                switch browser.sendState {
                case .idle:
                    EmptyView()
                case .sending:
                    Section { HStack { ProgressView(); Text("Verbinden…") } }
                case .sent:
                    Section {
                        Label("Je Apple TV is ingelogd.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Naar Apple TV in dit netwerk")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }
}
#endif

#if os(tvOS)
/// Shows the pairing code and waits for an iPhone, iPad or Mac to send the session.
struct TVPairingView: View {
    @Environment(AppModel.self) private var model
    @State private var host = PairingHost()

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Inloggen via je iPhone, iPad of Mac").font(.title3.bold())
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Installeer Pitwall op je iPhone, iPad of Mac en log daar in met F1 TV.")
                    step(2, "Ga naar Account › Naar Apple TV in dit netwerk.")
                    step(3, "Kies deze Apple TV en vul de code in.")
                }
                .foregroundStyle(.secondary)
                Text("Beide apparaten moeten op hetzelfde wifi-netwerk zitten.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 700, alignment: .leading)

            VStack(spacing: 16) {
                switch host.state {
                case .received(let name):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 90)).foregroundStyle(.green)
                    Text("Ingelogd als \(name)").font(.title3)
                case .failed(let message):
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 70)).foregroundStyle(.orange)
                    Text(message).font(.callout).multilineTextAlignment(.center)
                    Button("Opnieuw") { start() }
                default:
                    Text("Code").font(.headline).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        ForEach(Array(host.code.enumerated()), id: \.offset) { _, digit in
                            Text(String(digit))
                                .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                                .frame(width: 92, height: 120)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wachten op je iPhone, iPad of Mac…").foregroundStyle(.secondary)
                    }
                    Button("Nieuwe code") { start() }
                }
            }
        }
        .onAppear { start() }
        .onDisappear { host.stop() }
    }

    private func start() {
        host.start { session in
            model.account.signIn(session)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Theme.accent, in: Circle())
                .foregroundStyle(.white)
            Text(text)
        }
    }
}
#endif
