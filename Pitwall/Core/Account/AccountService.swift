import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Supabase-sessie van het Pitwall-account (alleen op dit apparaat bewaard).
struct AccountSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

struct AccountDevice: Identifiable, Hashable {
    var id: String
    var name: String
    var platform: String
    var createdAt: Date?
    var signedInAt: Date?
    var lastSeenAt: Date?
    var isCurrent: Bool

    var symbol: String {
        switch platform {
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Mac": return "laptopcomputer"
        case "Apple TV": return "appletv"
        default: return "display"
        }
    }
}

enum AccountError: LocalizedError, Equatable {
    case invalidCredentials, emailNotConfirmed, emailExists, invalidEmail, weakPassword
    case offline, invalidCode, notConfigured, notSignedIn, generic(String?)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return String(localized: "Onjuist e-mailadres of wachtwoord.")
        case .emailNotConfirmed: return String(localized: "Bevestig eerst je e-mailadres. Kijk in je inbox.")
        case .emailExists: return String(localized: "Er bestaat al een account met dit e-mailadres.")
        case .invalidEmail: return String(localized: "Vul een geldig e-mailadres in.")
        case .weakPassword: return String(localized: "Het wachtwoord moet minstens 6 tekens hebben.")
        case .offline: return String(localized: "Geen internetverbinding.")
        case .invalidCode: return String(localized: "Deze code is ongeldig of verlopen.")
        case .notConfigured: return String(localized: "Accounts zijn niet ingesteld in deze build.")
        case .notSignedIn: return String(localized: "Je bent niet ingelogd.")
        case .generic(let message): return message ?? String(localized: "Er ging iets mis. Probeer het opnieuw.")
        }
    }
}

/// Het verplichte Pitwall-account: inloggen, tv-koppeling, apparaten en versleutelde accountgegevens.
/// Contract: docs/ACCOUNT.md.
@MainActor
@Observable
final class AccountService {
    enum Phase: Equatable {
        case signedOut
        case deviceLimit(limit: Int, devices: [AccountDevice])
        case signedIn
    }

    private(set) var session: AccountSession?
    private(set) var phase: Phase = .signedOut
    /// Zonder Supabase-sleutels in de build kan de gebruiker zonder account verder.
    var continuedWithoutAccount = false

    /// Wordt aangeroepen na elke geslaagde login en bij elke heartbeat (sync van accountgegevens).
    @ObservationIgnored var onSignedIn: (() async -> Void)?
    @ObservationIgnored var onHeartbeat: (() async -> Void)?
    @ObservationIgnored var onSignedOut: (() -> Void)?

    @ObservationIgnored private var refreshTask: Task<AccountSession, Error>?
    @ObservationIgnored private var heartbeatTimer: Timer?
    @ObservationIgnored private let urlSession = URLSession(configuration: .ephemeral)

    let deviceID: String

    var isConfigured: Bool { AccountConfig.isConfigured }
    var isSignedIn: Bool { session != nil }
    var mayUseApp: Bool { phase == .signedIn || (!isConfigured && continuedWithoutAccount) }

    private static let sessionKey = "session"
    private static let deviceKey = "device-id"
    private static let lastUserKey = "pitwall.lastUserID"
    private static let registeredKey = "pitwall.deviceRegistered"

    init() {
        if let existing = LocalKeychain.string(Self.deviceKey) {
            deviceID = existing
        } else {
            let id = UUID().uuidString
            LocalKeychain.setString(id, for: Self.deviceKey)
            deviceID = id
        }
        if let data = LocalKeychain.data(Self.sessionKey), let stored = try? JSONDecoder().decode(AccountSession.self, from: data) {
            session = stored
            phase = .signedIn
        }
    }

    // MARK: - Device info

    static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    static var platform: String {
        #if os(tvOS)
        return "Apple TV"
        #elseif os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    // MARK: - Lifecycle

    /// Bij het starten en bij terugkeer naar de voorgrond.
    func resume() async {
        guard isConfigured, session != nil else { return }
        do {
            _ = try await validAccessToken()
        } catch AccountError.notSignedIn {
            return
        } catch {
            // offline: sessie houden
        }
        await checkDevice()
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkDevice() }
        }
    }

    /// Heartbeat (of registratie als dat nog niet gebeurd is); een ingetrokken apparaat logt uit.
    func checkDevice() async {
        guard session != nil else { return }
        if UserDefaults.standard.bool(forKey: Self.registeredKey) {
            if let result = try? await function("heartbeat", ["device_id": deviceID]), result["revoked"] as? Bool == true {
                clearLocal()
                return
            }
        } else {
            await registerDevice()
        }
        await onHeartbeat?()
    }

    // MARK: - E-mail en wachtwoord

    func signIn(email: String, password: String) async throws {
        try validate(email: email, password: password)
        let data = try await auth("token?grant_type=password", body: ["email": email.trimmed, "password": password])
        try await completeSignIn(with: data)
    }

    /// Geeft `true` als de gebruiker meteen is ingelogd, `false` als het e-mailadres eerst bevestigd moet worden.
    func signUp(email: String, password: String) async throws -> Bool {
        try validate(email: email, password: password)
        let lang = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "nl"
        let redirect = AccountConfig.confirmRedirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let data = try await auth("signup?redirect_to=\(redirect)", body: ["email": email.trimmed, "password": password, "data": ["lang": lang]])
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard object?["access_token"] != nil else { return false }
        try await completeSignIn(with: data)
        return true
    }

    func recover(email: String) async throws {
        guard email.trimmed.contains("@") else { throw AccountError.invalidEmail }
        let redirect = AccountConfig.resetRedirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        _ = try await auth("recover?redirect_to=\(redirect)", body: ["email": email.trimmed])
    }

    /// Nieuw wachtwoord na de herstellink (pitwall://reset#access_token=…).
    func updatePassword(_ password: String, recoveryAccessToken: String, refreshToken: String?) async throws {
        guard password.count >= 6 else { throw AccountError.weakPassword }
        var request = request(path: "auth/v1/user", method: "PUT", body: ["password": password])
        request.setValue("Bearer \(recoveryAccessToken)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
        if let refreshToken, !refreshToken.isEmpty {
            let data = try await auth("token?grant_type=refresh_token", body: ["refresh_token": refreshToken])
            try await completeSignIn(with: data)
        }
    }

    // MARK: - Tv-koppeling

    struct TVCode {
        let code: String
        let pollSecret: String
        let url: String
        let expiresIn: Int
        let interval: Int
        var display: String {
            code.count == 6 ? "\(code.prefix(3))-\(code.suffix(3))" : code
        }
    }

    func startTVCode() async throws -> TVCode {
        let result = try await function("start", ["device": Self.deviceName], authorized: false)
        guard let code = result["code"] as? String, let secret = result["poll_secret"] as? String else { throw AccountError.generic(nil) }
        return TVCode(code: code, pollSecret: secret, url: result["url"] as? String ?? "pitwall://link?code=\(code)",
                      expiresIn: result["expires_in"] as? Int ?? 600, interval: result["interval"] as? Int ?? 3)
    }

    enum PollResult { case pending, expired, signedIn }

    func poll(_ code: TVCode) async throws -> PollResult {
        let result = try await function("poll", ["code": code.code, "poll_secret": code.pollSecret], authorized: false)
        switch result["status"] as? String {
        case "approved":
            guard let hash = result["token_hash"] as? String else { return .expired }
            let data = try await auth("verify", body: ["type": "magiclink", "token_hash": hash])
            try await completeSignIn(with: data)
            return .signedIn
        case "pending": return .pending
        default: return .expired
        }
    }

    /// Telefoon of Mac keurt de code van een tv goed. Geeft de apparaatnaam terug.
    func approve(code: String) async throws -> String {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count == 6 else { throw AccountError.invalidCode }
        do {
            let result = try await function("approve", ["code": normalized])
            return result["device"] as? String ?? "Apple TV"
        } catch AccountError.generic {
            throw AccountError.invalidCode
        }
    }

    // MARK: - Apparaten

    func registerDevice() async {
        do {
            _ = try await function("register_device", ["device_id": deviceID, "name": Self.deviceName, "platform": Self.platform])
            UserDefaults.standard.set(true, forKey: Self.registeredKey)
            phase = .signedIn
        } catch LimitError.reached(let limit, let devices) {
            phase = .deviceLimit(limit: limit, devices: devices)
        } catch {
            // netwerkfout: later opnieuw (heartbeat); de app blijft bruikbaar
            if session != nil, !isAtDeviceLimit { phase = .signedIn }
        }
    }

    var isAtDeviceLimit: Bool {
        if case .deviceLimit = phase { return true }
        return false
    }

    func listDevices() async throws -> (limit: Int, devices: [AccountDevice]) {
        let result = try await function("list_devices", ["device_id": deviceID])
        return (result["limit"] as? Int ?? 10, Self.devices(from: result["devices"]))
    }

    func renameDevice(_ id: String, to name: String) async throws {
        _ = try await function("rename_device", ["device_id": id, "name": name])
    }

    func removeDevice(_ id: String) async throws {
        if id == deviceID { await signOut(); return }
        _ = try await function("remove_device", ["device_id": id])
        if isAtDeviceLimit {
            await registerDevice()
            if phase == .signedIn {
                startHeartbeat()
                await onSignedIn?()
            }
        }
    }

    // MARK: - Uitloggen

    func signOut() async {
        if session != nil {
            _ = try? await function("remove_device", ["device_id": deviceID])
            if let token = session?.accessToken {
                var request = request(path: "auth/v1/logout", method: "POST", body: [:])
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                _ = try? await send(request)
            }
        }
        clearLocal()
    }

    func deleteAccount() async throws {
        _ = try await function("delete_account", [:])
        clearLocal()
    }

    private func clearLocal() {
        heartbeatTimer?.invalidate()
        session = nil
        LocalKeychain.set(nil, for: Self.sessionKey)
        UserDefaults.standard.set(false, forKey: Self.registeredKey)
        phase = .signedOut
        onSignedOut?()
    }

    // MARK: - Accountgegevens (versleuteld op de server)

    struct StateEntry {
        let data: Any
        let updatedAt: Date?
    }

    func getState(_ sections: [String]) async throws -> [String: StateEntry] {
        let result = try await function("get_state", ["sections": sections])
        var out: [String: StateEntry] = [:]
        for (key, value) in result["sections"] as? [String: Any] ?? [:] {
            guard let entry = value as? [String: Any] else { continue }
            out[key] = StateEntry(data: entry["data"] ?? NSNull(), updatedAt: Self.date(entry["updatedAt"]))
        }
        return out
    }

    func putState(_ section: String, data: Any) async throws {
        _ = try await function("put_state", ["section": section, "data": data])
    }

    /// Wisselt er een ander account op dit apparaat? Dan moeten lokale gegevens wijken voor die van het account.
    var lastUserID: String? { UserDefaults.standard.string(forKey: Self.lastUserKey) }

    // MARK: - Tokens

    func validAccessToken() async throws -> String {
        guard let current = session else { throw AccountError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        return try await refresh().accessToken
    }

    private func refresh() async throws -> AccountSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw AccountError.notSignedIn }
        let task = Task { () throws -> AccountSession in
            let data = try await self.auth("token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken])
            guard let updated = Self.session(from: data, fallbackEmail: current.email) else { throw AccountError.generic(nil) }
            return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            store(updated)
            return updated
        } catch AccountError.invalidCredentials {
            clearLocal()
            throw AccountError.notSignedIn
        } catch APIError.http(let code) where code == 400 || code == 401 {
            clearLocal()
            throw AccountError.notSignedIn
        }
    }

    private func completeSignIn(with data: Data) async throws {
        guard let newSession = Self.session(from: data, fallbackEmail: "") else { throw AccountError.generic(nil) }
        let switchedAccount = lastUserID != nil && lastUserID != newSession.userID
        store(newSession)
        UserDefaults.standard.set(newSession.userID, forKey: Self.lastUserKey)
        if switchedAccount { UserDefaults.standard.set(true, forKey: "pitwall.accountSwitched") }
        UserDefaults.standard.set(false, forKey: Self.registeredKey)
        await registerDevice()
        if phase == .signedIn {
            startHeartbeat()
            await onSignedIn?()
        }
    }

    private func store(_ newSession: AccountSession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) { LocalKeychain.set(data, for: Self.sessionKey) }
    }

    // MARK: - HTTP

    private enum LimitError: Error { case reached(Int, [AccountDevice]) }

    private func request(path: String, method: String, body: [String: Any]) -> URLRequest {
        let base = AccountConfig.supabaseURL.hasSuffix("/") ? String(AccountConfig.supabaseURL.dropLast()) : AccountConfig.supabaseURL
        var request = URLRequest(url: URL(string: base + "/" + path) ?? AccountConfig.baseURL)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AccountConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func auth(_ path: String, body: [String: Any]) async throws -> Data {
        guard isConfigured else { throw AccountError.notConfigured }
        return try await send(request(path: "auth/v1/\(path)", method: "POST", body: body))
    }

    private func function(_ action: String, _ body: [String: Any], authorized: Bool = true) async throws -> [String: Any] {
        guard isConfigured else { throw AccountError.notConfigured }
        var payload = body
        payload["action"] = action
        var request = request(path: "functions/v1/device-auth", method: "POST", body: payload)
        if authorized {
            request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await perform(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403, object["error"] as? String == "device_limit" {
            throw LimitError.reached(object["limit"] as? Int ?? 10, Self.devices(from: object["devices"]))
        }
        if status == 401 { throw AccountError.notSignedIn }
        guard (200..<300).contains(status) else { throw AccountError.generic(nil) }
        return object
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await perform(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let code = (object["error_code"] as? String) ?? (object["error"] as? String) ?? ""
            let message = (object["msg"] as? String) ?? (object["error_description"] as? String) ?? ""
            switch code {
            case "invalid_credentials", "invalid_grant" where message.lowercased().contains("invalid login"):
                throw AccountError.invalidCredentials
            case "email_not_confirmed": throw AccountError.emailNotConfirmed
            case "user_already_exists", "email_exists": throw AccountError.emailExists
            case "weak_password": throw AccountError.weakPassword
            case "email_address_invalid", "validation_failed": throw AccountError.invalidEmail
            default: throw APIError.http(status)
            }
        }
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            throw AccountError.offline
        }
    }

    private func validate(email: String, password: String) throws {
        guard isConfigured else { throw AccountError.notConfigured }
        let trimmed = email.trimmed
        guard trimmed.contains("@"), trimmed.contains("."), trimmed.count >= 5 else { throw AccountError.invalidEmail }
        guard password.count >= 6 else { throw AccountError.weakPassword }
    }

    // MARK: - Parsing

    private static func session(from data: Data, fallbackEmail: String) -> AccountSession? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String else { return nil }
        let user = object["user"] as? [String: Any]
        let expiresIn = (object["expires_in"] as? Double) ?? 3600
        let expiresAt = (object["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(expiresIn)
        let userID = (user?["id"] as? String) ?? (F1Session.jwtPayload(access)?["sub"] as? String) ?? ""
        return AccountSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                              userID: userID, email: (user?["email"] as? String) ?? fallbackEmail)
    }

    private static func devices(from value: Any?) -> [AccountDevice] {
        (value as? [[String: Any]] ?? []).map { d in
            AccountDevice(
                id: d["device_id"] as? String ?? UUID().uuidString,
                name: d["name"] as? String ?? "",
                platform: d["platform"] as? String ?? "",
                createdAt: date(d["created_at"]),
                signedInAt: date(d["signed_in_at"]),
                lastSeenAt: date(d["last_seen_at"]),
                isCurrent: d["current"] as? Bool ?? false
            )
        }
    }

    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
