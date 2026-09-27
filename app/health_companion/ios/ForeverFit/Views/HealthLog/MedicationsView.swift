import SwiftUI

public enum MedicationFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case paused = "Paused"
}

public enum MedicationSortOrder: String, CaseIterable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case recentlyAdded = "Recently Added"
}

public struct MedicationsView: View {
    @ObservedObject var dataStore: HealthDataStore
    @State private var searchText: String = ""
    @State private var selectedFilter: MedicationFilter = .all
    @State private var sortOrder: MedicationSortOrder = .nameAsc
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<UUID> = []

    @State private var showingEditSheet: Bool = false
    @State private var editingMedication: Medication? = nil

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    private var filteredMedications: [Medication] {
        var list = dataStore.medications

        // Filter by text
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.dosage.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q)
            }
        }

        // Filter by active/paused
        switch selectedFilter {
        case .all:
            break
        case .active:
            list = list.filter { $0.isActive }
        case .paused:
            list = list.filter { !$0.isActive }
        }

        // Sort
        switch sortOrder {
        case .nameAsc:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .recentlyAdded:
            list.sort { $0.dateAdded > $1.dateAdded }
        }

        return list
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Adherence Banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Doses Taken Today: \(dataStore.dosesTakenToday)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Consistent medication adherence supports recovery.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.white.opacity(0.5))
                    TextField("Search medications...", text: $searchText)
                        .foregroundStyle(Color.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                // Filter & Sort Controls
                HStack(spacing: 8) {
                    // Filter Chips
                    ForEach(MedicationFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedFilter == filter ? Color.black : Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedFilter == filter ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    // Sort Menu
                    Menu {
                        ForEach(MedicationSortOrder.allCases, id: \.self) { sort in
                            Button {
                                sortOrder = sort
                            } label: {
                                HStack {
                                    Text(sort.rawValue)
                                    if sortOrder == sort {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.rawValue)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                    }
                }

                // Batch Actions Bar (when in selection mode)
                if isSelecting {
                    HStack {
                        Text("\(selectedIds.count) selected")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)

                        Spacer()

                        Button("Pause / Resume") {
                            for id in selectedIds {
                                if let med = dataStore.medications.first(where: { $0.id == id }) {
                                    dataStore.setMedicationActive(id: id, isActive: !med.isActive)
                                }
                            }
                            selectedIds.removeAll()
                            isSelecting = false
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)

                        Button("Delete") {
                            for id in selectedIds {
                                dataStore.removeMedication(id: id)
                            }
                            selectedIds.removeAll()
                            isSelecting = false
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                }

                // Medications List
                if filteredMedications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "pills")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.white.opacity(0.3))
                        Text(dataStore.medications.isEmpty ? "No medications added yet.\nTap 'Add Medication' below." : "No medications match your filter.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredMedications) { med in
                            MedicationCardView(
                                medication: med,
                                isSelecting: isSelecting,
                                isSelected: selectedIds.contains(med.id),
                                onToggleSelect: {
                                    if selectedIds.contains(med.id) {
                                        selectedIds.remove(med.id)
                                    } else {
                                        selectedIds.insert(med.id)
                                    }
                                },
                                onMarkDoseTaken: {
                                    dataStore.logMedicationDose(name: med.name)
                                },
                                onToggleActive: {
                                    dataStore.setMedicationActive(id: med.id, isActive: !med.isActive)
                                },
                                onEdit: {
                                    editingMedication = med
                                    showingEditSheet = true
                                },
                                onDelete: {
                                    dataStore.removeMedication(id: med.id)
                                }
                            )
                        }
                    }
                }

                Button {
                    editingMedication = nil
                    showingEditSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Medication")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassTheme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !dataStore.medications.isEmpty {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedIds.removeAll()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
        }
        .background(MeshGradientBackground())
        .sheet(isPresented: $showingEditSheet) {
            MedicationEditSheet(
                existing: editingMedication,
                onSave: { name, amount, unit, type, isActive, notes, schedules in
                    dataStore.saveMedication(
                        id: editingMedication?.id,
                        name: name,
                        amount: amount,
                        unit: unit,
                        type: type,
                        isActive: isActive,
                        notes: notes,
                        schedules: schedules
                    )
                    showingEditSheet = false
                }
            )
        }
    }
}

// MARK: - Medication Card View
private struct MedicationCardView: View {
    let medication: Medication
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onMarkDoseTaken: () -> Void
    let onToggleActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var iconName: String {
        switch medication.type {
        case .pill: return "pill.fill"
        case .capsule: return "capsule.fill"
        case .drops: return "drop.fill"
        case .liquid: return "cup.and.saucer.fill"
        case .injection: return "syringe.fill"
        case .topical: return "bandage.fill"
        case .unspecified: return "pills.fill"
        }
    }

    private var subtitleText: String {
        var parts: [String] = []
        if !medication.dosage.isEmpty { parts.append(medication.dosage) }
        parts.append(medication.type.label)
        if !medication.schedules.isEmpty {
            parts.append(medication.schedules.map(\.label).joined(separator: ", "))
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.4))
                }
            }

            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundStyle(medication.isActive ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.4))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(medication.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(medication.isActive ? Color.white : Color.white.opacity(0.5))
                    .strikethrough(!medication.isActive)

                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))

                if !medication.notes.isEmpty {
                    Text(medication.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isSelecting {
                Button(action: onMarkDoseTaken) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                        .frame(width: 32, height: 32)
                        .background(LiquidGlassTheme.emeraldGreen.opacity(0.15))
                        .clipShape(Circle())
                }

                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: onToggleActive) {
                        Label(medication.isActive ? "Pause" : "Resume", systemImage: medication.isActive ? "pause.circle" : "play.circle")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(medication.isActive ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect()
            } else {
                onEdit()
            }
        }
    }
}

// MARK: - Medication Edit Sheet
public struct MedicationEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: Medication?
    let onSave: (_ name: String, _ amount: String, _ unit: String, _ type: MedicationType, _ isActive: Bool, _ notes: String, _ schedules: [MedicationSchedule]) -> Void

    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var unit: String = ""
    @State private var type: MedicationType = .pill
    @State private var isActive: Bool = true
    @State private var notes: String = ""
    @State private var schedules: [MedicationSchedule] = []

    @State private var showingTimePicker: Bool = false
    @State private var pickedTime: Date = Date()

    public init(
        existing: Medication?,
        onSave: @escaping (_ name: String, _ amount: String, _ unit: String, _ type: MedicationType, _ isActive: Bool, _ notes: String, _ schedules: [MedicationSchedule]) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
    }

    private var availableUnits: [String] {
        type.units
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Name Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Medication Name")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        TextField("e.g. Metformin", text: $name)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .foregroundStyle(Color.white)
                    }

                    // Type Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MedicationType.allCases.filter { $0 != .unspecified }, id: \.self) { t in
                                    Button {
                                        type = t
                                        if !t.units.contains(unit) {
                                            unit = t.units.first ?? ""
                                        }
                                    } label: {
                                        Text(t.label)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(type == t ? Color.black : Color.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(type == t ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Amount & Unit Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Amount")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                            TextField("e.g. 500", text: $amount)
                                .keyboardType(.decimalPad)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                                .foregroundStyle(Color.white)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unit")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Picker("Unit", selection: $unit) {
                                ForEach(availableUnits, id: \.self) { u in
                                    Text(u).tag(u)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .tint(LiquidGlassTheme.neonCyan)
                        }
                    }

                    // Notes Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes (optional)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        TextField("e.g. Take with breakfast", text: $notes)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .foregroundStyle(Color.white)
                    }

                    // Schedule Times
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Schedule Times")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))

                        if !schedules.isEmpty {
                            WrapHStack(items: schedules) { schedule in
                                HStack(spacing: 6) {
                                    Text(schedule.label)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(LiquidGlassTheme.neonCyan)

                                    Button {
                                        schedules.removeAll { $0.hour == schedule.hour && $0.minute == schedule.minute }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                            }
                        }

                        Button {
                            showingTimePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Dose Time")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LiquidGlassTheme.neonCyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(LiquidGlassTheme.neonCyan.opacity(0.6), lineWidth: 1))
                        }
                    }

                    // Active Toggle
                    Toggle("Active Medication", isOn: $isActive)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                    Button("Save Medication") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(name.trimmingCharacters(in: .whitespaces), amount, unit, type, isActive, notes, schedules)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : LiquidGlassTheme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .navigationTitle(existing != nil ? "Edit Medication" : "New Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .background(MeshGradientBackground())
            .onAppear {
                if let ex = existing {
                    name = ex.name
                    amount = ex.amount
                    unit = ex.unit.isEmpty ? (ex.type.units.first ?? "") : ex.unit
                    type = ex.type
                    isActive = ex.isActive
                    notes = ex.notes
                    schedules = ex.schedules
                } else {
                    unit = type.units.first ?? ""
                }
            }
            .sheet(isPresented: $showingTimePicker) {
                NavigationStack {
                    VStack(spacing: 20) {
                        DatePicker("Select Time", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()

                        Button("Add Time") {
                            let cal = Calendar.current
                            let h = cal.component(.hour, from: pickedTime)
                            let m = cal.component(.minute, from: pickedTime)
                            let newSchedule = MedicationSchedule(hour: h, minute: m)
                            if !schedules.contains(where: { $0.hour == h && $0.minute == m }) {
                                schedules.append(newSchedule)
                                schedules.sort { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }
                            }
                            showingTimePicker = false
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LiquidGlassTheme.neonCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(20)
                    .navigationTitle("Add Dose Time")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingTimePicker = false }
                        }
                    }
                    .background(MeshGradientBackground())
                }
                .presentationDetents([.height(320)])
            }
        }
    }
}

// Helper view to layout schedules in a wrapping horizontal grid
private struct WrapHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}
