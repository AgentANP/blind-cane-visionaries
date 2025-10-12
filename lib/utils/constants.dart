// Constants used throughout the app

class AppConstants {
  // Google Maps API Key
  static const String googleApiKey = "AIzaSyCh6EuI2M6-6Jhx-11ebWcODh4ua4MY7VQ";
  
  // TTS Settings
  static const String defaultLanguage = "en-IN";
  static const double defaultSpeechRate = 0.5;
  static const double defaultVolume = 1.0;
  static const double defaultPitch = 1.0;
  
  // Bluetooth Settings
  static const int bluetoothScanTimeout = 15; // seconds
  
  // Navigation Settings
  static const int arrivalDistanceThreshold = 20; // meters
  static const int upcomingTurnDistance = 50; // meters
  static const int immediateActionDistance = 15; // meters
  static const int stepCompletionDistance = 5; // meters
  
  // Location Settings
  static const int positionUpdateFilter = 10; // meters
}
