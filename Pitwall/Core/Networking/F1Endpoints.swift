import Foundation

/// All F1 TV URLs in one place. Catalog requests are anonymous; video, playback
/// and reporting requests get the account headers added by `AccountStore`.
struct F1Endpoints: Sendable {
    var language: String

    static let catalogBase = URL(string: "https://f1tv.formula1.com")!
    static let accountBase = URL(string: "https://api.formula1.com")!
    static let imageBase = URL(string: "https://f1tv.formula1.com/image-resizer/image")!
    static let loginURL = URL(string: "https://account.formula1.com/#/login")!

    /// Browsing always uses the full web catalog; playback uses the big-screen CDN.
    static let catalogProvider = "WEB_HLS"
    static let playbackProvider = "BIG_SCREEN_HLS"

    static let accountAPIKey = "fCUCjWrKPu9ylJwRAv8BpGLEgiAuThx7"
    static let systemID = "60a9ad84-e93d-480f-80d6-af37494f2e22"

    static var deviceInfo: String {
        #if os(tvOS)
        return "device=tvos;screen=bigscreen;os=tvos;model=appletv14.1;osVersion=17.0;appVersion=2.11.0;playerVersion=3.16.0"
        #elseif os(macOS)
        return "device=web;screen=browser;os=macos;model=mac;osVersion=14.0;appVersion=2.11.0;playerVersion=3.16.0"
        #else
        return "device=ios;screen=handheld;os=ios;model=iphone;osVersion=17.0;appVersion=2.11.0;playerVersion=3.16.0"
        #endif
    }

    // MARK: Catalog

    func menu() -> URLRequest {
        URLRequest(url: URL(string: "/2.0/R/\(language)/\(Self.catalogProvider)/ALL/MENU/PREMIUM/14", relativeTo: Self.catalogBase)!.absoluteURL)
    }

    /// Page URIs come from the API itself; only the provider segment is normalised.
    func page(_ uri: String) throws -> URLRequest {
        guard let resolved = URL(string: uri, relativeTo: Self.catalogBase)?.absoluteURL,
              resolved.host == Self.catalogBase.host,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        var path = components.percentEncodedPath.split(separator: "/").map(String.init)
        if path.count >= 6, path[4] == "ALL" {
            path[2] = language
            path[3] = Self.catalogProvider
        }
        components.percentEncodedPath = "/" + path.joined(separator: "/")
        guard let url = components.url else { throw APIError.invalidURL }
        return URLRequest(url: url)
    }

    // MARK: Playback

    func videoDetails(_ contentID: String) throws -> URLRequest {
        guard !contentID.isEmpty, contentID.allSatisfy(\.isNumber) else { throw APIError.invalidPlayback }
        return URLRequest(url: URL(string: "/3.0/R/\(language)/\(Self.playbackProvider)/ALL/CONTENT/VIDEO/\(contentID)/F1_TV_Pro_Annual/14", relativeTo: Self.catalogBase)!.absoluteURL)
    }

    /// `target` is either a bare content id or an API channel URI (`CONTENT/PLAY?channelId=…&contentId=…`).
    func entitlement(_ target: String) throws -> URLRequest {
        let uri = target.hasPrefix("CONTENT/") ? target : "CONTENT/PLAY?contentId=\(target)"
        guard uri.hasPrefix("CONTENT/PLAY?"),
              let url = URL(string: "/2.0/R/\(language)/\(Self.playbackProvider)/ALL/\(uri)", relativeTo: Self.catalogBase)?.absoluteURL
        else { throw APIError.invalidPlayback }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(Self.deviceInfo, forHTTPHeaderField: "x-f1-device-info")
        return request
    }

    func fairPlayCertificate() -> URLRequest {
        URLRequest(url: Self.catalogBase.appendingPathComponent("fairplay01.der"))
    }

    func reportProgress(contentID: Int, subtype: String, position: Int) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "/1.0/R/\(language)/\(Self.playbackProvider)/ALL/ACTION/PLAY", relativeTo: Self.catalogBase)!.absoluteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contentId": contentID,
            "contentSubType": subtype,
            "playHeadPosition": position,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Account

    func retrieveSubscriber(sessionID: String) -> URLRequest {
        var request = URLRequest(url: Self.accountBase.appendingPathComponent("v1/account/Subscriber/RetrieveSubscriber"))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.accountAPIKey, forHTTPHeaderField: "apikey")
        request.setValue(Self.systemID, forHTTPHeaderField: "CD-SystemID")
        request.setValue(language, forHTTPHeaderField: "CD-Language")
        request.setValue(sessionID, forHTTPHeaderField: "CD-SessionID")
        return request
    }

    // MARK: Images

    static func image(_ pictureID: String?, width: CGFloat, height: CGFloat) -> URL? {
        guard let pictureID, !pictureID.isEmpty else { return nil }
        if pictureID.hasPrefix("http") { return URL(string: pictureID) }
        var components = URLComponents(url: imageBase.appendingPathComponent(pictureID), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "w", value: String(Int(ceil(width / 8) * 8))),
            URLQueryItem(name: "h", value: String(Int(ceil(height / 8) * 8))),
            URLQueryItem(name: "q", value: "HI")
        ]
        return components?.url
    }
}

/// How a request is authorised. F1 TV expects different tokens in `entitlementtoken`
/// depending on whether it fetches video details or a playback entitlement.
enum AuthorizationMode: Sendable {
    case video, entitlement, reporting
}
