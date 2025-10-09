**1. ## Project Overview & Core Philosophy**

You are tasked with building a Flutter mobile application that serves as a foundational prototype for a "Smart Blind Stick" companion app. The primary goal of this specific build is to create and test core, phone-based features without implementing any hardware connectivity for now.

**Target User:** A visually impaired individual. **Accessibility is the absolute highest priority.** Every aspect of the UI and UX must be designed for a user who relies entirely on non-visual feedback (screen readers, audio cues, haptic responses). The design should be minimalist to reduce cognitive load and ensure ease of use.

**Core Design Principles:**
* **High Contrast & Legibility:** Use a dark theme with large, clear fonts.
* **Simplicity:** The layout must be simple, with large, easy-to-press buttons. Avoid complex gestures.
* **Screen Reader First:** All widgets must have proper semantic labels for full compatibility with TalkBack (Android) and VoiceOver (iOS).
* **Clear Audio Feedback:** All actions and errors should be accompanied by clear, spoken feedback using Text-to-Speech.

**2. ## Technology Stack & Key Libraries**

* **Framework:** Flutter (latest stable version)
* **Language:** Dart
* **State Management:** Use a simple and clear solution like Provider.
* **Required Packages:**
    * `geolocator`: For accessing the device's GPS coordinates.
    * `geocoding`: For converting GPS coordinates into a human-readable address.
    * `flutter_tts`: For all Text-to-Speech functionality.
    * `url_launcher`: To open the native voice assistant.
    * `flutter_contacts`: To access the phone's contacts for the emergency contacts feature.
    * `shared_preferences`: For persistently storing the saved emergency contacts on the device.

**3. ## UI/UX Breakdown (Screen by Screen)**

The application will consist of two main screens: a Main Screen and a Settings Screen.

**### 3.1 Main Screen**

This is the primary interface for the user. It should be extremely straightforward.

* **Layout:** A `Scaffold` with an `AppBar` and a `Column` body.
* **AppBar:** Should have a title like "Smart Stick Assistant" and an `IconButton` (e.g., a gear icon) to navigate to the Settings Screen.
* **UI Elements in the Body:**
    1.  **Bluetooth Status Placeholder (Top):** A static, non-functional text area to show where the future Bluetooth feature will be integrated. It should clearly display text like **"Stick Connection: Inactive"**. This is a visual placeholder only; do not implement any BLE logic.
    2.  **Location Display Area (Middle):** A large text widget, centered, that will display status messages. Its default text should be "Press 'Where Am I?' to get your current location."
    3.  **"Where Am I?" Button:** A large, full-width `ElevatedButton`. It should have an icon (e.g., `Icons.location_on`) and clear, all-caps text: **"WHERE AM I?"**.
    4.  **"Start Navigation" Button:** A second large, full-width `ElevatedButton`, visually distinct from the first (e.g., different color). It should have an icon (e.g., `Icons.mic`) and clear, all-caps text: **"START NAVIGATION"**.

**### 3.2 Settings Screen**

This screen is for configuring the app's safety features.

* **Layout:** A `Scaffold` with an `AppBar` titled "Settings". The body should be a `ListView`.
* **Emergency Contacts Section:**
    * A clear heading: **"Emergency Contacts"**.
    * A `ListView` to display the contacts that have been saved. Each list item should show the contact's **Name** and **Phone Number**. Each item should also have a **"Delete"** `IconButton` to remove that contact.
    * An **"Add Emergency Contact"** `ElevatedButton` at the bottom. Pressing this button will trigger the contact picker functionality.

**4. ## Feature-by-Feature Implementation Details**

**### 4.1 "Where Am I?" Button Logic**

* **Trigger:** On press of the "WHERE AM I?" button.
* **Action:**
    1.  Implement a loading state (e.g., `_isBusy = true`) to prevent multiple presses and update the status text to "Fetching location...".
    2.  Check for and request location permissions using `geolocator`.
    3.  Fetch the high-accuracy GPS coordinates (`Geolocator.getCurrentPosition`).
    4.  Convert the coordinates to a detailed address using `geocoding` (`placemarkFromCoordinates`).
    5.  Update the status text area with the human-readable address.
    6.  Use `flutter_tts` to speak the address clearly to the user (e.g., "You are near 123 Main Street...").
    7.  Handle all errors (e.g., permissions denied) by updating the status text and speaking the error message.
    8.  Finally, reset the loading state.

**### 4.2 "Start Navigation" Button Logic**

* **Trigger:** On press of the "START NAVIGATION" button.
* **Action:**
    1.  Use `url_launcher` to attempt to launch the native voice assistant via a URL scheme (e.g., `googleassistant://`).
    2.  If the launch fails (e.g., the app is not installed), provide a spoken fallback message via `flutter_tts`, such as "Could not open voice assistant. Please activate it manually."

**### 4.3 Emergency Contact Management Logic**

* **Trigger:** On press of the "Add Emergency Contact" button on the Settings screen.
* **Action:**
    1.  Check for and request contact permissions using `flutter_contacts`.
    2.  Open the phone's native contact picker.
    3.  When the user selects a contact, retrieve their display name and phone number.
    4.  Save this contact information (name and number) to the device's local storage using `shared_preferences`. Store it as a list of JSON objects for easy retrieval and deletion.
    5.  Update the UI on the Settings screen to display the newly added contact.
* **Deletion:** The "Delete" button next to each contact should remove that contact from `shared_preferences` and update the UI list.

**5. ## Setup Requirements & Final Output**

* **Permissions:** The generated code must include comments detailing the required permissions for both `AndroidManifest.xml` (Android: `ACCESS_FINE_LOCATION`, `READ_CONTACTS`) and `Info.plist` (iOS: `NSLocationWhenInUseUsageDescription`, `NSContactsUsageDescription`).
* **Code Structure:** Please structure the code logically. You can use a single `main.dart` file for this prototype, but clearly separate the UI widgets from the logic functions.
* **Final Output:** The final output should be a complete, runnable, and well-commented Flutter application that fulfills all the requirements listed above.