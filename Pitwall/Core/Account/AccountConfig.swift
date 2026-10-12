import Foundation
import Security

/// Pitwall-accounts (Supabase). De URL en de publishable key zijn openbaar bedoeld en
/// mogen in de repo staan; geheime sleutels staan alleen als secrets op de server.
/// Zijn ze leeg, dan toont het inlogscherm "Accounts zijn niet ingesteld in deze build"
/// met een knop om zonder account door te gaan.
enum AccountConfig {
    static let supabaseURL = "https://zqkqeloraogowzgdjzpr.supabase.co"
    static let supabaseAnonKey = "sb_publishable_CbiaygVoY6jjbcq4FDR4Yw_poUWLKIG"

    static var isConfigured: Bool {
        URL(string: supabaseURL)?.host != nil && !supabaseAnonKey.isEmpty
    }

    static var baseURL: URL { URL(string: supabaseURL) ?? URL(string: "https://invalid.supabase.co")! }

    /// Deeplinks naar de app (moeten in de Supabase redirect-lijst staan: pitwall://**).
    static let confirmRedirect = "pitwall://confirmed"
    static let resetRedirect = "pitwall://reset"
}

/// Klein sleutelhangerdepot dat alleen op dit apparaat blijft (nooit iCloud).
enum LocalKeychain {
    private static let service = "nl.lrvdlinden.pitwall.account"

    static func data(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func string(_ key: String) -> String? { data(key).flatMap { String(data: $0, encoding: .utf8) } }
    static func setString(_ value: String?, for key: String) { set(value.map { Data($0.utf8) }, for: key) }
}
