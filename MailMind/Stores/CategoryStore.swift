import Foundation
import Combine

struct PresetCategory: Identifiable {
    let id: String
    let name: String
    let emails: [Email]
    let isEnabled: Bool
    let skillDescription: String
}

struct UserCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var skillDescription: String
    var attachedFileName: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        skillDescription: String,
        attachedFileName: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.skillDescription = skillDescription
        self.attachedFileName = attachedFileName
        self.isEnabled = isEnabled
    }
}

final class CategoryStore: ObservableObject {
    @Published private(set) var userCategories: [UserCategory] = []
    @Published private var presetEnabledState: [String: Bool] = [:]
    @Published private var presetSkillDescriptions: [String: String] = [:]
    @Published private var emailsByCategory: [String: [Email]] = [:]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let userCategoriesKey = "userCategories"
    private let presetEnabledStateKey = "presetCategoryEnabledState"
    private let presetSkillDescriptionsKey = "presetSkillDescriptions"
    private let didSeedTestCategoriesKey = "didSeedTestUserCategories"
    private let presetCategoryIDs: Set<String> = ["interview"]

    private static let defaultPresetSkillDescriptions: [String: String] = [
        "interview": """
        Interview-related: any of the following — recruiter or sourcing outreach; \
        interview scheduling (phone, video, onsite, panel); coding or take-home \
        assignments; offer letters or compensation discussion; rejection or \
        post-interview status updates; background-check or reference requests \
        tied to a job process.
        """
    ]

    var presetCategories: [PresetCategory] {
        MockData.categories
            .filter { presetCategoryIDs.contains($0.id) }
            .map { category in
                PresetCategory(
                    id: category.id,
                    name: category.name,
                    emails: category.emails,
                    isEnabled: isPresetEnabled(category.id),
                    skillDescription: presetSkillDescription(for: category.id)
                )
            }
    }

    var totalCategoryCount: Int {
        presetCategories.count + userCategories.count
    }

    var unreadCount: Int {
        emailsByCategory.values.flatMap { $0 }.filter(\.isUnread).count
    }

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.userCategories = Self.loadUserCategories(from: defaults, key: userCategoriesKey)
        self.presetEnabledState = Self.loadPresetEnabledState(from: defaults, key: presetEnabledStateKey)
        self.presetSkillDescriptions = Self.loadPresetSkillDescriptions(from: defaults, key: presetSkillDescriptionsKey)
        seedTestUserCategoriesIfNeeded()
    }

    private func seedTestUserCategoriesIfNeeded() {
        guard !defaults.bool(forKey: didSeedTestCategoriesKey) else {
            return
        }

        let seeds = MockData.categories
            .filter { !presetCategoryIDs.contains($0.id) }
            .map { category in
                UserCategory(
                    name: category.name,
                    skillDescription: "Auto-seeded test category for \(category.name)."
                )
            }

        if !seeds.isEmpty {
            userCategories.append(contentsOf: seeds)
            saveUserCategories()
        }

        defaults.set(true, forKey: didSeedTestCategoriesKey)
    }

    func addCategory(name: String, skillDescription: String, attachedFileURL: URL?) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw CategoryStoreError.missingName
        }

        guard !trimmedDescription.isEmpty || attachedFileURL != nil else {
            throw CategoryStoreError.missingSkillSource
        }

        let categoryID = UUID()
        let attachedFileName = try attachedFileURL.map { try copySkillFile(from: $0, categoryID: categoryID) }
        let category = UserCategory(
            id: categoryID,
            name: trimmedName,
            skillDescription: trimmedDescription,
            attachedFileName: attachedFileName
        )

        userCategories.append(category)
        saveUserCategories()
    }

    func updateCategory(id: UserCategory.ID, name: String, skillDescription: String, attachedFileURL: URL?) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw CategoryStoreError.missingName
        }

        guard let categoryIndex = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existingAttachedFileName = userCategories[categoryIndex].attachedFileName

        guard !trimmedDescription.isEmpty || attachedFileURL != nil || existingAttachedFileName != nil else {
            throw CategoryStoreError.missingSkillSource
        }

        let oldCategoryName = userCategories[categoryIndex].name
        let attachedFileName = try attachedFileURL.map { try copySkillFile(from: $0, categoryID: id) } ?? existingAttachedFileName

        userCategories[categoryIndex].name = trimmedName
        userCategories[categoryIndex].skillDescription = trimmedDescription
        userCategories[categoryIndex].attachedFileName = attachedFileName

        if oldCategoryName != trimmedName {
            emailsByCategory[trimmedName] = emailsByCategory[oldCategoryName]
            emailsByCategory[oldCategoryName] = nil
        }

        saveUserCategories()
    }

    func deleteCategory(id: UserCategory.ID) {
        guard let categoryIndex = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }

        let category = userCategories[categoryIndex]

        if let attachedFileName = category.attachedFileName {
            deleteSkillFile(named: attachedFileName)
        }

        emailsByCategory[category.name] = nil
        userCategories.remove(at: categoryIndex)
        saveUserCategories()
    }

    func isPresetEnabled(_ id: PresetCategory.ID) -> Bool {
        presetEnabledState[id] ?? true
    }

    func setPresetEnabled(_ isEnabled: Bool, for id: PresetCategory.ID) {
        presetEnabledState[id] = isEnabled
        savePresetEnabledState()
    }

    func presetSkillDescription(for id: PresetCategory.ID) -> String {
        presetSkillDescriptions[id] ?? Self.defaultPresetSkillDescriptions[id] ?? ""
    }

    func setPresetSkillDescription(_ skillDescription: String, for id: PresetCategory.ID) {
        let trimmed = skillDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        presetSkillDescriptions[id] = trimmed
        savePresetSkillDescriptions()
    }

    func isUserCategoryEnabled(_ id: UserCategory.ID) -> Bool {
        userCategories.first(where: { $0.id == id })?.isEnabled ?? true
    }

    func setUserCategoryEnabled(_ isEnabled: Bool, for id: UserCategory.ID) {
        guard let categoryIndex = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }

        userCategories[categoryIndex].isEnabled = isEnabled
        saveUserCategories()
    }

    func emails(for categoryName: String) -> [Email] {
        emailsByCategory[categoryName] ?? []
    }

    func setEmails(_ emails: [Email], for categoryName: String) {
        emailsByCategory[categoryName] = emails
    }

    func markEmail(_ emailID: Email.ID, in categoryName: String, isUnread: Bool) {
        guard var emails = emailsByCategory[categoryName],
              let emailIndex = emails.firstIndex(where: { $0.id == emailID }) else {
            return
        }

        emails[emailIndex] = emails[emailIndex].updatingUnreadState(isUnread)
        emailsByCategory[categoryName] = emails
    }

    func dismissEmail(_ emailID: Email.ID, in categoryName: String) {
        guard var emails = emailsByCategory[categoryName] else {
            return
        }

        emails.removeAll { $0.id == emailID }
        emailsByCategory[categoryName] = emails
    }

    func removeEmails(destinationAccount: String) {
        for (categoryName, emails) in emailsByCategory {
            emailsByCategory[categoryName] = emails.filter { $0.destinationAccount != destinationAccount }
        }
    }

    func indexOfEmail(_ emailID: Email.ID, in categoryName: String) -> Int? {
        emailsByCategory[categoryName]?.firstIndex(where: { $0.id == emailID })
    }

    func insertEmail(_ email: Email, at index: Int, in categoryName: String) {
        var emails = emailsByCategory[categoryName] ?? []

        guard !emails.contains(where: { $0.id == email.id }) else {
            return
        }

        let clampedIndex = max(0, min(index, emails.count))
        emails.insert(email, at: clampedIndex)
        emailsByCategory[categoryName] = emails
    }

    func categoryExists(named categoryName: String) -> Bool {
        if MockData.categories.contains(where: { presetCategoryIDs.contains($0.id) && $0.name == categoryName }) {
            return true
        }

        return userCategories.contains { $0.name == categoryName }
    }

    func restoreUserCategory(_ category: UserCategory) {
        guard !userCategories.contains(where: { $0.name == category.name }) else {
            return
        }

        userCategories.append(category)
        saveUserCategories()
    }

    func skillFileURL(named fileName: String) -> URL? {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let directoryURL = try? skillFilesDirectory() else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }

    func skillFileURL(for category: UserCategory) -> URL? {
        guard let fileName = category.attachedFileName else {
            return nil
        }
        return skillFileURL(named: fileName)
    }

    func loadSkillFileText(for category: UserCategory) throws -> String? {
        guard let url = skillFileURL(for: category) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func saveSkillFileText(for category: UserCategory, text: String) throws {
        guard let url = skillFileURL(for: category) else {
            throw CategoryStoreError.skillFileMissing
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func updateSkillDescription(for id: UserCategory.ID, skillDescription: String) {
        guard let categoryIndex = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }

        userCategories[categoryIndex].skillDescription = skillDescription
        saveUserCategories()
    }

    private func copySkillFile(from sourceURL: URL, categoryID: UUID) throws -> String {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directoryURL = try skillFilesDirectory()
        let fileName = "\(categoryID.uuidString)-\(sanitizedFileName(sourceURL.lastPathComponent))"
        let destinationURL = directoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    private func deleteSkillFile(named fileName: String) {
        guard let directoryURL = try? skillFilesDirectory() else {
            return
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func skillFilesDirectory() throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryURL = documentsURL.appendingPathComponent("SkillFiles", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func sanitizedFileName(_ fileName: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return fileName.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        .map(String.init)
        .joined()
    }

    private func saveUserCategories() {
        guard let data = try? JSONEncoder().encode(userCategories) else {
            return
        }

        defaults.set(data, forKey: userCategoriesKey)
    }

    private func savePresetEnabledState() {
        guard let data = try? JSONEncoder().encode(presetEnabledState) else {
            return
        }

        defaults.set(data, forKey: presetEnabledStateKey)
    }

    private func savePresetSkillDescriptions() {
        guard let data = try? JSONEncoder().encode(presetSkillDescriptions) else {
            return
        }

        defaults.set(data, forKey: presetSkillDescriptionsKey)
    }

    private static func loadUserCategories(from defaults: UserDefaults, key: String) -> [UserCategory] {
        guard let data = defaults.data(forKey: key),
              let categories = try? JSONDecoder().decode([UserCategory].self, from: data) else {
            return []
        }

        return categories
    }

    private static func loadPresetEnabledState(from defaults: UserDefaults, key: String) -> [String: Bool] {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }

        return state
    }

    private static func loadPresetSkillDescriptions(from defaults: UserDefaults, key: String) -> [String: String] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return map
    }
}

enum CategoryStoreError: LocalizedError {
    case missingName
    case missingSkillSource
    case skillFileMissing

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a category name."
        case .missingSkillSource:
            "Paste a skill description or attach a skill file."
        case .skillFileMissing:
            "Skill file not found."
        }
    }
}
