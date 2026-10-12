import Foundation

/// Houdt F1 TV-login, instellingen en multiview-setups gelijk tussen apparaten,
/// via twee kanalen tegelijk:
/// - iCloud Key-Value Store (zelfde Apple ID, ook zonder netwerk naar onze server);
/// - het Pitwall-account (versleuteld op de server, ook voor een Apple TV met een ander Apple ID).
///
/// Elk onderdeel is één geheel met een eigen `updatedAt`; de nieuwste versie wint.
@MainActor
final class SyncCoordinator {
    enum Section: String, CaseIterable {
        case f1tv, settings, setups
    }

    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var applying = false
    private var pendingUpload = Set<Section>()
    private var uploadTask: Task<Void, Never>?

    /// Leest de huidige lokale waarde van een onderdeel (JSON-compatibel; `NSNull` = leeg).
    var export: (Section) -> Any = { _ in NSNull() }
    /// Zet een waarde van iCloud of de server lokaal neer.
    var apply: (Section, Any) -> Void = { _, _ in }
    /// Het account voor serversync (nil = alleen iCloud).
    weak var account: AccountService?

    func start() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
        kv.synchronize()
        pullFromCloud()
        // Eerste keer na de update: wat lokaal al bestaat in iCloud zetten.
        for section in Section.allCases where localStamp(section) == 0 && !(export(section) is NSNull) {
            setLocalStamp(section, Date().timeIntervalSince1970 - 1)
            pushToCloud(section)
        }
    }

    // MARK: Lokale wijziging

    func localChanged(_ section: Section) {
        guard !applying else { return }
        setLocalStamp(section, Date().timeIntervalSince1970)
        pushToCloud(section)
        scheduleUpload(section)
    }

    // MARK: iCloud

    private func cloudKey(_ section: Section) -> String { "pitwall.sync.\(section.rawValue)" }

    private func pushToCloud(_ section: Section) {
        guard let json = Self.encode(export(section)) else { return }
        kv.set(["updatedAt": localStamp(section), "json": json], forKey: cloudKey(section))
        kv.synchronize()
    }

    func pullFromCloud() {
        for section in Section.allCases {
            guard let record = kv.dictionary(forKey: cloudKey(section)),
                  let stamp = record["updatedAt"] as? Double,
                  let json = record["json"] as? String,
                  stamp > localStamp(section),
                  let value = Self.decode(json) else { continue }
            applyRemote(section, value: value, stamp: stamp)
            // Ook het account bijwerken, zodat een Apple TV met een ander Apple ID het krijgt.
            scheduleUpload(section)
        }
    }

    // MARK: Account

    /// Na inloggen, bij het starten, bij terugkeer naar de voorgrond en bij elke heartbeat.
    func pullFromServer() async {
        guard let account, account.phase == .signedIn else { return }
        if defaults.bool(forKey: "pitwall.accountSwitched") {
            // Ander account op dit apparaat: lokale gegevens van het vorige account wijken.
            for section in Section.allCases { setLocalStamp(section, 0) }
            applying = true
            apply(.f1tv, NSNull())
            apply(.setups, [Any]())
            applying = false
            defaults.set(false, forKey: "pitwall.accountSwitched")
        }
        guard let entries = try? await account.getState(Section.allCases.map(\.rawValue)) else { return }
        for section in Section.allCases {
            let entry = entries[section.rawValue]
            let wrapper = entry?.data as? [String: Any]
            let stamp = wrapper?["updatedAt"] as? Double ?? 0
            if let wrapper, stamp > localStamp(section) {
                applyRemote(section, value: wrapper["value"] ?? NSNull(), stamp: stamp)
                pushToCloud(section)
            } else if localStamp(section) > stamp, !(export(section) is NSNull && stamp == 0) {
                pendingUpload.insert(section)
            }
        }
        if !pendingUpload.isEmpty { await upload() }
    }

    private func scheduleUpload(_ section: Section) {
        guard account?.phase == .signedIn else { return }
        pendingUpload.insert(section)
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.upload()
        }
    }

    private func upload() async {
        guard let account, account.phase == .signedIn else { return }
        let sections = pendingUpload
        pendingUpload.removeAll()
        for section in sections {
            let payload: [String: Any] = ["updatedAt": localStamp(section), "value": export(section)]
            do {
                try await account.putState(section.rawValue, data: payload)
            } catch {
                pendingUpload.insert(section)   // later opnieuw (heartbeat)
            }
        }
    }

    // MARK: Helpers

    private func applyRemote(_ section: Section, value: Any, stamp: Double) {
        applying = true
        apply(section, value)
        applying = false
        setLocalStamp(section, stamp)
    }

    private func localStamp(_ section: Section) -> Double { defaults.double(forKey: "sync.stamp.\(section.rawValue)") }
    private func setLocalStamp(_ section: Section, _ value: Double) { defaults.set(value, forKey: "sync.stamp.\(section.rawValue)") }

    static func encode(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["v": value]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String) -> Any? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        return object["v"]
    }

    /// Codable ↔ JSON-object.
    static func jsonObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return object
    }

    static func decodeObject<T: Decodable>(_ type: T.Type, from object: Any) -> T? {
        guard !(object is NSNull), JSONSerialization.isValidJSONObject(object) || object is [Any],
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
