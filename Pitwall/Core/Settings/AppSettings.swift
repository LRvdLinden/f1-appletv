import Foundation
import Observation

enum CatalogLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "ENG", dutch = "NLD", german = "DEU", french = "FRA", spanish = "SPA", portuguese = "POR"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .english: return "English"
        case .dutch: return "Nederlands"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        }
    }
    /// ISO 639-2 code as used in the HLS audio renditions.
    var audioCode: String {
        switch self {
        case .english: return "eng"
        case .dutch: return "nld"
        case .german: return "deu"
        case .french: return "fra"
        case .spanish: return "spa"
        case .portuguese: return "por"
        }
    }
}

enum LiveStart: String, CaseIterable, Identifiable, Codable {
    case liveEdge, beginning, ask
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .liveEdge: return String(localized: "Live")
        case .beginning: return String(localized: "Vanaf het begin")
        case .ask: return String(localized: "Altijd vragen")
        }
    }
}

enum DefaultFeed: String, CaseIterable, Identifiable, Codable {
    case international, f1Live
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .international: return String(localized: "Internationaal")
        case .f1Live: return "F1 Live"
        }
    }
}

enum StreamQuality: String, CaseIterable, Identifiable, Codable {
    case auto, uhd, fhd, hd, sd
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return String(localized: "Automatisch")
        case .uhd: return "4K"
        case .fhd: return "1080p"
        case .hd: return "720p"
        case .sd: return "480p"
        }
    }
    var maxSize: CGSize {
        switch self {
        case .auto, .uhd: return .zero
        case .fhd: return CGSize(width: 1920, height: 1080)
        case .hd: return CGSize(width: 1280, height: 720)
        case .sd: return CGSize(width: 854, height: 480)
        }
    }
    var peakBitRate: Double {
        switch self {
        case .auto, .uhd: return 0
        case .fhd: return 8_000_000
        case .hd: return 4_000_000
        case .sd: return 1_500_000
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var catalogLanguage: CatalogLanguage { didSet { save(catalogLanguage.rawValue, "catalogLanguage") } }
    var audioLanguage: CatalogLanguage { didSet { save(audioLanguage.rawValue, "audioLanguage") } }
    var liveStart: LiveStart { didSet { save(liveStart.rawValue, "liveStart") } }
    var defaultFeed: DefaultFeed { didSet { save(defaultFeed.rawValue, "defaultFeed") } }
    var quality: StreamQuality { didSet { save(quality.rawValue, "quality") } }
    var multiviewQuality: StreamQuality { didSet { save(multiviewQuality.rawValue, "multiviewQuality") } }
    var reportProgress: Bool { didSet { defaults.set(reportProgress, forKey: "reportProgress") } }
    var showCaptions: Bool { didSet { defaults.set(showCaptions, forKey: "showCaptions") } }

    init() {
        let d = UserDefaults.standard
        let preferredNL = Locale.preferredLanguages.first?.hasPrefix("nl") == true
        catalogLanguage = CatalogLanguage(rawValue: d.string(forKey: "catalogLanguage") ?? "") ?? (preferredNL ? .dutch : .english)
        audioLanguage = CatalogLanguage(rawValue: d.string(forKey: "audioLanguage") ?? "") ?? .english
        liveStart = LiveStart(rawValue: d.string(forKey: "liveStart") ?? "") ?? .ask
        defaultFeed = DefaultFeed(rawValue: d.string(forKey: "defaultFeed") ?? "") ?? .international
        quality = StreamQuality(rawValue: d.string(forKey: "quality") ?? "") ?? .auto
        multiviewQuality = StreamQuality(rawValue: d.string(forKey: "multiviewQuality") ?? "") ?? .hd
        reportProgress = d.object(forKey: "reportProgress") as? Bool ?? true
        showCaptions = d.object(forKey: "showCaptions") as? Bool ?? false
    }

    private func save(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
}

// MARK: - Saved multiview setups

enum MultiviewLayout: String, CaseIterable, Identifiable, Codable {
    case auto, single, sideBySide, mainPlusOne, mainPlusThree, grid2x2, grid3x3
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return String(localized: "Automatisch")
        case .single: return String(localized: "Eén feed")
        case .sideBySide: return String(localized: "Naast elkaar")
        case .mainPlusOne: return String(localized: "Hoofd + 1")
        case .mainPlusThree: return String(localized: "Hoofd + 3")
        case .grid2x2: return "2 × 2"
        case .grid3x3: return "3 × 3"
        }
    }
    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .single: return "rectangle"
        case .sideBySide: return "rectangle.split.2x1"
        case .mainPlusOne: return "rectangle.inset.bottomright.filled"
        case .mainPlusThree: return "rectangle.split.1x2"
        case .grid2x2: return "rectangle.split.2x2"
        case .grid3x3: return "square.grid.3x3"
        }
    }
    var capacity: Int {
        switch self {
        case .auto: return 9
        case .single: return 1
        case .sideBySide, .mainPlusOne: return 2
        case .mainPlusThree, .grid2x2: return 4
        case .grid3x3: return 9
        }
    }
}

struct SavedSetup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var layout: MultiviewLayout
    var feedKeys: [String]
}

enum SetupStore {
    private static let key = "savedSetups"

    static func load() -> [SavedSetup] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedSetup].self, from: data)) ?? []
    }

    static func save(_ setups: [SavedSetup]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(setups), forKey: key)
    }
}
