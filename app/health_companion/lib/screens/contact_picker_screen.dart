import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Lets the user search the phone's own address book and pick one contact
/// with a phone number — pushed from MedicalEmergencyScreen's "Pick from
/// contacts" button. Returns (name, phone), or null if the user backs out
/// without picking anything. Contacts with no phone number at all are
/// filtered out — this screen only exists to fill an emergency-contact
/// phone field, so showing them would just be dead-end taps.
class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  final _searchController = TextEditingController();
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await FlutterContacts.getAll(
        properties: const {ContactProperty.phone},
      );
      final withPhone = all.where((c) => c.phones.isNotEmpty).toList()
        ..sort((a, b) => (a.displayName ?? '')
            .toLowerCase()
            .compareTo((b.displayName ?? '').toLowerCase()));
      if (!mounted) return;
      setState(() {
        _contacts = withPhone;
        _filtered = withPhone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load contacts: $e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _contacts
          : _contacts
              .where((c) => (c.displayName ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  void _pick(Contact contact) {
    final primary = contact.phones.firstWhere(
      (p) => p.isPrimary ?? false,
      orElse: () => contact.phones.first,
    );
    Navigator.of(context).pop((contact.displayName ?? '', primary.number));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose contact')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search contacts',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          _contacts.isEmpty
              ? 'No contacts with a phone number found.'
              : 'No matches.',
        ),
      );
    }
    return ListView.builder(
      itemCount: _filtered.length,
      itemBuilder: (context, i) {
        final contact = _filtered[i];
        final primary = contact.phones.firstWhere(
          (p) => p.isPrimary ?? false,
          orElse: () => contact.phones.first,
        );
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(contact.displayName ?? '(no name)'),
          subtitle: Text(primary.number),
          onTap: () => _pick(contact),
        );
      },
    );
  }
}
