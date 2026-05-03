import SafariServices
import SwiftUI
import UIKit

enum SkillTarget: Hashable {
    case preset(String)
    case user(UUID)
}

struct SkillDetailView: View {
    let target: SkillTarget
    @EnvironmentObject private var categoryStore: CategoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var editorText = ""
    @State private var didLoadInitialText = false
    @State private var errorMessage: String?

    private var userCategory: UserCategory? {
        if case .user(let id) = target {
            return categoryStore.userCategories.first(where: { $0.id == id })
        }
        return nil
    }

    private var presetCategory: PresetCategory? {
        if case .preset(let id) = target {
            return categoryStore.presetCategories.first(where: { $0.id == id })
        }
        return nil
    }

    private var displayName: String? {
        userCategory?.name ?? presetCategory?.name
    }

    var body: some View {
        Form {
            if let displayName {
                Section("Category") {
                    Text(displayName)
                }

                Section {
                    TextEditor(text: $editorText)
                        .frame(minHeight: 260)
                        .font(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Skill Data")
                        Spacer(minLength: 0)
                        Button("Save") {
                            saveTapped()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color("AppTeal"))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Section {
                    Text("Skill not found.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Skill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareTapped()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(displayName == nil)
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .onAppear {
            loadInitialTextIfNeeded()
        }
    }

    private func loadInitialTextIfNeeded() {
        guard !didLoadInitialText else { return }
        didLoadInitialText = true
        errorMessage = nil

        if let userCategory {
            if userCategory.attachedFileName != nil {
                do {
                    editorText = (try categoryStore.loadSkillFileText(for: userCategory)) ?? ""
                } catch {
                    editorText = ""
                    errorMessage = error.localizedDescription
                }
            } else {
                editorText = userCategory.skillDescription
            }
        } else if let presetCategory {
            editorText = presetCategory.skillDescription
        } else {
            editorText = ""
        }
    }

    private func saveTapped() {
        errorMessage = nil
        let textToSave = editorText

        switch target {
        case .preset(let id):
            categoryStore.setPresetSkillDescription(textToSave, for: id)
            HapticManager.success()
            dismiss()
        case .user:
            guard let userCategory else { return }
            if userCategory.attachedFileName != nil {
                do {
                    try categoryStore.saveSkillFileText(for: userCategory, text: textToSave)
                    HapticManager.success()
                    dismiss()
                } catch {
                    HapticManager.error()
                    errorMessage = error.localizedDescription
                }
            } else {
                categoryStore.updateSkillDescription(for: userCategory.id, skillDescription: textToSave)
                HapticManager.success()
                dismiss()
            }
        }
    }

    private func shareTapped() {
        errorMessage = nil

        if let userCategory, let url = categoryStore.skillFileURL(for: userCategory) {
            shareItems = [url]
        } else {
            shareItems = [editorText]
        }
        isShowingShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

struct SettingsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}
