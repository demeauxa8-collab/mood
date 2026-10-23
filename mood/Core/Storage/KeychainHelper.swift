import Foundation
import Security

/// Credentials store. Unsigned builds (Mac Catalyst, simulator) have no keychain entitlement
/// (errSecMissingEntitlement), so nothing survived a relaunch and people signed in again after every
/// update. When the keychain refuses, values go to a private file instead (folder 0700, file 0600,
/// data protection on iPhone). Signed builds use the keychain and never write that file.
enum KeychainHelper {

    private static let service = "app.mood.matrix"

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            print("KeychainHelper.save(\(key)) failed: value is not UTF-8 encodable")
            return false
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        var values = readFile()
        guard status == errSecSuccess else {
            print("KeychainHelper.save(\(key)): keychain refused (OSStatus \(status)), using the private file")
            values[key] = value
            return writeFile(values)
        }
        if values.removeValue(forKey: key) != nil { writeFile(values) }
        return true
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("KeychainHelper.load(\(key)) failed: OSStatus \(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return readFile()[key] }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        var values = readFile()
        if values.removeValue(forKey: key) != nil { writeFile(values) }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("KeychainHelper.delete(\(key)) failed: OSStatus \(status)")
            return status == errSecMissingEntitlement
        }
        return true
    }

    @discardableResult
    static func deleteAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        writeFile([:])
        guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
            print("KeychainHelper.deleteAll failed: OSStatus \(status)")
            return false
        }
        return true
    }

    // MARK: - Private file (builds without keychain access)

    private static var fileURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let folder = support.appendingPathComponent("Mood", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        return folder.appendingPathComponent("credentials.json")
    }

    private static func readFile() -> [String: String] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    @discardableResult
    private static func writeFile(_ values: [String: String]) -> Bool {
        guard let url = fileURL else { return false }
        guard !values.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        guard let data = try? JSONEncoder().encode(values) else { return false }
        #if targetEnvironment(macCatalyst)
        let options: Data.WritingOptions = .atomic
        #else
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #endif
        do {
            try data.write(to: url, options: options)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            print("KeychainHelper: private file write failed: \(error.localizedDescription)")
            return false
        }
    }
}
