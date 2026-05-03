import UIKit

enum HapticManager {
    static func success() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
