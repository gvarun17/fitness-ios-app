import SwiftUI
import SwiftData
import RunCore

struct ShoesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shoe.addedDate, order: .reverse) private var shoes: [Shoe]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.defaultShoeID) private var defaultShoeID = ""
    @State private var editing: Shoe?
    @State private var adding = false

    var body: some View {
        Group {
            if shoes.isEmpty {
                ContentUnavailableView {
                    Label("No shoes yet", systemImage: "shoe.fill")
                } description: {
                    Text("Add your running shoes to track their mileage and know when to replace them.")
                } actions: {
                    Button("Add Shoes") { adding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(shoes) { shoe in
                        Button {
                            editing = shoe
                        } label: {
                            row(shoe)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(shoes[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Shoes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add shoes")
            }
        }
        .sheet(isPresented: $adding) {
            ShoeEditView(shoe: nil)
        }
        .sheet(item: $editing) { shoe in
            ShoeEditView(shoe: shoe)
        }
    }

    private func row(_ shoe: Shoe) -> some View {
        let fraction = shoe.wearFraction
        let color: Color = fraction >= 1 ? .red : (fraction >= 0.85 ? .orange : .accentColor)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(shoe.displayName)
                    .font(.headline)
                if shoe.uuid.uuidString == defaultShoeID {
                    Text("DEFAULT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if shoe.retired {
                    Text("Retired")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(1, max(0, fraction)))
                .tint(color)
            HStack {
                Text("\(Fmt.distance(shoe.totalDistance, unit: unit, decimals: 0)) of \(Fmt.distance(shoe.targetDistance, unit: unit, decimals: 0)) \(unit.abbreviation)")
                Spacer()
                if fraction >= 1 {
                    Text("Time to replace")
                        .foregroundStyle(.red)
                } else if fraction >= 0.85 {
                    Text("Replace soon")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(shoe.runs.count) runs")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(shoe.retired ? 0.55 : 1)
    }
}

struct ShoeEditView: View {
    var shoe: Shoe?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.defaultShoeID) private var defaultShoeID = ""

    @State private var brand = ""
    @State private var name = ""
    @State private var initialUnits = 0.0
    @State private var targetUnits = 0.0
    @State private var retired = false
    @State private var isDefault = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Shoe") {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $name)
                }

                Section {
                    Stepper(value: $initialUnits, in: 0...2000, step: 10) {
                        LabeledContent("Already run", value: "\(Int(initialUnits)) \(unit.abbreviation)")
                    }
                    Stepper(value: $targetUnits, in: 100...2000, step: 50) {
                        LabeledContent("Replace at", value: "\(Int(targetUnits)) \(unit.abbreviation)")
                    }
                } header: {
                    Text("Mileage")
                } footer: {
                    Text("Most running shoes last 500 to 800 km (300 to 500 miles).")
                }

                Section {
                    Toggle("Use by default", isOn: $isDefault)
                        .disabled(retired)
                    if shoe != nil {
                        Toggle("Retired", isOn: $retired)
                    }
                }
            }
            .navigationTitle(shoe == nil ? "New Shoes" : "Edit Shoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let shoe {
            brand = shoe.brand
            name = shoe.name
            initialUnits = (shoe.initialDistance / unit.meters).rounded()
            targetUnits = (shoe.targetDistance / unit.meters).rounded()
            retired = shoe.retired
            isDefault = shoe.uuid.uuidString == defaultShoeID
        } else {
            targetUnits = unit == .kilometers ? 700 : 450
        }
    }

    private func save() {
        let target: Shoe
        if let shoe {
            target = shoe
        } else {
            target = Shoe(name: "", brand: "", initialDistance: 0, targetDistance: 0)
            context.insert(target)
        }
        target.brand = brand.trimmingCharacters(in: .whitespaces)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.initialDistance = initialUnits * unit.meters
        target.targetDistance = targetUnits * unit.meters
        target.retired = retired
        try? context.save()

        let id = target.uuid.uuidString
        if isDefault && !retired {
            defaultShoeID = id
        } else if defaultShoeID == id {
            defaultShoeID = ""
        }
        dismiss()
    }
}
