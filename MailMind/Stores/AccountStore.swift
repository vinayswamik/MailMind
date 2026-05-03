import Foundation
import Combine
import GoogleSignIn

enum ConnectionStatus: String, Codable {
    case connected
    case reconnectRequired
}

struct GmailAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var emailAddress: String
    var includeInCategorization: Bool
    var connectionStatus: ConnectionStatus

    var isCredentialMissing: Bool {
        connectionStatus != .connected
    }

    init(
        id: UUID = UUID(),
        emailAddress: String,
        includeInCategorization: Bool = true,
        connectionStatus: ConnectionStatus = .reconnectRequired
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.includeInCategorization = includeInCategorization
        self.connectionStatus = connectionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        emailAddress = try container.decode(String.self, forKey: .emailAddress)
        includeInCategorization = try container.decodeIfPresent(Bool.self, forKey: .includeInCategorization) ?? true
        connectionStatus = try container.decodeIfPresent(ConnectionStatus.self, forKey: .connectionStatus) ?? .reconnectRequired
    }
}

final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [GmailAccount] = []

    private let defaults: UserDefaults
    private let storageKey = "gmailAccounts"
    private let tokenStore: GmailTokenStore

    init(defaults: UserDefaults = .standard, tokenStore: GmailTokenStore = GmailTokenStore()) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.accounts = Self.loadAccounts(from: defaults, key: storageKey)
    }

    enum ConnectOutcome {
        case added
        case reconnected
        case failed
    }

    @discardableResult
    func connectGoogleAccount(email: String, tokens: GmailTokens) -> ConnectOutcome {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            return .failed
        }

        if let existingIndex = accounts.firstIndex(where: { $0.emailAddress == normalizedEmail }) {
            let accountID = accounts[existingIndex].id
            guard tokenStore.save(tokens, for: accountID) else {
                return .failed
            }
            accounts[existingIndex].connectionStatus = .connected
            saveAccounts()
            return .reconnected
        }

        let newAccount = GmailAccount(
            emailAddress: normalizedEmail,
            connectionStatus: .connected
        )
        guard tokenStore.save(tokens, for: newAccount.id) else {
            return .failed
        }
        accounts.append(newAccount)
        saveAccounts()
        return .added
    }

    func setIncludeInCategorization(_ includeInCategorization: Bool, for id: GmailAccount.ID) {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        accounts[accountIndex].includeInCategorization = includeInCategorization
        saveAccounts()
    }

    func markReconnectRequired(for id: GmailAccount.ID) {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        accounts[accountIndex].connectionStatus = .reconnectRequired
        saveAccounts()
    }

    func deleteAccount(id: GmailAccount.ID) {
        guard let account = accounts.first(where: { $0.id == id }) else {
            return
        }

        tokenStore.delete(for: id)
        accounts.removeAll { $0.id == id }
        saveAccounts()
        signOutSDKIfMatches(account)
    }

    func deleteAccounts(at offsets: IndexSet) {
        let removed = offsets.map { accounts[$0] }

        for offset in offsets.sorted(by: >) {
            accounts.remove(at: offset)
        }

        for account in removed {
            tokenStore.delete(for: account.id)
        }

        saveAccounts()

        for account in removed {
            signOutSDKIfMatches(account)
        }
    }

    private func signOutSDKIfMatches(_ account: GmailAccount) {
        guard let currentEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email,
              currentEmail.lowercased() == account.emailAddress else {
            return
        }

        GIDSignIn.sharedInstance.signOut()
        Task { @MainActor in
            try? await GIDSignIn.sharedInstance.disconnect()
        }
    }

    func checkCredentialStatus() {
        var updatedAccounts = accounts

        for index in updatedAccounts.indices {
            if tokenStore.hasTokens(for: updatedAccounts[index].id) {
                updatedAccounts[index].connectionStatus = .connected
            } else if let restored = restoreTokensFromSDK(for: updatedAccounts[index]) {
                tokenStore.save(restored, for: updatedAccounts[index].id)
                updatedAccounts[index].connectionStatus = .connected
            } else {
                updatedAccounts[index].connectionStatus = .reconnectRequired
            }
        }

        accounts = updatedAccounts
        saveAccounts()
    }

    private func restoreTokensFromSDK(for account: GmailAccount) -> GmailTokens? {
        guard let user = GIDSignIn.sharedInstance.currentUser,
              let email = user.profile?.email,
              email.lowercased() == account.emailAddress else {
            return nil
        }

        return GmailTokens(
            accessToken: user.accessToken.tokenString,
            refreshToken: user.refreshToken.tokenString,
            accessTokenExpiresAt: user.accessToken.expirationDate ?? Date().addingTimeInterval(3300),
            scope: "https://www.googleapis.com/auth/gmail.readonly",
            email: email
        )
    }

    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    private static func loadAccounts(from defaults: UserDefaults, key: String) -> [GmailAccount] {
        guard let data = defaults.data(forKey: key),
              let accounts = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return []
        }

        return accounts
    }
}
