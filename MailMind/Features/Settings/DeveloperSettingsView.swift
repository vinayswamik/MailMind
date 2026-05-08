#if DEBUG
import SwiftUI

struct DeveloperSettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var processedStore: ProcessedMessageStore
    @EnvironmentObject private var emailStore: EmailStore
    @EnvironmentObject private var processingService: EmailProcessingService
    @EnvironmentObject private var toastManager: ToastManager

    @State private var activeAction: ActiveDeveloperAction?
    @State private var selectedAccountID: UUID?

    private var selectedAccount: GmailAccount? {
        guard let selectedAccountID else {
            return nil
        }
        return accountStore.accounts.first { $0.id == selectedAccountID }
    }

    private var resetTargetAccounts: [GmailAccount] {
        if let selectedAccount {
            return [selectedAccount]
        }
        return accountStore.accounts
    }

    private var reprocessTargetAccounts: [GmailAccount] {
        resetTargetAccounts.filter { $0.connectionStatus == .connected }
    }

    private var isReprocessingSelectedTarget: Bool {
        if let selectedAccountID {
            return activeAction == .reprocess(selectedAccountID)
        }
        return activeAction == .reprocessAll
    }

    private var simulateWakeTargetAccounts: [GmailAccount] {
        resetTargetAccounts.filter { $0.connectionStatus == .connected }
    }

    private var isSimulatingSelectedTarget: Bool {
        activeAction == .simulateWake(selectedAccountID)
    }

    var body: some View {
        Form {
            Section {
                if accountStore.accounts.isEmpty {
                    Label("No accounts connected", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mailbox", selection: $selectedAccountID) {
                            Text("All Accounts")
                                .pickerEmailLine()
                                .tag(UUID?.none)

                            ForEach(accountStore.accounts) { account in
                                Text(account.emailAddress)
                                    .pickerEmailLine()
                                    .tag(UUID?.some(account.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(activeAction != nil)

                        if let selectedAccount {
                            Label(
                                selectedAccount.connectionStatus == .connected ? "Connected" : "Reconnect required",
                                systemImage: selectedAccount.connectionStatus == .connected ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(selectedAccount.connectionStatus == .connected ? Color("AppTeal") : .orange)
                        }

                        HStack(spacing: 10) {
                            DeveloperActionButton(
                                title: "Reset",
                                systemImage: "arrow.counterclockwise",
                                tint: .orange,
                                style: .outline,
                                isLoading: false
                            ) {
                                resetSyncForSelectedTarget()
                            }
                            .disabled(activeAction != nil || resetTargetAccounts.isEmpty)

                            DeveloperActionButton(
                                title: "Re-process 10",
                                systemImage: "arrow.triangle.2.circlepath",
                                tint: Color("AppTeal"),
                                style: .filled,
                                isLoading: isReprocessingSelectedTarget
                            ) {
                                Task { await reprocessRecentForSelectedTarget() }
                            }
                            .disabled(activeAction != nil || reprocessTargetAccounts.isEmpty)
                        }

                        DeveloperActionButton(
                            title: "Simulate Silent Wake",
                            systemImage: "bell.badge",
                            tint: .blue,
                            style: .outline,
                            isLoading: isSimulatingSelectedTarget
                        ) {
                            Task { await simulateSilentWakeForSelectedTarget() }
                        }
                        .disabled(activeAction != nil || simulateWakeTargetAccounts.isEmpty)

                        DeveloperActionButton(
                            title: "Register Test Device",
                            systemImage: "antenna.radiowaves.left.and.right",
                            tint: .purple,
                            style: .outline,
                            isLoading: activeAction == .registerTestDevice
                        ) {
                            Task { await registerTestDevice() }
                        }
                        .disabled(activeAction != nil || accountStore.accounts.isEmpty)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Sync Tools")
            } footer: {
                Text("Reset clears the Gmail history cursor so the next sync re-establishes a baseline. Re-process scans the 10 newest messages and only routes ones not already in the processed set (no duplicates). Simulate Silent Wake exercises the APNs wake handler with route-only payload data. Register Test Device sends a test APNs token to the backend so webhook routing can be verified without a real push certificate.")
            }

            Section("Processing Log") {
                if processingService.syncLog.isEmpty {
                    Text("No sync events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(processingService.syncLog.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: accountStore.accounts) { _, accounts in
            guard let selectedAccountID,
                  !accounts.contains(where: { $0.id == selectedAccountID }) else {
                return
            }
            self.selectedAccountID = nil
        }
    }

    private func resetSyncForSelectedTarget() {
        let accounts = resetTargetAccounts
        guard !accounts.isEmpty else { return }

        for account in accounts {
            resetSyncState(for: account)
        }

        HapticManager.warning()
        let message = selectedAccount == nil ? "Reset sync for all accounts" : "Reset sync for \(accounts[0].emailAddress)"
        toastManager.show(message, style: .success)
    }

    @MainActor
    private func reprocessRecentForSelectedTarget() async {
        let accounts = reprocessTargetAccounts
        guard !accounts.isEmpty else { return }

        activeAction = selectedAccountID.map(ActiveDeveloperAction.reprocess) ?? .reprocessAll
        defer { activeAction = nil }

        do {
            for account in accounts {
                try Task.checkCancellation()
                try await processingService.reprocessRecentMessages(accountID: account.id, limit: 10)
            }

            HapticManager.success()
            let message = selectedAccount == nil ? "Re-processed recent mail for all accounts" : "Re-processed recent mail"
            toastManager.show(message, style: .success)
        } catch {
            HapticManager.error()
            toastManager.show(error.localizedDescription, style: .error)
        }
    }

    @MainActor
    private func registerTestDevice() async {
        activeAction = .registerTestDevice
        defer { activeAction = nil }

        // Reuse the same fake token across presses so Redis entries stay consistent.
        let tokenKey = "privacyTrigger.devTestAPNsToken"
        let fakeToken: String
        if let existing = UserDefaults.standard.string(forKey: tokenKey) {
            fakeToken = existing
        } else {
            fakeToken = "DEVTEST_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(fakeToken, forKey: tokenKey)
        }

        UserDefaults.standard.set(fakeToken, forKey: "privacyTrigger.apnsDeviceToken")
        await BackgroundSyncRunner.shared.refreshBackendRegistration()

        HapticManager.success()
        toastManager.show("Test device registered with backend", style: .success)
    }

    private func resetSyncState(for account: GmailAccount) {
        processedStore.setLastHistoryId(nil, account: account.id)
    }

    @MainActor
    private func simulateSilentWakeForSelectedTarget() async {
        guard !simulateWakeTargetAccounts.isEmpty else { return }

        activeAction = .simulateWake(selectedAccountID)
        defer { activeAction = nil }

        var userInfo: [AnyHashable: Any] = [
            "wakeReason": "developer-simulated-gmail-change"
        ]

        if let selectedAccount {
            userInfo["accountRouteKey"] = selectedAccount.id.uuidString
            if let historyId = processedStore.lastHistoryId(account: selectedAccount.id) {
                userInfo["latestHistoryHint"] = historyId
            }
        }

        let result = await BackgroundSyncRunner.shared.handleRemoteNotification(userInfo)

        switch result {
        case .newData, .noData:
            HapticManager.success()
            toastManager.show("Silent wake simulated", style: .success)
        case .failed:
            HapticManager.error()
            toastManager.show("Silent wake simulation failed", style: .error)
        @unknown default:
            HapticManager.error()
            toastManager.show("Silent wake returned unknown result", style: .error)
        }
    }
}

private enum ActiveDeveloperAction: Equatable {
    case reprocess(UUID)
    case reprocessAll
    case simulateWake(UUID?)
    case registerTestDevice
}

private struct DeveloperActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let style: DeveloperActionButtonStyle
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 10)
            .background(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(DeveloperPressButtonStyle())
    }

    private var foregroundColor: Color {
        style == .filled ? .white : tint
    }

    private var backgroundColor: Color {
        style == .filled ? tint : tint.opacity(0.08)
    }

    private var borderColor: Color {
        style == .filled ? tint : tint.opacity(0.55)
    }
}

private enum DeveloperActionButtonStyle {
    case filled
    case outline
}

private struct DeveloperPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension Text {
    /// Keeps the menu picker's caption to one line so the Sync Tools buttons stay aligned.
    func pickerEmailLine() -> some View {
        lineLimit(1).truncationMode(.middle)
    }
}

#Preview {
    let emailStore = EmailStore()
    let accountStore = AccountStore()
    let categoryStore = CategoryStore()
    let processedStore = ProcessedMessageStore()
    let gmailClient = GmailAPIClient()
    let llmService = OnDeviceLLMService()
    let processingService = EmailProcessingService(
        gmailClient: gmailClient,
        llmService: llmService,
        processedStore: processedStore,
        emailStore: emailStore,
        categoryStore: categoryStore,
        accountStore: accountStore
    )

    NavigationStack {
        DeveloperSettingsView()
    }
    .environmentObject(accountStore)
    .environmentObject(categoryStore)
    .environmentObject(processedStore)
    .environmentObject(emailStore)
    .environmentObject(processingService)
    .environmentObject(ToastManager())
}
#endif
