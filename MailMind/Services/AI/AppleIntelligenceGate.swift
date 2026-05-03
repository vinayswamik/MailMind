import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceStatus: Equatable {
    case available
    case osTooOld
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case other(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

@MainActor
final class AppleIntelligenceGate: ObservableObject {
    @Published private(set) var status: AppleIntelligenceStatus = .other("checking…")
    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleForeground() {
        Task { @MainActor in self.refresh() }
    }

    func refresh() {
        status = Self.currentStatus()
    }

    func refreshRepeatedly() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            refresh()
            guard case .modelNotReady = status else {
                return
            }

            let delays: [UInt64] = [
                10_000_000_000,
                30_000_000_000
            ]

            for delay in delays {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: delay)
                refresh()
                if status.isAvailable || status != .modelNotReady {
                    return
                }
            }
        }
    }

    private static func currentStatus() -> AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .notEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .other(String(describing: reason))
                }
            }
        }
        #endif
        return .osTooOld
    }
}
