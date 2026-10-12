import Foundation
import Network
import CryptoKit
import Observation

/// Apple TV has no web browser, so it signs in by receiving the session from an
/// iPhone, iPad or Mac on the same network. The TV advertises a Bonjour service and
/// shows a 6-digit code; the code is the TLS pre-shared key, so only a device that
/// knows it can connect, and the session travels encrypted.
enum Pairing {
    static let serviceType = "_pitwall._tcp"
    static let identity = "nl.lrvdlinden.pitwall.pairing"

    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = SymmetricKey(data: Data(code.utf8))
        let psk = HMAC<SHA256>.authenticationCode(for: Data(identity.utf8), using: key)
        let pskData = Data(psk)
        let pskDispatch = pskData.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityDispatch = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, pskDispatch as __DispatchData, identityDispatch as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// Messages are a 4-byte big-endian length followed by JSON.
    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }

    static func receiveFrame(on connection: NWConnection, completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else { completion(nil); return }
            let length = header.reduce(0) { ($0 << 8) | UInt32($1) }
            guard length > 0, length < 256 * 1024 else { completion(nil); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, error in
                completion(error == nil ? body : nil)
            }
        }
    }

    static func randomCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

// MARK: - Apple TV side

#if os(tvOS)
import UIKit

@MainActor
@Observable
final class PairingHost {
    enum State: Equatable { case idle, waiting, received(String), failed(String) }

    private(set) var code = Pairing.randomCode()
    private(set) var state: State = .idle

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var onSession: ((F1Session) -> Void)?

    func start(onSession: @escaping (F1Session) -> Void) {
        stop()
        self.onSession = onSession
        code = Pairing.randomCode()
        do {
            let listener = try NWListener(using: Pairing.parameters(code: code))
            listener.service = NWListener.Service(name: "Pitwall · \(UIDevice.current.name)", type: Pairing.serviceType)
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    switch newState {
                    case .ready: self?.state = .waiting
                    case .failed(let error): self?.state = .failed(error.localizedDescription)
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if case .received = state {} else { state = .idle }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        Pairing.receiveFrame(on: connection) { [weak self] data in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard let data, let session = try? JSONDecoder().decode(F1Session.self, from: data) else {
                    connection.cancel(); return
                }
                connection.send(content: Pairing.frame(Data("OK".utf8)), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.state = .received(session.displayName)
                self.onSession?(session)
                self.listener?.cancel()
                self.listener = nil
            }
        }
    }
}
#endif

// MARK: - iPhone / iPad / Mac side

#if !os(tvOS)
@MainActor
@Observable
final class PairingBrowser {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
        static func == (l: Device, r: Device) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    enum SendState: Equatable { case idle, sending, sent, failed(String) }

    private(set) var devices: [Device] = []
    private(set) var sendState: SendState = .idle
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?

    func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Pairing.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Device? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Device(id: "\(result.endpoint)", name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.devices = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    func send(_ session: F1Session, to device: Device, code: String) {
        connection?.cancel()
        sendState = .sending
        let trimmed = code.filter(\.isNumber)
        let connection = NWConnection(to: device.endpoint, using: Pairing.parameters(code: trimmed))
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let payload = try? JSONEncoder().encode(session) else { return }
                    connection.send(content: Pairing.frame(payload), completion: .contentProcessed { _ in })
                    Pairing.receiveFrame(on: connection) { reply in
                        Task { @MainActor in
                            self.sendState = reply.flatMap { String(data: $0, encoding: .utf8) } == "OK"
                                ? .sent
                                : .failed(String(localized: "De Apple TV heeft niet bevestigd. Controleer de code."))
                            connection.cancel()
                        }
                    }
                case .failed, .waiting:
                    if self.sendState == .sending {
                        self.sendState = .failed(String(localized: "Verbinden mislukt. Controleer de code op je Apple TV."))
                    }
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    func reset() { sendState = .idle }
}
#endif
