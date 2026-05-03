import Foundation
import Combine
import GoogleSignIn

// READ-ONLY: scope is gmail.readonly. Do not add mutating endpoints.
// Allowed: users.getProfile, users.history.list, users.messages.list, users.messages.get, users.watch
// Forbidden: users.messages.modify/trash/send, users.labels.*, users.drafts.*

struct GmailWatchResponse: Decodable {
    let historyId: String
    let expiration: String

    var expirationDate: Date? {
        Double(expiration).map { Date(timeIntervalSince1970: $0 / 1000.0) }
    }
}

struct GmailProfile: Decodable {
    let emailAddress: String
    let historyId: String
    let messagesTotal: Int?
    let threadsTotal: Int?
}

struct GmailHistoryPage {
    let messageIDs: [String]
    let latestHistoryId: String?
}

struct GmailMessageMetadata: Decodable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: Payload?

    struct Payload: Decodable {
        let headers: [Header]?
    }

    struct Header: Decodable, Equatable {
        let name: String
        let value: String
    }

    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var from: String { header("From") ?? "" }
    var subject: String { header("Subject") ?? "" }
    var dateHeader: String { header("Date") ?? "" }

    var bulkMailReason: String? {
        if let value = header("List-Unsubscribe"), !value.isEmpty {
            return "List-Unsubscribe header present"
        }
        if let value = header("Precedence"), ["bulk", "list", "junk"].contains(value.lowercased()) {
            return "Precedence: \(value)"
        }
        if let value = header("Auto-Submitted"), value.lowercased() != "no" {
            return "Auto-Submitted: \(value)"
        }
        return nil
    }
}

struct GmailMessageBody {
    let id: String
    let threadId: String?
    let labelIds: [String]
    let snippet: String
    let internalDate: Date?
    let from: String
    let subject: String
    let dateHeader: String
    let plainText: String
    let attachments: [EmailAttachment]
    let listUnsubscribe: String?
    let precedence: String?
    let autoSubmitted: String?

    var senderDomain: String {
        let trimmed = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed.firstIndex(of: ">"),
           start < end {
            address = String(trimmed[trimmed.index(after: start)..<end])
        } else {
            address = trimmed
        }
        return address.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
    }

    var bulkMailReason: String? {
        if listUnsubscribe?.isEmpty == false {
            return "List-Unsubscribe header present"
        }
        if let precedence, ["bulk", "list", "junk"].contains(precedence.lowercased()) {
            return "Precedence: \(precedence)"
        }
        if let autoSubmitted, autoSubmitted.lowercased() != "no" {
            return "Auto-Submitted: \(autoSubmitted)"
        }
        return nil
    }

    var isBulkMail: Bool { bulkMailReason != nil }

    static func extract(from raw: GmailFullMessage) -> GmailMessageBody {
        let headers = raw.payload?.headers ?? []
        let lookup: (String) -> String? = { name in
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        let from = lookup("From") ?? ""
        let subject = lookup("Subject") ?? ""
        let dateHeader = lookup("Date") ?? ""
        let listUnsubscribe = lookup("List-Unsubscribe")
        let precedence = lookup("Precedence")
        let autoSubmitted = lookup("Auto-Submitted")

        let internalDate: Date? = raw.internalDate.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0 / 1000.0) }

        let bodyText = Self.preferredText(from: raw.payload)
        let truncated = Self.truncate(bodyText)
        let attachments = Self.collectAttachments(from: raw.payload)

        return GmailMessageBody(
            id: raw.id,
            threadId: raw.threadId,
            labelIds: raw.labelIds ?? [],
            snippet: raw.snippet ?? "",
            internalDate: internalDate,
            from: from,
            subject: subject,
            dateHeader: dateHeader,
            plainText: truncated,
            attachments: attachments,
            listUnsubscribe: listUnsubscribe,
            precedence: precedence,
            autoSubmitted: autoSubmitted
        )
    }

    private static func collectAttachments(from payload: GmailPayload?) -> [EmailAttachment] {
        guard let payload else { return [] }
        var collected: [EmailAttachment] = []
        var seenNames = Set<String>()
        walk(payload, into: &collected, seen: &seenNames)
        return collected
    }

    private static func walk(_ payload: GmailPayload, into collected: inout [EmailAttachment], seen: inout Set<String>) {
        if let filename = payload.filename, !filename.isEmpty, seen.insert(filename).inserted {
            collected.append(EmailAttachment(name: filename, mimeType: payload.mimeType ?? ""))
        }
        for part in payload.parts ?? [] {
            walk(part, into: &collected, seen: &seen)
        }
    }

    private static func preferredText(from payload: GmailPayload?) -> String {
        guard let payload else { return "" }
        if let plain = firstPart(payload, mimeType: "text/plain") {
            return plain
        }
        if let html = firstPart(payload, mimeType: "text/html") {
            return stripHTML(html)
        }
        if let data = payload.body?.data, let decoded = decodeBase64URL(data) {
            return decoded
        }
        return ""
    }

    private static func firstPart(_ payload: GmailPayload, mimeType: String) -> String? {
        if payload.mimeType?.lowercased() == mimeType,
           let data = payload.body?.data,
           let decoded = decodeBase64URL(data) {
            return decoded
        }
        for part in payload.parts ?? [] {
            if let found = firstPart(part, mimeType: mimeType) {
                return found
            }
        }
        return nil
    }

    private static func decodeBase64URL(_ string: String) -> String? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stripHTML(_ html: String) -> String {
        var s = html
        if let regex = try? NSRegularExpression(pattern: "<style[^>]*>[\\s\\S]*?</style>", options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        if let regex = try? NSRegularExpression(pattern: "<script[^>]*>[\\s\\S]*?</script>", options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String) -> String {
        let head = 4 * 1024
        let tail = 1 * 1024
        let bytes = text.utf8.count
        guard bytes > head + tail else { return text }
        let prefix = String(text.prefix(head))
        let suffix = String(text.suffix(tail))
        return "\(prefix)\n\n[…truncated…]\n\n\(suffix)"
    }
}

struct GmailFullMessage: Decodable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: GmailPayload?
}

struct GmailPayload: Decodable {
    let mimeType: String?
    let filename: String?
    let headers: [GmailMessageMetadata.Header]?
    let body: GmailBody?
    let parts: [GmailPayload]?
}

struct GmailBody: Decodable {
    let size: Int?
    let data: String?
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum GmailAPIError: Error, LocalizedError {
    case missingTokens
    case needsReauth
    case historyExpired
    case http(status: Int, body: String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingTokens:
            return "No Gmail tokens stored for this account."
        case .needsReauth:
            return "Sign in again to refresh Gmail access."
        case .historyExpired:
            return "Gmail history cursor expired (>7 days old). Resetting to current."
        case .http(let status, let body):
            return "Gmail API HTTP \(status): \(body)"
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

final class GmailAPIClient: ObservableObject {
    private let session: URLSession
    private let tokenStore: GmailTokenStore
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    init(session: URLSession = .shared, tokenStore: GmailTokenStore = GmailTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func getProfile(accountID: UUID) async throws -> GmailProfile {
        let url = baseURL.appendingPathComponent("users/me/profile")
        return try await get(url, accountID: accountID)
    }

    func listRecentMessageIDs(accountID: UUID, maxResults: Int) async throws -> [String] {
        var messageIDs: [String] = []
        var pageToken: String? = nil
        let requestedCount = max(1, maxResults)

        repeat {
            let remaining = requestedCount - messageIDs.count
            var components = URLComponents(url: baseURL.appendingPathComponent("users/me/messages"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "maxResults", value: String(min(500, remaining))),
                URLQueryItem(name: "includeSpamTrash", value: "false")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            let response: MessageListResponse = try await get(components.url!, accountID: accountID)
            messageIDs.append(contentsOf: response.messages?.map(\.id) ?? [])
            pageToken = messageIDs.count < requestedCount ? response.nextPageToken : nil
        } while pageToken != nil

        return messageIDs
    }

    func listHistory(accountID: UUID, startHistoryId: String) async throws -> GmailHistoryPage {
        var messageIDs: [String] = []
        var seen = Set<String>()
        var pageToken: String? = nil
        var latestHistoryId: String? = nil

        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("users/me/history"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "startHistoryId", value: startHistoryId),
                URLQueryItem(name: "historyTypes", value: "messageAdded")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            let response: HistoryListResponse
            do {
                response = try await get(components.url!, accountID: accountID)
            } catch GmailAPIError.http(let status, _) where status == 404 {
                throw GmailAPIError.historyExpired
            }

            if latestHistoryId == nil {
                latestHistoryId = response.historyId
            }

            for entry in response.history ?? [] {
                for added in entry.messagesAdded ?? [] {
                    let id = added.message.id
                    if seen.insert(id).inserted {
                        messageIDs.append(id)
                    }
                }
            }

            pageToken = response.nextPageToken
        } while pageToken != nil

        return GmailHistoryPage(messageIDs: messageIDs, latestHistoryId: latestHistoryId)
    }

    func getMessage(accountID: UUID, messageID: String) async throws -> GmailMessageBody {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/messages/\(messageID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let raw: GmailFullMessage = try await get(components.url!, accountID: accountID)
        let body = GmailMessageBody.extract(from: raw)
        return body
    }

    // Subscribes this Gmail account to push notifications via Google Cloud Pub/Sub.
    // Gmail delivers a notification to topicName whenever a new message arrives in INBOX.
    // The watch expires after 7 days — call this every ~6 days to keep it active.
    func watchMailbox(accountID: UUID, topicName: String) async throws -> GmailWatchResponse {
        let url = baseURL.appendingPathComponent("users/me/watch")
        let body: [String: Any] = ["topicName": topicName, "labelIds": ["INBOX"]]
        return try await post(url, body: body, accountID: accountID)
    }

    func getMessageMetadata(accountID: UUID, messageID: String) async throws -> GmailMessageMetadata {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/messages/\(messageID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
            URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe"),
            URLQueryItem(name: "metadataHeaders", value: "Precedence"),
            URLQueryItem(name: "metadataHeaders", value: "Auto-Submitted")
        ]
        return try await get(components.url!, accountID: accountID)
    }

    private struct HistoryListResponse: Decodable {
        let history: [HistoryEntry]?
        let nextPageToken: String?
        let historyId: String?
    }

    private struct MessageListResponse: Decodable {
        let messages: [MessageRef]?
        let nextPageToken: String?
        let resultSizeEstimate: Int?
    }

    private struct HistoryEntry: Decodable {
        let id: String
        let messagesAdded: [MessageAdded]?
    }

    private struct MessageAdded: Decodable {
        let message: MessageRef
    }

    private struct MessageRef: Decodable {
        let id: String
        let threadId: String?
    }

    private func post<T: Decodable>(_ url: URL, body: [String: Any], accountID: UUID) async throws -> T {
        let token = try await accessToken(for: accountID, forceRefresh: false)
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GmailAPIError.decoding(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw GmailAPIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GmailAPIError.http(status: status, body: String(data: data, encoding: .utf8) ?? "<binary>")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GmailAPIError.decoding(error)
        }
    }

    private func get<T: Decodable>(_ url: URL, accountID: UUID) async throws -> T {
        let data = try await performGET(url, accountID: accountID)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GmailAPIError.decoding(error)
        }
    }

    private func performGET(_ url: URL, accountID: UUID) async throws -> Data {
        let token = try await accessToken(for: accountID, forceRefresh: false)
        let (data, response, status) = try await sendGET(url, bearer: token)

        if status == 401 {
            let retried = try await accessToken(for: accountID, forceRefresh: true)
            let (retryData, retryResponse, retryStatus) = try await sendGET(url, bearer: retried)
            try assertOK(status: retryStatus, response: retryResponse, body: retryData)
            return retryData
        }

        try assertOK(status: status, response: response, body: data)
        return data
    }

    private func sendGET(_ url: URL, bearer: String) async throws -> (Data, URLResponse, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, response, status)
        } catch {
            if (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw GmailAPIError.transport(error)
        }
    }

    private func assertOK(status: Int, response: URLResponse, body: Data) throws {
        guard (200..<300).contains(status) else {
            let bodyString = String(data: body, encoding: .utf8) ?? "<binary>"
            throw GmailAPIError.http(status: status, body: bodyString)
        }
    }

    private func accessToken(for accountID: UUID, forceRefresh: Bool) async throws -> String {
        guard let tokens = tokenStore.load(for: accountID) else {
            throw GmailAPIError.missingTokens
        }

        let isExpired = tokens.accessTokenExpiresAt.timeIntervalSinceNow < 60
        if !forceRefresh && !isExpired {
            return tokens.accessToken
        }

        let refreshed = try await refreshTokens(for: accountID, current: tokens)
        tokenStore.save(refreshed, for: accountID)
        return refreshed.accessToken
    }

    @MainActor
    private func refreshTokens(for accountID: UUID, current: GmailTokens) async throws -> GmailTokens {
        if let user = GIDSignIn.sharedInstance.currentUser,
           user.profile?.email.lowercased() == current.email.lowercased() {
            do {
                let refreshed = try await user.refreshTokensIfNeeded()
                return GmailTokens(
                    accessToken: refreshed.accessToken.tokenString,
                    refreshToken: refreshed.refreshToken.tokenString,
                    accessTokenExpiresAt: refreshed.accessToken.expirationDate ?? Date().addingTimeInterval(3300),
                    scope: current.scope,
                    email: current.email
                )
            } catch {
                // Fall back to the stored OAuth refresh token before requiring a new sign-in.
            }
        }

        return try await refreshStoredTokens(current)
    }

    private func refreshStoredTokens(_ current: GmailTokens) async throws -> GmailTokens {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            throw GmailAPIError.needsReauth
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: current.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw GmailAPIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            do {
                let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
                return GmailTokens(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken ?? current.refreshToken,
                    accessTokenExpiresAt: Date().addingTimeInterval(tokenResponse.expiresIn),
                    scope: tokenResponse.scope ?? current.scope,
                    email: current.email
                )
            } catch {
                throw GmailAPIError.decoding(error)
            }
        }

        if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
           errorResponse.error == "invalid_grant" {
            throw GmailAPIError.needsReauth
        }

        let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
        throw GmailAPIError.http(status: status, body: bodyString)
    }
}
