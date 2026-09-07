import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/emergency_location.dart';
import 'package:health_companion/domain/emergency_summary_builder.dart';

void main() {
  const location = EmergencyLocation(
      text: '221B Example Road, Kolkata', latitude: 22.5, longitude: 88.3);

  group('with specific readings', () {
    const summary = EmergencySummary(
      readings: [
        EmergencyReading(
            label: 'heart rate', valueText: '145 beats per minute'),
        EmergencyReading(label: 'oxygen saturation', valueText: '88 percent'),
      ],
      durationText: 'approximately 4 minutes',
      location: location,
      triggerReason: 'a possible fall was detected',
    );

    test('emergency-services script states measured values, not a diagnosis',
        () {
      final script = buildEmergencyServicesScript(summary);
      expect(script, contains('automated medical emergency alert'));
      expect(script, contains('145 beats per minute'));
      expect(script, contains('88 percent'));
      expect(script, contains('approximately 4 minutes'));
      expect(script, contains(location.text));
      // Never a diagnosis — no disease/condition names invented.
      expect(script, isNot(contains('heart attack')));
      expect(script, isNot(contains('stroke')));
    });

    test('contact script mentions services were already contacted', () {
      final script = buildContactScript(summary);
      expect(
          script, contains('Emergency services have already been contacted'));
      expect(script, contains('145 beats per minute'));
      expect(script, contains(location.text));
    });

    test('SMS text is structured and mentions the 5-attempt exhaustion', () {
      final sms = buildEmergencySms(summary);
      expect(sms, contains('EMERGENCY ALERT'));
      expect(sms, contains('Heart rate: 145 beats per minute'));
      expect(sms, contains('Oxygen saturation: 88 percent'));
      expect(sms, contains('Duration: approximately 4 minutes'));
      expect(sms, contains('Location: ${location.text}'));
      expect(sms, contains('5 call attempts'));
    });
  });

  group('with no specific data (generic, non-diagnostic fallback)', () {
    const summary = EmergencySummary(
      readings: [],
      durationText: null,
      location: location,
      triggerReason: 'the user manually requested emergency assistance',
    );

    test('hasSpecificData is false', () {
      expect(summary.hasSpecificData, false);
    });

    test('does not fabricate a reading or duration', () {
      final script = buildEmergencyServicesScript(summary);
      expect(script,
          contains('Specific vital sign data is not currently available'));
      expect(script, isNot(contains('beats per minute')));
      expect(script, isNot(contains('approximately')));
    });

    test('still includes location and a request for assistance', () {
      final script = buildEmergencyServicesScript(summary);
      expect(script, contains(location.text));
      expect(script, contains('Please send emergency medical assistance'));
    });
  });

  test('location unavailable text flows straight through into the scripts', () {
    const unavailable = EmergencyLocation(text: 'Location unavailable');
    const summary = EmergencySummary(
      readings: [],
      durationText: null,
      location: unavailable,
      triggerReason: 'a possible fall was detected',
    );
    expect(unavailable.isAvailable, false);
    expect(buildEmergencyServicesScript(summary),
        contains('Location unavailable'));
  });
}
