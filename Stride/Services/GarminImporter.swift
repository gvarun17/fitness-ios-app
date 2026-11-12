import Foundation
import SwiftData
import RunCore

enum GarminError: LocalizedError {
    case noKey
    case invalidKey
    case notAuthorized
    case rateLimited
    case server(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Garmin Personal API key first."
        case .invalidKey: return "Garmin didn't accept the key. It may be mistyped, deleted or expired. Create a new key on Garmin Connect and paste it here."
        case .notAuthorized: return "Garmin refused the request. Your key may have expired."
        case .rateLimited: return "Garmin is limiting requests right now. Runs imported so far are kept; try again later to continue."
        case .server(let code): return "Garmin returned an error (\(code)). Try again later."
        case .unreadable: return "Garmin's response couldn't be read."
        }
    }
}

/// Talks to the Garmin Connect Personal API with the runner's own key.
final class GarminClient {
    static let keyAccount = "garminPersonalAPIKey"

    private let session = URLSession(configuration: .ephemeral)
    private var token: String?
    private var tokenDate: Date?

    static var hasKey: Bool { Keychain.get(keyAccount) != nil }

    /// Exchanges the stored key for an access token (valid 24 hours; reused for 12).
    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token, let tokenDate, Date().timeIntervalSince(tokenDate) < 12 * 3600 {
            return token
        }
        guard let key = Keychain.get(Self.keyAccount) else { throw GarminError.noKey }
        var request = URLRequest(url: GarminAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 || status == 400 { throw GarminError.invalidKey }
        if status == 429 { throw GarminError.rateLimited }
        guard (200..<300).contains(status) else { throw GarminError.server(status) }
        guard let fresh = GarminAPI.parseToken(data) else { throw GarminError.unreadable }
        token = fresh
        tokenDate = Date()
        return fresh
    }

    /// Checks that the stored key works.
    func verifyKey() async throws {
        _ = try await accessToken(forceRefresh: true)
    }

    /// Returns nil for 404 (the resource doesn't exist).
    private func get(_ url: URL, retryingAuth: Bool = true) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 204, 404:
            return nil
        case 401:
            // The token may have been revoked or expired early; get a new one once.
            guard retryingAuth else { throw GarminError.notAuthorized }
            _ = try await accessToken(forceRefresh: true)
            return try await get(url, retryingAuth: false)
        case 403:
            throw GarminError.notAuthorized
        case 429:
            throw GarminError.rateLimited
        default:
            throw GarminError.server(status)
        }
    }

    func activities(start: Int, limit: Int, since: Date?) async throws -> [GarminActivity] {
        guard let data = try await get(GarminAPI.activitiesURL(start: start, limit: limit, since: since)) else { return [] }
        do {
            return try GarminAPI.parseActivities(data)
        } catch {
            throw GarminError.unreadable
        }
    }

    /// The activity's original FIT file, or nil when Garmin has none (e.g. manual entries).
    func activityFile(id: Int64) async throws -> [UInt8]? {
        guard let data = try await get(GarminAPI.downloadURL(activityID: id)) else { return nil }
        return ActivityFile.fitBytes(from: data)
    }
}

enum ActivityFile {
    /// Accepts a FIT file or a ZIP archive containing one.
    static func fitBytes(from data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard ZipArchive.isZip(bytes) else { return bytes }
        guard let entries = ZipArchive.entries(bytes),
              let entry = entries.first(where: { $0.name.lowercased().hasSuffix(".fit") }) else { return nil }
        switch entry.method {
        case 0:
            return entry.data
        case 8:
            // NSData's "zlib" algorithm is raw DEFLATE, which is what ZIP stores.
            guard let inflated = try? (Data(entry.data) as NSData).decompressed(using: .zlib) else { return nil }
            return [UInt8](inflated as Data)
        default:
            return nil
        }
    }

    static func run(from data: Data) -> ImportedRun? {
        guard let bytes = fitBytes(from: data), let file = try? FITDecoder.decode(bytes) else { return nil }
        return ActivityImport.run(from: file)
    }
}

/// Imports running history from Garmin Connect into the local store.
@MainActor
final class GarminImporter: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var imported = 0
    @Published private(set) var skipped = 0
    @Published private(set) var summaryOnly = 0
    @Published private(set) var currentName = ""
    @Published private(set) var hasKey = GarminClient.hasKey

    private let client = GarminClient()
    private var task: Task<Void, Never>?

    func saveKey(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Paste your key first." }
        let previous = Keychain.get(GarminClient.keyAccount)
        Keychain.set(trimmed, for: GarminClient.keyAccount)
        do {
            try await client.verifyKey()
            hasKey = true
            return nil
        } catch {
            // Don't keep a key that doesn't work; put back the old one if there was one.
            if let previous {
                Keychain.set(previous, for: GarminClient.keyAccount)
            } else {
                Keychain.remove(GarminClient.keyAccount)
            }
            hasKey = GarminClient.hasKey
            return (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Garmin. Check your connection and try again."
        }
    }

    func removeKey() {
        cancel()
        Keychain.remove(GarminClient.keyAccount)
        hasKey = false
        phase = .idle
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .running { phase = .finished }
    }

    /// Imports every run on or after `since` (nil for all history) that isn't already stored.
    func start(since: Date?, context: ModelContext) {
        guard phase != .running else { return }
        imported = 0
        skipped = 0
        summaryOnly = 0
        currentName = ""
        phase = .running
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(since: since, context: context)
                try? context.save()
                if !Task.isCancelled { self.phase = .finished }
            } catch is CancellationError {
                try? context.save()
            } catch {
                try? context.save()
                if Task.isCancelled { return }
                self.phase = .failed((error as? LocalizedError)?.errorDescription
                                     ?? "Couldn't reach Garmin. Check your connection and try again.")
            }
        }
    }

    private func run(since: Date?, context: ModelContext) async throws {
        var known = Set((try? context.fetch(FetchDescriptor<Run>()))?.compactMap(\.externalID) ?? [])
        let pageSize = 50
        var offset = 0

        while true {
            let page = try await client.activities(start: offset, limit: pageSize, since: since)
            for activity in page {
                try Task.checkCancellation()
                let externalID = GarminAPI.externalID(activityID: activity.activityId)
                if known.contains(externalID) {
                    skipped += 1
                    continue
                }
                currentName = activity.activityName ?? "Run"

                var run: ImportedRun?
                if let bytes = try await client.activityFile(id: activity.activityId),
                   let file = try? FITDecoder.decode(bytes) {
                    run = ActivityImport.run(from: file)
                }
                if run == nil {
                    // No readable file: keep the totals Garmin lists so the run still counts.
                    run = Self.summaryRun(from: activity)
                    if run != nil { summaryOnly += 1 }
                }
                if let run {
                    RunStore.insert(run, title: activity.activityName, externalID: externalID, in: context)
                    known.insert(externalID)
                    imported += 1
                    if imported % 10 == 0 { try? context.save() }
                }
                // Stay well clear of Garmin's (unpublished) request limits.
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            if page.count < pageSize { break }
            offset += pageSize
        }
    }

    private static func summaryRun(from activity: GarminActivity) -> ImportedRun? {
        guard let start = activity.startDate, let distance = activity.distance, let duration = activity.duration,
              distance > 0, duration > 0 else { return nil }
        return ImportedRun(startDate: start, endDate: start.addingTimeInterval(duration), duration: duration,
                           distance: distance, elevationGain: 0, calories: nil, points: [], heartRates: [],
                           averageHeartRate: nil, maxHeartRate: nil, isRun: true)
    }
}
