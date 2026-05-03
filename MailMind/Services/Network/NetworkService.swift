import Foundation

struct EmailAttachment: Codable, Equatable, Hashable {
    let name: String
    let mimeType: String

    init(name: String, mimeType: String = "") {
        self.name = name
        self.mimeType = mimeType
    }
}

struct Email: Identifiable, Codable, Equatable {
    let id: UUID
    let sender: String
    let senderEmail: String
    let subject: String
    let preview: String
    let receivedAt: String
    /// Gmail internal date — used for precise timestamp in detail view (seconds since 1970).
    let receivedAtUnix: Double?
    let destinationAccount: String
    let isUnread: Bool
    let summarizedBody: String
    let attachments: [EmailAttachment]
    let gmailThreadID: String?

    init(
        id: UUID = UUID(),
        sender: String,
        senderEmail: String = "",
        subject: String,
        preview: String,
        receivedAt: String,
        receivedAtUnix: Double? = nil,
        destinationAccount: String,
        isUnread: Bool = false,
        summarizedBody: String = "",
        attachments: [EmailAttachment] = [],
        gmailThreadID: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.senderEmail = senderEmail.isEmpty ? Self.derivedEmail(from: sender) : senderEmail
        self.subject = subject
        self.preview = preview
        self.receivedAt = receivedAt
        self.receivedAtUnix = receivedAtUnix
        self.destinationAccount = destinationAccount
        self.isUnread = isUnread
        self.summarizedBody = summarizedBody.isEmpty ? preview : summarizedBody
        self.attachments = attachments
        self.gmailThreadID = gmailThreadID
    }

    func updatingUnreadState(_ isUnread: Bool) -> Email {
        Email(
            id: id,
            sender: sender,
            senderEmail: senderEmail,
            subject: subject,
            preview: preview,
            receivedAt: receivedAt,
            receivedAtUnix: receivedAtUnix,
            destinationAccount: destinationAccount,
            isUnread: isUnread,
            summarizedBody: summarizedBody,
            attachments: attachments,
            gmailThreadID: gmailThreadID
        )
    }

    private static func derivedEmail(from sender: String) -> String {
        let slug = sender
            .lowercased()
            .replacingOccurrences(of: " ", with: ".")
        return "\(slug)@example.com"
    }

    private enum CodingKeys: String, CodingKey {
        case id, sender, senderEmail, subject, preview, receivedAt, receivedAtUnix
        case destinationAccount, isUnread, summarizedBody, attachments
        case gmailThreadID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let sender = try container.decode(String.self, forKey: .sender)
        let senderEmail = try container.decodeIfPresent(String.self, forKey: .senderEmail) ?? ""
        let subject = try container.decode(String.self, forKey: .subject)
        let preview = try container.decode(String.self, forKey: .preview)
        let receivedAt = try container.decode(String.self, forKey: .receivedAt)
        let receivedAtUnix = try container.decodeIfPresent(Double.self, forKey: .receivedAtUnix)
        let destinationAccount = try container.decode(String.self, forKey: .destinationAccount)
        let isUnread = try container.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
        let summarizedBody = try container.decodeIfPresent(String.self, forKey: .summarizedBody) ?? ""
        let gmailThreadID = try container.decodeIfPresent(String.self, forKey: .gmailThreadID)

        // Tolerate persisted records from before attachments carried mime types.
        let attachments: [EmailAttachment]
        if let typed = try? container.decode([EmailAttachment].self, forKey: .attachments) {
            attachments = typed
        } else if let legacy = try? container.decode([String].self, forKey: .attachments) {
            attachments = legacy.map { EmailAttachment(name: $0) }
        } else {
            attachments = []
        }

        self.init(
            id: id,
            sender: sender,
            senderEmail: senderEmail,
            subject: subject,
            preview: preview,
            receivedAt: receivedAt,
            receivedAtUnix: receivedAtUnix,
            destinationAccount: destinationAccount,
            isUnread: isUnread,
            summarizedBody: summarizedBody,
            attachments: attachments,
            gmailThreadID: gmailThreadID
        )
    }
}

protocol NetworkService {
    func fetchEmails(forCategory category: String, accounts: [String]) async -> [Email]
    func submitCategorySkill(categoryName: String, skillText: String) async -> Bool
    func getAPIKeyStatus(provider: String) async -> Bool
}

final class GmailNetworkService: ObservableObject, NetworkService {
    private let emailStore: EmailStore
    private let accountStore: AccountStore

    init(emailStore: EmailStore, accountStore: AccountStore) {
        self.emailStore = emailStore
        self.accountStore = accountStore
    }

    func fetchEmails(forCategory category: String, accounts: [String]) async -> [Email] {
        await MainActor.run {
            let requestedAccounts = Set(accounts.map { $0.lowercased() })
            let accountIDs = accountStore.accounts
                .filter { requestedAccounts.contains($0.emailAddress.lowercased()) }
                .map(\.id)
            return emailStore.emails(forCategory: category, accountIDs: accountIDs)
        }
    }

    func submitCategorySkill(categoryName: String, skillText: String) async -> Bool {
        true
    }

    func getAPIKeyStatus(provider: String) async -> Bool {
        true
    }
}
