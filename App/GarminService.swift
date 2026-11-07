import FitnessCore
import Foundation
import Security

/// The Garmin Personal API key, kept in the iPhone's Keychain (encrypted, this
/// device only, never in backups). It is never shown again after it's saved.
enum GarminKey {
    static let service = "com.gvarun17.fitness.garmin"

    static var stored: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static var isSet: Bool { stored != nil }

    static func save(_ key: String) -> Bool {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecValueData as String: Data(key.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    /// Strips spaces and line breaks a paste can bring along
    static func clean(_ s: String) -> String { s.components(separatedBy: .whitespacesAndNewlines).joined() }
}

/// Downloads from Garmin and keeps what's downloaded on the phone, in the
/// app's private folder (garmin.json).
actor GarminService {
    private var cache: GarminCache
    private var client: GarminClient?
    private let url: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = folder.appendingPathComponent("garmin.json")
        cache = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(GarminCache.self, from: $0) } ?? GarminCache()
    }

    var data: HealthData? { cache.lastSync == nil ? nil : cache.data }
    var lastSync: Date? { cache.lastSync }

    /// Checks a key with Garmin before it's saved: throws if Garmin refuses it.
    static func check(_ key: String) async throws {
        try await GarminClient(key: key).newToken()
    }

    private func currentClient() -> GarminClient? {
        guard let key = GarminKey.stored else { return nil }
        if client == nil { client = GarminClient(key: key) }
        return client
    }

    func sync(today: Day) async throws -> HealthData? {
        guard let c = currentClient() else { return nil }
        cache = try await GarminSync(client: c).run(cache, today: today)
        save()
        return cache.data
    }

    /// Graphs for a workout older than a week, fetched when you open it
    func detail(for w: Workout) async -> WorkoutDetail? {
        if let d = cache.workoutDetails[w.id] { return d }
        guard let c = currentClient(), let d = try? await GarminSync(client: c).workoutDetail(w), !d.isEmpty else { return nil }
        cache.workoutDetails[w.id] = d
        save()
        return d
    }

    func forget() {
        cache = GarminCache()
        client = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
