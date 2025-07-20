
# 🩺 MediTrack Rx

MediTrack Rx is a medicine and patient management app built with **Flutter** and **Firebase**. It helps manage medicine inventories, patient schedules, and automatically logs medicine intake with real-time alerts and reminders.

---

## 📱 Features

- 🔔 **Scheduled Medicine Reminders**  
  Get notified when it’s time to take medicine with **Taken** and **Missed** options.

- 🗂️ **Medicine Inventory**  
  Manage up to 10 medicine slots with names and expiry dates.

- 🧑‍⚕️ **Patient Management**  
  Add patients and assign scheduled medicines.

- 📋 **Automatic Logs**  
  Automatically record whether medicine was taken or missed.

- 🌙 **Dark & Light Theme Support**

- 📅 **Calendar & Time Picker Integration**

- 🇵🇭 **Asia/Manila Timezone Awareness**

---

## 🛠️ Built With

- [Flutter](https://flutter.dev/)
- [Firebase Firestore](https://firebase.google.com/)
- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
- [timezone](https://pub.dev/packages/timezone)

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK installed
- Firebase project with Firestore
- Android device or emulator

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/meditrackrx.git
   cd meditrackrx
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project.
   - Add your platform (iOS/Android) and download `google-services.json` / `GoogleService-Info.plist`.
   - Replace the contents of `firebase_options.dart` with your own configuration.

4. **Run the app**
   ```bash
   flutter run
   ```

---

## 📁 Folder Structure

```
📁 android
│
├── 📁 app
│   ├── 📁 src
│   │   └── 📁 main
│   │       └── 📄 AndroidManifest.xml
│   │
│   ├── 📄 build.gradle.kts
│   └── 📄 google-services.json
│
├── 📄 build.gradle.kts
│
📁 lib
├── 📄 firebase_options.dart
└── 📄 main.dart
│
📄 pubspec.yaml
```

---

## 👨‍💻 Authors

- Agdan, Clarissa R.
- Datinguinoo, Joshua S.
- Sistona, Jersey F.


---


## 📝 License

This project is for academic purposes under Batangas State University TNEU.
All rights reserved © 2025
