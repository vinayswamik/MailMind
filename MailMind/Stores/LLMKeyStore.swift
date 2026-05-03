import Foundation
import Combine
import Security

enum LLMProvider: String, CaseIterable, Codable, Identifiable {
    case openAI = "openai_gpt4"
    case anthropic = "anthropic_claude"
    case google = "google_gemini"
    case mistral = "mistral"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI (GPT-4)"
        case .anthropic:
            "Anthropic (Claude)"
        case .google:
            "Google (Gemini)"
        case .mistral:
            "Mistral"
        }
    }
}

final class LLMKeyStore: ObservableObject {
    @Published private(set) var savedProviders: [LLMProvider] = []

    private let defaults: UserDefaults
    private let keychainService = "MailMind.LLMAPIKeys"
    private let providerOrderKey = "llmProviderPriorityOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.savedProviders = loadSavedProviders()
    }

    @discardableResult
    func saveKey(_ apiKey: String, for provider: LLMProvider) -> Bool {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAPIKey.isEmpty,
              let keyData = trimmedAPIKey.data(using: .utf8) else {
            return false
        }

        deleteKeychainItem(for: provider)

        var query = baseKeychainQuery(for: provider)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = keyData

        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            return false
        }

        if !savedProviders.contains(provider) {
            savedProviders.append(provider)
            saveProviderOrder()
        }

        return true
    }

    func deleteKeys(at offsets: IndexSet) {
        let providersToDelete = offsets.map { savedProviders[$0] }

        for provider in providersToDelete {
            deleteKeychainItem(for: provider)
        }

        for offset in offsets.sorted(by: >) {
            savedProviders.remove(at: offset)
        }

        saveProviderOrder()
    }

    func deleteKey(for provider: LLMProvider) {
        deleteKeychainItem(for: provider)
        savedProviders.removeAll { $0 == provider }
        saveProviderOrder()
    }

    func moveProviders(from source: IndexSet, to destination: Int) {
        let movedProviders = source.sorted().map { savedProviders[$0] }
        var remainingProviders = savedProviders

        for offset in source.sorted(by: >) {
            remainingProviders.remove(at: offset)
        }

        let adjustedDestination = destination - source.filter { $0 < destination }.count
        let insertionIndex = min(max(adjustedDestination, 0), remainingProviders.count)
        remainingProviders.insert(contentsOf: movedProviders, at: insertionIndex)
        savedProviders = remainingProviders

        saveProviderOrder()
    }

    private func loadSavedProviders() -> [LLMProvider] {
        let providersWithKeys = LLMProvider.allCases.filter { hasKeychainItem(for: $0) }
        let savedOrder = defaults.stringArray(forKey: providerOrderKey) ?? []
        let orderedProviders = savedOrder.compactMap(LLMProvider.init(rawValue:))
            .filter { providersWithKeys.contains($0) }
        let unorderedProviders = providersWithKeys.filter { !orderedProviders.contains($0) }

        return orderedProviders + unorderedProviders
    }

    private func saveProviderOrder() {
        defaults.set(savedProviders.map(\.rawValue), forKey: providerOrderKey)
    }

    private func hasKeychainItem(for provider: LLMProvider) -> Bool {
        var query = baseKeychainQuery(for: provider)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func deleteKeychainItem(for provider: LLMProvider) {
        SecItemDelete(baseKeychainQuery(for: provider) as CFDictionary)
    }

    private func baseKeychainQuery(for provider: LLMProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}
