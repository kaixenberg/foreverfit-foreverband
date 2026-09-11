import Foundation

// MARK: - Unit Systems & Conversions (100% Flutter Parity)

public enum UnitSystem: String, Codable, CaseIterable {
    case metric
    case imperial
    case system

    public var displayName: String {
        switch self {
        case .metric: return "Metric (kg, cm, °C)"
        case .imperial: return "Imperial (lb, in, °F)"
        case .system: return "Use device locale"
        }
    }
}

public struct UnitValue {
    public let value: Double
    public let unit: String

    public init(_ value: Double, _ unit: String) {
        self.value = value
        self.unit = unit
    }

    public func toString(decimals: Int = 1) -> String {
        return String(format: "%.\(decimals)f %@", value, unit)
    }
}

public struct UnitFormatter {
    private static let kgToLb = 2.2046226218
    private static let cmToIn = 1.0 / 2.54
    private static let mlToFlOz = 1.0 / 29.5735
    private static let kmhToMph = 1.0 / 1.609344

    public static func resolveEffectiveUnitSystem(_ preference: UnitSystem) -> UnitSystem {
        guard preference == .system else { return preference }
        let countryCode = Locale.current.region?.identifier ?? "US"
        let imperialCodes: Set<String> = ["US", "LR", "MM"]
        return imperialCodes.contains(countryCode) ? .imperial : .metric
    }

    public static func formatWeightKg(_ kg: Double, system: UnitSystem) -> UnitValue {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? UnitValue(kg * kgToLb, "lb") : UnitValue(kg, "kg")
    }

    public static func parseWeightToKg(_ input: Double, system: UnitSystem) -> Double {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? input / kgToLb : input
    }

    public static func formatHeightCm(_ cm: Double, system: UnitSystem) -> UnitValue {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? UnitValue(cm * cmToIn, "in") : UnitValue(cm, "cm")
    }

    public static func parseHeightToCm(_ input: Double, system: UnitSystem) -> Double {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? input / cmToIn : input
    }

    public static func formatHydrationMl(_ ml: Double, system: UnitSystem) -> UnitValue {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? UnitValue(ml * mlToFlOz, "fl oz") : UnitValue(ml / 1000.0, "L")
    }

    public static func parseHydrationToMl(_ input: Double, system: UnitSystem) -> Double {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? input / mlToFlOz : input * 1000.0
    }

    public static func formatTemperatureC(_ c: Double, system: UnitSystem) -> UnitValue {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? UnitValue(c * 9.0 / 5.0 + 32.0, "°F") : UnitValue(c, "°C")
    }

    public static func temperatureUnit(_ system: UnitSystem) -> String {
        resolveEffectiveUnitSystem(system) == .imperial ? "°F" : "°C"
    }

    public static func parseTemperatureToC(_ input: Double, system: UnitSystem) -> Double {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? (input - 32.0) * 5.0 / 9.0 : input
    }

    public static func formatWindSpeedKmh(_ kmh: Double, system: UnitSystem) -> UnitValue {
        let eff = resolveEffectiveUnitSystem(system)
        return eff == .imperial ? UnitValue(kmh * kmhToMph, "mph") : UnitValue(kmh, "km/h")
    }
}

// MARK: - Sensor & Settings Enums

public enum AmbientSourcePreference: String, Codable, CaseIterable {
    case preferWearable
    case preferOnline

    public var title: String {
        switch self {
        case .preferWearable: return "Prefer wearable sensor"
        case .preferOnline: return "Prefer online weather"
        }
    }

    public var subtitle: String {
        switch self {
        case .preferWearable: return "Falls back to online weather if disconnected."
        case .preferOnline: return "Falls back to the wearable sensor if offline."
        }
    }
}

public enum AppThemeMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "Follow system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Health Metric Entries

public struct MetricPoint: Identifiable, Codable {
    public var id: UUID = UUID()
    public let at: Date
    public let value: Double

    public init(id: UUID = UUID(), at: Date, value: Double) {
        self.id = id
        self.at = at
        self.value = value
    }
}

public struct BloodPressureEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let systolic: Int
    public let diastolic: Int

    public init(id: UUID = UUID(), timestamp: Date = Date(), systolic: Int, diastolic: Int) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
    }
}

public struct BloodGlucoseEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let glucoseMgDl: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), glucoseMgDl: Double) {
        self.id = id
        self.timestamp = timestamp
        self.glucoseMgDl = glucoseMgDl
    }
}

public struct BodyMeasurementEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let weightKg: Double?
    public let heightCm: Double?

    public init(id: UUID = UUID(), timestamp: Date = Date(), weightKg: Double?, heightCm: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.weightKg = weightKg
        self.heightCm = heightCm
    }
}

public struct HydrationEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let amountMl: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), amountMl: Double) {
        self.id = id
        self.timestamp = timestamp
        self.amountMl = amountMl
    }
}

public struct InsulinEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let doseUnits: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), doseUnits: Double) {
        self.id = id
        self.timestamp = timestamp
        self.doseUnits = doseUnits
    }
}

public struct SleepEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let hoursSlept: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), hoursSlept: Double) {
        self.id = id
        self.timestamp = timestamp
        self.hoursSlept = hoursSlept
    }
}

public struct Medication: Identifiable, Codable {
    public var id: UUID = UUID()
    public var name: String
    public var dosage: String
    public var frequency: String
    public var dateAdded: Date

    public init(id: UUID = UUID(), name: String, dosage: String, frequency: String, dateAdded: Date = Date()) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.dateAdded = dateAdded
    }
}

public struct MedicationDose: Identifiable, Codable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let medicationName: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), medicationName: String) {
        self.id = id
        self.timestamp = timestamp
        self.medicationName = medicationName
    }
}

public struct MenstrualCycleEntry: Identifiable, Codable {
    public var id: UUID = UUID()
    public var startDate: Date
    public var endDate: Date?
    public var flow: String? // Light, Medium, Heavy
    public var notes: String?

    public init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil, flow: String? = nil, notes: String? = nil) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.flow = flow
        self.notes = notes
    }
}

// MARK: - Medical ID

public struct MedicalId: Codable, Equatable {
    public var bloodType: String
    public var allergies: String
    public var conditions: String
    public var medications: String
    public var notes: String
    public var organDonor: Bool

    public init(
        bloodType: String = "O+",
        allergies: String = "",
        conditions: String = "",
        medications: String = "",
        notes: String = "",
        organDonor: Bool = true
    ) {
        self.bloodType = bloodType
        self.allergies = allergies
        self.conditions = conditions
        self.medications = medications
        self.notes = notes
        self.organDonor = organDonor
    }

    public var isEmpty: Bool {
        bloodType.isEmpty && allergies.isEmpty && conditions.isEmpty && medications.isEmpty && notes.isEmpty
    }
}

// MARK: - Wellness Score & Snapshot

public struct WellnessFactor: Identifiable, Codable {
    public var id: String { label }
    public let label: String
    public let warn: Bool
    public let detail: String

    public init(label: String, warn: Bool, detail: String) {
        self.label = label
        self.warn = warn
        self.detail = detail
    }
}

public struct WellnessSnapshot: Codable {
    public let score: Int?
    public let factors: [WellnessFactor]

    public init(score: Int?, factors: [WellnessFactor]) {
        self.score = score
        self.factors = factors
    }

    public var headline: String {
        guard let score = score else { return "Nothing to score yet" }
        if score >= 90 { return "Optimal condition" }
        if score >= 75 { return "Normal condition" }
        if score >= 50 { return "Moderate stress detected" }
        return "Elevated risk flagged"
    }

    public var summary: String {
        guard let score = score else {
            return "Wearable is not connected or no finger is detected. Put on your ForeverBand to view your live score."
        }
        let warnCount = factors.filter { $0.warn }.count
        if warnCount == 0 {
            return "All vital and environmental signals are currently within healthy clinical reference bounds."
        } else if warnCount == 1 {
            let item = factors.first(where: { $0.warn })?.label ?? "signal"
            return "\(item) is currently flagged outside target parameters. Monitor your reading closely."
        } else {
            return "\(warnCount) signals are currently elevated or outside clinical target ranges."
        }
    }
}

// MARK: - Insights

public enum InsightSeverity: String, Codable {
    case critical
    case warning
    case info
}

public enum InsightCategory: String, Codable {
    case vitals
    case hazards
    case reminders
}

public struct Insight: Identifiable, Codable {
    public let id: String
    public let title: String
    public let message: String
    public let severity: InsightSeverity
    public let category: InsightCategory
    public let iconName: String

    public init(id: String, title: String, message: String, severity: InsightSeverity, category: InsightCategory, iconName: String) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.category = category
        self.iconName = iconName
    }
}

// MARK: - Body Composition Calculations

public struct HealthCalculations {
    public static func computeBMI(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let w = weightKg, let h = heightCm, h > 0 else { return nil }
        let heightM = h / 100.0
        return w / (heightM * heightM)
    }

    public static func computeBodyFat(bmi: Double?, dateOfBirth: Date?, sex: String) -> Double? {
        guard let bmi = bmi, let dob = dateOfBirth else { return nil }
        let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 30
        let sexFactor = sex == "Male" ? 1.0 : 0.0
        let fat = (1.20 * bmi) + (0.23 * Double(age)) - (10.8 * sexFactor) - 5.4
        return max(3.0, min(60.0, fat))
    }
}
