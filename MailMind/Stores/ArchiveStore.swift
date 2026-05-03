import Foundation
import Combine

struct ArchivedEmail: Identifiable, Equatable {
    let id: UUID
    let email: Email
    let categoryName: String
    let originalIndex: Int
    let originatingUserCategory: UserCategory?
    let archivedAt: Date
}

final class ArchiveStore: ObservableObject {
    @Published private(set) var archivedEmails: [ArchivedEmail] = []

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
    }

    func remove(id: UUID) {
        archivedEmails.removeAll { $0.id == id }
    }
}
