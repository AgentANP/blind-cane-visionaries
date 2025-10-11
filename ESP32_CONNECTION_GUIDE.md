# ESP32 Connection Guide - Quick Setup

## 🎯 How to Connect Your App to the ESP32 Stick

### Step 1: Prepare the ESP32

Your ESP32 needs to run this code (upload using Arduino IDE):

```cpp
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// UUIDs - You can use these or generate your own
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

// Callback for connection/disconnection
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Device disconnected");
      // Restart advertising to allow reconnection
      BLEDevice::getAdvertising()->start();
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting BLE Smart Stick...");

  // Initialize BLE with a clear name
  BLEDevice::init("Smart Stick ESP32");  // <-- Your stick will show up with this name!
  
  // Create BLE Server
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Create BLE Characteristic for sending data (like SOS)
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  
  // Add descriptor to enable notifications
  pCharacteristic->addDescriptor(new BLE2902());
  
  // Start the service
  pService->start();
  
  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Helps with iOS connections
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->start();
  
  Serial.println("BLE Device is now advertising as 'Smart Stick ESP32'");
  Serial.println("Waiting for app to connect...");
}

void loop() {
  // Example: Send SOS if a button is pressed
  // Connect button to GPIO 4 (or any pin you choose)
  static bool lastButtonState = HIGH;
  int buttonState = digitalRead(4);  // Change pin number as needed
  
  if (buttonState == LOW && lastButtonState == HIGH && deviceConnected) {
    // Button pressed - send SOS
    Serial.println("SOS Button Pressed! Sending SOS signal...");
    pCharacteristic->setValue("SOS");
    pCharacteristic->notify();
    delay(1000);  // Debounce
  }
  
  lastButtonState = buttonState;
  delay(100);
}
```

### Step 2: Upload Code to ESP32

1. Open Arduino IDE
2. Install ESP32 board support (if not already):
   - Go to **File → Preferences**
   - Add to "Additional Board Manager URLs": 
     `https://dl.espressif.com/dl/package_esp32_index.json`
   - Go to **Tools → Board → Boards Manager**
   - Search "ESP32" and install "esp32 by Espressif"

3. Install required libraries:
   - Go to **Sketch → Include Library → Manage Libraries**
   - No additional libraries needed (BLE is built-in for ESP32)

4. Select your board:
   - **Tools → Board → ESP32 Dev Module** (or your specific ESP32 model)
   - **Tools → Port** → Select your COM port

5. Upload the code

### Step 3: Test the Connection

#### 3.1 Power On ESP32
- After upload, open **Serial Monitor** (115200 baud)
- You should see:
  ```
  Starting BLE Smart Stick...
  BLE Device is now advertising as 'Smart Stick ESP32'
  Waiting for app to connect...
  ```

#### 3.2 Open Your Flutter App
1. Launch the app on your Android phone
2. The home screen shows Bluetooth status (should be red: "Disconnected")

#### 3.3 Scan for Devices
1. **Tap the red Bluetooth status card** at the top of home screen
2. You'll see the Bluetooth connection screen
3. **Tap "Scan for Devices"** button
4. Wait up to 15 seconds
5. **Look for "Smart Stick ESP32"** in the list

#### 3.4 Connect
1. **Tap on the "Smart Stick ESP32"** device card
2. App will say "Connecting to Smart Stick ESP32"
3. On ESP32 serial monitor, you'll see: `Device connected`
4. App will say "Connected to stick"
5. You'll return to home screen with **green status**: "Connected: Smart Stick ESP32"

### Step 4: Test SOS Signal

1. Make sure app shows "Connected" (green)
2. Press the button connected to GPIO 4 on your ESP32
3. ESP32 serial monitor shows: `SOS Button Pressed! Sending SOS signal...`
4. App should:
   - Announce: "Emergency SOS button pressed on stick"
   - Show red emergency dialog with your location
   - Display GPS coordinates

## 🔍 Troubleshooting

### Problem: ESP32 not showing in scan

**Check:**
- ✅ ESP32 is powered on (LED should be on)
- ✅ Serial Monitor shows "BLE Device is now advertising"
- ✅ ESP32 is within 10 meters of your phone
- ✅ Phone Bluetooth is ON
- ✅ Phone Location Services are ON (required for BLE scanning on Android)

**Try:**
- Restart ESP32 (press reset button)
- Turn phone Bluetooth off and on
- Close and reopen the app

### Problem: Device shows as "Unknown Device"

**Cause:** The device name isn't being advertised properly

**Fix:** Make sure line 38 in ESP32 code says:
```cpp
BLEDevice::init("Smart Stick ESP32");
```

**Note:** The app now filters devices smartly:
- Shows devices with "stick", "esp32", or "smart" in name
- Shows devices with strong signal (close to you)
- Your ESP32 should match one of these criteria

### Problem: Connection fails

**Check:**
- ✅ ESP32 isn't already connected to another device/app
- ✅ Serial Monitor shows "Device connected"
- ✅ App has Bluetooth permissions granted

**Try:**
- Restart ESP32
- Close app completely and reopen
- Go to phone Settings → Apps → Smart Stick → Permissions → Check Bluetooth is allowed

### Problem: SOS not detected

**Check:**
- ✅ Button is connected to GPIO 4 (or change pin number in code)
- ✅ Button wiring: One side to GPIO 4, other side to GND
- ✅ Pull-up is enabled (default on ESP32)
- ✅ Serial Monitor shows "SOS Button Pressed!"

**Debug:**
- Use nRF Connect app to verify ESP32 is sending "SOS"
- Check that notify is being called after setValue

## 📝 Customization

### Change Device Name
Line 38 in ESP32 code:
```cpp
BLEDevice::init("My Custom Stick Name");
```

### Change Button Pin
Line 53 in ESP32 code:
```cpp
int buttonState = digitalRead(4);  // Change 4 to your pin number
```

### Add More Features
You can send other signals besides SOS:
```cpp
// Example: Low battery warning
pCharacteristic->setValue("LOW_BATTERY");
pCharacteristic->notify();

// Example: Obstacle detected
pCharacteristic->setValue("OBSTACLE");
pCharacteristic->notify();
```

The app listens for "SOS" specifically. For other signals, you'd need to update the app code in `_setupSignalListeners()`.

## ✅ Success Checklist

- [ ] ESP32 code uploaded successfully
- [ ] Serial Monitor shows "BLE Device is now advertising"
- [ ] App finds "Smart Stick ESP32" in device scan
- [ ] App successfully connects (green status on home screen)
- [ ] Serial Monitor shows "Device connected"
- [ ] SOS button press triggers app emergency dialog
- [ ] App shows GPS location in emergency dialog

## 🎉 Next Steps

Once connection is working:
1. **Mount ESP32 in your stick** - Make sure it's secure and powered
2. **Test range** - Walk around to see how far connection works (typically 10m)
3. **Test auto-reconnect** - Close and reopen app, it should reconnect automatically
4. **Add emergency contacts** - Go to Settings and add contacts for SOS alerts
5. **Test in real scenarios** - Use the stick while walking to ensure reliable connection

## 📞 Need Help?

If connection still doesn't work:
1. Share the Serial Monitor output
2. Share the app console logs (from Android Studio or VS Code)
3. Check which Android version you're using (Android 12+ is better for BLE)
4. Try with a different ESP32 board if available
