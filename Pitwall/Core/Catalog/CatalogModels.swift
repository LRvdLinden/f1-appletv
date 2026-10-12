import Foundation

/// A page the user can navigate to (menu entry, "view all", launcher tile).
struct PageRef: Hashable, Codable, Identifiable {
    let uri: String
    let title: String
    var id: String { uri }
}

/// What starts playback: a content id plus an optional specific channel URI.
struct PlayTarget: Hashable, Codable {
    let contentID: String
    var channelURI: String?
}

enum ItemKind: String, Hashable, Codable {
    case video, launcher, bundle, unknown
}

enum ItemAction: Hashable {
    case play(PlayTarget)
    case open(PageRef)
}

struct RaceInfo: Hashable {
    var videoType: String?
    var meetingKey: String?
    var meetingName: String?
    var officialName: String?
    var countryName: String?
    var countryKey: String?
    var displayDate: String?
    var round: String?
    var series: String?
    var start: Date?
    var end: Date?

    var isSession: Bool { videoType == "meetingSession" }

    /// Two-letter ISO code turned into a flag emoji, when F1 sends a recognisable key.
    var flag: String? {
        guard let key = countryKey?.uppercased(), let iso = CountryCodes.alpha2(fromAlpha3: key) else { return nil }
        var result = ""
        for scalar in iso.unicodeScalars {
            if let regional = UnicodeScalar(127397 + scalar.value) { result.unicodeScalars.append(regional) }
        }
        return result
    }
}

struct CatalogItem: Identifiable, Hashable {
    var id: String
    var kind: ItemKind = .unknown
    var title: String = ""
    var subtitle: String?
    var summary: String?
    var pictureID: String?
    var contentID: String?
    var contentSubtype: String?
    var duration: String?
    var locked = false
    var race: RaceInfo?
    var action: ItemAction?
    var resumeSeconds: Double?

    var isLive: Bool { contentSubtype?.uppercased() == "LIVE" }

    var isLiveNow: Bool {
        guard let start = race?.start else { return isLive }
        let end = race?.end ?? start.addingTimeInterval(3 * 3600)
        return (start...end).contains(Date())
    }

    var isUpcoming: Bool {
        guard let start = race?.start else { return false }
        return start > Date()
    }

    static func == (lhs: CatalogItem, rhs: CatalogItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SectionStyle: Hashable {
    case hero, banner, landscape, portrait, heading, schedule, header
}

struct ScheduleGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let events: [CatalogItem]
}

struct CatalogSection: Identifiable, Hashable {
    var id: String
    var title: String
    var style: SectionStyle
    var items: [CatalogItem] = []
    var schedule: [ScheduleGroup] = []
    var viewAll: PageRef?
    var pictureID: String?
}

struct CatalogPage {
    var sections: [CatalogSection]
}

// MARK: - Playback models

enum FeedKind: String, Codable, Hashable {
    case main, additional, onboard
}

struct Feed: Identifiable, Hashable, Codable {
    var id: String
    var kind: FeedKind
    var title: String
    /// Value passed to the entitlement endpoint.
    var target: String
    var driverNumber: Int?
    var driverName: String?
    var team: String?
    var teamColor: String?
    var headshot: String?

    /// Stable key used by saved multiview setups ("main", "F1 LIVE", "obc:44").
    var setupKey: String {
        switch kind {
        case .main: return "main"
        case .additional: return title.uppercased()
        case .onboard: return "obc:\(driverNumber ?? 0)"
        }
    }

    var displayTitle: String {
        switch kind {
        case .main: return String(localized: "Internationaal")
        case .additional: return title.capitalized
        case .onboard:
            if let name = driverName, !name.isEmpty { return name }
            return title
        }
    }

    var symbol: String {
        switch kind {
        case .main: return "tv"
        case .additional:
            let lower = title.lowercased()
            if lower.contains("data") { return "chart.xyaxis.line" }
            if lower.contains("tracker") { return "map" }
            if lower.contains("live") { return "dot.radiowaves.left.and.right" }
            return "rectangle.stack"
        case .onboard: return "car.side"
        }
    }
}

struct VideoDetails {
    var item: CatalogItem
    var feeds: [Feed]
}

struct Entitlement {
    let streamURL: URL
    let isFairPlay: Bool
    let licenseURL: URL?
    let token: String
}

// MARK: - Country codes

enum CountryCodes {
    /// F1 uses IOC/ISO-3 style keys; map the ones that appear on the calendar.
    static func alpha2(fromAlpha3 code: String) -> String? {
        let table: [String: String] = [
            "AUS": "AU", "AUT": "AT", "AZE": "AZ", "BHR": "BH", "BEL": "BE", "BRA": "BR", "CAN": "CA",
            "CHN": "CN", "ESP": "ES", "FRA": "FR", "GBR": "GB", "HUN": "HU", "ITA": "IT", "JPN": "JP",
            "MEX": "MX", "MON": "MC", "MCO": "MC", "NED": "NL", "NLD": "NL", "POR": "PT", "PRT": "PT",
            "QAT": "QA", "KSA": "SA", "SAU": "SA", "SGP": "SG", "UAE": "AE", "ARE": "AE", "USA": "US",
            "RUS": "RU", "TUR": "TR", "GER": "DE", "DEU": "DE", "ARG": "AR", "MAR": "MA", "RSA": "ZA",
            "ZAF": "ZA", "KOR": "KR", "IND": "IN", "MAL": "MY", "MYS": "MY", "SWE": "SE", "SUI": "CH",
            "CHE": "CH", "VIE": "VN", "FIN": "FI", "DEN": "DK", "NZL": "NZ", "THA": "TH", "IRL": "IE"
        ]
        if code.count == 2 { return code }
        return table[code]
    }
}
