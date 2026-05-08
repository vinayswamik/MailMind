import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var networkService: GmailNetworkService
    @EnvironmentObject private var syncCoordinator: GmailSyncCoordinator
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var emailStore: EmailStore
    @EnvironmentObject private var toastManager: ToastManager
    @EnvironmentObject private var archiveStore: ArchiveStore

    @State private var isShowingAddCategory = false
    @State private var editingCategory: UserCategory?
    @State private var pendingDeleteCategory: UserCategory?
    @State private var loadErrorMessage: String?
    @State private var hasLoadedEmails = false
    @State private var hasSynced = false
    @State private var isRefreshing = false
    @State private var selectedEmail: SelectedEmail?

    private struct SelectedEmail: Identifiable {
        let email: Email
        let categoryName: String
        var id: UUID { email.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isRefreshing {
                    loadingBanner
                }

                if let loadErrorMessage {
                    errorBanner(loadErrorMessage)
                }

                if categoryStore.totalCategoryCount == 0 {
                    emptyState
                } else {
                    categoryGroupTitle("Default")

                    ForEach(categoryStore.presetCategories) { category in
                        CategorySection(
                            title: category.name,
                            emails: categoryStore.emails(for: category.name),
                            isEnabled: Binding(
                                get: { categoryStore.isPresetEnabled(category.id) },
                                set: { categoryStore.setPresetEnabled($0, for: category.id) }
                            ),
                            showsLock: true,
                            isLoading: isRefreshing,
                            onEmailReadStateChange: { emailID, isUnread in
                                categoryStore.markEmail(emailID, in: category.name, isUnread: isUnread)
                            },
                            onSwipeEmailReadStateChange: { email, previousValue, newValue in
                                markEmailFromSwipe(
                                    email,
                                    in: category.name,
                                    previousValue: previousValue,
                                    newValue: newValue
                                )
                            },
                            onArchiveEmail: { email in
                                archiveEmail(email, from: category.name)
                            },
                            onSelectEmail: { email in
                                selectedEmail = SelectedEmail(email: email, categoryName: category.name)
                            }
                        )
                    }

                    categoryGroupTitle("My Categories")

                    ForEach(categoryStore.userCategories) { category in
                        CategorySection(
                            title: category.name,
                            emails: categoryStore.emails(for: category.name),
                            isEnabled: Binding(
                                get: { categoryStore.isUserCategoryEnabled(category.id) },
                                set: { categoryStore.setUserCategoryEnabled($0, for: category.id) }
                            ),
                            showsLock: false,
                            isLoading: isRefreshing,
                            onEdit: {
                                editingCategory = category
                                isShowingAddCategory = true
                            },
                            onDelete: {
                                pendingDeleteCategory = category
                            },
                            onDeleteBlocked: {
                                toastManager.show("Archive or remove all emails before deleting.", style: .error)
                            },
                            onEmailReadStateChange: { emailID, isUnread in
                                categoryStore.markEmail(emailID, in: category.name, isUnread: isUnread)
                            },
                            onSwipeEmailReadStateChange: { email, previousValue, newValue in
                                markEmailFromSwipe(
                                    email,
                                    in: category.name,
                                    previousValue: previousValue,
                                    newValue: newValue
                                )
                            },
                            onArchiveEmail: { email in
                                archiveEmail(email, from: category.name)
                            },
                            onSelectEmail: { email in
                                selectedEmail = SelectedEmail(email: email, categoryName: category.name)
                            }
                        )
                    }

                }
            }
            .padding()
        }
        .refreshable {
            isRefreshing = true
            await syncCoordinator.syncNow()
            loadEmails()
            isRefreshing = false
        }
        .navigationTitle("Mails")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                LaunchMarkLogo(size: 40)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingCategory = nil
                    isShowingAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Category")
            }
        }
        .sheet(isPresented: $isShowingAddCategory) {
            AddCategorySheet(categoryStore: categoryStore, editingCategory: editingCategory)
        }
        .sheet(item: $selectedEmail) { selection in
            EmailDetailView(email: selection.email)
        }
        .alert(
            "Delete category?",
            isPresented: Binding(
                get: { pendingDeleteCategory != nil },
                set: { if !$0 { pendingDeleteCategory = nil } }
            ),
            presenting: pendingDeleteCategory
        ) { category in
            Button("Cancel", role: .cancel) {
                pendingDeleteCategory = nil
            }
            Button("Delete", role: .destructive) {
                categoryStore.deleteCategory(id: category.id)
                HapticManager.warning()
                pendingDeleteCategory = nil
            }
        } message: { category in
            Text("Delete \(category.name)? All associated skill data will be removed.")
        }
        .task {
            loadEmailsIfNeeded()
            guard !hasSynced else { return }
            hasSynced = true
            await syncCoordinator.syncNow()
            loadEmails()
        }
    }

    private func categoryGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color("AppTeal"))

            Text("No categories yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Tap + to add your first category")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Add Category") {
                editingCategory = nil
                isShowingAddCategory = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AppTeal"))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .multilineTextAlignment(.center)
    }

    private var loadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()

            Text("Loading emails")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadEmailsIfNeeded() {
        guard !hasLoadedEmails else { return }
        let allNames = categoryStore.presetCategories.map(\.name) + categoryStore.userCategories.map(\.name)
        if allNames.contains(where: { !categoryStore.emails(for: $0).isEmpty }) {
            hasLoadedEmails = true
            return
        }
        loadEmails()
    }

    private func loadEmails() {
        hasLoadedEmails = true
        loadErrorMessage = nil
        let accountIDs = accountStore.accounts
            .filter { $0.connectionStatus == .connected && $0.includeInCategorization }
            .map(\.id)
        let archivedIDs = archiveStore.archivedEmailIDs
        for name in categoryStore.presetCategories.map(\.name) + categoryStore.userCategories.map(\.name) {
            let emails = emailStore
                .emails(forCategory: name, accountIDs: accountIDs)
                .filter { !archivedIDs.contains($0.id) }
            categoryStore.setEmails(emails, for: name)
        }
    }

    private func archiveEmail(_ email: Email, from categoryName: String) {
        let index = categoryStore.indexOfEmail(email.id, in: categoryName) ?? 0
        let userCategory = categoryStore.userCategories.first { $0.name == categoryName }
        archiveStore.archive(
            email,
            from: categoryName,
            originalIndex: index,
            originatingUserCategory: userCategory
        )
        categoryStore.dismissEmail(email.id, in: categoryName)
        toastManager.show("Email archived", style: .success, actionTitle: "Undo") {
            undoArchiveEmail(email, categoryName: categoryName, index: index, userCategory: userCategory)
        }
    }

    private func undoArchiveEmail(
        _ email: Email,
        categoryName: String,
        index: Int,
        userCategory: UserCategory?
    ) {
        if !categoryStore.categoryExists(named: categoryName), let userCategory {
            categoryStore.restoreUserCategory(userCategory)
        }

        archiveStore.remove(id: email.id)
        categoryStore.insertEmail(email, at: index, in: categoryName)
        HapticManager.success()
    }

    private func markEmailFromSwipe(
        _ email: Email,
        in categoryName: String,
        previousValue: Bool,
        newValue: Bool
    ) {
        categoryStore.markEmail(email.id, in: categoryName, isUnread: newValue)
        toastManager.show(newValue ? "Marked unread" : "Marked read", style: .success, actionTitle: "Undo") {
            categoryStore.markEmail(email.id, in: categoryName, isUnread: previousValue)
            HapticManager.success()
        }
    }
}

#Preview {
    let emailStore = EmailStore()
    let accountStore = AccountStore()
    let categoryStore = CategoryStore()
    let gmailClient = GmailAPIClient()
    let llmService = OnDeviceLLMService()
    let processedStore = ProcessedMessageStore()
    let processingService = EmailProcessingService(
        gmailClient: gmailClient,
        llmService: llmService,
        processedStore: processedStore,
        emailStore: emailStore,
        categoryStore: categoryStore,
        accountStore: accountStore
    )

    NavigationStack {
        HomeView()
    }
    .environmentObject(GmailNetworkService(emailStore: emailStore, accountStore: accountStore))
    .environmentObject(GmailSyncCoordinator(processingService: processingService))
    .environmentObject(categoryStore)
    .environmentObject(accountStore)
    .environmentObject(emailStore)
    .environmentObject(ToastManager())
    .environmentObject(ArchiveStore())
}
