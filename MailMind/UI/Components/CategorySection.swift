import SwiftUI

struct CategorySection: View {
    let title: String
    let emails: [Email]
    @Binding var isEnabled: Bool
    let showsLock: Bool
    let isLoading: Bool
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onDeleteBlocked: (() -> Void)?
    let onEmailReadStateChange: (Email.ID, Bool) -> Void
    let onSwipeEmailReadStateChange: (Email, Bool, Bool) -> Void
    let onArchiveEmail: (Email) -> Void
    let onSelectEmail: (Email) -> Void

    @State private var isExpanded = false

    private var visibleEmails: [Email] {
        isExpanded ? emails : []
    }

    private var canDelete: Bool {
        onDelete != nil && emails.isEmpty
    }

    init(
        title: String,
        emails: [Email],
        isEnabled: Binding<Bool>,
        showsLock: Bool,
        isLoading: Bool = false,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onDeleteBlocked: (() -> Void)? = nil,
        onEmailReadStateChange: @escaping (Email.ID, Bool) -> Void = { _, _ in },
        onSwipeEmailReadStateChange: @escaping (Email, Bool, Bool) -> Void = { _, _, _ in },
        onArchiveEmail: @escaping (Email) -> Void = { _ in },
        onSelectEmail: @escaping (Email) -> Void = { _ in }
    ) {
        self.title = title
        self.emails = emails
        _isEnabled = isEnabled
        self.showsLock = showsLock
        self.isLoading = isLoading
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onDeleteBlocked = onDeleteBlocked
        self.onEmailReadStateChange = onEmailReadStateChange
        self.onSwipeEmailReadStateChange = onSwipeEmailReadStateChange
        self.onArchiveEmail = onArchiveEmail
        self.onSelectEmail = onSelectEmail
    }

    var body: some View {
        cardContent
            .opacity(isEnabled ? 1 : 0.55)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(name: title)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if showsLock {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }

                            Text("\(emails.count) \(emails.count == 1 ? "email" : "emails")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit Category", systemImage: "pencil")
                        }
                    }

                    if onDelete != nil {
                        Button(role: .destructive) {
                            if canDelete {
                                onDelete?()
                            } else {
                                onDeleteBlocked?()
                            }
                        } label: {
                            Label("Delete Category", systemImage: "trash")
                        }
                    }
                }

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            .padding()

            VStack(spacing: 0) {
                if isLoading {
                    Divider()
                        .padding(.leading)

                    ShimmerView(rowCount: 3)
                } else if emails.isEmpty {
                    Divider()
                        .padding(.leading)

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("No emails here yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                } else {
                    ForEach(visibleEmails) { email in
                        Divider()
                            .padding(.leading)

                        EmailRow(
                            email: email,
                            onReadStateChange: { isUnread in
                                onEmailReadStateChange(email.id, isUnread)
                            },
                            onSwipeReadStateChange: { previousValue, newValue in
                                onSwipeEmailReadStateChange(email, previousValue, newValue)
                            },
                            onArchive: {
                                onArchiveEmail(email)
                            },
                            onTap: {
                                onSelectEmail(email)
                            }
                        )
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    CategorySection(
        title: MockData.categories[0].name,
        emails: MockData.categories[0].emails,
        isEnabled: .constant(true),
        showsLock: true
    )
        .padding()
}
