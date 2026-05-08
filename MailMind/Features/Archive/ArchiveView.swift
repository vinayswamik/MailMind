import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var toastManager: ToastManager
    @EnvironmentObject private var emailStore: EmailStore
    @EnvironmentObject private var processedStore: ProcessedMessageStore

    @State private var pendingRemoval: ArchivedEmail?

    var body: some View {
        Group {
            if archiveStore.archivedEmails.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(archiveStore.archivedEmails) { entry in
                            ArchiveRow(
                                entry: entry,
                                onUnarchive: { unarchive(entry) },
                                onRequestRemove: { pendingRemoval = entry }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Archived (\(archiveStore.archivedEmails.count))")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Remove this email?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { entry in
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                confirmPermanentRemoval(entry)
                pendingRemoval = nil
            }
        } message: { entry in
            Text(
                "“\(entry.email.subject)” will be deleted from MailMind and unmarked for this Gmail account. After the next sync it can be categorized again. This cannot be undone."
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color("AppTeal"))

            Text("No archived emails")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Mark an email as done to move it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmPermanentRemoval(_ entry: ArchivedEmail) {
        if let record = emailStore.storedRecord(emailID: entry.email.id) {
            processedStore.unmarkProcessed(record.messageID, account: record.accountID)
        }
        emailStore.removeStoredEmail(emailID: entry.email.id)
        archiveStore.remove(id: entry.id)
        toastManager.show("Removed — this message can sync again", style: .success)
        HapticManager.success()
    }

    private func unarchive(_ entry: ArchivedEmail) {
        var didRestoreCategory = false

        if !categoryStore.categoryExists(named: entry.categoryName),
           let userCategory = entry.originatingUserCategory {
            categoryStore.restoreUserCategory(userCategory)
            didRestoreCategory = true
        }

        categoryStore.insertEmail(entry.email, at: entry.originalIndex, in: entry.categoryName)
        archiveStore.remove(id: entry.id)

        let message = didRestoreCategory
            ? "Restored \(entry.categoryName) and 1 email"
            : "Restored to \(entry.categoryName)"
        toastManager.show(message, style: .success, actionTitle: "Undo") {
            undoUnarchive(entry, didRestoreCategory: didRestoreCategory)
        }
    }

    private func undoUnarchive(_ entry: ArchivedEmail, didRestoreCategory: Bool) {
        categoryStore.dismissEmail(entry.email.id, in: entry.categoryName)

        if didRestoreCategory,
           let userCategory = entry.originatingUserCategory,
           categoryStore.emails(for: entry.categoryName).isEmpty {
            categoryStore.deleteCategory(id: userCategory.id)
        }

        archiveStore.archive(
            entry.email,
            from: entry.categoryName,
            originalIndex: entry.originalIndex,
            originatingUserCategory: entry.originatingUserCategory
        )
        HapticManager.success()
    }
}

private struct ArchiveRow: View {
    let entry: ArchivedEmail
    let onUnarchive: () -> Void
    let onRequestRemove: () -> Void

    var body: some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .revealSwipeActions(
                leading: removeAction,
                trailing: unarchiveAction,
                style: .archiveRow
            )
            .accessibilityHint("Swipe right to remove from MailMind, swipe left to unarchive.")
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(name: entry.categoryName)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.email.sender)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    Text(entry.categoryName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color("AppTeal"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color("AppTeal").opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(entry.email.subject)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(entry.email.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var removeAction: RevealSwipeAction {
        RevealSwipeAction(
            title: "Remove",
            systemImage: "trash.fill",
            tint: .red,
            haptic: .warning
        ) {
            onRequestRemove()
        }
    }

    private var unarchiveAction: RevealSwipeAction {
        RevealSwipeAction(
            title: "Unarchive",
            systemImage: "tray.and.arrow.up.fill",
            tint: Color("AppTeal")
        ) {
            onUnarchive()
        }
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
    }
    .environmentObject(ArchiveStore())
    .environmentObject(CategoryStore())
    .environmentObject(ToastManager())
    .environmentObject(EmailStore())
    .environmentObject(ProcessedMessageStore())
}
