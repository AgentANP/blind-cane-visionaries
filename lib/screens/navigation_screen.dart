import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../utils/constants.dart';
import '../models/place_suggestion.dart';
import '../services/tts_service.dart';
import '../services/location_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final TtsService _ttsService = TtsService();
  
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isNavigating = false;
  List<dynamic> _navigationSteps = [];
  int _currentStepIndex = 0;
  LatLng? _destination;
  StreamSubscription<Position>? _positionStream;
  bool _hasAnnouncedUpcoming = false;
  bool _hasAnnouncedNow = false;
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _getCurrentLocation();
  }

  Future<void> _initializeTts() async {
    await _ttsService.initialize();
  }

  Future<void> _speak(String text) async {
    await _ttsService.speak(text);
  }

  Future<void> _getCurrentLocation() async {
    final permissionResult = await LocationService.checkAndRequestPermission();
    
    if (!permissionResult.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(permissionResult.message ?? 'Permission denied')),
      );
      return;
    }
    
    final position = await LocationService.getCurrentPosition();
    
    if (position != null) {
      setState(() {
        _currentPosition = position;
        _markers.add(
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to get current location')),
      );
    }
  }

  Future<List<PlaceSuggestion>> _fetchSuggestions(String query) async {
    if (query.length < 3) return [];
    
    
    String url = 
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&components=country:in&key=${AppConstants.googleApiKey}';
    
    
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
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=${suggestion.placeId}&fields=name,geometry&key=${AppConstants.googleApiKey}';
    
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
        'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=$destLat,$destLng&mode=walking&key=${AppConstants.googleApiKey}';
    
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
      
      if (distanceToDestination < AppConstants.arrivalDistanceThreshold) {
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
      
      // Announce upcoming turn when at configured distance
      if (distanceToStepEnd <= AppConstants.upcomingTurnDistance && 
          distanceToStepEnd > 15 && 
          !_hasAnnouncedUpcoming) {
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
          
          if (distanceToNext <= AppConstants.upcomingTurnDistance) {
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
    _ttsService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
