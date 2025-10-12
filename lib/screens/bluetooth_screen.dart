import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/tts_service.dart';

class BluetoothScreen extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceConnected;
  
  const BluetoothScreen({super.key, required this.onDeviceConnected});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final TtsService _ttsService = TtsService();

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkBluetoothSupport();
  }

  Future<void> _initTts() async {
    await _ttsService.initialize();
  }

  Future<void> _speak(String text) async {
    await _ttsService.speak(text);
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
          advName.contains(keyword)) {
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
              
              print('Adding device:');
              print('  Platform Name: $deviceName');
              print('  Advertised Name: $advertisedName');
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
    _ttsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Stick'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
