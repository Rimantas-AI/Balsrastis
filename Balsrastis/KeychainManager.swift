import Foundation
import Security

/// Secure storage for provider API keys, backed by the macOS Keychain.
///
/// Keys are stored as generic passwords under one service, keyed by the
/// provider's `rawValue`. Nothing here ever touches `UserDefaults`, and keys are
/// never logged (satisfies "keys not visible in plain text" / "never log keys").
final class KeychainManager {

    static let shared = KeychainManager()
    private init() {}

    /// One service namespace for all API keys.
    private let service = "lt.balsrastis.app.apikeys"

    /// The namespace used while the app was called OmniScribe.
    ///
    /// Renaming the bundle would otherwise have silently orphaned every stored
    /// key — the entries stay in the Keychain, but under a service this app no
    /// longer looks at, so it would simply report no key and ask the user to
    /// paste both again on every machine. `apiKey(for:)` migrates on first read
    /// instead. Safe to delete once no install predates the rename.
    private let legacyService = "com.omniscribe.app.apikeys"

    enum KeychainError: LocalizedError {
        case encodingFailed
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Could not encode the API key for storage."
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
                return "Keychain error: \(message) (\(status))"
            }
        }
    }

    // MARK: – Create / Update

    /// Stores (or replaces) the key for a provider. Implemented as delete-then-add
    /// so it works whether or not an entry already exists.
    func setAPIKey(_ key: String, for provider: AIProviderID) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try? deleteAPIKey(for: provider)  // Ignore "not found" from a first-time save.

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      provider.rawValue,
            kSecValueData as String:        data,
            // Available after first unlock so a Launch-at-Login app can read it.
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: – Read

    /// Returns the stored key, or `nil` if none is set for this provider.
    ///
    /// Falls back to the pre-rename namespace once, copying anything found into
    /// the current one, so an install that predates the rename keeps working
    /// without the user re-entering both keys.
    func apiKey(for provider: AIProviderID) throws -> String? {
        if let key = try read(provider: provider, from: service) {
            return key
        }
        // `try?` on an Optional-returning throwing call flattens to String?, so
        // this covers both "no legacy entry" and "legacy lookup failed".
        guard let legacy = try? read(provider: provider, from: legacyService) else {
            return nil
        }
        // Copy forward; the old entry is left alone rather than deleted, so a
        // failure here cannot lose the only copy of a key.
        try? setAPIKey(legacy, for: provider)
        return legacy
    }

    private func read(provider: AIProviderID, from service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      provider.rawValue,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Convenience: `true` if a non-empty key exists.
    func hasAPIKey(for provider: AIProviderID) -> Bool {
        let key = (try? apiKey(for: provider)) ?? nil
        return key?.isEmpty == false
    }

    // MARK: – Delete

    func deleteAPIKey(for provider: AIProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  provider.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
