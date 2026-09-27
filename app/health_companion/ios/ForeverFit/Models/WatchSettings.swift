import Foundation

public enum WatchFace: UInt8, CaseIterable, Identifiable, Codable {
    case primary = 0
    case secondary = 1

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .primary: return "Classic Vitals Clock"
        case .secondary: return "Sensor Radar Matrix"
        }
    }
}

public enum WatchDateFormat: UInt8, CaseIterable, Identifiable, Codable {
    case weekdayShort = 0          // "Wed, Sep 09"
    case weekdayShortWithYear = 1  // "Wed, Sep 09 2026"
    case dayMonthYearSlash = 2     // "09/09/2026 (DD/MM)"
    case monthDayYearSlash = 3     // "09/09/2026 (MM/DD)"

    public var id: UInt8 { rawValue }

    public var label: String {
        switch self {
        case .weekdayShort: return "Wed, Sep 09"
        case .weekdayShortWithYear: return "Wed, Sep 09 2026"
        case .dayMonthYearSlash: return "09/09/2026 (DD/MM)"
        case .monthDayYearSlash: return "09/09/2026 (MM/DD)"
        }
    }
}

public struct WatchSettings: Codable, Equatable {
    public var selectedFace: WatchFace
    public var autoCycleEnabled: Bool
    public var autoCycleIntervalSeconds: UInt16
    public var use24HourFormat: Bool
    public var dateFormat: WatchDateFormat
    public var showSeconds: Bool
    public var ignoreBodyTempContactCheck: Bool

    public init(
        selectedFace: WatchFace = .primary,
        autoCycleEnabled: Bool = false,
        autoCycleIntervalSeconds: UInt16 = 10,
        use24HourFormat: Bool = true,
        dateFormat: WatchDateFormat = .weekdayShortWithYear,
        showSeconds: Bool = false,
        ignoreBodyTempContactCheck: Bool = false
    ) {
        self.selectedFace = selectedFace
        self.autoCycleEnabled = autoCycleEnabled
        self.autoCycleIntervalSeconds = autoCycleIntervalSeconds
        self.use24HourFormat = use24HourFormat
        self.dateFormat = dateFormat
        self.showSeconds = showSeconds
        self.ignoreBodyTempContactCheck = ignoreBodyTempContactCheck
    }

    public static let defaults = WatchSettings()
}
