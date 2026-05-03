import Foundation
import Combine

enum ToastStyle: Equatable {
    case success
    case warning
    case error
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
    let actionTitle: String?
    let action: (() -> Void)?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ToastManager: ObservableObject {
    @Published var currentToast: ToastMessage?

    func show(
        _ text: String,
        style: ToastStyle,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        let toast = ToastMessage(
            text: text,
            style: style,
            actionTitle: actionTitle,
            action: action
        )
        currentToast = toast

        Task {
            try? await Task.sleep(nanoseconds: action == nil ? 2_500_000_000 : 4_000_000_000)

            if currentToast == toast {
                currentToast = nil
            }
        }
    }

    func performAction(for toast: ToastMessage) {
        guard currentToast == toast else {
            return
        }

        currentToast = nil
        toast.action?()
    }
}
