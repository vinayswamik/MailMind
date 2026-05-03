import SwiftUI
import UniformTypeIdentifiers

struct AddCategorySheet: View {
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) private var dismiss
    private let editingCategory: UserCategory?

    @State private var categoryName = ""
    @State private var skillDescription = ""
    @State private var attachedFileURL: URL?
    @State private var attachedFileName: String?
    @State private var isShowingFileImporter = false
    @State private var errorMessage: String?

    private var trimmedCategoryName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSkillDescription: String {
        skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedCategoryName.isEmpty && (!trimmedSkillDescription.isEmpty || attachedFileURL != nil || attachedFileName != nil)
    }

    private static var allowedSkillFileTypes: [UTType] {
        [
            .plainText,
            UTType(filenameExtension: "md")
        ].compactMap { $0 }
    }

    init(categoryStore: CategoryStore, editingCategory: UserCategory? = nil) {
        self.categoryStore = categoryStore
        self.editingCategory = editingCategory
        _categoryName = State(initialValue: editingCategory?.name ?? "")
        _skillDescription = State(initialValue: editingCategory?.skillDescription ?? "")
        _attachedFileName = State(initialValue: editingCategory?.attachedFileName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Category name", text: $categoryName)
                        .textInputAutocapitalization(.words)
                }

                Section("Skill Description") {
                    TextField("Paste skill description text", text: $skillDescription, axis: .vertical)
                        .lineLimit(5...10)

                    HStack {
                        Text("OR")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label(attachedFileName ?? "Attach skill file (.txt, .md)", systemImage: "paperclip")
                        }
                    }

                    if let attachedFileName {
                        Text(attachedFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingCategory == nil ? "Add Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveCategory()
                    } label: {
                        Text(editingCategory == nil ? "Save" : "Update")
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? .blue : .secondary)
                    }
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: Self.allowedSkillFileTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    attachedFileURL = urls.first
                    attachedFileName = urls.first?.lastPathComponent
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveCategory() {
        do {
            if let editingCategory {
                try categoryStore.updateCategory(
                    id: editingCategory.id,
                    name: trimmedCategoryName,
                    skillDescription: trimmedSkillDescription,
                    attachedFileURL: attachedFileURL
                )
            } else {
                try categoryStore.addCategory(
                    name: trimmedCategoryName,
                    skillDescription: trimmedSkillDescription,
                    attachedFileURL: attachedFileURL
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddCategorySheet(categoryStore: CategoryStore())
}
