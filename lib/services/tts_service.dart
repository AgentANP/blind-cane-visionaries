import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/constants.dart';

// Text-to-Speech Service
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      // Stop any ongoing speech first
      await _tts.stop();
      
      // Set Indian English voice
      await _tts.setLanguage(AppConstants.defaultLanguage);
      await _tts.setSpeechRate(AppConstants.defaultSpeechRate);
      await _tts.setVolume(AppConstants.defaultVolume);
      await _tts.setPitch(AppConstants.defaultPitch);
      
      // Wait a bit for settings to take effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      _isInitialized = true;
      print('TTS initialized successfully with ${AppConstants.defaultLanguage}');
    } catch (e) {
      print('TTS initialization error: $e');
      _isInitialized = false;
    }
  }

  Future<void> speak(String text) async {
    try {
      // If TTS not initialized, wait for it
      if (!_isInitialized) {
        print('TTS not initialized, waiting...');
        await initialize();
        
        // If still not initialized after retry, skip speech
        if (!_isInitialized) {
          print('TTS initialization failed, skipping speech');
          return;
        }
      }

      // Re-confirm language setting before speaking
      await _tts.setLanguage(AppConstants.defaultLanguage);
      
      // Create a completer to wait for speech completion
      final completer = Completer<void>();
      
      // Set up completion handler
      _tts.setCompletionHandler(() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      
      // Set up error handler
      _tts.setErrorHandler((msg) {
        print('TTS error: $msg');
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      
      print('Speaking: $text');
      // Start speaking
      await _tts.speak(text);
      
      // Wait for completion with timeout to prevent hanging
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('TTS timeout');
        },
      );
    } catch (e) {
      print('Speech error: $e');
      // If speech fails, continue silently
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }
}
