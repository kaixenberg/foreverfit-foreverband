import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/units.dart';
import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import '../storage/metrics_store.dart';
import '../storage/user_profile_store.dart';

const _sexOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

/// One combined form — name/DOB/sex, weight/height, and the Medical ID
/// fields (blood type/allergies/conditions/notes) — used in two places:
/// embedded as onboarding's second page ([isOnboarding] true, button
/// reads "Continue", marks onboarding complete on finish) and standalone
/// from Settings → Profile & Medical ([isOnboarding] false, button reads
/// "Save", pre-filled from whatever's already saved). Replaces the old
/// standalone MedicalIdScreen entirely — one place to edit this data,
/// not two.
class ProfileMedicalScreen extends StatefulWidget {
  const ProfileMedicalScreen({super.key, required this.isOnboarding});

  final bool isOnboarding;

  @override
  State<ProfileMedicalScreen> createState() => _ProfileMedicalScreenState();
}

class _ProfileMedicalScreenState extends State<ProfileMedicalScreen> {
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _notesController = TextEditingController();
  String _sex = '';
  DateTime? _dateOfBirth;
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _prefillOnce(
    UserProfileStore profile,
    MetricsStore metrics,
    HealthLogStore healthLog,
    UnitSystem unitSystem,
  ) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = profile.name;
    _sex = profile.sex;
    _dateOfBirth = profile.dateOfBirth;
    if (metrics.latestWeightKg != null) {
      _weightController.text =
          formatWeightKg(metrics.latestWeightKg!, unitSystem)
              .value
              .toStringAsFixed(1);
    }
    if (metrics.latestHeightCm != null) {
      _heightController.text =
          formatHeightCm(metrics.latestHeightCm!, unitSystem)
              .value
              .toStringAsFixed(1);
    }
    final medical = healthLog.medicalId;
    _bloodTypeController.text = medical?.bloodType ?? '';
    _allergiesController.text = medical?.allergies ?? '';
    _conditionsController.text = medical?.conditions ?? '';
    _notesController.text = medical?.notes ?? '';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save(
    UnitSystem unitSystem,
    UserProfileStore profile,
    MetricsStore metrics,
    HealthLogStore healthLog,
  ) async {
    await profile.saveProfile(
      name: _nameController.text,
      dateOfBirth: _dateOfBirth,
      sex: _sex,
    );
    final weightInput = double.tryParse(_weightController.text);
    if (weightInput != null) {
      await metrics.addWeightKg(parseWeightToKg(weightInput, unitSystem));
    }
    final heightInput = double.tryParse(_heightController.text);
    if (heightInput != null) {
      await metrics.addHeightCm(parseHeightToCm(heightInput, unitSystem));
    }
    await healthLog.saveMedicalId(MedicalIdProfile(
      bloodType: _bloodTypeController.text.trim(),
      allergies: _allergiesController.text.trim(),
      conditions: _conditionsController.text.trim(),
      notes: _notesController.text.trim(),
    ));

    if (widget.isOnboarding) {
      await profile.completeOnboarding();
      // Pops the full-screen OnboardingScreen route OnboardingGate pushed
      // — nothing else closes it once onboarding is done.
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile & medical info saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileStore>();
    final metrics = context.watch<MetricsStore>();
    final healthLog = context.watch<HealthLogStore>();
    final settings = context.watch<AppSettingsStore>();
    final unitSystem = resolveEffectiveUnitSystem(settings.unitSystem);
    _prefillOnce(profile, metrics, healthLog, unitSystem);

    final weightUnit = formatWeightKg(0, unitSystem).unit;
    final heightUnit = formatHeightCm(0, unitSystem).unit;

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.isOnboarding) ...[
          Text('Tell us about you',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Kept only on this device. You can edit this anytime from '
            'Settings → Profile & Medical.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        Text('About you', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
              labelText: 'Name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.cake_outlined),
          onPressed: _pickDateOfBirth,
          label: Text(_dateOfBirth == null
              ? 'Date of birth'
              : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _sex.isEmpty ? null : _sex,
          decoration: const InputDecoration(
              labelText: 'Sex', border: OutlineInputBorder()),
          items: [
            for (final option in _sexOptions)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) => setState(() => _sex = value ?? ''),
        ),
        const SizedBox(height: 20),
        Text('Body', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _weightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: weightUnit,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _heightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Height',
            suffixText: heightUnit,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text('Medical ID', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Visible to a responder in an emergency — kept only on this device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bloodTypeController,
          decoration: const InputDecoration(
            labelText: 'Blood type',
            hintText: 'e.g. O+',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _allergiesController,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Allergies', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _conditionsController,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Medical conditions', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Other notes for responders',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _save(unitSystem, profile, metrics, healthLog),
          child: Text(widget.isOnboarding ? 'Continue' : 'Save'),
        ),
      ],
    );

    if (!widget.isOnboarding) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile & Medical')),
        body: content,
      );
    }
    return content;
  }
}
