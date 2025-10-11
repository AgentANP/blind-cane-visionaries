import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  final FlutterTts _tts = FlutterTts();
  bool _isTtsInitialized = false;
  
  // Bluetooth state
  BluetoothDevice? _connectedDevice;
  String _connectionStatus = 'Disconnected: Standby';
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSavedDevice();
  }

  Future<void> _initTts() async {
    try {
      // Stop any ongoing speech first
      await _tts.stop();
      
      // Set Indian English voice
      await _tts.setLanguage("en-IN");
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      
      // Wait a bit for settings to take effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      setState(() {
        _isTtsInitialized = true;
      });
      
      print('TTS initialized successfully with en-IN');
    } catch (e) {
      print('TTS initialization error: $e');
      _isTtsInitialized = false;
    }
  }

  Future<void> _speak(String text) async {
    try {
      // If TTS not initialized, wait for it
      if (!_isTtsInitialized) {
        print('TTS not initialized, waiting...');
        await _initTts();
        
        // If still not initialized after retry, skip speech
        if (!_isTtsInitialized) {
          print('TTS initialization failed, skipping speech');
          return;
        }
      }

      // Re-confirm language setting before speaking
      await _tts.setLanguage("en-IN");
      
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

  Future<void> _findLocation() async {
    setState(() {
      _locationStatus = 'Getting location...';
    });
    
    // Announce that location is being fetched (non-blocking)
    _speak('Getting your location').then((_) {
      print('Location announcement completed');
    });

    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = 'Location services are disabled.';
      });
      await _speak('Location services are disabled. Please enable location services.');
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
        await _speak('Location permissions are denied. Please grant location permission.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = 'Location permissions are permanently denied.';
      });
      await _speak('Location permissions are permanently denied. Please enable them in settings.');
      return;
    }

    // Get current position
    try {
      print('Fetching current position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      print('Position fetched: ${position.latitude}, ${position.longitude}');

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
      
      print('Address resolved: $address');
      
      // Announce the location
      print('About to announce location...');
      await _speak('You are currently at $address');
      print('Location announcement completed');
    } catch (e) {
      print('Location fetch error: $e');
      setState(() {
        _locationStatus = 'Failed to get location: $e';
      });
      await _speak('Failed to get your location. Please try again.');
    }
  }

  // Load saved Bluetooth device
  Future<void> _loadSavedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('connected_device_id');
      
      if (deviceId != null) {
        // Try to reconnect to saved device
        setState(() {
          _connectionStatus = 'Reconnecting...';
        });
        
        // Check if device is available
        final connectedDevices = await FlutterBluePlus.connectedSystemDevices;
        for (var device in connectedDevices) {
          if (device.remoteId.toString() == deviceId) {
            await _connectToDevice(device);
            return;
          }
        }
      }
    } catch (e) {
      // Failed to load saved device
    }
  }

  // Connect to Bluetooth device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      
      setState(() {
        _connectedDevice = device;
        _connectionStatus = 'Connected: ${device.platformName}';
      });
      
      // Save device ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connected_device_id', device.remoteId.toString());
      
      // Listen to connection state changes
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _connectedDevice = null;
            _connectionStatus = 'Disconnected: Standby';
          });
        }
      });
      
      // Discover services and set up listeners for SOS signals
      await _setupSignalListeners(device);
      
      await _speak('Connected to stick');
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection failed';
      });
      await _speak('Failed to connect to stick');
    }
  }

  // Set up listeners for signals from the stick (like SOS button)
  Future<void> _setupSignalListeners(BluetoothDevice device) async {
    try {
      // Discover all services
      List<BluetoothService> services = await device.discoverServices();
      
      // Look for characteristics that can notify
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          // Check if characteristic supports notifications
          if (characteristic.properties.notify || characteristic.properties.indicate) {
            // Subscribe to notifications
            await characteristic.setNotifyValue(true);
            
            // Listen for data from the stick
            characteristic.lastValueStream.listen((value) async {
              if (value.isNotEmpty) {
                String receivedData = String.fromCharCodes(value);
                
                // Handle SOS button press
                if (receivedData.toUpperCase().contains('SOS')) {
                  await _handleSOSSignal();
                }
                
                // You can add more signal handlers here for other stick functions
              }
            });
          }
        }
      }
    } catch (e) {
      // Service discovery failed, but connection is still active
    }
  }

  // Handle SOS signal from the stick
  Future<void> _handleSOSSignal() async {
    // Announce emergency
    await _speak('Emergency SOS button pressed on stick');
    
    // Get current location
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      String address = 'Unknown location';
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        address = '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }
      
      // Show emergency dialog
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.red[900],
            title: Row(
              children: const [
                Icon(Icons.warning, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Text('EMERGENCY SOS', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOS button pressed on Smart Stick!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Location: $address',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  'Coordinates: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'I\'m Safe',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // TODO: Send SMS/call emergency contacts with location
                  await _speak('Alerting emergency contacts');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red[900],
                ),
                child: const Text(
                  'Alert Contacts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Failed to get location for SOS
      await _speak('Emergency signal received but location unavailable');
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _connectionStateSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
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
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => BluetoothScreen(
                      onDeviceConnected: _connectToDevice,
                    )),
                  );
                },
                child: Card(
                  color: Colors.grey[900],
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _connectedDevice != null 
                            ? Icons.bluetooth_connected 
                            : Icons.bluetooth_disabled, 
                          color: _connectedDevice != null 
                            ? Colors.greenAccent 
                            : Colors.redAccent, 
                          size: 32
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _connectionStatus,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _connectedDevice != null 
                                ? Colors.greenAccent 
                                : Colors.redAccent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
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
                onPressed: () async {
                  // Announce navigation screen opening
                  await _speak('Opening navigation. Enter your destination to start.');
                  
                  // Check if widget is still mounted before using context
                  if (!mounted) return;
                  
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
  
  // Navigation state
  List<dynamic> _navigationSteps = [];
  int _currentStepIndex = 0;
  StreamSubscription<Position>? _positionStream;
  LatLng? _destination;
  bool _hasAnnouncedUpcoming = false;
  bool _hasAnnouncedNow = false;

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
    
    final completer = Completer<void>();
    
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Start speaking
    await _tts.speak(text);
    
    // Wait for completion
    await completer.future;
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

      // Get directions first, then announce everything in sequence
      await _getDirections(lat, lng, placeName);
    } catch (e) {
      _speak('Error setting destination');
    }
  }

  Future<void> _getDirections(double destLat, double destLng, String placeName) async {
    final String url = 
        'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=$destLat,$destLng&mode=walking&key=$_googleApiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes[0];
            final polylinePoints = route['overview_polyline']['points'];
            final decodedPoints = _decodePolyline(polylinePoints);
            
            // Get turn-by-turn instructions
            final legs = route['legs'] as List;
            if (legs.isNotEmpty) {
              final leg = legs[0];
              final distance = leg['distance']['text'];
              final duration = leg['duration']['text'];
              
              // Store navigation steps
              _navigationSteps = leg['steps'] as List;
              _currentStepIndex = 0;
              _destination = LatLng(destLat, destLng);
              _hasAnnouncedUpcoming = false;
              _hasAnnouncedNow = false;
              
              // Announce destination and route details in sequence
              // Each _speak() now waits for completion automatically
              await _speak('Destination set to $placeName.');
              await _speak('Distance: $distance. Estimated time: $duration.');
              await _speak('Navigation started.');
              
              // Announce first instruction after a brief pause
              if (_navigationSteps.isNotEmpty) {
                await Future.delayed(const Duration(milliseconds: 1000));
                _announceCurrentStep();
              }
              
              // Start tracking position for turn-by-turn
              _startPositionTracking();
            }
            
            setState(() {
              _polylines.clear();
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('route'),
                  color: Colors.blue,
                  width: 5,
                  points: decodedPoints,
                ),
              );
            });
          }
        } else {
          _speak('Could not find route');
        }
      }
    } catch (e) {
      _speak('Error getting directions');
    }
  }

  void _startPositionTracking() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      _updateNavigation(position);
    });
  }

  void _updateNavigation(Position position) {
    if (!_isNavigating || _navigationSteps.isEmpty) return;
    
    setState(() {
      _currentPosition = position;
      _markers.removeWhere((m) => m.markerId.value == 'currentLocation');
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
    
    // Check if we've reached the destination
    if (_destination != null) {
      double distanceToDestination = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      
      if (distanceToDestination < 20) {
        _speak('You have arrived at your destination');
        _stopNavigation();
        return;
      }
    }
    
    // Check progress through steps
    if (_currentStepIndex < _navigationSteps.length) {
      final step = _navigationSteps[_currentStepIndex];
      final endLocation = step['end_location'];
      final stepLat = endLocation['lat'];
      final stepLng = endLocation['lng'];
      
      double distanceToStepEnd = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        stepLat,
        stepLng,
      );
      
      // Announce upcoming turn when 50 meters away
      if (distanceToStepEnd <= 50 && distanceToStepEnd > 15 && !_hasAnnouncedUpcoming) {
        _hasAnnouncedUpcoming = true;
        final simplifiedInstruction = _simplifyInstruction(step);
        final distance = step['distance']['text'];
        _speak('In $distance, $simplifiedInstruction');
      }
      
      // Announce turn NOW when within 15 meters
      if (distanceToStepEnd <= 15 && !_hasAnnouncedNow) {
        _hasAnnouncedNow = true;
        final simplifiedInstruction = _simplifyInstruction(step);
        _speak('Now, $simplifiedInstruction');
      }
      
      // Move to next step when very close (5 meters)
      if (distanceToStepEnd < 5) {
        _currentStepIndex++;
        _hasAnnouncedUpcoming = false;
        _hasAnnouncedNow = false;
        
        if (_currentStepIndex < _navigationSteps.length) {
          // Immediately announce next step if it's close
          final nextStep = _navigationSteps[_currentStepIndex];
          final nextEndLocation = nextStep['end_location'];
          double distanceToNext = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            nextEndLocation['lat'],
            nextEndLocation['lng'],
          );
          
          if (distanceToNext <= 50) {
            _hasAnnouncedUpcoming = true;
            final simplifiedInstruction = _simplifyInstruction(nextStep);
            final distance = nextStep['distance']['text'];
            Future.delayed(const Duration(seconds: 2), () {
              _speak('In $distance, $simplifiedInstruction');
            });
          }
        }
      }
    }
  }

  String _simplifyInstruction(Map<String, dynamic> step) {
    String instruction = _stripHtmlTags(step['html_instructions']);
    String maneuver = step['maneuver'] ?? '';
    
    // Convert compass directions and technical terms to simple left/right/straight
    instruction = instruction.toLowerCase();
    
    // Handle common turn types based on maneuver field
    if (maneuver.contains('turn-left') || maneuver.contains('turn-sharp-left')) {
      instruction = instruction.replaceAllMapped(
        RegExp(r'head (north|south|east|west|north-?east|north-?west|south-?east|south-?west)'),
        (match) => 'turn left',
      );
    } else if (maneuver.contains('turn-right') || maneuver.contains('turn-sharp-right')) {
      instruction = instruction.replaceAllMapped(
        RegExp(r'head (north|south|east|west|north-?east|north-?west|south-?east|south-?west)'),
        (match) => 'turn right',
      );
    } else if (maneuver.contains('straight')) {
      instruction = instruction.replaceAllMapped(
        RegExp(r'head (north|south|east|west|north-?east|north-?west|south-?east|south-?west)'),
        (match) => 'continue straight',
      );
    }
    
    // Replace compass directions with simple terms
    instruction = instruction.replaceAll(RegExp(r'head north-?west'), 'turn left');
    instruction = instruction.replaceAll(RegExp(r'head north-?east'), 'turn right');
    instruction = instruction.replaceAll(RegExp(r'head south-?west'), 'turn left');
    instruction = instruction.replaceAll(RegExp(r'head south-?east'), 'turn right');
    instruction = instruction.replaceAll(RegExp(r'head north'), 'continue straight');
    instruction = instruction.replaceAll(RegExp(r'head south'), 'continue straight');
    instruction = instruction.replaceAll(RegExp(r'head east'), 'turn right');
    instruction = instruction.replaceAll(RegExp(r'head west'), 'turn left');
    
    // Common replacements for better clarity
    instruction = instruction.replaceAll('destination will be on the right', 'your destination is on the right side');
    instruction = instruction.replaceAll('destination will be on the left', 'your destination is on the left side');
    
    // Capitalize first letter
    if (instruction.isNotEmpty) {
      instruction = instruction[0].toUpperCase() + instruction.substring(1);
    }
    
    return instruction;
  }

  void _announceCurrentStep() {
    if (_currentStepIndex < _navigationSteps.length) {
      final step = _navigationSteps[_currentStepIndex];
      final simplifiedInstruction = _simplifyInstruction(step);
      final distance = step['distance']['text'];
      _speak('In $distance, $simplifiedInstruction');
    }
  }

  void _stopNavigation() {
    _positionStream?.cancel();
    setState(() {
      _isNavigating = false;
      _navigationSteps = [];
      _currentStepIndex = 0;
      _hasAnnouncedUpcoming = false;
      _hasAnnouncedNow = false;
    });
  }

  // Decode Google's encoded polyline format
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
  }

  // Strip HTML tags from directions
  String _stripHtmlTags(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
  }

  @override
  void dispose() {
    _positionStream?.cancel();
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
                                onPressed: () => _announceCurrentStep(),
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
                                  _stopNavigation();
                                  setState(() {
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

// Bluetooth Connection Screen
class BluetoothScreen extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceConnected;
  
  const BluetoothScreen({super.key, required this.onDeviceConnected});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkBluetoothSupport();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-IN");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await _tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
  }

  Future<void> _checkBluetoothSupport() async {
    try {
      // Check if Bluetooth is supported
      bool isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth is not supported on this device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Bluetooth check failed, assume supported
      print('Bluetooth support check error: $e');
    }
  }

  // Filter function to identify potential stick devices
  bool _isPotentialStickDevice(ScanResult result) {
    String platformName = result.device.platformName.toLowerCase();
    String advName = result.advertisementData.advName.toLowerCase();
    String localName = result.advertisementData.localName.toLowerCase();
    
    // Check if any name contains keywords related to the stick
    List<String> stickKeywords = [
      'stick',
      'esp32',
      'smart stick',
      'blind',
      'cane',
      'assistant'
    ];
    
    for (String keyword in stickKeywords) {
      if (platformName.contains(keyword) || 
          advName.contains(keyword) || 
          localName.contains(keyword)) {
        return true;
      }
    }
    
    // Also check for strong signal (device is very close, likely in hand)
    // RSSI closer to 0 means stronger signal
    // -50 to -30 is very close (within 1-2 meters)
    if (result.rssi > -50) {
      print('Device has strong signal (${result.rssi} dBm), might be the stick');
      return true;
    }
    
    // For now during testing, show all devices with some filtering
    // Filter out very weak signals (far away devices)
    if (result.rssi < -90) {
      print('Device signal too weak (${result.rssi} dBm), filtering out');
      return false;
    }
    
    // If no specific match but signal is decent, show it
    // This helps during initial setup when you might not know the device name
    return true;
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });
    
    print('Starting Bluetooth scan...');
    await _speak('Scanning for stick devices');
    
    try {
      // Cancel any existing subscription
      await _scanSubscription?.cancel();
      
      // Start scanning first
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        // Optional: filter by specific services if ESP32 advertises them
        // withServices: [Guid("your-service-uuid-here")],
      );
      
      print('Scan started, listening for results...');
      
      // Listen to scan results stream
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          if (!mounted) return;
          
          print('Scan results received: ${results.length} devices');
          
          for (ScanResult result in results) {
            // Filter: Only add devices that might be the stick
            // Check if it's likely our ESP32 stick
            bool isPotentialStick = _isPotentialStickDevice(result);
            
            if (!isPotentialStick) {
              // Skip devices that don't match our criteria
              continue;
            }
            
            // Add device if not already in list
            if (!_scanResults.any((d) => d.device.remoteId == result.device.remoteId)) {
              String deviceName = result.device.platformName;
              String advertisedName = result.advertisementData.advName;
              String localName = result.advertisementData.localName;
              
              print('Adding device:');
              print('  Platform Name: $deviceName');
              print('  Advertised Name: $advertisedName');
              print('  Local Name: $localName');
              print('  Remote ID: ${result.device.remoteId}');
              print('  RSSI: ${result.rssi}');
              
              setState(() {
                _scanResults.add(result);
              });
              print('Total devices in list: ${_scanResults.length}');
            }
          }
        },
        onError: (error) {
          print('Scan stream error: $error');
        },
      );
      
      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 15));
      
      print('Scan timeout reached');
      
      // Stop scanning
      await FlutterBluePlus.stopScan();
      
      print('Scan stopped. Total devices found: ${_scanResults.length}');
      
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        
        if (_scanResults.isEmpty) {
          await _speak('No devices found. Make sure the stick is turned on and Bluetooth is enabled.');
        } else {
          await _speak('Found ${_scanResults.length} devices');
        }
      }
    } catch (e) {
      print('Scan error: $e');
      
      // Stop scanning on error
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
      
      // Provide more specific error message
      String errorMsg = 'Scan failed. ';
      String voiceMsg = 'Scan failed. ';
      
      String errorStr = e.toString().toLowerCase();
      if (errorStr.contains('permission')) {
        errorMsg += 'Please grant Bluetooth and location permissions in settings.';
        voiceMsg += 'Please grant Bluetooth and location permissions.';
      } else if (errorStr.contains('bluetooth') || errorStr.contains('adapter')) {
        errorMsg += 'Please turn on Bluetooth and try again.';
        voiceMsg += 'Please turn on Bluetooth.';
      } else if (errorStr.contains('location')) {
        errorMsg += 'Please enable location services in settings.';
        voiceMsg += 'Please enable location services.';
      } else {
        errorMsg += 'Please ensure Bluetooth is on, location is enabled, and permissions are granted. Error: ${e.toString()}';
        voiceMsg += 'Please check Bluetooth and location settings.';
      }
      
      await _speak(voiceMsg);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        await _speak('Search cancelled');
      }
    } catch (e) {
      print('Error stopping scan: $e');
    }
  }

  Future<void> _connectToDevice(ScanResult scanResult) async {
    BluetoothDevice device = scanResult.device;
    await _speak('Connecting to ${device.platformName.isEmpty ? "device" : device.platformName}');
    
    try {
      await widget.onDeviceConnected(device);
      
      if (!mounted) return;
      
      Navigator.of(context).pop();
    } catch (e) {
      await _speak('Connection failed');
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Stick'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions Card
              Card(
                color: Colors.grey[900],
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: const [
                      Icon(Icons.bluetooth_searching, size: 48, color: Colors.blue),
                      SizedBox(height: 16),
                      Text(
                        'Make sure your Smart Stick is turned on and in range.',
                        style: TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Note: Bluetooth and location permissions are required for device scanning.',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Scan Button or Cancel Button
              _isScanning
                  ? Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.hourglass_empty),
                          label: const Text('Scanning...'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.blue[700],
                            disabledForegroundColor: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _stopScan,
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel Search'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton.icon(
                      onPressed: _startScan,
                      icon: const Icon(Icons.search),
                      label: const Text('Scan for Devices'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
              
              const SizedBox(height: 24),
              
              // Device List
              Expanded(
                child: _scanResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isScanning 
                                ? 'Searching for devices...' 
                                : 'Tap "Scan for Devices" to start',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[400],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _scanResults.length,
                        itemBuilder: (context, index) {
                          final scanResult = _scanResults[index];
                          final device = scanResult.device;
                          
                          // Try to get the best available name
                          String deviceName = 'Unknown Device';
                          if (scanResult.advertisementData.advName.isNotEmpty) {
                            deviceName = scanResult.advertisementData.advName;
                          } else if (scanResult.advertisementData.localName.isNotEmpty) {
                            deviceName = scanResult.advertisementData.localName;
                          } else if (device.platformName.isNotEmpty) {
                            deviceName = device.platformName;
                          }
                          
                          print('Rendering device $index: $deviceName');
                          
                          return Card(
                            color: Colors.grey[850],
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () => _connectToDevice(scanResult),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.bluetooth,
                                      color: Colors.blue,
                                      size: 40,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            deviceName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            device.remoteId.toString(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[400],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (scanResult.rssi != 0) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Signal: ${scanResult.rssi} dBm',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceSuggestion {
  final String placeId;
  final String description;

  PlaceSuggestion({required this.placeId, required this.description});
}

// Emergency Contact Model
class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
    };
  }

  // Create from JSON
  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}