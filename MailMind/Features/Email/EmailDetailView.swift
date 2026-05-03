import SwiftUI
import UIKit

struct EmailDetailView: View {
    let email: Email

    @Environment(\.dismiss) private var dismiss

    private var receivedTimestampText: String {
        if let unix = email.receivedAtUnix {
            return Self.detailReceivedAtFormatter.string(from: Date(timeIntervalSince1970: unix))
        }
        return email.receivedAt
    }

    private static let detailReceivedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    senderHeader

                    subjectBlock

                    summaryCard

                    if !email.attachments.isEmpty {
                        attachmentsSection
                    }

                    gmailFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                closeButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var senderHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(email.sender)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(email.senderEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(receivedTimestampText)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            Spacer()
        }
    }

    private var subjectBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(email.subject)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.caption2)
                Text(email.destinationAccount)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color("AppTeal"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color("AppTeal").opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color("AppTeal"))

                Text("Summary")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text(email.summarizedBody)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Attachments")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            VStack(spacing: 8) {
                ForEach(email.attachments, id: \.name) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    private func attachmentRow(_ attachment: EmailAttachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: attachment))
                .font(.title3)
                .foregroundStyle(Color("AppTeal"))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(typeLabel(for: attachment))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var gmailFooter: some View {
        if gmailWebLink != nil {
            Button {
                openFullEmail()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                    Text("For the full email, open in Gmail")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
        } else {
            Text("For the full email, open in Gmail")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    private func openFullEmail() {
        guard let webLink = gmailWebLink else { return }
        guard let appLink = gmailAppLink else {
            UIApplication.shared.open(webLink, options: [:], completionHandler: nil)
            return
        }

        UIApplication.shared.open(appLink, options: [:]) { success in
            guard !success else { return }
            UIApplication.shared.open(webLink, options: [:], completionHandler: nil)
        }
    }

    private var gmailAppLink: URL? {
        guard let threadID = encodedGmailThreadID else { return nil }
        return URL(string: "googlegmail:///cv=\(threadID)")
    }

    private var gmailWebLink: URL? {
        guard let threadID = trimmedGmailThreadID else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "mail.google.com"
        components.path = "/mail/"
        components.queryItems = [
            URLQueryItem(name: "authuser", value: email.destinationAccount)
        ]
        components.fragment = "all/\(threadID)"
        return components.url
    }

    private var trimmedGmailThreadID: String? {
        guard let threadID = email.gmailThreadID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !threadID.isEmpty else {
            return nil
        }
        return threadID
    }

    private var encodedGmailThreadID: String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmedGmailThreadID?.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Close")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    private var avatar: some View {
        Text(senderInitial)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(avatarColor)
            .clipShape(Circle())
    }

    private var senderInitial: String {
        email.sender.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }

    private var avatarColor: Color {
        let colors: [Color] = [.indigo, .purple, .pink, .orange, .green, .blue, .teal]
        let hash = email.sender.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[hash % colors.count]
    }

    private func iconName(for attachment: EmailAttachment) -> String {
        let mime = attachment.mimeType.lowercased()
        if mime.hasPrefix("image/") { return "photo.fill" }
        if mime == "application/pdf" { return "doc.richtext.fill" }
        if mime.contains("spreadsheet") || mime.hasSuffix("/csv") { return "tablecells.fill" }
        if mime.contains("wordprocessing") || mime == "application/msword" { return "doc.text.fill" }
        if mime.contains("zip") { return "doc.zipper" }

        let ext = (attachment.name as NSString).pathExtension.lowercased()
        switch ext {
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo.fill"
        case "pdf": return "doc.richtext.fill"
        case "zip": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    private func typeLabel(for attachment: EmailAttachment) -> String {
        let ext = (attachment.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty { return ext }
        if !attachment.mimeType.isEmpty { return attachment.mimeType }
        return "FILE"
    }
}

#Preview {
    EmailDetailView(email: MockData.categories[0].emails[0])
}
