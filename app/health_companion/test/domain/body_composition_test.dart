import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/body_composition.dart';

void main() {
  test('returns null without a BMI or date of birth', () {
    expect(
        computeBodyFatPercent(
            bmi: null, dateOfBirth: DateTime(1990), sex: 'Male'),
        isNull);
    expect(
        computeBodyFatPercent(bmi: 24, dateOfBirth: null, sex: 'Male'), isNull);
  });

  test('matches the Deurenberg formula for a known case', () {
    final dob = DateTime.now().copyWith(year: DateTime.now().year - 30);
    final result =
        computeBodyFatPercent(bmi: 24, dateOfBirth: dob, sex: 'Male');
    // 1.20*24 + 0.23*30 - 10.8*1 - 5.4 = 28.8 + 6.9 - 10.8 - 5.4 = 19.5
    expect(result, closeTo(19.5, 0.5));
  });

  test('male and female differ by the sex term, unspecified splits it', () {
    final dob = DateTime.now().copyWith(year: DateTime.now().year - 30);
    final male = computeBodyFatPercent(bmi: 24, dateOfBirth: dob, sex: 'Male')!;
    final female =
        computeBodyFatPercent(bmi: 24, dateOfBirth: dob, sex: 'Female')!;
    final other =
        computeBodyFatPercent(bmi: 24, dateOfBirth: dob, sex: 'Other')!;
    expect(female - male, closeTo(10.8, 0.1));
    expect(other, closeTo((male + female) / 2, 0.1));
  });

  test('never returns negative', () {
    final dob = DateTime.now().copyWith(year: DateTime.now().year - 5);
    final result = computeBodyFatPercent(bmi: 1, dateOfBirth: dob, sex: 'Male');
    expect(result, 0);
  });
}
