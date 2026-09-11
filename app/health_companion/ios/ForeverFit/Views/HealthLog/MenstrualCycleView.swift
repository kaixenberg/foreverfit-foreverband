import SwiftUI

public struct MenstrualCycleView: View {
    @ObservedObject var dataStore: HealthDataStore

    @State private var showingAddPeriod: Bool = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(4 * 86400)
    @State private var hasEndDate: Bool = true
    @State private var flow: String = "Medium"
    @State private var notes: String = ""

    private let flowOptions = ["Light", "Medium", "Heavy"]

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Prediction & Stats Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.pink)
                        Text("Cycle Insights")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                        Spacer()
                    }

                    if let avg = dataStore.averageCycleLengthDays {
                        Text("Average cycle length: **\(Int(avg)) days**")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }

                    if let next = dataStore.predictedNextPeriod {
                        Text("Predicted next period: **\(next.formatted(date: .abbreviated, time: .omitted))**")
                            .font(.system(size: 13))
                            .foregroundStyle(LiquidGlassTheme.neonCyan)
                    }

                    if dataStore.averageCycleLengthDays == nil {
                        Text("Log at least two periods to calculate cycle length predictions.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                // Period Log Entries
                if dataStore.menstrualCycleEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.pink.opacity(0.4))
                        Text("No period entries logged yet.\nTap 'Log Period' below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dataStore.menstrualCycleEntries) { entry in
                            HStack(spacing: 14) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.pink)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(entry.startDate.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Color.white)

                                        if let end = entry.endDate {
                                            let days = Calendar.current.dateComponents([.day], from: entry.startDate, to: end).day ?? 0
                                            Text("– \(end.formatted(date: .abbreviated, time: .omitted)) (\(days + 1) d)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.white.opacity(0.7))
                                        }
                                    }

                                    if let fl = entry.flow {
                                        Text("Flow: \(fl)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.6))
                                    }
                                }

                                Spacer()

                                Button {
                                    dataStore.deleteCycleEntry(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        }
                    }
                }

                Button {
                    showingAddPeriod = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log Period")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .navigationTitle("Menstrual Cycle")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .sheet(isPresented: $showingAddPeriod) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .colorScheme(.dark)

                    Toggle("Has End Date", isOn: $hasEndDate)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .colorScheme(.dark)
                    }

                    Picker("Flow", selection: $flow) {
                        ForEach(flowOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(4)

                    TextField("Notes (optional)", text: $notes)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .foregroundStyle(Color.white)

                    Spacer()

                    Button("Save Period") {
                        dataStore.addCycleEntry(
                            startDate: startDate,
                            endDate: hasEndDate ? endDate : nil,
                            flow: flow,
                            notes: notes.isEmpty ? nil : notes
                        )
                        showingAddPeriod = false
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(20)
                .navigationTitle("Log Period")
                .navigationBarTitleDisplayMode(.inline)
                .background(MeshGradientBackground())
            }
        }
    }
}
