import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var emailStore: EmailStore
    @StateObject private var processedStore: ProcessedMessageStore
    @StateObject private var gmailClient: GmailAPIClient
    @StateObject private var llmService: OnDeviceLLMService
    @StateObject private var networkService: GmailNetworkService
    @StateObject private var processingService: EmailProcessingService
    @StateObject private var syncCoordinator: GmailSyncCoordinator
    @StateObject private var accountStore: AccountStore
    @StateObject private var categoryStore: CategoryStore
    @StateObject private var toastManager: ToastManager
    @StateObject private var archiveStore: ArchiveStore
    @StateObject private var aiGate: AppleIntelligenceGate
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var selectedTab = AppTab.home

    init() {
        let emailStore = EmailStore()
        let processedStore = ProcessedMessageStore()
        let gmailClient = GmailAPIClient()
        let llmService = OnDeviceLLMService()
        let accountStore = AccountStore()
        let categoryStore = CategoryStore()
        let networkService = GmailNetworkService(emailStore: emailStore, accountStore: accountStore)
        let processingService = EmailProcessingService(
            gmailClient: gmailClient,
            llmService: llmService,
            processedStore: processedStore,
            emailStore: emailStore,
            categoryStore: categoryStore,
            accountStore: accountStore
        )
        let syncCoordinator = GmailSyncCoordinator(processingService: processingService)

        accountStore.checkCredentialStatus()
        processedStore.warmUp(accounts: accountStore.accounts.map(\.id))
        Self.refreshCategoryEmails(
            emailStore: emailStore,
            accountStore: accountStore,
            categoryStore: categoryStore
        )

        _emailStore = StateObject(wrappedValue: emailStore)
        _processedStore = StateObject(wrappedValue: processedStore)
        _gmailClient = StateObject(wrappedValue: gmailClient)
        _llmService = StateObject(wrappedValue: llmService)
        _networkService = StateObject(wrappedValue: networkService)
        _processingService = StateObject(wrappedValue: processingService)
        _syncCoordinator = StateObject(wrappedValue: syncCoordinator)
        _accountStore = StateObject(wrappedValue: accountStore)
        _categoryStore = StateObject(wrappedValue: categoryStore)
        _toastManager = StateObject(wrappedValue: ToastManager())
        _archiveStore = StateObject(wrappedValue: ArchiveStore())
        _aiGate = StateObject(wrappedValue: AppleIntelligenceGate())
    }

    var body: some View {
        Group {
            if aiGate.status.isAvailable {
                appContent
            } else {
                AppleIntelligenceUnavailableView(status: aiGate.status) {
                    aiGate.refreshRepeatedly()
                }
            }
        }
        .environmentObject(aiGate)
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                aiGate.refresh()
            }
        }
        .task {
            refreshCategoryEmails()
        }
    }

    private var appContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "tray.2.fill")
            }
            .badge(categoryStore.unreadCount > 0 ? String(categoryStore.unreadCount) : nil)
            .tag(AppTab.home)

            NavigationStack {
                ArchiveView()
            }
            .tabItem {
                Label("Archived", systemImage: "archivebox.fill")
            }
            .tag(AppTab.archive)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .environmentObject(networkService)
        .environmentObject(emailStore)
        .environmentObject(processedStore)
        .environmentObject(gmailClient)
        .environmentObject(llmService)
        .environmentObject(processingService)
        .environmentObject(syncCoordinator)
        .environmentObject(accountStore)
        .environmentObject(categoryStore)
        .environmentObject(toastManager)
        .environmentObject(archiveStore)
        .tint(Color("AppTeal"))
        .overlay(alignment: .bottom) {
            if let toast = toastManager.currentToast {
                ToastView(toast: toast) {
                    toastManager.performAction(for: toast)
                }
                    .zIndex(1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: toast)
            }
        }
        .fullScreenCover(isPresented: onboardingIsPresented) {
            OnboardingView(
                onCompleted: { didConnect in
                    hasOnboarded = true
                    selectedTab = didConnect ? .home : .settings
                }
            )
            .environmentObject(accountStore)
            .environmentObject(toastManager)
        }
        .onAppear {
            syncCoordinator.updateScenePhase(scenePhase)
            Task {
                await BackgroundSyncRunner.shared.refreshBackendRegistration()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            syncCoordinator.updateScenePhase(newValue)
        }
        .onChange(of: accountStore.accounts) { oldAccounts, newAccounts in
            let removedIDs = Set(oldAccounts.map(\.id)).subtracting(newAccounts.map(\.id))
            for id in removedIDs {
                emailStore.purge(accountID: id)
            }
            refreshCategoryEmails()
            Task {
                await BackgroundSyncRunner.shared.refreshBackendRegistration()
            }
        }
        .onReceive(emailStore.$stored) { _ in
            refreshCategoryEmails()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            accountStore.checkCredentialStatus()
        }
    }

    private func refreshCategoryEmails() {
        Self.refreshCategoryEmails(
            emailStore: emailStore,
            accountStore: accountStore,
            categoryStore: categoryStore
        )
    }

    private static func refreshCategoryEmails(
        emailStore: EmailStore,
        accountStore: AccountStore,
        categoryStore: CategoryStore
    ) {
        let accountIDs = accountStore.accounts
            .filter { $0.connectionStatus == .connected && $0.includeInCategorization }
            .map(\.id)
        for name in categoryStore.presetCategories.map(\.name) + categoryStore.userCategories.map(\.name) {
            categoryStore.setEmails(emailStore.emails(forCategory: name, accountIDs: accountIDs), for: name)
        }
    }

    private var onboardingIsPresented: Binding<Bool> {
        Binding(
            get: { !hasOnboarded },
            set: { isPresented in
                if !isPresented {
                    hasOnboarded = true
                }
            }
        )
    }
}

private enum AppTab: Hashable {
    case home
    case archive
    case settings
}

private struct AppleIntelligenceUnavailableView: View {
    let status: AppleIntelligenceStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color("AppTeal"))

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let cta {
                Button(cta.label, action: cta.action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AppTeal"))
            }

            Button("Re-check", action: onRetry)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var title: String {
        switch status {
        case .available: return "Ready"
        case .osTooOld: return "iOS 26 or later required"
        case .deviceNotEligible: return "This device doesn't support Apple Intelligence"
        case .notEnabled: return "Turn on Apple Intelligence"
        case .modelNotReady: return "Apple Intelligence is downloading"
        case .other: return "Apple Intelligence unavailable"
        }
    }

    private var detail: String {
        switch status {
        case .available:
            return ""
        case .osTooOld:
            return "MailMind categorizes mail entirely on-device using Apple Foundation Models. Update to iOS 26 to use the app."
        case .deviceNotEligible:
            return "Apple Intelligence requires an iPhone 15 Pro or newer, or an iPad with M-series chip. MailMind doesn't run on this device."
        case .notEnabled:
            return "Open Settings → Apple Intelligence & Siri and turn it on, then come back."
        case .modelNotReady:
            return "Apple Intelligence is on, but the local model is not ready yet. Keep the phone on Wi-Fi and power, then tap Re-check."
        case .other(let message):
            return message
        }
    }

    private var cta: (label: String, action: () -> Void)? {
        switch status {
        case .notEnabled:
            return (
                label: "Open Settings",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
        default:
            return nil
        }
    }
}

#Preview {
    ContentView()
}
