import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Stick Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        textTheme: ThemeData.dark().textTheme.copyWith(
              bodyLarge: const TextStyle(fontSize: 20, color: Colors.white),
              bodyMedium: const TextStyle(fontSize: 18, color: Colors.white),
              bodySmall: const TextStyle(fontSize: 16, color: Colors.white),
            ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
  home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _locationStatus = 'Press "Where Am I?" to get your current location.';

  Future<void> _findLocation() async {
    setState(() {
      _locationStatus = 'Getting location...';
    });

    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = 'Location services are disabled.';
      });
      return;
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationStatus = 'Location permissions are denied.';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = 'Location permissions are permanently denied.';
      });
      return;
    }

    // Get current position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      Placemark place = placemarks.first;
      String address =
          '${place.name}, ${place.locality}, ${place.administrativeArea}, ${place.country}';

      setState(() {
        _locationStatus = 'Your location:\n$address';
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Failed to get location: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Stick Assistant'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bluetooth Status Card at the top
              Card(
                color: Colors.grey[900],
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.bluetooth_disabled, color: Colors.redAccent, size: 32),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Disconnected: Standby',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Accessibility Features Card
              Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accessibility Features',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'This app is fully compatible with screen readers (TalkBack/VoiceOver). All actions provide audio feedback. Navigate using standard gestures or keyboard controls.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Location Status Display, "Where Am I?" Button, "Start Navigation" Button at bottom
              Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _locationStatus,
                    style: const TextStyle(fontSize: 16, color: Colors.tealAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.location_on, size: 28),
                label: const Text('WHERE AM I?'),
                onPressed: _findLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  elevation: 4,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.mic, size: 24),
                label: const Text('START NAVIGATION'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const NavigationScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent),
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterNativeContactPicker _contactPicker = FlutterNativeContactPicker();
  
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
  
  final List<Map<String, String>> _contacts = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();

  void _addContact() {
    if (_nameController.text.isNotEmpty && _numberController.text.isNotEmpty) {
      setState(() {
        _contacts.add({
          'name': _nameController.text,
          'number': _numberController.text,
        });
        _nameController.clear();
        _numberController.clear();
      });
    }
  }

  void _removeContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
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
                      'Emergency Contacts (${_contacts.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _contacts.isEmpty
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
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              return Card(
                                color: Colors.grey[850],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: const Icon(Icons.person, color: Colors.tealAccent),
                                  title: Text(contact['name'] ?? ''),
                                  subtitle: Text(contact['number'] ?? ''),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _removeContact(index),
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: const Column(
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

// Navigation Screen with Google Places Autocomplete
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const String _googleApiKey = "AIzaSyCh6EuI2M6-6Jhx-11ebWcODh4ua4MY7VQ";
  
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _searchController = TextEditingController();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _getCurrentLocation();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-IN");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _markers.add(
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: LatLng(position.latitude, position.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'Your Location'),
          ),
        );
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      _speak('Unable to get your location');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<List<PlaceSuggestion>> _fetchSuggestions(String query) async {
    if (query.length < 3) return [];
    
    
    String url = 
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&components=country:in&key=$_googleApiKey';
    
    
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      url += '&location=$lat,$lng&radius=50000'; // 50km radius for biasing
    }
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          return predictions
              .map((p) => PlaceSuggestion(
                    placeId: p['place_id'],
                    description: p['description'],
                  ))
              .toList();
        }
      }
    } catch (e) {
      // Handle error silently
    }
    return [];
  }

  Future<void> _getPlaceDetails(PlaceSuggestion suggestion) async {
    final String url = 
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=${suggestion.placeId}&fields=name,geometry&key=$_googleApiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];
          final name = result['name'];
          
          _handlePlaceSelection(name, location['lat'], location['lng']);
        }
      }
    } catch (e) {
      _speak('Error getting place details');
    }
  }

  Future<void> _handlePlaceSelection(String placeName, double lat, double lng) async {
    try {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'destination');
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: placeName),
          ),
        );
        _isNavigating = true;
      });

      double minLat = _currentPosition!.latitude < lat ? _currentPosition!.latitude : lat;
      double maxLat = _currentPosition!.latitude > lat ? _currentPosition!.latitude : lat;
      double minLng = _currentPosition!.longitude < lng ? _currentPosition!.longitude : lng;
      double maxLng = _currentPosition!.longitude > lng ? _currentPosition!.longitude : lng;
      
      double latPadding = (maxLat - minLat) * 0.1;
      double lngPadding = (maxLng - minLng) * 0.1;
      if (latPadding == 0) latPadding = 0.01;
      if (lngPadding == 0) lngPadding = 0.01;
      
      try {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat - latPadding, minLng - lngPadding),
              northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
            ),
            50,
          ),
        );
      } catch (e) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 13),
        );
      }

      _speak('Destination set to $placeName. Navigation started.');
      
      setState(() {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: [
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              LatLng(lat, lng),
            ],
          ),
        );
      });
    } catch (e) {
      _speak('Error setting destination');
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        elevation: 0,
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // TypeAhead Search bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TypeAheadField<PlaceSuggestion>(
                    controller: _searchController,
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Enter destination',
                          hintText: 'e.g., Charbagh Railway Station',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                    decorationBuilder: (context, child) {
                      return Material(
                        type: MaterialType.card,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      );
                    },
                    itemBuilder: (context, suggestion) {
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.tealAccent),
                        title: Text(suggestion.description),
                      );
                    },
                    onSelected: (suggestion) {
                      _searchController.text = suggestion.description;
                      _getPlaceDetails(suggestion);
                    },
                    suggestionsCallback: (search) async {
                      return await _fetchSuggestions(search);
                    },
                    debounceDuration: const Duration(milliseconds: 1500),
                    hideOnEmpty: true,
                    hideOnError: true,
                    hideOnLoading: false,
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No places found'),
                    ),
                    errorBuilder: (context, error) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Error loading suggestions'),
                    ),
                    loadingBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
                // Map
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      zoom: 15,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    compassEnabled: true,
                  ),
                ),
                // Navigation controls
                if (_isNavigating)
                  SafeArea(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[900],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.volume_up),
                                label: const Text('Repeat'),
                                onPressed: () => _speak('Continue straight ahead'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.stop),
                                label: const Text('End'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  minimumSize: const Size(0, 48),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isNavigating = false;
                                    _polylines.clear();
                                    _markers.removeWhere((m) => m.markerId.value == 'destination');
                                  });
                                  _speak('Navigation ended');
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class PlaceSuggestion {
  final String placeId;
  final String description;

  PlaceSuggestion({required this.placeId, required this.description});
}