import Foundation
import GRDB

private let emailStoreJSONEncoder = JSONEncoder()
private let emailStoreJSONDecoder = JSONDecoder()

struct StoredEmail: Codable, Equatable {
    let email: Email
    let accountID: UUID
    let messageID: String
    let category: String
    let storedAt: Date
}

@MainActor
final class EmailStore: ObservableObject {
    @Published private(set) var stored: [StoredEmail] = []
    @Published private(set) var isLoaded = false

    private let fileManager: FileManager
    private let legacyStoreURL: URL
    private let databaseURL: URL
    private let databasePool: DatabasePool?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let supportURL = Self.makeSupportURL(fileManager: fileManager)
        self.legacyStoreURL = supportURL.appendingPathComponent("emails.json")
        self.databaseURL = supportURL.appendingPathComponent("emails.sqlite")

        do {
            let pool = try DatabasePool(path: databaseURL.path)
            try Self.createSchema(in: pool)
            self.databasePool = pool
            self.stored = (try? Self.fetchStoredEmails(from: pool)) ?? []
            self.isLoaded = true

            Task {
                let migrated = await Self.migrateLegacyInBackground(
                    databasePool: pool,
                    legacyStoreURL: legacyStoreURL,
                    fileManager: fileManager
                )
                if migrated {
                    refreshStoredSnapshot()
                }
            }
        } catch {
            // Delete the failed file so a corrupt/partial sqlite never coexists with emails.json.
            // Try once more with a clean file; if that also fails, start with an empty in-memory store.
            try? fileManager.removeItem(at: databaseURL)
            if let pool = try? DatabasePool(path: databaseURL.path),
               (try? Self.createSchema(in: pool)) != nil {
                self.databasePool = pool
                self.stored = (try? Self.fetchStoredEmails(from: pool)) ?? []
            } else {
                self.databasePool = nil
                self.stored = []
            }
            self.isLoaded = true
        }
    }

    func insert(_ email: Email, accountID: UUID, messageID: String, category: String) {
        guard let databasePool else {
            insertLegacy(email, accountID: accountID, messageID: messageID, category: category)
            return
        }

        guard let emailData = try? emailStoreJSONEncoder.encode(email),
              let emailJSON = String(data: emailData, encoding: .utf8) else {
            return
        }

        let storedAt = Date()

        do {
            try databasePool.write { db in
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO stored_emails
                    (id, account_id, message_id, category, stored_at, email_json)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        email.id.uuidString,
                        accountID.uuidString,
                        messageID,
                        category,
                        storedAt.timeIntervalSince1970,
                        emailJSON
                    ]
                )
            }
            refreshStoredSnapshot()
        } catch {
            return
        }
    }

    func emails(forCategory category: String, accountIDs: [UUID]) -> [Email] {
        guard !accountIDs.isEmpty else {
            return []
        }

        guard let databasePool else {
            let accountSet = Set(accountIDs)
            return stored
                .filter { $0.category == category && accountSet.contains($0.accountID) }
                .sorted { $0.storedAt > $1.storedAt }
                .map(\.email)
        }

        let placeholders = Array(repeating: "?", count: accountIDs.count).joined(separator: ", ")
        let arguments = [category] + accountIDs.map(\.uuidString)

        do {
            let emailJSONs = try databasePool.read { db in
                try String.fetchAll(
                    db,
                    sql: """
                    SELECT email_json FROM stored_emails
                    WHERE category = ? AND account_id IN (\(placeholders))
                    ORDER BY stored_at DESC
                    """,
                    arguments: StatementArguments(arguments)
                )
            }

            return emailJSONs.compactMap { json in
                guard let data = json.data(using: .utf8) else {
                    return nil
                }
                return try? emailStoreJSONDecoder.decode(Email.self, from: data)
            }
        } catch {
            return []
        }
    }

    func purge(accountID: UUID) {
        guard let databasePool else {
            stored.removeAll { $0.accountID == accountID }
            persistLegacy()
            return
        }

        do {
            try databasePool.write { db in
                try db.execute(
                    sql: "DELETE FROM stored_emails WHERE account_id = ?",
                    arguments: [accountID.uuidString]
                )
            }
            refreshStoredSnapshot()
        } catch {
            return
        }
    }

    func storedRecord(emailID: Email.ID) -> StoredEmail? {
        stored.first { $0.email.id == emailID }
    }

    /// Deletes the stored categorized row for this MailMind email id (primary key in SQLite).
    func removeStoredEmail(emailID: Email.ID) {
        guard let databasePool else {
            stored.removeAll { $0.email.id == emailID }
            persistLegacy()
            return
        }

        do {
            try databasePool.write { db in
                try db.execute(
                    sql: "DELETE FROM stored_emails WHERE id = ?",
                    arguments: [emailID.uuidString]
                )
            }
            refreshStoredSnapshot()
        } catch {
            return
        }
    }

    func remove(accountID: UUID, messageID: String) -> StoredEmail? {
        guard let databasePool else {
            guard let index = stored.firstIndex(where: { $0.accountID == accountID && $0.messageID == messageID }) else {
                return nil
            }

            let removed = stored.remove(at: index)
            persistLegacy()
            return removed
        }

        do {
            var removed: StoredEmail?
            var didDelete = false
            try databasePool.write { db in
                if let row = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT account_id, message_id, category, stored_at, email_json
                    FROM stored_emails
                    WHERE account_id = ? AND message_id = ?
                    """,
                    arguments: [accountID.uuidString, messageID]
                ) {
                    // DELETE runs unconditionally — corrupt email_json must never block removal
                    try db.execute(
                        sql: "DELETE FROM stored_emails WHERE account_id = ? AND message_id = ?",
                        arguments: [accountID.uuidString, messageID]
                    )
                    didDelete = true
                    removed = try? Self.storedEmail(from: row)
                }
            }
            if didDelete {
                refreshStoredSnapshot()
            }
            return removed
        } catch {
            return nil
        }
    }

    private func insertLegacy(_ email: Email, accountID: UUID, messageID: String, category: String) {
        if stored.contains(where: { $0.accountID == accountID && $0.messageID == messageID }) {
            return
        }

        let entry = StoredEmail(
            email: email,
            accountID: accountID,
            messageID: messageID,
            category: category,
            storedAt: Date()
        )
        stored.insert(entry, at: 0)
        persistLegacy()
    }

    private func persistLegacy() {
        guard let data = try? emailStoreJSONEncoder.encode(stored) else {
            return
        }
        try? data.write(to: legacyStoreURL, options: .atomic)
    }

    private func refreshStoredSnapshot() {
        guard let databasePool,
              let snapshot = try? Self.fetchStoredEmails(from: databasePool) else {
            return
        }
        stored = snapshot
    }

    private nonisolated static func createSchema(in databasePool: DatabasePool) throws {
        try databasePool.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS stored_emails (
                    id          TEXT    PRIMARY KEY NOT NULL,
                    account_id  TEXT    NOT NULL,
                    message_id  TEXT    NOT NULL,
                    category    TEXT    NOT NULL,
                    stored_at   REAL    NOT NULL,
                    email_json  TEXT    NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_account_message
                    ON stored_emails(account_id, message_id)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_category_account
                    ON stored_emails(category, account_id)
                """)
        }
    }

    private nonisolated static func migrateLegacyInBackground(
        databasePool pool: DatabasePool,
        legacyStoreURL: URL,
        fileManager: FileManager
    ) async -> Bool {
        await Task.detached(priority: .utility) {
            Self.migrateLegacyJSONIfNeeded(
                databasePool: pool,
                legacyStoreURL: legacyStoreURL,
                fileManager: fileManager
            )
        }.value
    }

    private nonisolated static func migrateLegacyJSONIfNeeded(
        databasePool: DatabasePool,
        legacyStoreURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: legacyStoreURL.path),
              let entries = decodeLegacyStore(from: legacyStoreURL) else {
            return false
        }

        do {
            try databasePool.write { db in
                for entry in entries {
                    guard let emailData = try? emailStoreJSONEncoder.encode(entry.email),
                          let emailJSON = String(data: emailData, encoding: .utf8) else {
                        continue
                    }

                    try db.execute(
                        sql: """
                        INSERT OR IGNORE INTO stored_emails
                        (id, account_id, message_id, category, stored_at, email_json)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            entry.email.id.uuidString,
                            entry.accountID.uuidString,
                            entry.messageID,
                            entry.category,
                            entry.storedAt.timeIntervalSince1970,
                            emailJSON
                        ]
                    )
                }
            }

            try? fileManager.removeItem(at: legacyStoreURL)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func fetchStoredEmails(from databasePool: DatabasePool) throws -> [StoredEmail] {
        try databasePool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, message_id, category, stored_at, email_json
                FROM stored_emails
                ORDER BY stored_at DESC
                """
            )
            return try rows.map(storedEmail(from:))
        }
    }

    private nonisolated static func storedEmail(from row: Row) throws -> StoredEmail {
        let accountIDString: String = row["account_id"]
        let messageID: String = row["message_id"]
        let category: String = row["category"]
        let storedAt: Double = row["stored_at"]
        let emailJSON: String = row["email_json"]

        guard let accountID = UUID(uuidString: accountIDString),
              let emailData = emailJSON.data(using: .utf8) else {
            throw EmailStoreError.invalidRecord
        }

        let email = try emailStoreJSONDecoder.decode(Email.self, from: emailData)
        return StoredEmail(
            email: email,
            accountID: accountID,
            messageID: messageID,
            category: category,
            storedAt: Date(timeIntervalSince1970: storedAt)
        )
    }

    private nonisolated static func decodeLegacyStore(from url: URL) -> [StoredEmail]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? emailStoreJSONDecoder.decode([StoredEmail].self, from: data)
    }

    private static func makeSupportURL(fileManager: FileManager) -> URL {
        let supportURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailMind", isDirectory: true)
        if !fileManager.fileExists(atPath: supportURL.path) {
            try? fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        }
        return supportURL
    }
}

private enum EmailStoreError: Error {
    case invalidRecord
}
