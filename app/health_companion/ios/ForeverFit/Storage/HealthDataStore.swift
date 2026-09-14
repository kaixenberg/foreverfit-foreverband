import Foundation
import Combine

@MainActor
public final class HealthDataStore: ObservableObject {
    // MARK: - Published Stores
    @Published public var userProfile: UserProfile
    @Published public var medicalId: MedicalId
    @Published public var watchSettings: WatchSettings

    // App Preferences
    @Published public var unitSystem: UnitSystem = .system
    @Published public var themeMode: AppThemeMode = .system
    @Published public var oledBlack: Bool = false
    @Published public var ambientSourcePreference: AmbientSourcePreference = .preferWearable
    @Published public var notifyVitals: Bool = true
    @Published public var notifyHazards: Bool = true
    @Published public var notifyReminders: Bool = true
    @Published public var fallDetectionEnabled: Bool = true

    // Emergency Contact Settings
    @Published public var emergencyContactName: String = ""
    @Published public var emergencyContactPhone: String = ""
    @Published public var customEmergencyNumber: String = "112"
    @Published public var mockMode: Bool = true
    @Published public var mockAnswerOnAttempt: Int? = 2

    // Health Metric Logs
    @Published public var bloodPressureEntries: [BloodPressureEntry] = []
    @Published public var bloodGlucoseEntries: [BloodGlucoseEntry] = []
    @Published public var bodyMeasurementEntries: [BodyMeasurementEntry] = []
    @Published public var hydrationEntries: [HydrationEntry] = []
    @Published public var insulinEntries: [InsulinEntry] = []
    @Published public var sleepEntries: [SleepEntry] = []
    @Published public var medications: [Medication] = []
    @Published public var medicationDoses: [MedicationDose] = []
    @Published public var menstrualCycleEntries: [MenstrualCycleEntry] = []
    @Published public var vitalsHistory: [VitalsReading] = []

    private let userDefaults = UserDefaults.standard

    public init() {
        self.userProfile = UserProfile()
        self.medicalId = MedicalId()
        self.watchSettings = WatchSettings.defaults
        loadAll()
    }

    // MARK: - Persistence

    private func loadAll() {
        if let data = userDefaults.data(forKey: "user_profile"), let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.userProfile = p
        }
        if let data = userDefaults.data(forKey: "medical_id"), let m = try? JSONDecoder().decode(MedicalId.self, from: data) {
            self.medicalId = m
        }
        if let data = userDefaults.data(forKey: "watch_settings"), let w = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            self.watchSettings = w
        }

        if let u = userDefaults.string(forKey: "unit_system"), let parsed = UnitSystem(rawValue: u) {
            self.unitSystem = parsed
        }
        if let t = userDefaults.string(forKey: "theme_mode"), let parsed = AppThemeMode(rawValue: t) {
            self.themeMode = parsed
        }
        self.oledBlack = userDefaults.bool(forKey: "oled_black")
        if let a = userDefaults.string(forKey: "ambient_pref"), let parsed = AmbientSourcePreference(rawValue: a) {
            self.ambientSourcePreference = parsed
        }
        self.notifyVitals = userDefaults.object(forKey: "notify_vitals") as? Bool ?? true
        self.notifyHazards = userDefaults.object(forKey: "notify_hazards") as? Bool ?? true
        self.notifyReminders = userDefaults.object(forKey: "notify_reminders") as? Bool ?? true
        self.fallDetectionEnabled = userDefaults.object(forKey: "fall_detection_enabled") as? Bool ?? true

        self.emergencyContactName = userDefaults.string(forKey: "emergency_name") ?? ""
        self.emergencyContactPhone = userDefaults.string(forKey: "emergency_phone") ?? ""
        self.customEmergencyNumber = userDefaults.string(forKey: "custom_emergency_number") ?? "112"
        self.mockMode = userDefaults.object(forKey: "mock_mode") as? Bool ?? true
        self.mockAnswerOnAttempt = userDefaults.object(forKey: "mock_attempt") as? Int ?? 2

        if let data = userDefaults.data(forKey: "bp_entries"), let b = try? JSONDecoder().decode([BloodPressureEntry].self, from: data) {
            self.bloodPressureEntries = b
        }
        if let data = userDefaults.data(forKey: "glucose_entries"), let g = try? JSONDecoder().decode([BloodGlucoseEntry].self, from: data) {
            self.bloodGlucoseEntries = g
        }
        if let data = userDefaults.data(forKey: "body_entries"), let b = try? JSONDecoder().decode([BodyMeasurementEntry].self, from: data) {
            self.bodyMeasurementEntries = b
        }
        if let data = userDefaults.data(forKey: "hydration_entries"), let h = try? JSONDecoder().decode([HydrationEntry].self, from: data) {
            self.hydrationEntries = h
        }
        if let data = userDefaults.data(forKey: "insulin_entries"), let i = try? JSONDecoder().decode([InsulinEntry].self, from: data) {
            self.insulinEntries = i
        }
        if let data = userDefaults.data(forKey: "sleep_entries"), let s = try? JSONDecoder().decode([SleepEntry].self, from: data) {
            self.sleepEntries = s
        }
        if let data = userDefaults.data(forKey: "medications"), let m = try? JSONDecoder().decode([Medication].self, from: data) {
            self.medications = m
        }
        if let data = userDefaults.data(forKey: "medication_doses"), let d = try? JSONDecoder().decode([MedicationDose].self, from: data) {
            self.medicationDoses = d
        }
        if let data = userDefaults.data(forKey: "cycle_entries"), let c = try? JSONDecoder().decode([MenstrualCycleEntry].self, from: data) {
            self.menstrualCycleEntries = c
        }

        // Initialize default sample data if fresh install
        if bodyMeasurementEntries.isEmpty {
            bodyMeasurementEntries.append(BodyMeasurementEntry(weightKg: 70.0, heightCm: 175.0))
        }
    }

    // MARK: - Mutators

    public func saveUserProfile(_ profile: UserProfile) {
        self.userProfile = profile
        if let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: "user_profile")
        }
    }

    public func saveMedicalId(_ medId: MedicalId) {
        self.medicalId = medId
        if let data = try? JSONEncoder().encode(medId) {
            userDefaults.set(data, forKey: "medical_id")
        }
    }

    public func saveWatchSettings(_ settings: WatchSettings) {
        self.watchSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: "watch_settings")
        }
    }

    public func setUnitSystem(_ system: UnitSystem) {
        self.unitSystem = system
        userDefaults.set(system.rawValue, forKey: "unit_system")
    }

    public func setThemeMode(_ mode: AppThemeMode) {
        self.themeMode = mode
        userDefaults.set(mode.rawValue, forKey: "theme_mode")
    }

    public func setOledBlack(_ val: Bool) {
        self.oledBlack = val
        userDefaults.set(val, forKey: "oled_black")
    }

    public func setAmbientSourcePreference(_ pref: AmbientSourcePreference) {
        self.ambientSourcePreference = pref
        userDefaults.set(pref.rawValue, forKey: "ambient_pref")
    }

    public func setNotifyVitals(_ val: Bool) {
        self.notifyVitals = val
        userDefaults.set(val, forKey: "notify_vitals")
    }

    public func setNotifyHazards(_ val: Bool) {
        self.notifyHazards = val
        userDefaults.set(val, forKey: "notify_hazards")
    }

    public func setNotifyReminders(_ val: Bool) {
        self.notifyReminders = val
        userDefaults.set(val, forKey: "notify_reminders")
    }

    public func setFallDetectionEnabled(_ val: Bool) {
        self.fallDetectionEnabled = val
        userDefaults.set(val, forKey: "fall_detection_enabled")
    }

    public func saveEmergencyContact(name: String, phone: String, customNumber: String? = nil) {
        self.emergencyContactName = name
        self.emergencyContactPhone = phone
        userDefaults.set(name, forKey: "emergency_name")
        userDefaults.set(phone, forKey: "emergency_phone")
        if let num = customNumber {
            self.customEmergencyNumber = num
            userDefaults.set(num, forKey: "custom_emergency_number")
        }
    }

    public func setMockMode(_ val: Bool) {
        self.mockMode = val
        userDefaults.set(val, forKey: "mock_mode")
    }

    public func setMockAnswerOnAttempt(_ attempt: Int?) {
        self.mockAnswerOnAttempt = attempt
        userDefaults.set(attempt, forKey: "mock_attempt")
    }

    // Health Entries
    public func addBloodPressure(systolic: Int, diastolic: Int, date: Date = Date()) {
        let entry = BloodPressureEntry(timestamp: date, systolic: systolic, diastolic: diastolic)
        bloodPressureEntries.insert(entry, at: 0)
        saveList(bloodPressureEntries, key: "bp_entries")
    }

    public func addBloodGlucose(mgDl: Double, date: Date = Date()) {
        let entry = BloodGlucoseEntry(timestamp: date, glucoseMgDl: mgDl)
        bloodGlucoseEntries.insert(entry, at: 0)
        saveList(bloodGlucoseEntries, key: "glucose_entries")
    }

    public func addWeightKg(_ kg: Double) {
        let h = latestHeightCm
        let entry = BodyMeasurementEntry(weightKg: kg, heightCm: h)
        bodyMeasurementEntries.insert(entry, at: 0)
        saveList(bodyMeasurementEntries, key: "body_entries")
    }

    public func addHeightCm(_ cm: Double) {
        let w = latestWeightKg
        let entry = BodyMeasurementEntry(weightKg: w, heightCm: cm)
        bodyMeasurementEntries.insert(entry, at: 0)
        saveList(bodyMeasurementEntries, key: "body_entries")
    }

    public func addHydration(ml: Double) {
        let entry = HydrationEntry(amountMl: ml)
        hydrationEntries.insert(entry, at: 0)
        saveList(hydrationEntries, key: "hydration_entries")
    }

    public func addInsulin(units: Double) {
        let entry = InsulinEntry(doseUnits: units)
        insulinEntries.insert(entry, at: 0)
        saveList(insulinEntries, key: "insulin_entries")
    }

    public func addSleep(hours: Double) {
        let entry = SleepEntry(hoursSlept: hours)
        sleepEntries.insert(entry, at: 0)
        saveList(sleepEntries, key: "sleep_entries")
    }

    public func addMedication(name: String, dosage: String, frequency: String) {
        let med = Medication(name: name, dosage: dosage, frequency: frequency)
        medications.append(med)
        saveList(medications, key: "medications")
    }

    public func removeMedication(id: UUID) {
        medications.removeAll { $0.id == id }
        saveList(medications, key: "medications")
    }

    public func logMedicationDose(name: String) {
        let dose = MedicationDose(medicationName: name)
        medicationDoses.insert(dose, at: 0)
        saveList(medicationDoses, key: "medication_doses")
    }

    public func addCycleEntry(startDate: Date, endDate: Date?, flow: String?, notes: String?) {
        let entry = MenstrualCycleEntry(startDate: startDate, endDate: endDate, flow: flow, notes: notes)
        menstrualCycleEntries.insert(entry, at: 0)
        menstrualCycleEntries.sort { $0.startDate > $1.startDate }
        saveList(menstrualCycleEntries, key: "cycle_entries")
    }

    public func deleteCycleEntry(id: UUID) {
        menstrualCycleEntries.removeAll { $0.id == id }
        saveList(menstrualCycleEntries, key: "cycle_entries")
    }

    public func recordVitalsSample(_ vitals: VitalsReading) {
        guard vitals.fingerPresent else { return }
        vitalsHistory.append(vitals)
        if vitalsHistory.count > 500 {
            vitalsHistory.removeFirst()
        }
    }

    private func saveList<T: Encodable>(_ list: [T], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            userDefaults.set(data, forKey: key)
        }
    }

    // MARK: - Computed Properties

    public var todayHydrationMl: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return hydrationEntries
            .filter { $0.timestamp >= startOfDay }
            .reduce(0.0) { $0 + $1.amountMl }
    }

    public var dosesTakenToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return medicationDoses.filter { $0.timestamp >= startOfDay }.count
    }

    public var latestBloodPressure: (Int, Int)? {
        guard let first = bloodPressureEntries.first else { return nil }
        return (first.systolic, first.diastolic)
    }

    public var latestGlucose: Double? {
        bloodGlucoseEntries.first?.glucoseMgDl
    }

    public var latestWeightKg: Double? {
        bodyMeasurementEntries.compactMap(\.weightKg).first
    }

    public var latestHeightCm: Double? {
        bodyMeasurementEntries.compactMap(\.heightCm).first
    }

    public var bmi: Double? {
        HealthCalculations.computeBMI(weightKg: latestWeightKg, heightCm: latestHeightCm)
    }

    public var bodyFatPercent: Double? {
        HealthCalculations.computeBodyFat(bmi: bmi, dateOfBirth: userProfile.dateOfBirth, sex: userProfile.sex)
    }

    public var latestCycleStart: Date? {
        menstrualCycleEntries.first?.startDate
    }

    public var averageCycleLengthDays: Double? {
        guard menstrualCycleEntries.count >= 2 else { return nil }
        var totalDays = 0.0
        var intervals = 0
        for i in 0..<(menstrualCycleEntries.count - 1) {
            let days = Calendar.current.dateComponents([.day], from: menstrualCycleEntries[i + 1].startDate, to: menstrualCycleEntries[i].startDate).day ?? 0
            if days >= 20 && days <= 45 {
                totalDays += Double(days)
                intervals += 1
            }
        }
        guard intervals > 0 else { return 28.0 }
        return totalDays / Double(intervals)
    }

    public var predictedNextPeriod: Date? {
        guard let start = latestCycleStart, let avg = averageCycleLengthDays else { return nil }
        return start.addingTimeInterval(avg * 86400)
    }

    // MARK: - JSON Backup & Restore

    public func exportBackupJson() -> String {
        let payload: [String: Any] = [
            "appVersion": "1.0.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "userProfile": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(userProfile))) ?? [:],
            "medicalId": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(medicalId))) ?? [:],
            "bpEntries": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(bloodPressureEntries))) ?? [],
            "glucoseEntries": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(bloodGlucoseEntries))) ?? [],
            "bodyEntries": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(bodyMeasurementEntries))) ?? [],
            "hydrationEntries": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(hydrationEntries))) ?? [],
            "medications": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(medications))) ?? [],
            "cycleEntries": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(menstrualCycleEntries))) ?? []
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    public func importBackupJson(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let profileDict = dict["userProfile"], let pData = try? JSONSerialization.data(withJSONObject: profileDict),
           let p = try? JSONDecoder().decode(UserProfile.self, from: pData) {
            saveUserProfile(p)
        }
        if let medDict = dict["medicalId"], let mData = try? JSONSerialization.data(withJSONObject: medDict),
           let m = try? JSONDecoder().decode(MedicalId.self, from: mData) {
            saveMedicalId(m)
        }
        if let bpList = dict["bpEntries"], let bData = try? JSONSerialization.data(withJSONObject: bpList),
           let b = try? JSONDecoder().decode([BloodPressureEntry].self, from: bData) {
            self.bloodPressureEntries = b
            saveList(b, key: "bp_entries")
        }
        if let gList = dict["glucoseEntries"], let gData = try? JSONSerialization.data(withJSONObject: gList),
           let g = try? JSONDecoder().decode([BloodGlucoseEntry].self, from: gData) {
            self.bloodGlucoseEntries = g
            saveList(g, key: "glucose_entries")
        }
        return true
    }
}
