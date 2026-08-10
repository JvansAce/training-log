import Foundation
import Security

/// A minimal wrapper over the Keychain calls WHOOP's tokens need: set, get,
/// delete, nothing else.
///
/// `kSecAttrSynchronizable` mirrors each item through iCloud Keychain, so a
/// WHOOP connection made on one iPhone is already there on the next —
/// matching how everything else in this app treats "your other devices" as
/// solved, not as a feature to build. Tokens live here rather than in
/// SwiftData/CloudKit on principle: an OAuth token is a credential, and
/// credentials belong in the platform's credential store, not alongside
/// training logs in the app's own database.
struct KeychainStore {
    let service: String

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
    }

    func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let matchQuery = query(account: account)
        if SecItemCopyMatching(matchQuery as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(matchQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var insertQuery = matchQuery
            insertQuery[kSecValueData as String] = data
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    func get(account: String) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
