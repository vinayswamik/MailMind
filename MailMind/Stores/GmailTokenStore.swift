import Foundation
import Security

struct GmailTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var scope: String
    var email: String
}

final class GmailTokenStore {
    private let service = "MailMind.GmailTokens"

    @discardableResult
    func save(_ tokens: GmailTokens, for accountID: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else {
            return false
        }

        deleteItem(for: accountID)

        var query = baseQuery(for: accountID)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func load(for accountID: UUID) -> GmailTokens? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(GmailTokens.self, from: data)
    }

    func hasTokens(for accountID: UUID) -> Bool {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(for accountID: UUID) {
        deleteItem(for: accountID)
    }

    private func deleteItem(for accountID: UUID) {
        SecItemDelete(baseQuery(for: accountID) as CFDictionary)
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "tokens_\(accountID.uuidString)"
        ]
    }
}
