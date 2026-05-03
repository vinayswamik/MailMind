import Foundation
import Combine

final class MockNetworkService: ObservableObject, NetworkService {
    func fetchEmails(forCategory category: String, accounts: [String]) async -> [Email] {
        await delay()

        let account = accounts.first

        let mockEmails = MockData.categories.first { $0.name.lowercased() == category.lowercased() }?.emails ?? []

        guard let account else {
            return mockEmails
        }

        return mockEmails.map { email in
            Email(
                id: email.id,
                sender: email.sender,
                senderEmail: email.senderEmail,
                subject: email.subject,
                preview: email.preview,
                receivedAt: email.receivedAt,
                receivedAtUnix: email.receivedAtUnix,
                destinationAccount: account,
                isUnread: email.isUnread,
                summarizedBody: email.summarizedBody,
                attachments: email.attachments
            )
        }
    }

    func submitCategorySkill(categoryName: String, skillText: String) async -> Bool {
        await delay()
        return !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !skillText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func getAPIKeyStatus(provider: String) async -> Bool {
        await delay()
        return ["OpenAI (GPT-4)", "openai_gpt4", "OpenAI"].contains(provider)
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
