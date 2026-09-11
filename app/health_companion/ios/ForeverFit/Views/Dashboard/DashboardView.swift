import SwiftUI

public struct DashboardView: View {
    @ObservedObject var bleManager: ForeverBandBLEManager
    @ObservedObject var fallDetector: FallDetectorService
    @ObservedObject var motionService: PhoneMotionService
    @ObservedObject var pedometerService: PedometerService
    @ObservedObject var baselineService: BaselineService
    @ObservedObject var disasterService: DisasterService
    @ObservedObject var dataStore: HealthDataStore

    @Binding var selectedTab: AppTab

    @State private var showingScanConnect: Bool = false
    @State private var showingWatchSettings: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingWellnessDetail: Bool = false
    @State private var showingAiChat: Bool = false
    @State private var selectedMetricDetail: String? = nil

    public init(
        bleManager: ForeverBandBLEManager,
        fallDetector: FallDetectorService,
        motionService: PhoneMotionService,
        pedometerService: PedometerService,
        baselineService: BaselineService,
        disasterService: DisasterService,
        dataStore: HealthDataStore,
        selectedTab: Binding<AppTab>
    ) {
        self.bleManager = bleManager
        self.fallDetector = fallDetector
        self.motionService = motionService
        self.pedometerService = pedometerService
        self.baselineService = baselineService
        self.disasterService = disasterService
        self.dataStore = dataStore
        self._selectedTab = selectedTab
    }

    private var isConnected: Bool {
        bleManager.status == .connected
    }

    private var vitals: VitalsReading? {
        bleManager.latestVitals
    }

    private var hasFingerReading: Bool {
        isConnected && vitals != nil && vitals!.fingerPresent
    }

    private var currentCeiling: Float {
        HealthThresholds.heartRateCeiling(for: motionService.currentActivity)
    }

    private var heartRateWarn: Bool {
        guard let v = vitals, hasFingerReading else { return false }
        return v.heartRate < HealthThresholds.heartRateFloor ||
               v.heartRate > currentCeiling ||
               baselineService.isAnomalous(v.heartRate)
    }

    private var spo2Warn: Bool {
        guard let v = vitals, hasFingerReading else { return false }
        return v.spo2 > 0 && v.spo2 < HealthThresholds.spo2FloorPercent
    }

    private var bodyTempWarn: Bool {
        guard let v = vitals, hasFingerReading else { return false }
        return v.bodyTempC > HealthThresholds.bodyTempHighC || v.bodyTempC < HealthThresholds.bodyTempLowC
    }

    private var resolvedAmbientTemp: Float? {
        let preferWearable = dataStore.ambientSourcePreference == .preferWearable
        if preferWearable {
            return bleManager.latestEnv?.ambientTempC ?? Float(disasterService.weather.temperatureC)
        } else {
            return Float(disasterService.weather.temperatureC)
        }
    }

    private var resolvedHumidity: Float? {
        let preferWearable = dataStore.ambientSourcePreference == .preferWearable
        if preferWearable {
            return bleManager.latestEnv?.humidity ?? Float(disasterService.weather.relativeHumidity)
        } else {
            return Float(disasterService.weather.relativeHumidity)
        }
    }

    private var resolvedPressure: Float? {
        let preferWearable = dataStore.ambientSourcePreference == .preferWearable
        if preferWearable {
            return bleManager.latestEnv?.pressureHPa ?? Float(disasterService.weather.pressureHPa)
        } else {
            return Float(disasterService.weather.pressureHPa)
        }
    }

    private var ambientWarn: Bool {
        guard let temp = resolvedAmbientTemp, let hum = resolvedHumidity else { return false }
        let idx = HeatIndex.compute(tempC: Double(temp), relativeHumidity: Double(hum))
        let risk = HeatIndex.stressLevel(heatIndexC: idx)
        return risk == .danger || risk == .extremeDanger
    }

    private var heatStressWarn: Bool {
        guard let temp = resolvedAmbientTemp, let hum = resolvedHumidity, let v = vitals, hasFingerReading else { return false }
        let idx = HeatIndex.compute(tempC: Double(temp), relativeHumidity: Double(hum))
        let risk = HeatIndex.stressLevel(heatIndexC: idx)
        return (risk == .caution || risk == .extremeCaution || risk == .danger) && v.bodyTempC > HealthThresholds.bodyTempHighC
    }

    private var wellnessScore: Int? {
        HealthThresholds.computeWellnessScore(
            hasVitals: hasFingerReading,
            heartRateWarn: heartRateWarn,
            spo2Warn: spo2Warn,
            bodyTempWarn: bodyTempWarn,
            ambientWarn: ambientWarn,
            heatStressWarn: heatStressWarn
        )
    }

    private var wellnessSnapshot: WellnessSnapshot {
        HealthThresholds.buildWellnessSnapshot(
            score: wellnessScore,
            hasFingerReading: hasFingerReading,
            heartRate: vitals?.heartRate ?? 0,
            heartRateCeiling: currentCeiling,
            heartRateWarn: heartRateWarn,
            spo2: vitals?.spo2 ?? 0,
            spo2Warn: spo2Warn,
            bodyTemp: vitals?.bodyTempC ?? 0,
            bodyTempWarn: bodyTempWarn,
            ambientWarn: ambientWarn,
            heatStressWarn: heatStressWarn
        )
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Top Bar
                    topBar

                    // Emergency Alert Banner (if fall / SOS active)
                    EmergencyAlertBanner(fallDetector: fallDetector)

                    // Connect Wearable Banner (if disconnected)
                    if !isConnected {
                        connectWearableBanner
                    }

                    // Insights Section
                    insightsSection

                    // Disaster & Hazard Map Nav Card
                    disasterNavCard

                    // 1. Live Vitals Grid
                    liveVitalsGrid

                    // 2. Wellness Overview Row
                    wellnessOverviewRow

                    // 3. Body & Activity Paged Grid
                    bodyAndActivitySection

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Floating AI Assistant Bubble
            floatingAiBubble
                .padding(.trailing, 20)
                .padding(.bottom, 90)
        }
        .sheet(isPresented: $showingScanConnect) {
            ScanConnectView(bleManager: bleManager)
        }
        .sheet(isPresented: $showingWatchSettings) {
            WearableSettingsView(bleManager: bleManager, dataStore: dataStore)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(dataStore: dataStore, bleManager: bleManager, fallDetector: fallDetector)
        }
        .sheet(isPresented: $showingWellnessDetail) {
            WellnessDetailView(snapshot: wellnessSnapshot)
        }
        .sheet(isPresented: Binding(
            get: { selectedMetricDetail != nil },
            set: { if !$0 { selectedMetricDetail = nil } }
        )) {
            if let metric = selectedMetricDetail {
                MetricDetailView(
                    metricName: metric,
                    vitals: bleManager.latestVitals,
                    history: dataStore.vitalsHistory,
                    baseline: baselineService
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ForeverFit")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.amberWarning)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "FOREVERBAND CONNECTED" : "WEARABLE DISCONNECTED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // Manual SOS Button
                Button {
                    fallDetector.triggerManualSOS()
                } label: {
                    Image(systemName: "sos")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(LiquidGlassTheme.alertCrimson.opacity(0.6), lineWidth: 1.2))
                }

                // Bluetooth Connect / Disconnect Button
                Button {
                    if isConnected {
                        bleManager.disconnect()
                    } else {
                        showingScanConnect = true
                    }
                } label: {
                    Image(systemName: isConnected ? "antenna.radiowaves.left.and.right" : "sparkle.magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isConnected ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Watch Settings Button
                Button {
                    showingWatchSettings = true
                } label: {
                    Image(systemName: "applewatch")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Settings Button
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connect Wearable Banner

    private var connectWearableBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(LiquidGlassTheme.amberWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wearable not connected")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Vitals and environment readings need the wearable.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()

            Button {
                showingScanConnect = true
            } label: {
                Text("Connect")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(LiquidGlassTheme.neonCyan)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LiquidGlassTheme.amberWarning.opacity(0.5), lineWidth: 1)
                }
        }
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        let insights = InsightEngine.computeInsights(
            vitals: vitals,
            env: bleManager.latestEnv,
            weather: disasterService.weather,
            activity: motionService.currentActivity,
            baselineHeartRateMean: baselineService.heartRateMean,
            latestBP: dataStore.latestBloodPressure,
            latestGlucose: dataStore.latestGlucose,
            latestSleep: dataStore.sleepEntries.first?.hoursSlept,
            pressureTrendHPa: disasterService.pressureTrendHPa,
            earthquakesCount: disasterService.recentEarthquakes.count,
            aqi: Int(disasterService.airQuality.usAqi)
        )

        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clinical & Environmental Insights")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    VStack(spacing: 8) {
                        ForEach(insights) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.iconName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(severityColor(item.severity))
                                    .frame(width: 28, height: 28)
                                    .background(severityColor(item.severity).opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text(item.message)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.white.opacity(0.75))
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        }
                    }
                }
            }
        }
    }

    private func severityColor(_ sev: InsightSeverity) -> Color {
        switch sev {
        case .critical: return LiquidGlassTheme.alertCrimson
        case .warning: return LiquidGlassTheme.amberWarning
        case .info: return LiquidGlassTheme.neonCyan
        }
    }

    // MARK: - Disaster Nav Card

    private var disasterNavCard: some View {
        Button {
            selectedTab = .disaster
        } label: {
            HStack(spacing: 12) {
                Image(systemName: disasterService.activeWarnings.isEmpty ? "map.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(disasterService.activeWarnings.isEmpty ? LiquidGlassTheme.neonCyan : LiquidGlassTheme.alertCrimson)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Disaster & Safety Radar")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text(disasterService.activeWarnings.first?.headline ?? "GPS-based earthquake, flood, and cyclone risk for your area")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                (disasterService.activeWarnings.isEmpty ? LiquidGlassTheme.neonCyan : LiquidGlassTheme.alertCrimson).opacity(0.4),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 1. Live Vitals Grid

    private var liveVitalsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vital Telemetry")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // Heart Rate
                let hrVal = hasFingerReading ? String(format: "%.0f", vitals!.heartRate) : "--"
                let hrUnit = (isConnected && vitals != nil && !vitals!.fingerPresent) ? "no finger" : "bpm"
                MetricCardView(
                    icon: "heart.fill",
                    iconColor: LiquidGlassTheme.alertCrimson,
                    title: "Heart rate",
                    value: hrVal,
                    unit: hrUnit,
                    warn: heartRateWarn,
                    onTap: { selectedMetricDetail = "Heart Rate" }
                )

                // SpO2
                let spo2Val = hasFingerReading ? String(format: "%.0f", vitals!.spo2) : "--"
                let spo2Unit = (isConnected && vitals != nil && !vitals!.fingerPresent) ? "no finger" : "%"
                MetricCardView(
                    icon: "lungs.fill",
                    iconColor: LiquidGlassTheme.neonCyan,
                    title: "SpO2",
                    value: spo2Val,
                    unit: spo2Unit,
                    warn: spo2Warn,
                    onTap: { selectedMetricDetail = "Blood Oxygen (SpO2)" }
                )

                // Body Temp
                let tempVal = hasFingerReading
                    ? UnitFormatter.formatTemperatureC(Double(vitals!.bodyTempC), system: dataStore.unitSystem).value.formatted()
                    : "--"
                let tempUnit = (isConnected && vitals != nil && !vitals!.fingerPresent)
                    ? "no finger"
                    : UnitFormatter.temperatureUnit(dataStore.unitSystem)
                MetricCardView(
                    icon: "thermometer.medium",
                    iconColor: LiquidGlassTheme.amberWarning,
                    title: "Body temp",
                    value: tempVal,
                    unit: tempUnit,
                    warn: bodyTempWarn,
                    onTap: { selectedMetricDetail = "Body Temperature" }
                )

                // Ambient Temp
                let ambVal = resolvedAmbientTemp != nil
                    ? UnitFormatter.formatTemperatureC(Double(resolvedAmbientTemp!), system: dataStore.unitSystem).value.formatted()
                    : "--"
                let ambUnit = resolvedAmbientTemp != nil
                    ? UnitFormatter.formatTemperatureC(Double(resolvedAmbientTemp!), system: dataStore.unitSystem).unit
                    : ""
                MetricCardView(
                    icon: "sun.max.fill",
                    iconColor: LiquidGlassTheme.amberWarning,
                    title: "Ambient temp",
                    value: ambVal,
                    unit: ambUnit,
                    warn: ambientWarn
                )

                // Humidity
                let humVal = resolvedHumidity != nil ? String(format: "%.0f", resolvedHumidity!) : "--"
                MetricCardView(
                    icon: "humidity.fill",
                    iconColor: LiquidGlassTheme.neonCyan,
                    title: "Humidity",
                    value: humVal,
                    unit: resolvedHumidity != nil ? "%" : ""
                )

                // Pressure
                let presVal = resolvedPressure != nil ? String(format: "%.0f", resolvedPressure!) : "--"
                MetricCardView(
                    icon: "barometer",
                    iconColor: Color.purple,
                    title: "Pressure",
                    value: presVal,
                    unit: resolvedPressure != nil ? "hPa" : ""
                )
            }
        }
    }

    // MARK: - 2. Wellness Overview Row

    private var wellnessOverviewRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wellness Overview")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Wellness Score Card
                    Button {
                        showingWellnessDetail = true
                    } label: {
                        HStack(spacing: 14) {
                            WellnessScoreRing(score: wellnessScore)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wellness")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text(wellnessScore != nil ? "\(wellnessScore!)/100" : "No vitals")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.white)
                                Text("Tap for breakdown")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.6))
                            }
                        }
                        .padding(14)
                        .frame(width: 190, height: 110)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)

                    // Current Activity Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                            Spacer()
                        }
                        Spacer()
                        Text("Activity")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text(motionService.currentActivity.rawValue.capitalized)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .padding(14)
                    .frame(width: 140, height: 110)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                    // Baseline Mean Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(LiquidGlassTheme.neonCyan)
                            Spacer()
                        }
                        Spacer()
                        Text("Baseline HR")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(baselineService.heartRateMean != nil ? String(format: "%.0f", baselineService.heartRateMean!) : "--")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.white)
                            Text("bpm")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    .padding(14)
                    .frame(width: 140, height: 110)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                }
            }
        }
    }

    // MARK: - 3. Body & Activity Section (Paged Grid)

    private var bodyAndActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body & Activity")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // Steps
                MetricCardView(
                    icon: "figure.walk",
                    iconColor: LiquidGlassTheme.emeraldGreen,
                    title: "Steps today",
                    value: "\(pedometerService.todaySteps)",
                    unit: "steps",
                    onTap: { selectedTab = .healthLog }
                )

                // Weight
                let wt = dataStore.latestWeightKg != nil
                    ? UnitFormatter.formatWeightKg(dataStore.latestWeightKg!, system: dataStore.unitSystem).value.formatted()
                    : "--"
                let wtUnit = dataStore.latestWeightKg != nil
                    ? UnitFormatter.formatWeightKg(dataStore.latestWeightKg!, system: dataStore.unitSystem).unit
                    : ""
                MetricCardView(
                    icon: "scalemass.fill",
                    iconColor: LiquidGlassTheme.amberWarning,
                    title: "Weight",
                    value: wt,
                    unit: wtUnit,
                    onTap: { selectedTab = .healthLog }
                )

                // Height
                let ht = dataStore.latestHeightCm != nil
                    ? UnitFormatter.formatHeightCm(dataStore.latestHeightCm!, system: dataStore.unitSystem).value.formatted()
                    : "--"
                let htUnit = dataStore.latestHeightCm != nil
                    ? UnitFormatter.formatHeightCm(dataStore.latestHeightCm!, system: dataStore.unitSystem).unit
                    : ""
                MetricCardView(
                    icon: "ruler.fill",
                    iconColor: Color.purple,
                    title: "Height",
                    value: ht,
                    unit: htUnit,
                    onTap: { selectedTab = .healthLog }
                )

                // BMI
                let bmiVal = dataStore.bmi != nil ? String(format: "%.1f", dataStore.bmi!) : "--"
                MetricCardView(
                    icon: "chart.bar.xaxis",
                    iconColor: LiquidGlassTheme.neonCyan,
                    title: "BMI",
                    value: bmiVal,
                    unit: "",
                    onTap: { selectedTab = .healthLog }
                )

                // Body Fat
                let fatVal = dataStore.bodyFatPercent != nil ? String(format: "%.1f", dataStore.bodyFatPercent!) : "--"
                MetricCardView(
                    icon: "percent",
                    iconColor: LiquidGlassTheme.emeraldGreen,
                    title: "Body fat",
                    value: fatVal,
                    unit: dataStore.bodyFatPercent != nil ? "%" : "",
                    onTap: { selectedTab = .healthLog }
                )

                // Hydration
                let hyd = UnitFormatter.formatHydrationMl(dataStore.todayHydrationMl, system: dataStore.unitSystem)
                MetricCardView(
                    icon: "drop.fill",
                    iconColor: LiquidGlassTheme.neonCyan,
                    title: "Hydration",
                    value: String(format: "%.2f", hyd.value),
                    unit: hyd.unit,
                    onTap: { selectedTab = .healthLog }
                )

                // Blood Pressure
                let bpVal = dataStore.latestBloodPressure != nil ? "\(dataStore.latestBloodPressure!.0)/\(dataStore.latestBloodPressure!.1)" : "--"
                MetricCardView(
                    icon: "heart.text.square.fill",
                    iconColor: LiquidGlassTheme.alertCrimson,
                    title: "Blood pressure",
                    value: bpVal,
                    unit: dataStore.latestBloodPressure != nil ? "mmHg" : "",
                    onTap: { selectedTab = .healthLog }
                )

                // Blood Glucose
                let gluVal = dataStore.latestGlucose != nil ? String(format: "%.0f", dataStore.latestGlucose!) : "--"
                MetricCardView(
                    icon: "drop.triangle.fill",
                    iconColor: Color.purple,
                    title: "Blood glucose",
                    value: gluVal,
                    unit: dataStore.latestGlucose != nil ? "mg/dL" : "",
                    onTap: { selectedTab = .healthLog }
                )

                // Insulin
                let insVal = dataStore.insulinEntries.first != nil ? String(format: "%.1f", dataStore.insulinEntries.first!.doseUnits) : "--"
                MetricCardView(
                    icon: "cross.vial.fill",
                    iconColor: LiquidGlassTheme.emeraldGreen,
                    title: "Insulin",
                    value: insVal,
                    unit: dataStore.insulinEntries.first != nil ? "units" : "",
                    onTap: { selectedTab = .healthLog }
                )

                // Sleep
                let slpVal = dataStore.sleepEntries.first != nil ? String(format: "%.1f", dataStore.sleepEntries.first!.hoursSlept) : "--"
                MetricCardView(
                    icon: "bed.double.fill",
                    iconColor: LiquidGlassTheme.neonCyan,
                    title: "Sleep",
                    value: slpVal,
                    unit: dataStore.sleepEntries.first != nil ? "hrs" : "",
                    onTap: { selectedTab = .healthLog }
                )

                // Medications
                let medVal = dataStore.medications.isEmpty ? "--" : "\(dataStore.medications.count)"
                MetricCardView(
                    icon: "pills.fill",
                    iconColor: LiquidGlassTheme.emeraldGreen,
                    title: "Medications",
                    value: medVal,
                    unit: dataStore.medications.isEmpty ? "" : "tracked",
                    onTap: { selectedTab = .healthLog }
                )

                // Menstrual Cycle (disabled if male)
                let isMale = dataStore.userProfile.sex == "Male"
                let cycleDays: String = {
                    guard !isMale, let start = dataStore.latestCycleStart else { return "--" }
                    let diff = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
                    return "\(diff)"
                }()
                MetricCardView(
                    icon: "calendar",
                    iconColor: Color.pink,
                    title: "Cycle",
                    value: cycleDays,
                    unit: (!isMale && dataStore.latestCycleStart != nil) ? "days ago" : "",
                    onTap: {
                        if !isMale { selectedTab = .healthLog }
                    }
                )
            }
        }
    }

    // MARK: - Floating AI Chat Bubble

    private var floatingAiBubble: some View {
        Button {
            showingAiChat = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                Text("AI Health")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [LiquidGlassTheme.neonCyan, LiquidGlassTheme.electricViolet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: LiquidGlassTheme.neonCyan.opacity(0.5), radius: 10, x: 0, y: 4)
            }
        }
    }
}
