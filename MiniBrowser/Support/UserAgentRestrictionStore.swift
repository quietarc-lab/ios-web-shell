import Foundation
import CryptoKit

struct UserAgentRestrictionStore {
    static let defaultDuration: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let storageKey: String
    private let saltKey: String
    private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         storageKey: String = "userAgentRestrictionExpiries",
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.saltKey = "\(storageKey).generatedKeySalt"
        self.now = now
    }

    func isRestricted(_ userAgentID: Int) -> Bool {
        isRestricted(String(userAgentID))
    }

    func isRestricted(_ key: String) -> Bool {
        guard let expiry = expiry(for: key) else { return false }
        return expiry > now()
    }

    func expiry(for userAgentID: Int) -> Date? {
        expiry(for: String(userAgentID))
    }

    func expiry(for key: String) -> Date? {
        let entries = storedEntries()
        guard let timestamp = entries[key] else { return nil }
        let expiry = Date(timeIntervalSince1970: timestamp)
        if expiry <= now() {
            var pruned = entries
            pruned.removeValue(forKey: key)
            saveEntries(pruned)
            return nil
        }
        return expiry
    }

    func restrictedIDs() -> Set<Int> {
        Set(restrictedKeys().compactMap(Int.init))
    }

    func restrictedKeys() -> Set<String> {
        let currentDate = now()
        var entries = storedEntries()
        entries = entries.filter { $0.value > currentDate.timeIntervalSince1970 }
        saveEntries(entries)
        return Set(entries.keys)
    }

    @discardableResult
    func restrict(_ userAgentID: Int,
                  duration: TimeInterval = UserAgentRestrictionStore.defaultDuration) -> Date {
        restrict(String(userAgentID), duration: duration)
    }

    @discardableResult
    func restrict(_ key: String,
                  duration: TimeInterval = UserAgentRestrictionStore.defaultDuration) -> Date {
        var entries = storedEntries()
        let expiry = now().addingTimeInterval(duration)
        entries[key] = expiry.timeIntervalSince1970
        saveEntries(entries)
        return expiry
    }

    func clear(_ userAgentID: Int) {
        clear(String(userAgentID))
    }

    func clear(_ key: String) {
        var entries = storedEntries()
        entries.removeValue(forKey: key)
        saveEntries(entries)
    }

    /// Returns a local-only key for a generated UA. The raw value is never
    /// persisted; the per-install salt prevents the key from being useful as
    /// a cross-device or cross-install identifier.
    func generatedRestrictionKey(for userAgent: String) -> String {
        let salt = installationSalt()
        var data = Data()
        data.append(salt)
        data.append(0)
        data.append(contentsOf: userAgent.utf8)
        let digest = SHA256.hash(data: data)
        return "generated:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Explicit administrative reset retained for compatibility with older
    /// callers. Catalog migrations no longer call this method: fixed profile
    /// IDs and legacy generated keys remain valid across append-only updates.
    func clearAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private func storedEntries() -> [String: TimeInterval] {
        guard let raw = defaults.dictionary(forKey: storageKey) else { return [:] }
        return raw.reduce(into: [String: TimeInterval]()) { result, item in
            if let value = item.value as? TimeInterval {
                result[item.key] = value
            } else if let number = item.value as? NSNumber {
                result[item.key] = number.doubleValue
            }
        }
    }

    private func saveEntries(_ entries: [String: TimeInterval]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(entries, forKey: storageKey)
        }
    }

    private func installationSalt() -> Data {
        if let existing = defaults.data(forKey: saltKey), !existing.isEmpty {
            return existing
        }
        let generated = Data(UUID().uuidString.utf8)
        defaults.set(generated, forKey: saltKey)
        return generated
    }
}
