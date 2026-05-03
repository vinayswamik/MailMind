import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var toastManager: ToastManager

    @State private var pendingAccountRemoval: GmailAccount?
    @State private var isShowingPrivacyPolicy = false
    @State private var isAddingAccount = false

    private let authService: any GoogleAccountSigning

    init(authService: any GoogleAccountSigning = GoogleAuthService()) {
        self.authService = authService
    }

    private let privacyPolicyURL = URL(string: "https://example.com/mailmind/privacy")!

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        Form {
            Section("Email Accounts") {
                if accountStore.accounts.isEmpty {
                    Label("No accounts added yet", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountStore.accounts) { account in
                        accountRow(for: account)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingAccountRemoval = account
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                    }
                }

                Button {
                    Task { await addAccountTapped() }
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                }
                .disabled(isAddingAccount)
            }

            Section("Skills") {
                ForEach(categoryStore.presetCategories) { preset in
                    NavigationLink {
                        SkillDetailView(target: .preset(preset.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preset.name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            let trimmed = preset.skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                Text(trimmed)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                ForEach(categoryStore.userCategories) { category in
                    NavigationLink {
                        SkillDetailView(target: .user(category.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            if let attachedFileName = category.attachedFileName, !attachedFileName.isEmpty {
                                Label(attachedFileName, systemImage: "paperclip")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            let trimmed = category.skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                Text(trimmed)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section {
                Text(versionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink("About MailMind") {
                    AboutView()
                }

#if DEBUG
                NavigationLink("Developer Settings") {
                    DeveloperSettingsView()
                }
#endif

                Button("Privacy Policy") {
                    isShowingPrivacyPolicy = true
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            SettingsSafariView(url: privacyPolicyURL)
        }
        .alert(
            "Remove account?",
            isPresented: Binding(
                get: { pendingAccountRemoval != nil },
                set: { if !$0 { pendingAccountRemoval = nil } }
            ),
            presenting: pendingAccountRemoval
        ) { account in
            Button("Cancel", role: .cancel) {
                pendingAccountRemoval = nil
            }
            Button("Remove", role: .destructive) {
                accountStore.deleteAccount(id: account.id)
                HapticManager.warning()
                pendingAccountRemoval = nil
            }
        } message: { account in
            Text("Remove \(account.emailAddress)? This will stop emails from this account being categorized.")
        }
    }

    @ViewBuilder
    private func accountRow(for account: GmailAccount) -> some View {
        if account.isCredentialMissing {
            HStack(spacing: 8) {
                Text(account.emailAddress)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Reconnect") {
                    Task { await reconnectAccountTapped(account) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color("AppTeal"))
                .disabled(isAddingAccount)
            }
        } else {
            Toggle(
                isOn: Binding(
                    get: { account.includeInCategorization },
                    set: { accountStore.setIncludeInCategorization($0, for: account.id) }
                )
            ) {
                Text(account.emailAddress)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @MainActor
    private func addAccountTapped() async {
        guard !isAddingAccount else { return }
        guard let presenter = topViewController() else {
            toastManager.show("Couldn't open Google sign-in", style: .error)
            return
        }

        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let result = try await authService.signIn(presenting: presenter, hint: nil)
            switch accountStore.connectGoogleAccount(email: result.email, tokens: result.tokens) {
            case .added:
                HapticManager.success()
                toastManager.show("Account connected", style: .success)
            case .reconnected:
                HapticManager.success()
                toastManager.show("\(result.email) reconnected", style: .success)
            case .failed:
                HapticManager.error()
                toastManager.show("Couldn't save credentials. Try again.", style: .error)
            }
        } catch GoogleAuthError.userCancelled {
            // Silent — cancellation is not an error.
        } catch {
            HapticManager.error()
            toastManager.show(error.localizedDescription, style: .error)
        }
    }

    @MainActor
    private func reconnectAccountTapped(_ account: GmailAccount) async {
        guard !isAddingAccount else { return }
        guard let presenter = topViewController() else {
            toastManager.show("Couldn't open Google sign-in", style: .error)
            return
        }

        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let result = try await authService.signIn(presenting: presenter, hint: account.emailAddress)

            guard result.email == account.emailAddress else {
                HapticManager.error()
                toastManager.show("Picked a different account. Use Add Account instead.", style: .error)
                return
            }

            switch accountStore.connectGoogleAccount(email: result.email, tokens: result.tokens) {
            case .added, .reconnected:
                HapticManager.success()
                toastManager.show("\(account.emailAddress) reconnected", style: .success)
            case .failed:
                HapticManager.error()
                toastManager.show("Couldn't save credentials. Try again.", style: .error)
            }
        } catch GoogleAuthError.userCancelled {
            // Silent.
        } catch {
            HapticManager.error()
            toastManager.show(error.localizedDescription, style: .error)
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
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AccountStore())
    .environmentObject(CategoryStore())
    .environmentObject(ToastManager())
}
