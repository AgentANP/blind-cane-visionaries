# Bluetooth ESP32 Integration - Implementation Guide

## ✅ What Has Been Implemented

### 1. **Bluetooth Connection Screen**
- **Location**: Tap the Bluetooth status card on the home screen
- **Features**:
  - Device scanning (15-second scan timeout)
  - Visual list of all discovered Bluetooth devices
  - One-tap connection to ESP32 stick
  - Voice announcements for scanning and connection status

### 2. **Dynamic Connection Status**
- **Home Screen Status Card** shows:
  - 🔴 **Disconnected: Standby** (red) - No device connected
  - 🟢 **Connected: [Device Name]** (green) - Successfully connected
  - Real-time updates when connection changes

### 3. **Auto-Reconnect Feature**
- App remembers the last connected device (stored in SharedPreferences)
- Automatically attempts to reconnect on app restart
- Status updates to "Reconnecting..." during the process

### 4. **SOS Signal Listener**
When connected to the ESP32 stick:
- Listens for Bluetooth notifications from the stick
- Detects when "SOS" text is sent from ESP32
- **Automatic Response**:
  1. Voice announcement: "Emergency SOS button pressed on stick"
  2. Gets current GPS location
  3. Shows red emergency dialog with:
     - Location address
     - GPS coordinates
     - Options: "I'm Safe" or "Alert Contacts"

### 5. **Voice Feedback (Indian English)**
All Bluetooth actions have TTS announcements:
- "Scanning for stick devices"
- "Found X devices"
- "No devices found. Make sure the stick is turned on."
- "Connecting to [Device Name]"
- "Connected to stick"
- "Failed to connect to stick"
- "Emergency SOS button pressed on stick"

---

## 📱 Android Permissions Added

Added to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
                 android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>

<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>
```

These permissions allow:
- **BLUETOOTH** - Basic Bluetooth access
- **BLUETOOTH_ADMIN** - Device discovery and connection
- **BLUETOOTH_SCAN** - Scanning for nearby devices (Android 12+)
- **BLUETOOTH_CONNECT** - Connecting to paired/discovered devices (Android 12+)

---

## 🔧 ESP32 Configuration Requirements

### For the Hardware Team:

Your ESP32 controller should:

1. **Enable Bluetooth** (Classic or BLE):
   ```cpp
   // For BLE (Recommended)
   #include <BLEDevice.h>
   #include <BLEServer.h>
   #include <BLEUtils.h>
   ```

2. **Make device discoverable**:
   - Set a clear device name (e.g., "SmartStick_001")
   - Enable advertising so the app can find it

3. **Create a characteristic for notifications**:
   - The app listens to ALL characteristics that support notifications
   - When SOS button is pressed, send the text "SOS" through any notify characteristic

4. **Example BLE Code for ESP32**:
   ```cpp
   #define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
   #define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
   
   BLECharacteristic *pCharacteristic;
   
   void setup() {
     BLEDevice::init("SmartStick_001");
     BLEServer *pServer = BLEDevice::createServer();
     BLEService *pService = pServer->createService(SERVICE_UUID);
     
     pCharacteristic = pService->createCharacteristic(
                         CHARACTERISTIC_UUID,
                         BLECharacteristic::PROPERTY_READ |
                         BLECharacteristic::PROPERTY_NOTIFY
                       );
     
     pService->start();
     BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
     pAdvertising->start();
   }
   
   void sendSOSSignal() {
     pCharacteristic->setValue("SOS");
     pCharacteristic->notify();
   }
   ```

5. **SOS Button Handler**:
   ```cpp
   const int SOS_BUTTON_PIN = 2;
   
   void loop() {
     if (digitalRead(SOS_BUTTON_PIN) == LOW) {
       sendSOSSignal();
       delay(1000); // Debounce
     }
   }
   ```

---

## 🧪 Testing Instructions

### Test 1: Device Discovery
1. Open the Smart Stick app
2. Tap the red "Disconnected: Standby" card on home screen
3. Turn on your ESP32 stick's Bluetooth
4. Tap "Scan for Devices" button
5. ✅ **Expected**: ESP32 device appears in the list within 15 seconds

### Test 2: Connection
1. From the device list, tap "Connect" button next to your ESP32
2. ✅ **Expected**: 
   - Voice says "Connecting to [Device Name]"
   - Then "Connected to stick"
   - Returns to home screen
   - Status card turns green: "Connected: [Device Name]"

### Test 3: Auto-Reconnect
1. Connect to ESP32 (as in Test 2)
2. Close the app completely
3. Reopen the app
4. ✅ **Expected**: 
   - Status shows "Reconnecting..."
   - Then automatically connects
   - Status turns green again

### Test 4: SOS Signal
1. Ensure ESP32 is connected
2. Press the SOS button on your physical stick
3. ESP32 should send "SOS" text via Bluetooth
4. ✅ **Expected**:
   - Voice announces: "Emergency SOS button pressed on stick"
   - Red emergency dialog appears
   - Shows current location and coordinates
   - Two buttons: "I'm Safe" and "Alert Contacts"

---

## 🔍 Troubleshooting

### "No devices found"
- ✅ Ensure ESP32 Bluetooth is enabled and advertising
- ✅ Make sure ESP32 is within range (typically 10 meters)
- ✅ Check that Android location services are enabled (required for Bluetooth scanning)
- ✅ Try turning Bluetooth off/on in Android settings

### "Connection failed"
- ✅ Restart the ESP32
- ✅ Clear app data and reconnect
- ✅ Check ESP32 isn't already connected to another device
- ✅ Ensure ESP32 accepts incoming connections (not just advertising)

### "SOS not detected"
- ✅ Verify ESP32 is sending exactly "SOS" (case-insensitive)
- ✅ Check that characteristic has NOTIFY property enabled
- ✅ Use a Bluetooth scanner app (like nRF Connect) to verify ESP32 is sending data
- ✅ Check that `notify()` is called after `setValue("SOS")`

### App crashes on Bluetooth screen
- ✅ Ensure location permission is granted (Android requires it for BLE scan)
- ✅ Check logcat for specific error messages
- ✅ Try on Android 12+ device (better Bluetooth permission handling)

---

## 📊 Technical Details

### Packages Used
- **flutter_blue_plus**: ^1.36.8 - Bluetooth communication
- **shared_preferences**: ^2.5.3 - Storing last connected device

### Key Classes
1. **BluetoothScreen** (line ~1470)
   - Handles scanning and connection UI
   - Uses `FlutterBluePlus.startScan()` for device discovery
   - 15-second scan timeout

2. **HomePage._connectToDevice()** (line ~232)
   - Manages connection logic
   - Calls `_setupSignalListeners()` after connection
   - Saves device ID for auto-reconnect

3. **HomePage._setupSignalListeners()** (line ~267)
   - Discovers all services and characteristics
   - Subscribes to all notify-enabled characteristics
   - Listens for "SOS" string in incoming data

4. **HomePage._handleSOSSignal()** (line ~296)
   - Gets current GPS location
   - Shows emergency dialog
   - Provides voice feedback

### Data Flow
```
ESP32 Button Press 
  → ESP32 sends "SOS" via BLE notify
  → App's characteristic listener receives data
  → _setupSignalListeners() detects "SOS" string
  → _handleSOSSignal() triggered
  → Voice announcement + Emergency dialog + Location fetch
```

---

## 🚀 Next Steps (Not Yet Implemented)

### 1. Emergency Contact Alerts
When "Alert Contacts" is pressed:
- Send SMS to saved emergency contacts
- Include current location link (Google Maps)
- Requires SMS permission

### 2. Background Service
- Keep Bluetooth connection alive when app is minimized
- Use Android Foreground Service
- Show persistent notification

### 3. Connection Strength Indicator
- Display RSSI (signal strength)
- Warn user if connection is weak
- Auto-reconnect on disconnect

### 4. Battery Level Monitoring
- Read battery level from ESP32
- Show in status card
- Alert when battery is low

### 5. Other Sensor Data
- Receive ultrasonic sensor readings
- Water detection alerts
- Fall detection signals

---

## 📝 Code Locations

| Feature | File | Line |
|---------|------|------|
| Bluetooth imports | main.dart | ~10 |
| Connection status variables | main.dart | ~66-68 |
| Load saved device | main.dart | ~206 |
| Connect to device | main.dart | ~232 |
| Setup signal listeners | main.dart | ~267 |
| Handle SOS signal | main.dart | ~296 |
| Bluetooth screen | main.dart | ~1470 |
| Android permissions | AndroidManifest.xml | ~10-17 |

---

## 🎯 Current Status: ✅ READY FOR TESTING

All core Bluetooth functionality is implemented and ready to test with your ESP32 hardware. The app can:
- ✅ Scan for ESP32 devices
- ✅ Connect to ESP32
- ✅ Auto-reconnect on app restart
- ✅ Listen for SOS signals
- ✅ Show emergency dialog with location

Test with your hardware team and report any issues!
