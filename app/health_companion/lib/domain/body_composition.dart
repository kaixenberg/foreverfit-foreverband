/// Body fat % is no longer manually logged — it's computed from BMI, age,
/// and sex (Deurenberg et al. 1991: a standard, transparent formula, not
/// a trained model — same "formula over black box" pattern as the
/// wellness score/baseline/heat index elsewhere in this app). Needs
/// `UserProfileStore.dateOfBirth`/`sex` to be set; returns null
/// otherwise rather than guessing.
double? computeBodyFatPercent({
  required double? bmi,
  required DateTime? dateOfBirth,
  required String sex,
}) {
  if (bmi == null || dateOfBirth == null) return null;
  final age = _ageFromDob(dateOfBirth);
  // "Other"/"Prefer not to say"/unset splits the difference between the
  // formula's male/female terms rather than guessing a sex to assume.
  final sexTerm = switch (sex) {
    'Male' => 1.0,
    'Female' => 0.0,
    _ => 0.5,
  };
  final result = 1.20 * bmi + 0.23 * age - 10.8 * sexTerm - 5.4;
  return result < 0 ? 0 : result;
}

int _ageFromDob(DateTime dob) {
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age;
}
