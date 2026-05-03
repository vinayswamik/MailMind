import SwiftUI

struct ToastView: View {
    let toast: ToastMessage
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(foregroundColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let actionTitle = toast.actionTitle {
                Button(actionTitle) {
                    onAction()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(actionColor)
                .buttonStyle(.plain)
            }
        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 62)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var backgroundColor: Color {
        switch toast.style {
        case .success:
            Color(.secondarySystemBackground).opacity(0.98)
        case .warning:
            Color(.secondarySystemBackground).opacity(0.98)
        case .error:
            Color.red.opacity(0.92)
        }
    }

    private var foregroundColor: Color {
        toast.style == .error ? .white : .primary
    }

    private var actionColor: Color {
        toast.style == .error ? .white : Color("AppTeal")
    }
}
