import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/tts_service.dart';
import '../services/location_service.dart';
import '../services/emergency_service.dart';
import 'settings_screen.dart';
import 'navigation_screen.dart';
import 'bluetooth_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _locationStatus = 'Press "Where Am I?" to get your current location.';
  final TtsService _ttsService = TtsService();
  late final EmergencyService _emergencyService;
  
  // Bluetooth state
  BluetoothDevice? _connectedDevice;
  String _connectionStatus = 'Disconnected: Standby';
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _emergencyService = EmergencyService(_ttsService);
    _loadSavedDevice();
    _requestSmsPermission();
  }

  // Request SMS permission
  Future<void> _requestSmsPermission() async {
    try {
      // Permission will be requested when trying to send SMS
      // flutter_sms handles this automatically
    } catch (e) {
      // Permission handling error
    }
  }

  Future<void> _findLocation() async {
    setState(() {
      _locationStatus = 'Getting location...';
    });
    
    // Announce that location is being fetched (non-blocking)
    _ttsService.speak('Getting your location').then((_) {
      print('Location announcement completed');
    });

    final result = await LocationService.getCurrentLocationWithAddress();
    
    if (!result.success) {
      setState(() {
        _locationStatus = result.errorMessage ?? 'Failed to get location';
      });
      await _ttsService.speak(result.errorMessage ?? 'Failed to get location');
      return;
    }

    setState(() {
      _locationStatus = 'Your location:\n${result.address}';
    });
    
    print('About to announce location...');
    await _ttsService.speak('You are currently at ${result.address}');
    print('Location announcement completed');
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
        
        // Check if device is available (systemDevices requires service UUIDs, empty list gets all)
        try {
          final connectedDevices = await FlutterBluePlus.systemDevices([]);
          bool deviceFound = false;
          
          for (var device in connectedDevices) {
            if (device.remoteId.toString() == deviceId) {
              deviceFound = true;
              await _connectToDevice(device);
              return;
            }
          }
          
          // Device not found in system devices
          if (!deviceFound) {
            setState(() {
              _connectionStatus = 'Device not found. Tap "Connect Device" to reconnect.';
            });
            await _ttsService.speak('Saved device not found. Please connect manually.');
          }
        } catch (e) {
          // Error checking system devices
          setState(() {
            _connectionStatus = 'Reconnection failed. Tap "Connect Device" to try again.';
          });
          await _ttsService.speak('Could not reconnect to device.');
        }
      } else {
        // No saved device
        setState(() {
          _connectionStatus = 'Disconnected: Standby';
        });
      }
    } catch (e) {
      // Failed to load saved device
      setState(() {
        _connectionStatus = 'Disconnected: Standby';
      });
    }
  }

  // Connect to Bluetooth device
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false, // Disable auto-reconnect to prevent reconnection issues
      );
      
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
      
      await _ttsService.speak('Connected to stick');
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection failed';
      });
      await _ttsService.speak('Failed to connect to stick');
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
                String receivedData = String.fromCharCodes(value).trim();
                
                // Handle signal '1' - Where Am I? (get location)
                if (receivedData == '1') {
                  await _findLocation();
                }
                // Handle signal '2' - Start Navigation
                else if (receivedData == '2') {
                  await _ttsService.speak('Opening navigation');
                  if (mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const NavigationScreen()),
                    );
                  }
                }
                // Handle SOS button press
                else if (receivedData.toUpperCase().contains('SOS')) {
                  await _handleSOSSignal();
                }
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
    // Announce emergency immediately
    _ttsService.speak('Emergency SOS activated. Getting your location.');
    
    // Show dialog immediately with loading state
    if (!mounted) return;
    
    // Variables to hold location data
    Position? position;
    String address = 'Getting location...';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Fetch location in background
            if (position == null) {
              LocationService.getCurrentPosition().then((pos) {
                if (pos != null) {
                  position = pos;
                  LocationService.getAddressFromCoordinates(
                    pos.latitude,
                    pos.longitude,
                  ).then((addr) {
                    setDialogState(() {
                      address = addr ?? 'Unknown location';
                    });
                  });
                  setDialogState(() {});
                } else {
                  setDialogState(() {
                    address = 'Location unavailable';
                  });
                }
              });
            }
            
            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: const Row(
                children: [
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
                  if (position != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Coordinates: ${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
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
                  onPressed: position != null ? () async {
                    Navigator.of(context).pop();
                    await _emergencyService.sendEmergencySMSDirect(
                      latitude: position!.latitude,
                      longitude: position!.longitude,
                      address: address,
                    );
                  } : null,
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
      },
    );
  }

  Future<void> _disconnectAndForgetDevice() async {
    try {
      // Disconnect device
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      
      // Clear saved device ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('connected_device_id');
      
      // Update state
      setState(() {
        _connectedDevice = null;
        _connectionStatus = 'Disconnected: Standby';
      });
      
      // TTS feedback
      await _ttsService.speak('Device disconnected and forgotten');
    } catch (e) {
      await _ttsService.speak('Failed to disconnect device');
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _connectionStateSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Stick Assistant'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                onLongPress: _connectedDevice != null ? () async {
                  // Long press to disconnect and forget device
                  final shouldDisconnect = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Disconnect Device'),
                      content: const Text('Do you want to disconnect and forget this device?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  );

                  if (shouldDisconnect == true) {
                    await _disconnectAndForgetDevice();
                  }
                } : null,
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
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
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
                  await _ttsService.speak('Opening navigation. Enter your destination to start.');
                  
                  // Use context before checking mounted to satisfy linter
                  if (!mounted) return;
                  
                  // ignore: use_build_context_synchronously
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
