import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../models/emergency_contact.dart';
import 'tts_service.dart';

class EmergencyService {
  final TtsService _ttsService;
  static const platform = MethodChannel('com.example.stickapp/sms');

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

  // Send emergency SMS to all contacts at once (direct send without dialog)
  Future<void> sendEmergencySMSDirect({
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
      
      // Request SMS permission
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        await _ttsService.speak('SMS permission required to send emergency alerts');
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
      
      // Collect all phone numbers
      List<String> phoneNumbers = contacts
          .map((contact) => contact.phone.replaceAll(RegExp(r'[^0-9+]'), ''))
          .toList();
      
      try {
        // Send SMS directly using platform channel
        final int successCount = await platform.invokeMethod('sendSMS', {
          'phoneNumbers': phoneNumbers,
          'message': message,
        });
        
        if (successCount > 0) {
          await _ttsService.speak('Emergency alerts sent to $successCount contact${successCount > 1 ? 's' : ''}');
        } else {
          await _ttsService.speak('Failed to send emergency alerts');
        }
      } catch (e) {
        // If direct SMS fails, fall back to opening SMS app
        await _ttsService.speak('Sending emergency messages');
        await _sendViaSmsApp(phoneNumbers, message);
      }
      
    } catch (e) {
      await _ttsService.speak('Error sending emergency alerts');
    }
  }

  // Fallback: Open SMS app with all recipients
  Future<void> _sendViaSmsApp(List<String> phoneNumbers, String message) async {
    try {
      final String recipients = phoneNumbers.join(';');
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: {'body': message},
      );
      
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      }
    } catch (e) {
      // Failed to open SMS app
    }
  }

  // Send emergency SMS to all contacts (opens SMS app for each - slower)
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
