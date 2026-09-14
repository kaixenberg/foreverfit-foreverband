import SwiftUI

public struct HealthLogView: View {
    @ObservedObject var dataStore: HealthDataStore
    @ObservedObject var bleManager: ForeverBandBLEManager
    @ObservedObject var pedometerService: PedometerService

    @State private var showingAddBPSheet = false
    @State private var showingAddGlucoseSheet = false
    @State private var showingAddWeightSheet = false
    @State private var showingAddHydrationSheet = false
    @State private var showingAddInsulinSheet = false
    @State private var showingAddSleepSheet = false
    @State private var pdfDataToShare: Data?
    @State private var showingShareSheet = false

    public init(dataStore: HealthDataStore, bleManager: ForeverBandBLEManager, pedometerService: PedometerService) {
        self.dataStore = dataStore
        self.bleManager = bleManager
        self.pedometerService = pedometerService
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Header
                headerSection

                // Medical ID Card
                MedicalIdView(dataStore: dataStore)

                // Body Composition Card
                bodyCompositionSection

                // Quick Log Action Chips
                quickLogActions

                // Hydration Tracker Card
                hydrationCard

                // Navigation to Medications & Cycle
                medsAndCycleSection

                // Blood Pressure Section
                bloodPressureSection

                // Blood Glucose Section
                bloodGlucoseSection

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .sheet(isPresented: $showingAddBPSheet) {
            AddBloodPressureSheet(dataStore: dataStore)
        }
        .sheet(isPresented: $showingAddGlucoseSheet) {
            AddBloodGlucoseSheet(dataStore: dataStore)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = pdfDataToShare {
                ShareSheet(items: [data])
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLINICAL LOGS & RECORDS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(LiquidGlassTheme.neonCyan)

                Text("Health Log")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            Spacer()

            // Export Clinical PDF Button
            Button {
                exportPdfReport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                    Text("PDF Report")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(LiquidGlassTheme.neonCyan)
                .clipShape(Capsule())
            }
        }
    }

    private var bodyCompositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body Composition")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)

            HStack(spacing: 12) {
                statBox(title: "BMI", value: dataStore.bmi != nil ? String(format: "%.1f", dataStore.bmi!) : "--", category: "Calculated")
                statBox(title: "Body Fat", value: dataStore.bodyFatPercent != nil ? "\(Int(dataStore.bodyFatPercent!))%" : "--", category: "Deurenberg")
                statBox(title: "Weight", value: dataStore.latestWeightKg != nil ? String(format: "%.1f kg", dataStore.latestWeightKg!) : "--", category: "\(Int(dataStore.latestHeightCm ?? 175)) cm")
            }
        }
    }

    private func statBox(title: String, value: String, category: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            Text(category)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LiquidGlassTheme.emeraldGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    private var quickLogActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickLogButton(label: "+ Log BP", icon: "heart.text.square.fill") {
                    showingAddBPSheet = true
                }
                quickLogButton(label: "+ Log Glucose", icon: "drop.triangle.fill") {
                    showingAddGlucoseSheet = true
                }
                quickLogButton(label: "+250ml Water", icon: "drop.fill") {
                    dataStore.addHydration(ml: 250)
                }
                quickLogButton(label: "+500ml Water", icon: "drop.fill") {
                    dataStore.addHydration(ml: 500)
                }
            }
        }
    }

    private func quickLogButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        }
    }

    private var hydrationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "drop.fill")
                .font(.system(size: 26))
                .foregroundStyle(LiquidGlassTheme.neonCyan)

            VStack(alignment: .leading, spacing: 2) {
                let hyd = UnitFormatter.formatHydrationMl(dataStore.todayHydrationMl, system: dataStore.unitSystem)
                Text("Hydration Today: \(hyd.value.formatted()) \(hyd.unit)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Daily target: ~2.5 L to prevent heat-stress and vital anomalies.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }

    private var medsAndCycleSection: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: MedicationsView(dataStore: dataStore)) {
                HStack(spacing: 10) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medications")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("\(dataStore.medications.count) tracked")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            if dataStore.userProfile.sex != "Male" {
                NavigationLink(destination: MenstrualCycleView(dataStore: dataStore)) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cycle Log")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text(dataStore.latestCycleStart != nil ? "Tracked" : "No entries")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bloodPressureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Blood Pressure Log")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
                Button("+ Add") { showingAddBPSheet = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
            }

            if dataStore.bloodPressureEntries.isEmpty {
                Text("No blood pressure readings recorded.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(dataStore.bloodPressureEntries.prefix(5)) { bp in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(bp.systolic)/\(bp.diastolic) mmHg")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                Text(bp.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                            Spacer()
                            Text(bpStatus(systolic: bp.systolic, diastolic: bp.diastolic))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(bpColor(systolic: bp.systolic, diastolic: bp.diastolic))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(bpColor(systolic: bp.systolic, diastolic: bp.diastolic).opacity(0.15)))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    }
                }
            }
        }
    }

    private var bloodGlucoseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Blood Glucose Log")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
                Button("+ Add") { showingAddGlucoseSheet = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
            }

            if dataStore.bloodGlucoseEntries.isEmpty {
                Text("No blood glucose readings recorded.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(dataStore.bloodGlucoseEntries.prefix(5)) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.0f mg/dL", g.glucoseMgDl))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                Text(g.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                            Spacer()
                            let isNormal = g.glucoseMgDl >= 70 && g.glucoseMgDl <= 140
                            Text(isNormal ? "Normal" : "Review")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isNormal ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.amberWarning)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill((isNormal ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.amberWarning).opacity(0.15)))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    }
                }
            }
        }
    }

    private func bpStatus(systolic: Int, diastolic: Int) -> String {
        if systolic >= 180 || diastolic >= 120 { return "Crisis" }
        if systolic >= 140 || diastolic >= 90 { return "High" }
        if systolic <= 120 && diastolic <= 80 { return "Optimal" }
        return "Elevated"
    }

    private func bpColor(systolic: Int, diastolic: Int) -> Color {
        if systolic >= 180 || diastolic >= 120 { return LiquidGlassTheme.alertCrimson }
        if systolic >= 140 || diastolic >= 90 { return LiquidGlassTheme.amberWarning }
        return LiquidGlassTheme.emeraldGreen
    }

    private func exportPdfReport() {
        let pdfData = PDFReportGenerator.generateClinicalReport(
            userProfile: dataStore.userProfile,
            medicalId: dataStore.medicalId,
            vitalsHistory: dataStore.vitalsHistory,
            bpEntries: dataStore.bloodPressureEntries,
            glucoseEntries: dataStore.bloodGlucoseEntries,
            todaySteps: pedometerService.todaySteps
        )
        self.pdfDataToShare = pdfData
        self.showingShareSheet = true
    }
}
