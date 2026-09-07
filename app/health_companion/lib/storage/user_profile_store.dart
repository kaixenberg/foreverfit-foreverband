import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// The user's own identity fields — name/date of birth/sex. Deliberately
/// separate from EmergencyContactStore (that's someone else's contact
/// info) and from HealthLogStore's MedicalIdProfile (clinical, not
/// identity). Weight/height are NOT duplicated here — they live in
/// MetricsStore, the same place the Dashboard's cards already read them
/// from; this store only tracks identity plus whether onboarding has
/// been completed, which is what gates OnboardingGate.
class UserProfileStore extends ChangeNotifier {
  static const _boxName = 'user_profile';
  static const _key = 'profile';

  Box<Map>? _box;

  String name = '';
  DateTime? dateOfBirth;
  String sex = '';
  bool onboardingCompleted = false;

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    final saved = box.get(_key);
    if (saved == null) return;
    name = saved['name'] as String? ?? '';
    final dobString = saved['dateOfBirth'] as String?;
    dateOfBirth = dobString != null ? DateTime.tryParse(dobString) : null;
    sex = saved['sex'] as String? ?? '';
    onboardingCompleted = saved['onboardingCompleted'] as bool? ?? false;
  }

  Future<void> saveProfile({
    required String name,
    DateTime? dateOfBirth,
    required String sex,
  }) async {
    this.name = name.trim();
    this.dateOfBirth = dateOfBirth;
    this.sex = sex.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboardingCompleted = true;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _box?.put(_key, {
      'name': name,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'sex': sex,
      'onboardingCompleted': onboardingCompleted,
    });
  }
}
