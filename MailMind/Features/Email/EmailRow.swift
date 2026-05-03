import SwiftUI

struct EmailRow: View {
    let email: Email
    let onReadStateChange: (Bool) -> Void
    let onSwipeReadStateChange: ((Bool, Bool) -> Void)?
    let onArchive: () -> Void
    let onTap: () -> Void
    @State private var isUnread: Bool

    init(
        email: Email,
        onReadStateChange: @escaping (Bool) -> Void = { _ in },
        onSwipeReadStateChange: ((Bool, Bool) -> Void)? = nil,
        onArchive: @escaping () -> Void = {},
        onTap: @escaping () -> Void = {}
    ) {
        self.email = email
        self.onReadStateChange = onReadStateChange
        self.onSwipeReadStateChange = onSwipeReadStateChange
        self.onArchive = onArchive
        self.onTap = onTap
        _isUnread = State(initialValue: email.isUnread)
    }

    var body: some View {
        rowContent
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color(.secondarySystemGroupedBackground))
            .onTapGesture {
                if isUnread {
                    isUnread = false
                    onReadStateChange(false)
                }
                onTap()
            }
            .revealSwipeActions(
                leading: markReadAction,
                trailing: archiveAction,
                style: .emailRow
            )
            .accessibilityLabel("\(email.sender), \(email.subject)")
            .accessibilityHint("Opens email details. Swipe left to archive, right to toggle read.")
            .onChange(of: email.isUnread) { _, newValue in
                isUnread = newValue
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isUnread ? Color("AppTeal") : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 15)

            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(email.sender)
                        .font(.subheadline)
                        .fontWeight(isUnread ? .bold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(email.receivedAt)
                        .font(.caption)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .foregroundStyle(isUnread ? .primary : .secondary)
                        .lineLimit(1)
                }

                Text(email.subject)
                    .font(.subheadline)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(email.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var markReadAction: RevealSwipeAction {
        RevealSwipeAction(
            title: isUnread ? "Read" : "Unread",
            systemImage: isUnread ? "envelope.open" : "envelope",
            tint: Color("AppTeal")
        ) {
            let previousValue = isUnread
            isUnread.toggle()
            if let onSwipeReadStateChange {
                onSwipeReadStateChange(previousValue, isUnread)
            } else {
                onReadStateChange(isUnread)
            }
        }
    }

    private var archiveAction: RevealSwipeAction {
        RevealSwipeAction(
            title: "Archive",
            systemImage: "archivebox.fill",
            tint: .gray
        ) {
            onArchive()
        }
    }

    private var avatar: some View {
        Text(senderInitial)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(avatarColor)
            .clipShape(Circle())
    }

    private var senderInitial: String {
        email.sender.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            .indigo,
            .purple,
            .pink,
            .orange,
            .green,
            .blue,
            .teal
        ]

        return colors[Self.stableHash(email.sender) % colors.count]
    }

    private static func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult &+ Int(scalar.value)
        }
    }

}

#Preview {
    EmailRow(email: MockData.categories[0].emails[0])
        .padding()
}
