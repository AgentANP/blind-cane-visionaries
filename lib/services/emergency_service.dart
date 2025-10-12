import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/emergency_contact.dart';
import 'tts_service.dart';

class EmergencyService {
  final TtsService _ttsService;

  EmergencyService(this._ttsService);

  // Load emergency contacts from storage
  Future<List<EmergencyContact>> loadEmergencyContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contactsJson = prefs.getString('emergency_contacts');
      
      if (contactsJson == null || contactsJson.isEmpty) {
        return [];
      }
      
      final List<dynamic> contactsList = json.decode(contactsJson);
      return contactsList
          .map((json) => EmergencyContact.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Send emergency SMS to all contacts
  Future<void> sendEmergencySMS({
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    try {
      // Load emergency contacts
      final contacts = await loadEmergencyContacts();
      
      if (contacts.isEmpty) {
        await _ttsService.speak('No emergency contacts found. Please add contacts in settings.');
        return;
      }
      
      // Create Google Maps link
      final String mapsLink = 'https://www.google.com/maps?q=$latitude,$longitude';
      
      // Create emergency message
      final String message = 'EMERGENCY SOS ALERT!\n\n'
          'I need help! This is an emergency! My current location:\n'
          '$address\n\n'
          'Coordinates: $latitude, $longitude\n\n'
          'View on Google Maps:\n$mapsLink';
      
      // Send SMS to each contact
      int successCount = 0;
      
      for (var contact in contacts) {
        try {
          // Remove any non-numeric characters from phone number
          String phoneNumber = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');
          
          // Create SMS URI
          final Uri smsUri = Uri(
            scheme: 'sms',
            path: phoneNumber,
            queryParameters: {'body': message},
          );
          
          // Try to launch SMS
          if (await canLaunchUrl(smsUri)) {
            await launchUrl(smsUri);
            successCount++;
            // Small delay between SMS launches
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          // Failed to send to this contact, continue with others
        }
      }
      
      // Announce result
      if (successCount > 0) {
        await _ttsService.speak('Emergency alerts sent to $successCount contact${successCount > 1 ? 's' : ''}');
      } else {
        await _ttsService.speak('Failed to send emergency alerts. Please call contacts manually.');
      }
      
    } catch (e) {
      await _ttsService.speak('Error sending emergency alerts');
    }
  }

  // Send emergency alert with SMS and optional phone call
  Future<void> sendEmergencyAlert({
    required double latitude,
    required double longitude,
    required String address,
    bool makeCall = false,
  }) async {
    // Send SMS first
    await sendEmergencySMS(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );

    // If requested, also initiate a call to the first emergency contact
    if (makeCall) {
      final contacts = await loadEmergencyContacts();
      if (contacts.isNotEmpty) {
        await makeEmergencyCall(contacts.first.phone);
      }
    }
  }

  // Make emergency call to a specific number
  Future<void> makeEmergencyCall(String phoneNumber) async {
    try {
      // Remove any non-numeric characters from phone number
      String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      
      final Uri telUri = Uri(
        scheme: 'tel',
        path: cleanNumber,
      );
      
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
        await _ttsService.speak('Calling emergency contact');
      } else {
        await _ttsService.speak('Unable to make call');
      }
    } catch (e) {
      await _ttsService.speak('Failed to initiate call');
    }
  }
}
