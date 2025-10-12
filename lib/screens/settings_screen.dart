import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/emergency_contact.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterNativeContactPicker _contactPicker = FlutterNativeContactPicker();
  List<EmergencyContact> _savedContacts = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  // Load contacts from SharedPreferences
  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? contactsJson = prefs.getString('emergency_contacts');
    
    if (contactsJson != null) {
      final List<dynamic> contactsList = json.decode(contactsJson);
      setState(() {
        _savedContacts = contactsList
            .map((json) => EmergencyContact.fromJson(json))
            .toList();
      });
    }
  }

  // Save contacts to SharedPreferences
  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String contactsJson = json.encode(
      _savedContacts.map((contact) => contact.toJson()).toList(),
    );
    await prefs.setString('emergency_contacts', contactsJson);
  }

  // Add new contact
  Future<void> _addContact() async {
    if (_nameController.text.isNotEmpty && _numberController.text.isNotEmpty) {
      setState(() {
        _savedContacts.add(EmergencyContact(
          name: _nameController.text,
          phone: _numberController.text,
        ));
        _nameController.clear();
        _numberController.clear();
      });
      await _saveContacts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact saved successfully')),
        );
      }
    }
  }

  // Delete contact
  Future<void> _deleteContact(int index) async {
    setState(() {
      _savedContacts.removeAt(index);
    });
    await _saveContacts();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact deleted')),
      );
    }
  }
  
  Future<void> _pickContact() async {
    try {
      final contact = await _contactPicker.selectContact();
      if (contact != null && contact.phoneNumbers != null && contact.phoneNumbers!.isNotEmpty) {
        setState(() {
          _nameController.text = contact.fullName ?? '';
          _numberController.text = contact.phoneNumbers!.first;
        });
      }
    } catch (e) {
      // Handle error or permission denial
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Manage Emergency Contacts Heading
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Manage your emergency SOS contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            // Add Emergency Contact Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Emergency Contact',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Name',
                        hintText: 'e.g., Mom, John Smith',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'e.g., +91 99911 03355',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.group_add),
                        label: const Text('Add Contact'),
                        onPressed: _addContact,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.contacts),
                        label: const Text('Pick from Contacts'),
                        onPressed: _pickContact,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Emergency Contacts Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Contacts (${_savedContacts.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _savedContacts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'No emergency contacts added yet. Add at least one contact to enable SOS alerts.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _savedContacts.length,
                            itemBuilder: (context, index) {
                              final contact = _savedContacts[index];
                              return Card(
                                color: Colors.grey[850],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: const Icon(Icons.person, color: Colors.tealAccent),
                                  title: Text(contact.name),
                                  subtitle: Text(contact.phone),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteContact(index),
                                    tooltip: 'Delete Contact',
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // About SOS Alerts Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About SOS Alerts',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'When you trigger an SOS alert by pressing the SOS button, the app will:',
                      style: TextStyle(fontSize: 14),
                    ),
                    SizedBox(height: 8),
                    Text('• Get your current GPS location'),
                    Text('• Send an emergency message to all listed contacts'),
                    Text('• Include a Google Maps link with your exact coordinates'),
                    Text('• Provide audio confirmation of the alert'),
                    SizedBox(height: 12),
                    Text(
                      'Note: Make sure location permissions are enabled for this app. Test your SOS feature regularly to ensure it works when needed.',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Privacy & Data Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy & Data',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'All contact information is stored locally on your device only. No data is sent to external servers except during an SOS alert, when your location is shared with your emergency contacts.',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
