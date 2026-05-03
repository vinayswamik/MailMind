import Foundation
import SwiftUI

@MainActor
final class GmailSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false

    private let processingService: any MailboxSyncPerforming
    private var activeLoopTask: Task<Void, Never>?

    init(processingService: any MailboxSyncPerforming) {
        self.processingService = processingService
    }

    func updateScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            startActiveLoop()
        case .inactive, .background:
            stopActiveLoop()
        @unknown default:
            stopActiveLoop()
        }
    }

    func syncNow() async {
        await runSync()
    }

    private func startActiveLoop() {
        guard activeLoopTask == nil else {
            return
        }

        activeLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                await self?.runSync()
            }
        }
    }

    private func stopActiveLoop() {
        activeLoopTask?.cancel()
        activeLoopTask = nil
    }

    private func runSync() async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await processingService.syncAll()
        } catch is CancellationError {
        } catch {
            // The processing service keeps the user-visible debug log.
        }
    }
}
