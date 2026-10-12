import Foundation
import Observation

/// Owns the signed-in F1 TV session: persistence, refresh and request signing.
@MainActor
@Observable
final class AccountStore {
    private(set) var session: F1Session?
    /// Set when F1 rejects the stored session and the user has to sign in again.
    private(set) var sessionExpired = false
    var language: String

    @ObservationIgnored private let client = HTTPClient.shared
    @ObservationIgnored private let playbackSessionID = UUID().uuidString
    @ObservationIgnored private var refreshTask: Task<F1Session, Error>?
    /// Login, logout of vernieuwd token: de sync stuurt het door naar andere apparaten.
    @ObservationIgnored var onSessionChange: (() -> Void)?

    var isSignedIn: Bool { session != nil }
    private var endpoints: F1Endpoints { F1Endpoints(language: language) }

    init(language: String) {
        self.language = language
        self.session = KeychainStore.load()
    }

    func signIn(_ newSession: F1Session) {
        session = newSession
        sessionExpired = false
        KeychainStore.save(newSession)
        onSessionChange?()
    }

    func signOut() {
        session = nil
        sessionExpired = false
        KeychainStore.clear()
        onSessionChange?()
    }

    /// Refreshes the token when it expires within a day. Called at launch and on foreground.
    func refreshIfNeeded() async {
        guard let expiry = session?.tokenExpiry else { return }
        if expiry.timeIntervalSinceNow < 24 * 3600 {
            _ = try? await refresh()
        }
    }

    @discardableResult
    func refresh() async throws -> F1Session {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw APIError.notSignedIn }
        let request = endpoints.retrieveSubscriber(sessionID: current.sessionID)
        let client = self.client
        let task = Task { () throws -> F1Session in
            let data = try await client.data(request)
            guard let updated = F1Session.decode(data, previous: current) else { throw APIError.decoding }
            return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            signIn(updated)
            return updated
        } catch APIError.http(let code) where code == 401 || code == 403 {
            sessionExpired = true
            throw APIError.http(code)
        }
    }

    /// Sends a request with the F1 TV account headers, refreshing once on 401/403.
    func authorizedData(_ request: URLRequest, mode: AuthorizationMode) async throws -> Data {
        guard let current = session else { throw APIError.notSignedIn }
        do {
            return try await client.data(sign(request, with: current, mode: mode))
        } catch APIError.http(let code) where (code == 401 || code == 403) && mode != .reporting {
            let refreshed = try await refresh()
            return try await client.data(sign(request, with: refreshed, mode: mode))
        }
    }

    func subscriptionToken() throws -> String {
        guard let token = session?.subscriptionToken else { throw APIError.notSignedIn }
        return token
    }

    private func sign(_ request: URLRequest, with session: F1Session, mode: AuthorizationMode) -> URLRequest {
        var request = request
        request.setValue(playbackSessionID, forHTTPHeaderField: "sessionid")
        request.setValue(session.subscriptionToken, forHTTPHeaderField: "ascendontoken")
        request.setValue(mode == .video ? session.subscriptionToken : session.sessionID, forHTTPHeaderField: "entitlementtoken")
        return request
    }
}
