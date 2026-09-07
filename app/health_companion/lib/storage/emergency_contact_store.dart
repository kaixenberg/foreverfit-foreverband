import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local, offline storage for the emergency-response feature's settings:
/// the saved emergency contact, an optional custom emergency-number
/// override, and the mock-mode toggle. Same Hive pattern as
/// HealthLogStore/MetricsStore. A single-document box (one key,
/// `_settingsKey`) rather than a list — there's exactly one contact and
/// one set of settings, not a timestamped series.
class EmergencyContactStore extends ChangeNotifier {
  static const String _boxName = 'emergency_settings';
  static const String _settingsKey = 'settings';

  EmergencyContactStore();

  /// Test-only: sets fields directly with no Hive box, so unit tests don't
  /// need a real (or faked) Hive environment just to exercise
  /// EmergencyWorkflowService against a contact/mock-mode configuration.
  /// Setter methods still work — they just skip persistence (`_box` stays
  /// null, and `_persist()` is a no-op when it is).
  EmergencyContactStore.forTesting({
    this.contactName = '',
    this.contactPhone = '',
    this.customEmergencyNumber = '',
    this.mockMode = true,
    this.mockAnswerOnAttempt = 3,
  });

  Box<Map>? _box;

  String contactName = '';
  String contactPhone = '';
  String customEmergencyNumber = '';

  /// Defaults to true — real calls/SMS require an explicit, confirmed
  /// opt-out in Settings. See the spec's own testing-safety requirement:
  /// never place real emergency calls by accident during development.
  bool mockMode = true;

  /// Mock-mode only: which contact-call attempt (1-5) the simulated
  /// contact "answers" on. Null means it never answers, exercising the
  /// SMS-fallback path. Has no effect when [mockMode] is false.
  int? mockAnswerOnAttempt = 3;

  bool get hasContact => contactPhone.trim().isNotEmpty;

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    final saved = box.get(_settingsKey);
    if (saved != null) {
      contactName = saved['contactName'] as String? ?? '';
      contactPhone = saved['contactPhone'] as String? ?? '';
      customEmergencyNumber = saved['customEmergencyNumber'] as String? ?? '';
      mockMode = saved['mockMode'] as bool? ?? true;
      // Distinguish "never saved" (use the default) from "saved as null",
      // i.e. the user deliberately chose the never-answers scenario.
      if (saved.containsKey('mockAnswerOnAttempt')) {
        mockAnswerOnAttempt = saved['mockAnswerOnAttempt'] as int?;
      }
    }
  }

  Future<void> saveContact(
      {required String name, required String phone}) async {
    contactName = name.trim();
    contactPhone = phone.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setCustomEmergencyNumber(String number) async {
    customEmergencyNumber = number.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMockMode(bool value) async {
    mockMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setMockAnswerOnAttempt(int? attempt) async {
    mockAnswerOnAttempt = attempt;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _box?.put(_settingsKey, {
      'contactName': contactName,
      'contactPhone': contactPhone,
      'customEmergencyNumber': customEmergencyNumber,
      'mockMode': mockMode,
      'mockAnswerOnAttempt': mockAnswerOnAttempt,
    });
  }
}
