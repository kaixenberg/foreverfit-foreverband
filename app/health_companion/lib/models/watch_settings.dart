/// Which of the wearable's two OLED faces is active — see
/// health_companion.ino's drawPrimaryFace()/drawSecondaryFace(). Index
/// order matters: sent over BLE as a raw byte (see
/// HealthCompanionProtocol.buildWatchSettingsPacket), must match the
/// firmware's own face-index convention.
enum WatchFace { primary, secondary }

/// Preset date formats for the primary watch face. Index order matters —
/// sent over BLE as a raw byte, must match the firmware's own
/// dateFormatSetting handling in health_companion.ino.
enum WatchDateFormat {
  /// "Wed, Sep 09"
  weekdayShort,

  /// "Wed, Sep 09 2026" — the original hardcoded format.
  weekdayShortWithYear,

  /// "09/09/2026"
  dayMonthYearSlash,

  /// "09/09/2026" (US ordering)
  monthDayYearSlash,
}

extension WatchDateFormatLabel on WatchDateFormat {
  String get label => switch (this) {
        WatchDateFormat.weekdayShort => 'Wed, Sep 09',
        WatchDateFormat.weekdayShortWithYear => 'Wed, Sep 09 2026',
        WatchDateFormat.dayMonthYearSlash => '09/09/2026 (DD/MM)',
        WatchDateFormat.monthDayYearSlash => '09/09/2026 (MM/DD)',
      };
}

/// Everything about the wearable's watch faces that's controlled from
/// the phone — see WatchSettingsStore (persistence) and
/// HealthCompanionProtocol.buildWatchSettingsPacket (wire format).
class WatchSettings {
  final WatchFace selectedFace;
  final bool autoCycleEnabled;
  final int autoCycleIntervalSeconds;
  final bool use24HourFormat;
  final WatchDateFormat dateFormat;
  final bool showSeconds;

  /// Developer/demo override: when true, body temp (DS18B20) is reported
  /// and shown — on both the watch and the app — without requiring the
  /// MAX30102 to also detect finger/wrist contact. Off by default: a
  /// watch lying on a table would otherwise report a plausible-looking
  /// but meaningless "body" temperature. While this is on, the app
  /// suppresses the low/high body-temp WARNING outright rather than
  /// trusting an unverified reading — see dashboard_screen.dart.
  final bool ignoreBodyTempContactCheck;

  const WatchSettings({
    required this.selectedFace,
    required this.autoCycleEnabled,
    required this.autoCycleIntervalSeconds,
    required this.use24HourFormat,
    required this.dateFormat,
    required this.showSeconds,
    required this.ignoreBodyTempContactCheck,
  });

  static const defaults = WatchSettings(
    selectedFace: WatchFace.primary,
    autoCycleEnabled: false,
    autoCycleIntervalSeconds: 10,
    use24HourFormat: true,
    dateFormat: WatchDateFormat.weekdayShortWithYear,
    showSeconds: false,
    ignoreBodyTempContactCheck: false,
  );

  WatchSettings copyWith({
    WatchFace? selectedFace,
    bool? autoCycleEnabled,
    int? autoCycleIntervalSeconds,
    bool? use24HourFormat,
    WatchDateFormat? dateFormat,
    bool? showSeconds,
    bool? ignoreBodyTempContactCheck,
  }) =>
      WatchSettings(
        selectedFace: selectedFace ?? this.selectedFace,
        autoCycleEnabled: autoCycleEnabled ?? this.autoCycleEnabled,
        autoCycleIntervalSeconds:
            autoCycleIntervalSeconds ?? this.autoCycleIntervalSeconds,
        use24HourFormat: use24HourFormat ?? this.use24HourFormat,
        dateFormat: dateFormat ?? this.dateFormat,
        showSeconds: showSeconds ?? this.showSeconds,
        ignoreBodyTempContactCheck:
            ignoreBodyTempContactCheck ?? this.ignoreBodyTempContactCheck,
      );
}
