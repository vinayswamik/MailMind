import Foundation
import Combine

struct ArchivedEmail: Identifiable, Equatable, Codable {
    let id: UUID
    let email: Email
    let categoryName: String
    let originalIndex: Int
    let originatingUserCategory: UserCategory?
    let archivedAt: Date
}

final class ArchiveStore: ObservableObject {
    @Published private(set) var archivedEmails: [ArchivedEmail] = []

    private let defaults: UserDefaults
    private let persistenceKey = "mailmind.archivedEmails.v1"

    var archivedEmailIDs: Set<UUID> {
        Set(archivedEmails.map(\.id))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([ArchivedEmail].self, from: data) {
            self.archivedEmails = decoded
        } else {
            self.archivedEmails = []
        }
    }

    func archive(
        _ email: Email,
        from categoryName: String,
        originalIndex: Int,
        originatingUserCategory: UserCategory? = nil
    ) {
        let entry = ArchivedEmail(
            id: email.id,
            email: email,
            categoryName: categoryName,
            originalIndex: originalIndex,
            originatingUserCategory: originatingUserCategory,
            archivedAt: Date()
        )
        archivedEmails.insert(entry, at: 0)
        persist()
    }

    func remove(id: UUID) {
        archivedEmails.removeAll { $0.id == id }
        persist()
    }

    func removeAll(forDestinationAccountEmail accountEmail: String) {
        let normalized = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        archivedEmails.removeAll {
            $0.email.destinationAccount.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(normalized) == .orderedSame
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(archivedEmails) else {
            return
        }
        defaults.set(data, forKey: persistenceKey)
    }
}
