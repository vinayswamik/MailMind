import Foundation
import UserNotifications

private actor AccountSyncLocks {
    private var lockedAccounts: Set<UUID> = []
    private var waitersByAccount: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ accountID: UUID) async {
        if !lockedAccounts.contains(accountID) {
            lockedAccounts.insert(accountID)
            return
        }

        await withCheckedContinuation { continuation in
            waitersByAccount[accountID, default: []].append(continuation)
        }
    }

    func release(_ accountID: UUID) {
        if var waiters = waitersByAccount[accountID], !waiters.isEmpty {
            let next = waiters.removeFirst()
            waitersByAccount[accountID] = waiters.isEmpty ? nil : waiters
            next.resume()
        } else {
            lockedAccounts.remove(accountID)
        }
    }
}

enum EmailProcessingError: Error, LocalizedError {
    case accountNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .accountNotFound(let accountID):
            return "No connected Gmail account found for \(accountID.uuidString)."
        }
    }
}

private enum MessageFailureDisposition {
    case permanentSkip(reason: String)
    case retryLater(reason: String)
    case pauseAccount(reason: String)
}

enum LocalNotificationDeliveryResult {
    case delivered
    case permissionDenied
    case failed(Error)
}

final class LocalNotificationService {
    private let center: UNUserNotificationCenter
    private let presentationDelegate = LocalNotificationPresentationDelegate()

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        self.center.delegate = presentationDelegate
    }

    func deliverCategorizedEmailNotification(
        email: Email,
        category: String,
        accountEmail: String,
        messageID: String
    ) async -> LocalNotificationDeliveryResult {
        let isAuthorized = await ensureAuthorization()
        guard isAuthorized else {
            return .permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = "New \(category) email"
        content.subtitle = email.sender
        content.body = Self.body(subject: email.subject, preview: email.preview)
        content.sound = .default
        content.threadIdentifier = category
        content.userInfo = [
            "source": "MailMind",
            "category": category,
            "emailID": email.id.uuidString,
            "messageID": messageID,
            "account": accountEmail
        ]

        let identifier = "MailMind.categorized.\(accountEmail).\(messageID)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
            return .delivered
        } catch {
            return .failed(error)
        }
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private static func body(subject: String, preview: String) -> String {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)

        let body: String
        if trimmedPreview.isEmpty {
            body = trimmedSubject.isEmpty ? "Open MailMind to review it." : trimmedSubject
        } else if trimmedSubject.isEmpty || trimmedSubject == "(No subject)" {
            body = trimmedPreview
        } else {
            body = "\(trimmedSubject): \(trimmedPreview)"
        }

        let limit = 220
        guard body.count > limit else {
            return body
        }
        return String(body.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private final class LocalNotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor
final class EmailProcessingService: ObservableObject {
    @Published private(set) var syncLog: [String] = []

    private let gmailClient: any GmailMailboxServing
    private let llmService: any OnDeviceEmailIntelligence
    private let processedStore: ProcessedMessageStore
    private let emailStore: EmailStore
    private let categoryStore: CategoryStore
    private let accountStore: AccountStore
    private let notificationService: LocalNotificationService
    private let privacyBackendClient: PrivacyTriggerBackendClient
    private let locks = AccountSyncLocks()
    private let historyExpirationCatchUpLimit = 1000
    private let marketingCategoryLabels: Set<String> = [
        "CATEGORY_SOCIAL",
        "CATEGORY_PROMOTIONS",
        "CATEGORY_UPDATES"
    ]

    init(
        gmailClient: any GmailMailboxServing,
        llmService: any OnDeviceEmailIntelligence,
        processedStore: ProcessedMessageStore,
        emailStore: EmailStore,
        categoryStore: CategoryStore,
        accountStore: AccountStore,
        notificationService: LocalNotificationService = LocalNotificationService(),
        privacyBackendClient: PrivacyTriggerBackendClient = .shared
    ) {
        self.gmailClient = gmailClient
        self.llmService = llmService
        self.processedStore = processedStore
        self.emailStore = emailStore
        self.categoryStore = categoryStore
        self.accountStore = accountStore
        self.notificationService = notificationService
        self.privacyBackendClient = privacyBackendClient
    }

    func syncAll() async throws {
        let accounts = accountStore.accounts
            .filter { $0.connectionStatus == .connected && $0.includeInCategorization }

        for account in accounts {
            try Task.checkCancellation()
            try await sync(accountID: account.id)
        }
    }

    func sync(accountID: UUID) async throws {
        await locks.acquire(accountID)

        do {
            try await performSync(accountID: accountID)
            await acknowledgeCatchUp(accountID: accountID)
            await renewWatchIfNeeded(accountID: accountID)
            await locks.release(accountID)
        } catch is CancellationError {
            await locks.release(accountID)
            throw CancellationError()
        } catch {
            updateCredentialStatusIfNeeded(error, accountID: accountID)
            appendLog("Sync failed for \(accountEmail(accountID)): \(error.localizedDescription)")
            await locks.release(accountID)
            throw error
        }
    }

    func reprocessRecentMessages(accountID: UUID, limit: Int = 10) async throws {
        await locks.acquire(accountID)

        do {
            let messageIDs = try await gmailClient.listRecentMessageIDs(accountID: accountID, maxResults: limit)
            let account = try account(for: accountID)

            let inserted = try await processMessages(messageIDs, account: account, force: true)

            appendLog("Re-processed \(inserted) of \(messageIDs.count) recent message(s) for \(account.emailAddress).")
            await locks.release(accountID)
        } catch is CancellationError {
            await locks.release(accountID)
            throw CancellationError()
        } catch {
            updateCredentialStatusIfNeeded(error, accountID: accountID)
            appendLog("Re-process failed for \(accountEmail(accountID)): \(error.localizedDescription)")
            await locks.release(accountID)
            throw error
        }
    }

    private func performSync(accountID: UUID) async throws {
        let account = try account(for: accountID)
        let resumedMatches = try await drainPendingQueue(for: account)

        guard let lastHistoryId = processedStore.lastHistoryId(account: accountID) else {
            try await establishCurrentHistoryBaseline(for: account)
            if resumedMatches > 0 {
                appendLog("Synced \(account.emailAddress): routed \(resumedMatches) pending match(es).")
            }
            return
        }

        let historyPage: GmailHistoryPage
        do {
            historyPage = try await gmailClient.listHistory(accountID: accountID, startHistoryId: lastHistoryId)
        } catch GmailAPIError.historyExpired {
            try await recoverFromExpiredHistory(account: account)
            return
        } catch GmailAPIError.http(let status, _) where status == 404 {
            try await recoverFromExpiredHistory(account: account)
            return
        }

        let queued = processedStore.enqueuePending(historyPage.messageIDs, account: accountID)

        if let latestHistoryId = historyPage.latestHistoryId {
            processedStore.setLastHistoryId(latestHistoryId, account: accountID)
        }

        let inserted = try await drainPendingQueue(for: account)
        let totalInserted = resumedMatches + inserted

        if queued > 0 || totalInserted > 0 {
            appendLog("Synced \(account.emailAddress): queued \(queued) message(s), routed \(totalInserted) match(es).")
        }
    }

    private func recoverFromExpiredHistory(account: GmailAccount) async throws {
        appendLog("History cursor expired for \(account.emailAddress). Catching up from recent mail before resetting.")

        let inserted: Int
        do {
            inserted = try await catchUpFromRecentMail(account: account)
        } catch GmailAPIError.http(let status, _) where status == 404 {
            appendLog("Recent Gmail catch-up was unavailable for \(account.emailAddress). Resetting sync cursor automatically.")
            try await establishCurrentHistoryBaseline(for: account)
            return
        }

        try await establishCurrentHistoryBaseline(for: account)
        appendLog("Recovered sync for \(account.emailAddress): routed \(inserted) recent message(s).")
    }

    private func establishCurrentHistoryBaseline(for account: GmailAccount) async throws {
        let profile = try await gmailClient.getProfile(accountID: account.id)
        processedStore.setLastHistoryId(profile.historyId, account: account.id)
    }

    private func catchUpFromRecentMail(account: GmailAccount) async throws -> Int {
        let messageIDs = try await gmailClient.listRecentMessageIDs(
            accountID: account.id,
            maxResults: historyExpirationCatchUpLimit
        )
        let queued = processedStore.enqueuePending(messageIDs, account: account.id)
        let inserted = try await drainPendingQueue(for: account)
        appendLog("Catch-up scanned \(messageIDs.count) recent message(s) for \(account.emailAddress), queued \(queued), routed \(inserted) match(es).")
        return inserted
    }

    private func drainPendingQueue(for account: GmailAccount) async throws -> Int {
        let pendingIDs = processedStore.pendingMessageIDs(account: account.id)
        guard !pendingIDs.isEmpty else {
            return 0
        }

        return try await processMessages(
            pendingIDs,
            account: account,
            force: false,
            removePendingWhenTerminal: true
        )
    }

    private func processMessages(
        _ messageIDs: [String],
        account: GmailAccount,
        force: Bool,
        removePendingWhenTerminal: Bool = false
    ) async throws -> Int {
        var inserted = 0
        for messageID in messageIDs {
            try Task.checkCancellation()
            do {
                if try await processMessage(id: messageID, account: account, force: force) {
                    inserted += 1
                }
                if removePendingWhenTerminal {
                    processedStore.removePending(messageID, account: account.id)
                }
            } catch GmailAPIError.http(let status, _) where status == 404 {
                processedStore.markProcessed(messageID, account: account.id)
                if removePendingWhenTerminal {
                    processedStore.removePending(messageID, account: account.id)
                }
                appendLog("Skipped unavailable Gmail message for \(account.emailAddress).")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                switch disposition(forMessageError: error) {
                case .permanentSkip(let reason):
                    processedStore.markProcessed(messageID, account: account.id)
                    if removePendingWhenTerminal {
                        processedStore.removePending(messageID, account: account.id)
                    }
                    appendLog("Skipped Gmail message for \(account.emailAddress): \(reason).")
                case .retryLater(let reason):
                    appendLog("Deferred Gmail message for \(account.emailAddress): \(reason).")
                    continue
                case .pauseAccount(let reason):
                    appendLog("Paused sync for \(account.emailAddress): \(reason).")
                    throw error
                }
            }
        }
        return inserted
    }

    private func disposition(forMessageError error: Error) -> MessageFailureDisposition {
        if let gmailError = error as? GmailAPIError {
            switch gmailError {
            case .http(let status, _) where status == 404:
                return .permanentSkip(reason: "message no longer available")
            case .decoding:
                return .permanentSkip(reason: "malformed Gmail response")
            case .transport:
                return .pauseAccount(reason: "network failure")
            case .http(let status, _) where status == 429:
                return .pauseAccount(reason: "Gmail rate limit")
            case .http(let status, _) where status >= 500:
                return .pauseAccount(reason: "temporary Gmail server error")
            case .missingTokens, .needsReauth:
                return .pauseAccount(reason: "Gmail account needs reconnect")
            case .historyExpired:
                return .pauseAccount(reason: "Gmail history cursor expired")
            case .http:
                return .pauseAccount(reason: "Gmail request failed")
            }
        }

        if let llmError = error as? OnDeviceLLMError {
            switch llmError {
            case .modelUnavailable:
                return .pauseAccount(reason: "on-device model unavailable")
            case .generationFailed:
                return .retryLater(reason: "on-device model generation failed")
            }
        }

        return .retryLater(reason: error.localizedDescription)
    }

    @discardableResult
    private func processMessage(id messageID: String, account: GmailAccount, force: Bool) async throws -> Bool {
        if !force && processedStore.isProcessed(messageID, account: account.id) {
            return false
        }

        let metadata = try await gmailClient.getMessageMetadata(accountID: account.id, messageID: messageID)

        // Pre-LLM cheap filters — these never need the model.
        let labels = Set(metadata.labelIds ?? [])
        if !labels.isDisjoint(with: marketingCategoryLabels) {
            processedStore.markProcessed(messageID, account: account.id)
            return false
        }
        if metadata.bulkMailReason != nil {
            processedStore.markProcessed(messageID, account: account.id)
            return false
        }

        if force, let removed = emailStore.remove(accountID: account.id, messageID: messageID) {
            categoryStore.dismissEmail(removed.email.id, in: removed.category)
        }

        let message = try await gmailClient.getMessage(accountID: account.id, messageID: messageID)

        // Belt-and-suspenders: the full payload may surface bulk headers the metadata fetch missed.
        if message.isBulkMail {
            processedStore.markProcessed(messageID, account: account.id)
            return false
        }

        let userCats = categoryStore.userCategories.filter(\.isEnabled)
        let presetCats = categoryStore.presetCategories
            .filter(\.isEnabled)
            .map { preset in
                UserCategory(name: preset.name, skillDescription: preset.skillDescription)
            }
        let categories = presetCats + userCats

        guard !categories.isEmpty else {
            processedStore.markProcessed(messageID, account: account.id)
            return false
        }

        let skillFiles = loadSkillFiles(for: userCats)

        // Pass 1 — classify. If the model is unsure, drop the email entirely.
        let classification = try await llmService.classify(
            email: message,
            categories: categories,
            skillFiles: skillFiles
        )
        guard classification.isMatched else {
            let confidenceText = String(format: "%.2f", classification.confidence)
            appendLog("Skipped \"\(message.subject)\" — Uncategorized (conf \(confidenceText)).")
            processedStore.markProcessed(messageID, account: account.id)
            return false
        }

        // Pass 2 — summarize, only on matched emails.
        let matchedCategory = categories.first { $0.name.caseInsensitiveCompare(classification.category) == .orderedSame }
        let matchedSkillText = matchedCategory.flatMap { cat -> String? in
            let inline = cat.skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.isEmpty { return inline }
            return skillFiles[cat.id]
        } ?? ""

        let summary = try await llmService.summarize(
            email: message,
            matchedCategoryName: classification.category,
            matchedSkillText: matchedSkillText
        )

        let email = Email(
            sender: Self.senderName(from: message.from),
            senderEmail: Self.senderEmail(from: message.from),
            subject: message.subject.isEmpty ? "(No subject)" : message.subject,
            preview: summary,
            receivedAt: Self.formatReceivedAt(message.internalDate),
            receivedAtUnix: message.internalDate?.timeIntervalSince1970,
            destinationAccount: account.emailAddress,
            isUnread: true,
            summarizedBody: summary,
            attachments: message.attachments,
            gmailThreadID: message.threadId
        )

        emailStore.insert(email, accountID: account.id, messageID: messageID, category: classification.category)
        categoryStore.insertEmail(email, at: 0, in: classification.category)
        processedStore.markProcessed(messageID, account: account.id)
        await deliverNotification(email: email, category: classification.category, account: account, messageID: messageID)
        let confidenceText = String(format: "%.2f", classification.confidence)
        appendLog("Routed \"\(message.subject)\" → \(classification.category) (conf \(confidenceText)).")
        return true
    }

    private func deliverNotification(
        email: Email,
        category: String,
        account: GmailAccount,
        messageID: String
    ) async {
        let result = await notificationService.deliverCategorizedEmailNotification(
            email: email,
            category: category,
            accountEmail: account.emailAddress,
            messageID: messageID
        )

        if case .failed(let error) = result {
            appendLog("Local notification failed for \(account.emailAddress): \(error.localizedDescription)")
        }
    }

    private func renewWatchIfNeeded(accountID: UUID) async {
        guard let topicName = pubSubTopicName() else { return }

        let expiry = processedStore.watchExpiry(account: accountID)
        let renewalThreshold: TimeInterval = 24 * 60 * 60
        guard expiry == nil || expiry!.timeIntervalSinceNow < renewalThreshold else { return }

        guard let account = accountStore.accounts.first(where: {
            $0.id == accountID && $0.connectionStatus == .connected
        }) else { return }

        do {
            let response = try await gmailClient.watchMailbox(accountID: accountID, topicName: topicName)
            if let expiryDate = response.expirationDate {
                processedStore.setWatchExpiry(expiryDate, account: accountID)
                appendLog("Gmail watch renewed for \(account.emailAddress).")
            }
        } catch {
            appendLog("Gmail watch renewal failed for \(account.emailAddress): \(error.localizedDescription)")
        }
    }

    private func pubSubTopicName() -> String? {
        if let override = UserDefaults.standard.string(forKey: "gmailPubSubTopicName"), !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: "GmailPubSubTopicName") as? String
    }

    private func acknowledgeCatchUp(accountID: UUID) async {
        await privacyBackendClient.acknowledgeCatchUp(
            accountRouteKey: accountID.uuidString,
            latestHistoryHint: processedStore.lastHistoryId(account: accountID)
        )
    }

    private func account(for accountID: UUID) throws -> GmailAccount {
        guard let account = accountStore.accounts.first(where: { $0.id == accountID && $0.connectionStatus == .connected }) else {
            throw EmailProcessingError.accountNotFound(accountID)
        }
        return account
    }

    private func accountEmail(_ accountID: UUID) -> String {
        accountStore.accounts.first(where: { $0.id == accountID })?.emailAddress ?? accountID.uuidString
    }

    private func updateCredentialStatusIfNeeded(_ error: Error, accountID: UUID) {
        guard let gmailError = error as? GmailAPIError else {
            return
        }

        switch gmailError {
        case .missingTokens, .needsReauth:
            accountStore.markReconnectRequired(for: accountID)
        case .historyExpired, .http, .transport, .decoding:
            break
        }
    }

    private func loadSkillFiles(for categories: [UserCategory]) -> [UUID: String] {
        var skillFiles: [UUID: String] = [:]
        for category in categories {
            if let text = try? categoryStore.loadSkillFileText(for: category) {
                skillFiles[category.id] = text
            }
        }
        return skillFiles
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logFormatter.string(from: Date())
        syncLog.insert("[\(timestamp)] \(message)", at: 0)
        if syncLog.count > 100 {
            syncLog.removeLast(syncLog.count - 100)
        }
    }

    private static func senderName(from fromHeader: String) -> String {
        let trimmed = fromHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "<") {
            let name = trimmed[..<range.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty {
                return String(name)
            }
        }
        return senderEmail(from: trimmed).components(separatedBy: "@").first ?? trimmed
    }

    private static func senderEmail(from fromHeader: String) -> String {
        let trimmed = fromHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed.firstIndex(of: ">"),
           start < end {
            return String(trimmed[trimmed.index(after: start)..<end])
        }
        return trimmed
    }

    private static func formatReceivedAt(_ date: Date?) -> String {
        guard let date else {
            return ""
        }
        return receivedAtFormatter.string(from: date)
    }

    private static let receivedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}
