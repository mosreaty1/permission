# PermissionHub — Setup Guide

## What you get
- **Flutter APK**: Mobile app that requests ALL device permissions, browses files & images, syncs permission state from Firebase in real-time
- **Web Dashboard**: Admin panel to toggle each permission ON/OFF per user — changes apply instantly on mobile

---

## Step 1 — Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click **Add project** → name it (e.g. `permission-hub`)
3. Enable **Google Analytics** (optional)

### Enable Authentication
- Firebase Console → **Authentication** → **Sign-in method**
- Enable **Email/Password**

### Enable Firestore
- Firebase Console → **Firestore Database** → **Create database**
- Start in **production mode**
- Choose a region close to you

### Upload Firestore Rules
- Firestore → **Rules** tab → paste contents of `firebase/firestore.rules` → Publish

---

## Step 2 — Add Admin User

1. Firebase Console → Authentication → **Add user** → your admin email & password
2. Copy the **UID** of the admin user
3. Firestore → **Start collection** → Collection ID: `admins`
4. Document ID: paste the admin UID → Add field: `email` (string) → your email → Save

---

## Step 3 — Configure Web Dashboard

1. Firebase Console → Project Settings → **Your apps** → click **</>** (Web)
2. Register app name (e.g. `admin-dashboard`)
3. Copy the `firebaseConfig` object
4. Open `web_dashboard/js/firebase-config.js`
5. Replace the placeholder values with your config

Then just open `web_dashboard/index.html` in your browser — no server needed!

---

## Step 4 — Configure Flutter App

### Add Android app to Firebase
1. Firebase Console → **Add app** → Android
2. Android package name: `com.example.permission_app`
3. Download `google-services.json`
4. Place it at: `flutter_app/android/app/google-services.json`

### Update firebase_options.dart
Open `flutter_app/lib/firebase_options.dart` and fill in your Firebase values:
```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey:            'YOUR_API_KEY',
  appId:             'YOUR_APP_ID',
  messagingSenderId: 'YOUR_SENDER_ID',
  projectId:         'YOUR_PROJECT_ID',
  storageBucket:     'YOUR_PROJECT_ID.appspot.com',
);
```

Or run `flutterfire configure` to auto-generate this file.

### Update android/build.gradle (project level)
```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

### Update android/app/build.gradle (bottom)
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

## Step 5 — Build the APK

```bash
cd flutter_app
flutter pub get
flutter build apk --release
```

APK will be at: `flutter_app/build/app/outputs/flutter-apk/app-release.apk`

Transfer to your phone via USB, WhatsApp, or email and install.

> Enable "Install from unknown sources" in Android settings if prompted.

---

## How It Works

```
Admin Dashboard (Web)
       │
       │ toggles permission ON/OFF
       ▼
   Firebase Firestore
  users/{uid}/permissions
       │
       │ real-time onSnapshot listener
       ▼
 Flutter App (Mobile)
       │
       │ auto-requests newly enabled permissions
       ▼
   Android Permission Dialog
```

1. User registers in the mobile app → account appears in admin dashboard
2. Admin opens dashboard → finds the user → toggles permissions
3. Mobile app listens in real-time → automatically prompts for newly enabled permissions
4. User can browse files and images if Storage/Photos permission is enabled

---

## Permission List (18 total)

| ID | Label | Android Permission |
|----|-------|--------------------|
| camera | Camera | CAMERA |
| microphone | Microphone | RECORD_AUDIO |
| location | Location | ACCESS_FINE_LOCATION |
| location_always | Location Always | ACCESS_BACKGROUND_LOCATION |
| storage | Storage | READ/WRITE_EXTERNAL_STORAGE |
| photos | Photos & Media | READ_MEDIA_IMAGES/VIDEO |
| contacts | Contacts | READ/WRITE_CONTACTS |
| phone | Phone | CALL_PHONE, READ_PHONE_STATE |
| sms | SMS | SEND/RECEIVE/READ_SMS |
| call_log | Call Log | READ_CALL_LOG |
| bluetooth | Bluetooth | BLUETOOTH_CONNECT |
| bluetooth_scan | Bluetooth Scan | BLUETOOTH_SCAN |
| notifications | Notifications | POST_NOTIFICATIONS |
| calendar | Calendar | READ/WRITE_CALENDAR |
| sensors | Body Sensors | BODY_SENSORS |
| activity | Activity | ACTIVITY_RECOGNITION |
| nearby_wifi | Nearby WiFi | NEARBY_WIFI_DEVICES |
| manage_storage | Manage All Files | MANAGE_EXTERNAL_STORAGE |
