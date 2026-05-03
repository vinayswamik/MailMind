import SwiftUI
import UIKit

struct OnboardingView: View {
    let onCompleted: (_ didConnect: Bool) -> Void

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var toastManager: ToastManager
    @State private var pageIndex = 0
    @State private var isConnecting = false

    private let authService: any GoogleAccountSigning

    init(onCompleted: @escaping (_ didConnect: Bool) -> Void, authService: any GoogleAccountSigning = GoogleAuthService()) {
        self.onCompleted = onCompleted
        self.authService = authService
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $pageIndex) {
                VStack(spacing: 18) {
                    LaunchMarkLogo(height: 80)

                    Text("Welcome to MailMind")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Your inbox, intelligently sorted")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .tag(0)

                onboardingPage(
                    symbolName: "person.crop.circle.badge.plus",
                    title: "Connect your Gmail accounts",
                    subtitle: "Add the inboxes you want MailMind to categorize on your device."
                )
                .tag(1)

                VStack(spacing: 22) {
                    onboardingPageContent(
                        symbolName: "sparkles",
                        title: "On-device sorting",
                        subtitle: "MailMind uses Apple Intelligence on your device to categorize mail—no AI API keys or cloud models."
                    )

                    Button {
                        Task { await connectGmailTapped() }
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Get Started")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AppTeal"))
                    .disabled(isConnecting)
                }
                .padding(32)
                .tag(2)
            }
            .tabViewStyle(.page)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if pageIndex < 2 {
                        Button("Skip") {
                            onCompleted(false)
                        }
                    }
                }
            }
        }
    }

    private func onboardingPage(symbolName: String, title: String, subtitle: String) -> some View {
        onboardingPageContent(symbolName: symbolName, title: title, subtitle: subtitle)
            .padding(32)
    }

    private func onboardingPageContent(symbolName: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbolName)
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(Color("AppTeal"))

            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func connectGmailTapped() async {
        guard !isConnecting else { return }
        guard let presenter = topViewController() else {
            toastManager.show("Couldn't open Google sign-in", style: .error)
            onCompleted(false)
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            let result = try await authService.signIn(presenting: presenter, hint: nil)
            switch accountStore.connectGoogleAccount(email: result.email, tokens: result.tokens) {
            case .added, .reconnected:
                HapticManager.success()
                toastManager.show("Account connected", style: .success)
                onCompleted(true)
            case .failed:
                HapticManager.error()
                toastManager.show("Couldn't save credentials. Try again.", style: .error)
            }
        } catch GoogleAuthError.userCancelled {
            onCompleted(false)
        } catch {
            HapticManager.error()
            toastManager.show(error.localizedDescription, style: .error)
            onCompleted(false)
        }
    }

    @MainActor
    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

#Preview {
    OnboardingView(onCompleted: { _ in })
        .environmentObject(AccountStore())
        .environmentObject(ToastManager())
}
