import Foundation

/// Video details, playback entitlements and progress reporting (all signed requests).
@MainActor
struct PlaybackService {
    let account: AccountStore
    var endpoints: F1Endpoints { F1Endpoints(language: account.language) }

    func details(contentID: String) async throws -> VideoDetails {
        let data = try await account.authorizedData(try endpoints.videoDetails(contentID), mode: .video)
        let payload = try HTTPClient.envelope(WirePayload.self, from: data)
        guard let node = payload.containers?.values.first else { throw APIError.decoding }
        var item = CatalogMapper.item(node, fallbackID: "video:\(contentID)")
        if item.contentID == nil { item.contentID = contentID }
        let id = item.contentID ?? contentID

        var feeds = [Feed(id: "main:\(id)", kind: .main, title: "INTERNATIONAL", target: id)]
        var seen = Set<String>()
        for stream in node.metadata?.additionalStreams?.values ?? [] {
            guard let uri = stream.playbackUrl, !uri.isEmpty, seen.insert(uri).inserted else { continue }
            let title = stream.title ?? ""
            if title.uppercased() == "INTERNATIONAL" { continue }
            let kind: FeedKind
            switch stream.type?.lowercased() {
            case "obc": kind = .onboard
            default: kind = .additional
            }
            let name = [stream.driverFirstName, stream.driverLastName].compactMap { $0 }.joined(separator: " ")
            feeds.append(Feed(
                id: uri, kind: kind, title: title, target: uri,
                driverNumber: stream.racingNumber.flatMap { Int($0.value) },
                driverName: name.isEmpty ? nil : name,
                team: stream.teamName, teamColor: stream.hex, headshot: stream.driverImg
            ))
        }
        // Main first, then extra channels, then onboards sorted by car number.
        let extras = feeds.filter { $0.kind == .additional }
        let onboards = feeds.filter { $0.kind == .onboard }.sorted { ($0.driverNumber ?? 999) < ($1.driverNumber ?? 999) }
        return VideoDetails(item: item, feeds: [feeds[0]] + extras + onboards)
    }

    func entitlement(for feed: Feed) async throws -> Entitlement {
        let data = try await account.authorizedData(try endpoints.entitlement(feed.target), mode: .entitlement)
        let wire = try HTTPClient.envelope(WireEntitlement.self, from: data)
        guard let url = URL(string: wire.url), url.scheme == "https" else { throw APIError.invalidPlayback }
        let isFairPlay = wire.drmType?.lowercased().contains("fairplay") == true
        let license = wire.licenseURL.flatMap(URL.init(string:))
        if isFairPlay && license == nil { throw APIError.invalidPlayback }
        return Entitlement(streamURL: url, isFairPlay: isFairPlay, licenseURL: license, token: wire.entitlementToken)
    }

    func fairPlayCertificate() async throws -> Data {
        if let cached = Self.certificate { return cached }
        let data = try await HTTPClient.shared.data(endpoints.fairPlayCertificate(), retryTransient: true)
        guard !data.isEmpty else { throw APIError.invalidPlayback }
        Self.certificate = data
        return data
    }

    func license(spc: Data, assetID: String, entitlement: Entitlement) async throws -> Data {
        guard let url = entitlement.licenseURL else { throw APIError.invalidPlayback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("spc=\(spc.base64EncodedString())&assetId=\(assetID)".utf8)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(entitlement.token, forHTTPHeaderField: "entitlementtoken")
        request.setValue(try account.subscriptionToken(), forHTTPHeaderField: "ascendontoken")
        let data = try await HTTPClient.shared.data(request)
        guard let ckc = Data(base64Encoded: data), !ckc.isEmpty else { throw APIError.invalidPlayback }
        return ckc
    }

    func report(contentID: String, subtype: String, position: Double) async {
        guard let id = Int(contentID), position >= 0 else { return }
        guard let request = try? endpoints.reportProgress(contentID: id, subtype: subtype, position: Int(position)) else { return }
        _ = try? await account.authorizedData(request, mode: .reporting)
    }

    private static var certificate: Data?
}
