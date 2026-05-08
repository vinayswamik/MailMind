import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

struct EmailClassification: Equatable {
    let category: String
    let confidence: Double
    let matchReason: String

    var isMatched: Bool {
        category != OnDeviceLLMService.uncategorized && !category.isEmpty
    }
}

enum OnDeviceLLMError: Error, LocalizedError {
    case modelUnavailable
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligence is not available on this device."
        case .generationFailed(let error):
            return "On-device model failed: \(error.localizedDescription)"
        }
    }
}

final class OnDeviceLLMService: ObservableObject {
    static let uncategorized = "Uncategorized"

    /// Classifications below this confidence are treated as Uncategorized to suppress
    /// false positives. Tunable from a single place if we expose it later.
    static let minimumClassificationConfidence: Double = 0.75
    static let classifyBodyCharacterLimit = 2_500
    static let summarizeBodyCharacterLimit = 6_000

    func classify(
        email: GmailMessageBody,
        categories: [UserCategory],
        skillFiles: [UUID: String]
    ) async throws -> EmailClassification {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await runClassify(email: email, categories: categories, skillFiles: skillFiles)
        }
        #endif
        throw OnDeviceLLMError.modelUnavailable
    }

    func summarize(
        email: GmailMessageBody,
        matchedCategoryName: String,
        matchedSkillText: String
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await runSummarize(
                email: email,
                matchedCategoryName: matchedCategoryName,
                matchedSkillText: matchedSkillText
            )
        }
        #endif
        throw OnDeviceLLMError.modelUnavailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func runClassify(
        email: GmailMessageBody,
        categories: [UserCategory],
        skillFiles: [UUID: String]
    ) async throws -> EmailClassification {
        guard case .available = SystemLanguageModel.default.availability else {
            throw OnDeviceLLMError.modelUnavailable
        }

        let instructions = Self.buildClassifyInstructions(categories: categories, skillFiles: skillFiles)
        let prompt = Self.buildEmailContext(
            email: email,
            includeBody: true,
            bodyCharacterLimit: Self.classifyBodyCharacterLimit
        )

        let session = await LanguageModelSessionPools.shared.session(for: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GenerableClassification.self
            )
            let value = response.content
            let resolved = Self.resolveCategory(value.category, against: categories)
            let confidence = max(0.0, min(1.0, value.confidence))

            if resolved == Self.uncategorized || confidence < Self.minimumClassificationConfidence {
                return EmailClassification(
                    category: Self.uncategorized,
                    confidence: confidence,
                    matchReason: value.matchReason
                )
            }
            return EmailClassification(
                category: resolved,
                confidence: confidence,
                matchReason: value.matchReason
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnDeviceLLMError.generationFailed(error)
        }
    }

    @available(iOS 26.0, *)
    private func runSummarize(
        email: GmailMessageBody,
        matchedCategoryName: String,
        matchedSkillText: String
    ) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw OnDeviceLLMError.modelUnavailable
        }

        let instructions = Self.buildSummaryInstructions(
            categoryName: matchedCategoryName,
            skillText: matchedSkillText
        )
        let prompt = Self.buildEmailContext(
            email: email,
            includeBody: true,
            bodyCharacterLimit: Self.summarizeBodyCharacterLimit
        )

        let session = await LanguageModelSessionPools.shared.session(for: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GenerableSummary.self
            )
            return response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnDeviceLLMError.generationFailed(error)
        }
    }
    #endif

    private static func resolveCategory(_ raw: String, against categories: [UserCategory]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.name
        }
        return uncategorized
    }

    private static func buildClassifyInstructions(categories: [UserCategory], skillFiles: [UUID: String]) -> String {
        let active = categories.filter(\.isEnabled)
        let categoryLines: [String] = active.map { category in
            var skill = category.skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fileText = skillFiles[category.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !fileText.isEmpty {
                skill += "\n  Reference notes: \(fileText.prefix(2000))"
            }
            return "- \(category.name): \(skill)"
        }

        let categoryBlock = categoryLines.isEmpty
            ? "(no user categories defined — return Uncategorized)"
            : categoryLines.joined(separator: "\n")

        return """
        You are an email triage classifier running entirely on-device. Your only job is to decide whether the email below clearly matches ONE of the user's categories.

        Categories:
        \(categoryBlock)

        Decision rules — follow them strictly:
        1. If the email clearly matches exactly one category, return that category's exact name.
        2. If you are unsure, or the email could plausibly fit none or multiple, return "\(uncategorized)".
        3. Never invent a category. Only the names listed above are valid.
        4. Confidence must reflect how unambiguous the match is:
           - 0.90–1.00: explicit, on-the-nose match (e.g. recruiter scheduling an interview for an Interview category).
           - 0.75–0.89: strong but not explicit.
           - Below 0.75: uncertain — return "\(uncategorized)" instead.
        5. matchReason must quote or paraphrase a SPECIFIC sentence or phrase from the email that justifies the match. If you cannot ground the match in the email's actual text, return "\(uncategorized)".

        Bias toward "\(uncategorized)". Missing a borderline match is preferable to a false positive.
        """
    }

    private static func buildSummaryInstructions(categoryName: String, skillText: String) -> String {
        let trimmedSkill = skillText.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillBlock = trimmedSkill.isEmpty
            ? ""
            : "\n\nWhat the user cares about for \(categoryName):\n\(trimmedSkill)"

        return """
        You are summarizing an email that has already been classified as "\(categoryName)". Produce a 2–3 sentence neutral summary focused on what the user needs to know to act: what is being asked, by when, and any concrete numbers, dates, people, or links.\(skillBlock)

        Do not invent details. Do not editorialize. Do not include greetings or sign-offs. If the email contains nothing actionable, say so plainly.
        """
    }

    private static func buildEmailContext(
        email: GmailMessageBody,
        includeBody: Bool,
        bodyCharacterLimit: Int? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("From: \(email.from)")
        if !email.senderDomain.isEmpty {
            lines.append("Sender domain: \(email.senderDomain)")
        }
        lines.append("Subject: \(email.subject)")
        lines.append("Date: \(email.dateHeader)")

        if email.attachments.isEmpty {
            lines.append("Attachments: none")
        } else {
            let formatted = email.attachments.map { attachment in
                let type = attachment.mimeType.isEmpty ? "" : " (\(attachment.mimeType))"
                return "\(attachment.name)\(type)"
            }
            lines.append("Attachments: \(formatted.joined(separator: ", "))")
        }

        if let reason = email.bulkMailReason {
            lines.append("Bulk-mail signal: \(reason)")
        }

        if includeBody {
            var body = email.plainText.isEmpty ? email.snippet : email.plainText
            if let bodyCharacterLimit, body.count > bodyCharacterLimit {
                body = String(body.prefix(bodyCharacterLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
                body += "\n\n[…truncated for on-device speed…]"
            }
            lines.append("")
            lines.append("Body:")
            lines.append(body)
        }

        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum LanguageModelSessionPools {
    static let shared = LanguageModelSessionPool()
}

@available(iOS 26.0, *)
private actor LanguageModelSessionPool {
    private var sessionsByInstructions: [String: LanguageModelSession] = [:]
    private var lruKeys: [String] = []
    private let maxSessionCount = 8

    func session(for instructions: String) -> LanguageModelSession {
        if let existing = sessionsByInstructions[instructions] {
            touch(instructions)
            return existing
        }

        let created = LanguageModelSession(instructions: instructions)
        sessionsByInstructions[instructions] = created
        lruKeys.append(instructions)
        trimIfNeeded()
        return created
    }

    private func touch(_ key: String) {
        if let index = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: index)
            lruKeys.append(key)
        }
    }

    private func trimIfNeeded() {
        while lruKeys.count > maxSessionCount {
            let oldest = lruKeys.removeFirst()
            sessionsByInstructions.removeValue(forKey: oldest)
        }
    }
}

@available(iOS 26.0, *)
@Generable
private struct GenerableClassification {
    @Guide(description: "Exact name of one of the listed categories, or 'Uncategorized' if none clearly fit")
    let category: String

    @Guide(description: "Confidence in this classification, between 0.0 and 1.0. Below 0.75 means uncertain — return Uncategorized instead.")
    let confidence: Double

    @Guide(description: "One short sentence quoting or paraphrasing concrete text from the email that justifies this classification")
    let matchReason: String
}

@available(iOS 26.0, *)
@Generable
private struct GenerableSummary {
    @Guide(description: "Two to three neutral sentences capturing what the user needs to act on: the ask, the deadline, and any concrete numbers, dates, people, or links")
    let summary: String
}
#endif
