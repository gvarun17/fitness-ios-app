import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import RunCore

/// Connect a Garmin Personal API key and import running history.
struct GarminView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @StateObject private var importer = GarminImporter()

    @State private var keyText = ""
    @State private var isSavingKey = false
    @State private var keyError: String?
    @State private var range = 0
    @State private var confirmRemove = false
    @State private var pickingFiles = false
    @State private var fileResult: String?

    private var since: Date? {
        let days: Int
        switch range {
        case 1: days = 365
        case 2: days = 90
        case 3: days = 30
        default: return nil
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    var body: some View {
        List {
            if importer.hasKey {
                importSection
                Section {
                    Button("Remove Key", role: .destructive) { confirmRemove = true }
                } footer: {
                    Text("Removes the key from this iPhone. Imported runs are kept. To revoke the key itself, delete it on Garmin Connect.")
                }
            } else {
                keySection
            }

            Section {
                Button("Import .fit Files…") { pickingFiles = true }
                if let fileResult {
                    Text(fileResult)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("From files")
            } footer: {
                Text("Works without a key: import activity files exported from Garmin Connect or another app.")
            }
        }
        .navigationTitle("Garmin Connect")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove your Garmin key?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Key", role: .destructive) { importer.removeKey() }
        }
        .fileImporter(isPresented: $pickingFiles,
                      allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data, .zip],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
    }

    // MARK: Key

    private var keySection: some View {
        Group {
            Section {
                Text("Garmin lets you create a personal key that gives read-only access to your own data. Stride uses it to bring in your past runs with their routes, pace and heart rate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Garmin Key Page") {
                    if let url = URL(string: GarminAPI.keyPageURL) { openURL(url) }
                }
            } header: {
                Text("1. Create a key")
            } footer: {
                Text("Sign in, choose Create Key, pick an expiry and copy the key. Garmin shows it only once.")
            }

            Section {
                SecureField("Personal API key", text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveKey()
                } label: {
                    HStack {
                        Text("Save Key")
                        if isSavingKey {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSavingKey || keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                if let keyError {
                    Text(keyError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("2. Paste it here")
            } footer: {
                Text("The key is stored in this iPhone's Keychain and is only ever sent to Garmin.")
            }
        }
    }

    private func saveKey() {
        isSavingKey = true
        keyError = nil
        Task {
            keyError = await importer.saveKey(keyText)
            isSavingKey = false
            if keyError == nil { keyText = "" }
        }
    }

    // MARK: Import

    private var importSection: some View {
        Section {
            switch importer.phase {
            case .running:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing… \(importer.imported) runs so far")
                            .font(.headline)
                    }
                    if !importer.currentName.isEmpty {
                        Text(importer.currentName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("Keep Stride open until it finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Stop", role: .destructive) { importer.cancel() }
            case .idle, .finished, .failed:
                Label("Key connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Picker("Import", selection: $range) {
                    Text("All history").tag(0)
                    Text("Last 12 months").tag(1)
                    Text("Last 90 days").tag(2)
                    Text("Last 30 days").tag(3)
                }
                Button("Import Runs") {
                    importer.start(since: since, context: context)
                }
                .fontWeight(.semibold)
                if importer.phase == .finished {
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if case .failed(let message) = importer.phase {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    if importer.imported > 0 {
                        Text(resultText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Import runs")
        } footer: {
            Text("Only running activities are imported. Runs already in Stride are skipped, so you can run this again any time to pick up new ones. A full history can take several minutes.")
        }
    }

    private var resultText: String {
        var parts = ["Imported \(importer.imported) \(importer.imported == 1 ? "run" : "runs")."]
        if importer.skipped > 0 { parts.append("\(importer.skipped) already in Stride.") }
        if importer.summaryOnly > 0 { parts.append("\(importer.summaryOnly) had no activity file, so only their totals were saved.") }
        return parts.joined(separator: " ")
    }

    // MARK: Files

    private func importFiles(_ urls: [URL]) {
        var added = 0
        var unreadable = 0
        var notRuns = 0
        let known = Set((try? context.fetch(FetchDescriptor<Run>()))?.map(\.startDate) ?? [])
        var seen = known
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let run = ActivityFile.run(from: data) else {
                unreadable += 1
                continue
            }
            guard run.isRun else {
                notRuns += 1
                continue
            }
            // A run starting at the same second is the same run.
            guard !seen.contains(run.startDate) else { continue }
            seen.insert(run.startDate)
            RunStore.insert(run, title: nil, externalID: nil, in: context)
            added += 1
        }
        try? context.save()
        var parts = ["Imported \(added) \(added == 1 ? "run" : "runs")."]
        let duplicates = urls.count - added - unreadable - notRuns
        if duplicates > 0 { parts.append("\(duplicates) already in Stride.") }
        if notRuns > 0 { parts.append("\(notRuns) weren't runs.") }
        if unreadable > 0 { parts.append("\(unreadable) couldn't be read.") }
        fileResult = parts.joined(separator: " ")
    }
}
