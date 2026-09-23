import Foundation
import Security
import LocalAuthentication
import MacBridgeCore

/// Separate service/account namespace; no raw secrets in preferences, logs or file URLs.
public struct KeychainStore: Sendable {
    private static let vaultLock = NSLock()
    private let service: String
    private let allowInteraction: Bool
    public init(service: String, allowInteraction: Bool = false) { self.service = service; self.allowInteraction = allowInteraction }
    private func query(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        return [kSecUseAuthenticationContext as String: context,
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    // Existing users have legacy file-based Keychain items. LAContext governs modern
    // items; this process-wide legacy switch ensures background startup cannot prompt.
    public static func setLegacyInteractionAllowed(_ allowed: Bool) {
        SecKeychainSetUserInteractionAllowed(allowed)
    }
    public static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ContractError(code: "random_generation_failed")
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func legacyWrite(_ value: String, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ContractError(code: "keychain_write_failed") }
        } else if status != errSecSuccess { throw ContractError(code: "keychain_write_failed") }
    }
    private func legacyRead(account: String) throws -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ContractError(code: "keychain_read_failed")
        }
        return value
    }
    private func legacyDelete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ContractError(code: "keychain_delete_failed") }
    }
    private var vaultStore: KeychainStore { KeychainStore(service: service + ".credentials-v2", allowInteraction: allowInteraction) }
    private func loadVault() throws -> [String:String]? {
        guard let raw = try vaultStore.legacyRead(account: "credentials") else { return nil }
        guard let data = raw.data(using: .utf8), let values = try? JSONDecoder().decode([String:String].self, from: data) else { throw ContractError(code: "keychain_credentials_invalid") }
        return values
    }
    private func saveVault(_ values: [String:String]) throws {
        let raw = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        try vaultStore.legacyWrite(raw, account: "credentials")
    }
    /// One Keychain read per connection attempt, even when several tokens are needed.
    /// Do not retain a process-wide cache: deletion and revocation must remain authoritative.
    public func connectionCredentials() throws -> ConnectionCredentials {
        Self.vaultLock.lock(); defer { Self.vaultLock.unlock() }
        return try Self.prepareConnection(load: loadVault, readLegacy: { try legacyRead(account: $0) },
                                          save: saveVault, generate: Self.randomToken)
    }

    static func prepareConnection(load: () throws -> [String: String]?,
                                  readLegacy: (String) throws -> String?,
                                  save: ([String: String]) throws -> Void,
                                  generate: () throws -> String) throws -> ConnectionCredentials {
        let existing = try load()
        var values: [String: String]
        if let existing {
            values = existing
        } else {
            values = [:]
            // Only installations without a vault need the old, separate items.
            // Complete every read before writing; a denied read must not replace secrets.
            for account in ["device-token", "local-api-token", "bootstrap-token", "pending-device-token"] {
                values[account] = try readLegacy(account)
            }
        }
        if values["local-api-token"] == nil { values["local-api-token"] = try generate() }
        if existing != values { try save(values) }
        guard let local = values["local-api-token"] else { throw ContractError(code: "keychain_credentials_invalid") }
        return ConnectionCredentials(device: values["device-token"], local: local,
                                     hasBootstrap: values["bootstrap-token"] != nil)
    }

    public func read(account: String) throws -> String? {
        Self.vaultLock.lock(); defer { Self.vaultLock.unlock() }
        if let values = try loadVault() { return values[account] }
        return try legacyRead(account: account)
    }
    public func write(_ value: String, account: String) throws {
        Self.vaultLock.lock(); defer { Self.vaultLock.unlock() }
        // New installations create one item. Existing installs migrate at connection setup.
        if var values = try loadVault() { values[account] = value; try saveVault(values) }
        else { try legacyWrite(value, account: account) }
    }
    public func delete(account: String) throws {
        Self.vaultLock.lock(); defer { Self.vaultLock.unlock() }
        if var values = try loadVault() { values.removeValue(forKey: account); try saveVault(values) }
        try legacyDelete(account: account)
    }

}

public struct ConnectionCredentials: Sendable {
    public let device: String?
    public let local: String
    public let hasBootstrap: Bool
}
