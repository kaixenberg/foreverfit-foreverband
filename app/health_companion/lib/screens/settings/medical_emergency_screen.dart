import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../storage/emergency_contact_store.dart';
import '../contact_picker_screen.dart';

/// Emergency contact + local emergency hotline number — migrated as-is
/// from the old flat Settings screen (test mode and previews now live in
/// Developer/demo instead). See ARCHITECTURE.md for how the
/// AI-assisted emergency call workflow uses these.
class MedicalEmergencyScreen extends StatefulWidget {
  const MedicalEmergencyScreen({super.key});

  @override
  State<MedicalEmergencyScreen> createState() => _MedicalEmergencyScreenState();
}

class _MedicalEmergencyScreenState extends State<MedicalEmergencyScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNumberController = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  void _prefillOnce(EmergencyContactStore store) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = store.contactName;
    _phoneController.text = store.contactPhone;
    _emergencyNumberController.text = store.customEmergencyNumber;
  }

  Future<void> _pickFromContacts() async {
    var status = await Permission.contacts.status;
    if (status.isPermanentlyDenied) {
      if (!mounted) return;
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contacts permission needed'),
          content:
              const Text('Allow contacts access in system Settings to pick an '
                  'emergency contact from your address book, or just type it '
                  'in below instead.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) await openAppSettings();
      return;
    }

    if (!status.isGranted) {
      status = await Permission.contacts.request();
    }
    if (!status.isGranted) return;

    if (!mounted) return;
    final picked = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (picked != null) {
      _nameController.text = picked.$1;
      _phoneController.text = picked.$2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactStore = context.watch<EmergencyContactStore>();
    _prefillOnce(contactStore);

    return Scaffold(
      appBar: AppBar(title: const Text('Medical emergency')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Emergency contact',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Called automatically (with a spoken summary) after a fall or '
            'manual SOS, following the emergency-services call. See '
            'ARCHITECTURE.md for how this works and its platform limits.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.contacts_outlined),
            label: const Text('Pick from contacts'),
            onPressed: _pickFromContacts,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Contact name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await contactStore.saveContact(
                name: _nameController.text,
                phone: _phoneController.text,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emergency contact saved')),
              );
            },
            child: const Text('Save contact'),
          ),
          const SizedBox(height: 24),
          Text('Local emergency hotline',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Leave blank to auto-detect your region's emergency number "
            '(defaults to 112, India\'s unified emergency number). Set '
            'this only if auto-detection is wrong for your device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emergencyNumberController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Custom emergency number (optional)',
              hintText: '112',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => contactStore
                .setCustomEmergencyNumber(_emergencyNumberController.text),
            child: const Text('Save emergency number'),
          ),
        ],
      ),
    );
  }
}
