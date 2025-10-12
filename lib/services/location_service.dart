import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

// Location Service for handling GPS and permissions
class LocationService {
  // Check and request location permissions
  static Future<LocationPermissionResult> checkAndRequestPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult(
        isGranted: false,
        message: 'Location services are disabled. Please enable location services.',
      );
    }

    // Check for location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationPermissionResult(
          isGranted: false,
          message: 'Location permissions are denied. Please grant location permission.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult(
        isGranted: false,
        message: 'Location permissions are permanently denied. Please enable them in settings.',
      );
    }

    return LocationPermissionResult(isGranted: true);
  }

  // Get current position
  static Future<Position?> getCurrentPosition() async {
    try {
      print('Fetching current position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('Position fetched: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Location fetch error: $e');
      return null;
    }
  }

  // Get address from coordinates
  static Future<String?> getAddressFromCoordinates(
      double latitude, double longitude) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isEmpty) return null;

      Placemark place = placemarks.first;
      String address =
          '${place.name}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
      
      print('Address resolved: $address');
      return address;
    } catch (e) {
      print('Address resolution error: $e');
      return null;
    }
  }

  // Get current position with address
  static Future<LocationResult> getCurrentLocationWithAddress() async {
    final permissionResult = await checkAndRequestPermission();
    if (!permissionResult.isGranted) {
      return LocationResult(
        success: false,
        errorMessage: permissionResult.message,
      );
    }

    final position = await getCurrentPosition();
    if (position == null) {
      return LocationResult(
        success: false,
        errorMessage: 'Failed to get your location. Please try again.',
      );
    }

    final address = await getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return LocationResult(
      success: true,
      position: position,
      address: address ?? 'Address not available',
    );
  }
}

// Result class for permission checks
class LocationPermissionResult {
  final bool isGranted;
  final String? message;

  LocationPermissionResult({required this.isGranted, this.message});
}

// Result class for location fetch
class LocationResult {
  final bool success;
  final Position? position;
  final String? address;
  final String? errorMessage;

  LocationResult({
    required this.success,
    this.position,
    this.address,
    this.errorMessage,
  });
}
