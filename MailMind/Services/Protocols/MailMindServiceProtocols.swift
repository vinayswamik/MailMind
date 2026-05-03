import Foundation
import UIKit

// MARK: - Gmail (fetch + watch)

/// Read-only Gmail operations used by `EmailProcessingService`. Enables mocks in unit tests.
protocol GmailMailboxServing: AnyObject {
    func getProfile(accountID: UUID) async throws -> GmailProfile
    func listRecentMessageIDs(accountID: UUID, maxResults: Int) async throws -> [String]
    func listHistory(accountID: UUID, startHistoryId: String) async throws -> GmailHistoryPage
    func getMessage(accountID: UUID, messageID: String) async throws -> GmailMessageBody
    func getMessageMetadata(accountID: UUID, messageID: String) async throws -> GmailMessageMetadata
    func watchMailbox(accountID: UUID, topicName: String) async throws -> GmailWatchResponse
}

extension GmailAPIClient: GmailMailboxServing {}

// MARK: - On-device LLM

/// Classify + summarize pipeline used by `EmailProcessingService`.
protocol OnDeviceEmailIntelligence: AnyObject {
    func classify(
        email: GmailMessageBody,
        categories: [UserCategory],
        skillFiles: [UUID: String]
    ) async throws -> EmailClassification

    func summarize(
        email: GmailMessageBody,
        matchedCategoryName: String,
        matchedSkillText: String
    ) async throws -> String
}

extension OnDeviceLLMService: OnDeviceEmailIntelligence {}

// MARK: - Sync orchestration

/// Minimal sync surface for foreground loops and background runners.
@MainActor
protocol MailboxSyncPerforming: AnyObject {
    func syncAll() async throws
    func sync(accountID: UUID) async throws
}

extension EmailProcessingService: MailboxSyncPerforming {}

// MARK: - Google Sign-In

/// Presents Google account linking UI from settings and onboarding.
protocol GoogleAccountSigning: AnyObject {
    @MainActor
    func signIn(presenting viewController: UIViewController, hint: String?) async throws -> GoogleSignInResult
}

extension GoogleAuthService: GoogleAccountSigning {}
