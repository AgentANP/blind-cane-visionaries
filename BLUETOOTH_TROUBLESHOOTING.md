# Bluetooth Scan Troubleshooting Guide

## Issue: "Scan failed" Error When Pressing "Scan for Devices"

### Most Common Causes:

### 1. **Location Services Are OFF** ⚠️ (Most Likely!)
**Android requires location services to be enabled for Bluetooth scanning**, even though we're not using location data.

**Fix:**
1. Open Android Settings → Location
2. Turn ON "Use location"
3. Return to Smart Stick app
4. Try scanning again

### 2. **Location Permission Not Granted**
The app needs "Allow all the time" or "While using the app" location permission.

**Fix:**
1. Open Android Settings → Apps → Smart Stick
2. Tap "Permissions"
3. Tap "Location"
4. Select "Allow all the time" or "While using the app"
5. Return to app and try again

### 3. **Bluetooth is OFF**
The app should prompt you to turn on Bluetooth, but sometimes it doesn't.

**Fix:**
1. Swipe down from top of screen
2. Tap Bluetooth icon to turn it ON
3. Try scanning again

### 4. **Nearby Devices Permission (Android 12+)**
On Android 12 and newer, there's a new "Nearby devices" permission.

**Fix:**
1. Open Android Settings → Apps → Smart Stick
2. Tap "Permissions"
3. Look for "Nearby devices" or "Bluetooth"
4. Set to "Allow"

---

## Quick Diagnostic Steps:

### Step 1: Check Bluetooth
- Swipe down from top
- Ensure Bluetooth icon is blue/active
- If not, tap to enable

### Step 2: Enable Location Services
- Settings → Location
- Toggle ON

### Step 3: Grant ALL Permissions
- Settings → Apps → Smart Stick → Permissions
- Location: "Allow all the time"
- Nearby devices: "Allow"

### Step 4: Restart App
- Close Smart Stick completely
- Reopen and try scanning

---

## What the Error Log Should Show:

When you press "Scan for Devices", check the terminal output for:

```
Scan error: <error details here>
```

Common error messages:
- `BluetoothAdapterState.off` → Bluetooth is OFF
- `permission denied` → Location permission not granted
- `location services disabled` → GPS/Location services are OFF
- `user denied` → You tapped "Deny" on a permission prompt

---

## Testing Checklist:

✅ **Before Testing:**
1. [ ] Bluetooth is ON (blue icon in notification shade)
2. [ ] Location services are ON (Settings → Location)
3. [ ] Location permission granted (Settings → Apps → Smart Stick → Permissions → Location → Allow)
4. [ ] Nearby devices permission granted (Android 12+)
5. [ ] ESP32 stick is powered ON and advertising

✅ **During Test:**
1. Open Smart Stick app
2. Tap red "Disconnected: Standby" card
3. Wait for Bluetooth screen to load
4. Tap "Scan for Devices"
5. Voice should say "Scanning for stick devices"
6. Wait 15 seconds for scan to complete
7. Devices should appear in list

✅ **Expected Result:**
- Scan runs for full 15 seconds
- Voice announces "Found X devices" or "No devices found"
- Device list shows all nearby Bluetooth devices

❌ **If Scan Fails Immediately:**
- Check location services (most common issue!)
- Check permissions
- Read error in terminal/logcat

---

## Advanced Debugging:

### View Detailed Logs:
```powershell
# In terminal, after starting the app:
flutter run

# Then press "Scan for Devices" button
# Watch for "Scan error:" message
```

### Check Android Logcat:
```powershell
adb logcat | findstr "flutter"
```

### Force Permission Request:
If app doesn't ask for permissions:
1. Settings → Apps → Smart Stick
2. Storage → Clear Data
3. Reopen app (will ask for permissions again)

---

## Code Changes Made:

### 1. Added Bluetooth State Check
Before scanning, the app now checks if Bluetooth is ON:
```dart
final adapterState = await FlutterBluePlus.adapterState.first;
if (adapterState != BluetoothAdapterState.on) {
  // Show error and try to turn on Bluetooth
}
```

### 2. Improved Error Messages
Different errors now give specific guidance:
- Permission error → "grant permissions in settings"
- Adapter error → "turn on Bluetooth"
- Other errors → "try again"

### 3. Added Visual Feedback
- SnackBar shows error details
- Voice announces what went wrong
- Status updates properly

---

## Next Steps if Still Failing:

1. **Test with Another Bluetooth Scanner App:**
   - Install "nRF Connect" from Play Store
   - Try scanning for devices
   - If this also fails → phone Bluetooth issue
   - If this works → Smart Stick app issue

2. **Check Phone Bluetooth Settings:**
   - Settings → Connected devices → Connection preferences → Bluetooth
   - Ensure "Bluetooth" is ON
   - Try "Pair new device" manually

3. **Restart Phone:**
   - Sometimes Bluetooth stack gets stuck
   - Full phone restart can fix it

4. **Check Android Version:**
   - Settings → About phone → Android version
   - Android 12+ has stricter Bluetooth permissions
   - May need to grant permissions manually

---

## What Should Happen (Success Case):

1. User taps "Scan for Devices"
2. Voice: "Scanning for stick devices"
3. Screen shows "Scanning..." with hourglass icon
4. After 15 seconds:
   - If devices found: Voice says "Found X devices", list appears
   - If none found: Voice says "No devices found. Make sure the stick is turned on."

5. User taps "Connect" on ESP32 device
6. Voice: "Connecting to [Device Name]"
7. Connection succeeds
8. Returns to home screen with green "Connected: [Device Name]"

---

## Contact Developer If:

- Location services are ON but still fails
- All permissions granted but still fails  
- Other Bluetooth apps work fine
- Error message is unclear

Provide:
- Android version
- Phone model
- Full error log from terminal
- Screenshot of permissions page

