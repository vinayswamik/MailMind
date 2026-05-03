import SwiftUI
import GoogleSignIn
import BackgroundTasks
import UIKit

@main
struct MailMindApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(MailMindAppDelegate.self) private var appDelegate

    private let backgroundSyncRunner = BackgroundSyncRunner.shared

    init() {
        backgroundSyncRunner.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
                }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                backgroundSyncRunner.schedule()
            }
        }
    }
}

final class MailMindAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        BackgroundSyncRunner.shared.updateAPNsDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            let result = await BackgroundSyncRunner.shared.handleRemoteNotification(userInfo)
            completionHandler(result)
        }
    }
}

struct PrivacyTriggerWakePayload: Codable, Equatable {
    let accountRouteKey: String?
    let latestHistoryHint: String?
    let wakeReason: String
    let receivedAt: Date

    init(userInfo: [AnyHashable: Any], receivedAt: Date = Date()) {
        self.accountRouteKey = Self.stringValue(
            userInfo,
            keys: ["accountRouteKey", "account_route_key", "routeKey", "route_key"]
        )
        self.latestHistoryHint = Self.stringValue(
            userInfo,
            keys: ["latestHistoryHint", "latest_history_hint", "historyId", "history_id"]
        )
        self.wakeReason = Self.stringValue(
            userInfo,
            keys: ["wakeReason", "wake_reason", "reason"]
        ) ?? "gmail-change"
        self.receivedAt = receivedAt
    }

    var accountID: UUID? {
        accountRouteKey.flatMap(UUID.init(uuidString:))
    }

    private static func stringValue(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            let value = userInfo[AnyHashable(key)]
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }
}

final class PrivacyTriggerBackendClient {
    static let shared = PrivacyTriggerBackendClient()

    private let session: URLSession
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    private let endpointDefaultsKey = "privacyTriggerBackendURL"
    private let endpointInfoPlistKey = "PrivacyTriggerBackendURL"
    private let deviceTokenKey = "privacyTrigger.apnsDeviceToken"
    private let lastWakePayloadKey = "privacyTrigger.lastWakePayload"
    private let lastDeviceACKKey = "privacyTrigger.lastDeviceACKAt"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func storeAPNsDeviceToken(_ token: String) {
        defaults.set(token, forKey: deviceTokenKey)
    }

    func storeWakePayload(_ payload: PrivacyTriggerWakePayload) {
        guard let data = try? encoder.encode(payload) else {
            return
        }
        defaults.set(data, forKey: lastWakePayloadKey)
    }

    func registerDevice(accounts: [(routeKey: String, emailAddress: String)]) async {
        let unique = Dictionary(accounts.map { ($0.routeKey, $0.emailAddress) }, uniquingKeysWith: { a, _ in a })
            .map { AccountEntry(routeKey: $0.key, emailAddress: $0.value) }
            .sorted { $0.routeKey < $1.routeKey }

        guard let token = defaults.string(forKey: deviceTokenKey), !token.isEmpty else {
            return
        }

        let payload = DeviceRegistrationPayload(
            apnsDeviceToken: token,
            accounts: unique,
            registeredAt: Date()
        )

        await post(payload, path: "device/register")
    }

    func acknowledgeCatchUp(accountRouteKey: String, latestHistoryHint: String?) async {
        defaults.set(Date(), forKey: lastDeviceACKKey)

        let payload = DeviceAcknowledgmentPayload(
            accountRouteKey: accountRouteKey,
            latestHistoryHint: latestHistoryHint,
            deviceAcknowledgedAt: Date()
        )

        await post(payload, path: "device/ack")
    }

    private func post<T: Encodable>(_ payload: T, path: String) async {
        guard let url = configuredBaseURL()?.appendingPathComponent(path),
              let body = try? encoder.encode(payload) else {
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        _ = try? await session.data(for: request)
    }

    private func configuredBaseURL() -> URL? {
        let raw = defaults.string(forKey: endpointDefaultsKey)
            ?? Bundle.main.object(forInfoDictionaryKey: endpointInfoPlistKey) as? String

        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return URL(string: raw)
    }

    private struct AccountEntry: Encodable {
        let routeKey: String
        let emailAddress: String
    }

    private struct DeviceRegistrationPayload: Encodable {
        let apnsDeviceToken: String
        let accounts: [AccountEntry]
        let registeredAt: Date
    }

    private struct DeviceAcknowledgmentPayload: Encodable {
        let accountRouteKey: String
        let latestHistoryHint: String?
        let deviceAcknowledgedAt: Date
    }
}

final class BackgroundSyncRunner {
    static let shared = BackgroundSyncRunner()

    private let identifier = "com.mailmind.refresh"
    private let privacyBackendClient = PrivacyTriggerBackendClient.shared

    @MainActor private lazy var processingService: EmailProcessingService = {
        let emailStore = EmailStore()
        let processedStore = ProcessedMessageStore()
        let gmailClient = GmailAPIClient()
        let llmService = OnDeviceLLMService()
        let accountStore = AccountStore()
        let categoryStore = CategoryStore()
        return EmailProcessingService(
            gmailClient: gmailClient,
            llmService: llmService,
            processedStore: processedStore,
            emailStore: emailStore,
            categoryStore: categoryStore,
            accountStore: accountStore
        )
    }()

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handle(task)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort scheduling; foreground polling remains the primary path.
        }
    }

    func updateAPNsDeviceToken(_ deviceToken: Data) {
        privacyBackendClient.storeAPNsDeviceToken(Self.hexString(from: deviceToken))

        Task { @MainActor [weak self] in
            await self?.refreshBackendRegistration()
        }
    }

    @MainActor
    func refreshBackendRegistration() async {
        let accounts = AccountStore()
            .accounts
            .filter { $0.connectionStatus == .connected }
            .map { (routeKey: $0.id.uuidString, emailAddress: $0.emailAddress) }

        await privacyBackendClient.registerDevice(accounts: accounts)
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let payload = PrivacyTriggerWakePayload(userInfo: userInfo)
        privacyBackendClient.storeWakePayload(payload)
        schedule()

        do {
            try await syncWithBudget(accountID: payload.accountID)
            return .newData
        } catch is CancellationError {
            return .failed
        } catch {
            return .failed
        }
    }

    private func handle(_ task: BGTask) {
        schedule()

        let syncTask = Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }

            do {
                try await syncWithBudget()
                task.setTaskCompleted(success: true)
            } catch is CancellationError {
                task.setTaskCompleted(success: false)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    private func syncWithBudget(accountID: UUID? = nil) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                if let accountID {
                    try await processingService.sync(accountID: accountID)
                } else {
                    try await processingService.syncAll()
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(25))
                throw CancellationError()
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private static func hexString(from data: Data) -> String {
        data.map { String(format: "%02.2hhx", $0) }.joined()
    }
}
