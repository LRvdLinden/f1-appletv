import Foundation

/// The parts of an F1 TV web session the app needs. Passwords are never stored.
struct F1Session: Codable, Equatable, Sendable {
    var sessionID: String
    var subscriptionToken: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var country: String?
    var subscriptionStatus: String?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (email ?? String(localized: "F1 TV-account")) : name
    }

    /// Expiry of the subscription token, read from its JWT payload.
    var tokenExpiry: Date? {
        guard let payload = Self.jwtPayload(subscriptionToken), let exp = payload["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    var subscriptionTier: String? {
        guard let payload = Self.jwtPayload(subscriptionToken) else { return nil }
        return (payload["SubscribedProduct"] as? String) ?? (payload["SubscriptionProduct"] as? String)
    }

    /// Parses the JSON the F1 website keeps in `localStorage.ascSessionInfo`
    /// or in the `login-session` cookie, and the RetrieveSubscriber response.
    static func decode(_ data: Data, previous: F1Session? = nil) -> F1Session? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tokenData = object["data"] as? [String: Any]
        guard let token = tokenData?["subscriptionToken"] as? String, !token.isEmpty else { return nil }

        let rawSession = object["SessionId"] ?? object["sessionId"]
        var sessionID = (rawSession as? String) ?? (rawSession as? NSNumber)?.stringValue
        if sessionID == nil || sessionID?.isEmpty == true { sessionID = previous?.sessionID }
        if sessionID == nil || sessionID?.isEmpty == true { sessionID = jwtPayload(token)?["SessionId"] as? String }
        guard let sessionID, !sessionID.isEmpty else { return nil }

        let summary = (object["Subscriber"] ?? object["SessionSummary"]) as? [String: Any]
        return F1Session(
            sessionID: sessionID,
            subscriptionToken: token,
            firstName: summary?["FirstName"] as? String ?? previous?.firstName,
            lastName: summary?["LastName"] as? String ?? previous?.lastName,
            email: summary?["Email"] as? String ?? previous?.email,
            country: summary?["HomeCountry"] as? String ?? previous?.country,
            subscriptionStatus: tokenData?["subscriptionStatus"] as? String ?? previous?.subscriptionStatus
        )
    }

    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
