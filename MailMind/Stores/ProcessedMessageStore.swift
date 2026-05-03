import Foundation
import Combine

final class ProcessedMessageStore: ObservableObject {
    private let defaults: UserDefaults
    private let maxIDsPerAccount = 5000

    private var processedIDsByAccount: [UUID: [String]] = [:]
    private var processedSetByAccount: [UUID: Set<String>] = [:]
    private var pendingIDsByAccount: [UUID: [String]] = [:]
    private var pendingSetByAccount: [UUID: Set<String>] = [:]
    private let queue = DispatchQueue(label: "com.mailmind.processedMessageStore", attributes: .concurrent)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func warmUp(accounts: [UUID]) {
        queue.sync(flags: .barrier) {
            for account in accounts {
                ensureLoaded(account: account)
                ensurePendingLoaded(account: account)
                _ = defaults.string(forKey: historyKey(account: account))
                _ = defaults.object(forKey: watchExpiryKey(account: account))
            }
        }
    }

    func isProcessed(_ messageID: String, account: UUID) -> Bool {
        queue.sync {
            ensureLoaded(account: account)
            return processedSetByAccount[account]?.contains(messageID) ?? false
        }
    }

    func markProcessed(_ messageID: String, account: UUID) {
        queue.sync(flags: .barrier) {
            ensureLoaded(account: account)

            var set = processedSetByAccount[account] ?? []
            guard !set.contains(messageID) else {
                return
            }

            var ids = processedIDsByAccount[account] ?? []
            ids.append(messageID)
            set.insert(messageID)

            if ids.count > maxIDsPerAccount {
                let overflow = ids.count - maxIDsPerAccount
                let removed = ids.prefix(overflow)
                ids.removeFirst(overflow)
                for removedID in removed {
                    set.remove(removedID)
                }
            }

            processedIDsByAccount[account] = ids
            processedSetByAccount[account] = set
            persistIDs(ids, account: account)
        }
    }

    func pendingMessageIDs(account: UUID) -> [String] {
        queue.sync {
            ensurePendingLoaded(account: account)
            return pendingIDsByAccount[account] ?? []
        }
    }

    @discardableResult
    func enqueuePending(_ messageIDs: [String], account: UUID) -> Int {
        queue.sync(flags: .barrier) {
            ensureLoaded(account: account)
            ensurePendingLoaded(account: account)

            let processed = processedSetByAccount[account] ?? []
            var pendingIDs = pendingIDsByAccount[account] ?? []
            var pendingSet = pendingSetByAccount[account] ?? []
            var inserted = 0

            for messageID in messageIDs {
                guard !messageID.isEmpty,
                      !processed.contains(messageID),
                      pendingSet.insert(messageID).inserted else {
                    continue
                }

                pendingIDs.append(messageID)
                inserted += 1
            }

            guard inserted > 0 else {
                return 0
            }

            pendingIDsByAccount[account] = pendingIDs
            pendingSetByAccount[account] = pendingSet
            persistPendingIDs(pendingIDs, account: account)
            return inserted
        }
    }

    func removePending(_ messageID: String, account: UUID) {
        queue.sync(flags: .barrier) {
            ensurePendingLoaded(account: account)

            var pendingSet = pendingSetByAccount[account] ?? []
            guard pendingSet.remove(messageID) != nil else {
                return
            }

            var pendingIDs = pendingIDsByAccount[account] ?? []
            pendingIDs.removeAll { $0 == messageID }

            pendingIDsByAccount[account] = pendingIDs
            pendingSetByAccount[account] = pendingSet
            persistPendingIDs(pendingIDs, account: account)
        }
    }

    func lastHistoryId(account: UUID) -> String? {
        defaults.string(forKey: historyKey(account: account))
    }

    func setLastHistoryId(_ historyId: String?, account: UUID) {
        if let historyId {
            defaults.set(historyId, forKey: historyKey(account: account))
        } else {
            defaults.removeObject(forKey: historyKey(account: account))
        }
    }

    func watchExpiry(account: UUID) -> Date? {
        let key = watchExpiryKey(account: account)
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    func setWatchExpiry(_ date: Date, account: UUID) {
        defaults.set(date.timeIntervalSince1970, forKey: watchExpiryKey(account: account))
    }

    func reset(account: UUID) {
        queue.sync(flags: .barrier) {
            processedIDsByAccount[account] = []
            processedSetByAccount[account] = []
            pendingIDsByAccount[account] = []
            pendingSetByAccount[account] = []
            defaults.removeObject(forKey: idsKey(account: account))
            defaults.removeObject(forKey: historyKey(account: account))
            defaults.removeObject(forKey: pendingKey(account: account))
            defaults.removeObject(forKey: watchExpiryKey(account: account))
        }
    }

    private func ensureLoaded(account: UUID) {
        if processedSetByAccount[account] != nil {
            return
        }
        let ids = loadIDs(account: account)
        processedIDsByAccount[account] = ids
        processedSetByAccount[account] = Set(ids)
    }

    private func ensurePendingLoaded(account: UUID) {
        if pendingSetByAccount[account] != nil {
            return
        }
        let ids = loadPendingIDs(account: account)
        pendingIDsByAccount[account] = ids
        pendingSetByAccount[account] = Set(ids)
    }

    private func loadIDs(account: UUID) -> [String] {
        guard let data = defaults.data(forKey: idsKey(account: account)),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private func persistIDs(_ ids: [String], account: UUID) {
        guard let data = try? JSONEncoder().encode(ids) else {
            return
        }
        defaults.set(data, forKey: idsKey(account: account))
    }

    private func loadPendingIDs(account: UUID) -> [String] {
        guard let data = defaults.data(forKey: pendingKey(account: account)),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private func persistPendingIDs(_ ids: [String], account: UUID) {
        guard let data = try? JSONEncoder().encode(ids) else {
            return
        }
        defaults.set(data, forKey: pendingKey(account: account))
    }

    private func idsKey(account: UUID) -> String {
        "processedMessages.\(account.uuidString)"
    }

    private func historyKey(account: UUID) -> String {
        "lastHistoryId.\(account.uuidString)"
    }

    private func pendingKey(account: UUID) -> String {
        "pendingMessages.\(account.uuidString)"
    }

    private func watchExpiryKey(account: UUID) -> String {
        "gmailWatchExpiry.\(account.uuidString)"
    }
}
