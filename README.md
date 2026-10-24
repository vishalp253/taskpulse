# TaskPulse

Flutter app for Android and Windows with Firebase task sync and scheduled FCM reminders.

## First setup

Prerequisites: Flutter stable (with Windows desktop enabled), Android SDK, Node.js 20, npm, Firebase CLI, and a Firebase project with Firestore, Authentication, and Cloud Messaging enabled.

```powershell
flutter config --enable-windows-desktop
dart pub global activate flutterfire_cli
firebase login
firebase use --add
flutterfire configure --project YOUR_FIREBASE_PROJECT_ID --platforms android,windows
flutter pub get
cd functions
npm install
npm run build
cd ..
```

`flutterfire configure` generates `lib/firebase_options.dart` and adds the native Firebase configuration. Enable Email/Password (or another sign-in provider) in Firebase Authentication before allowing users to create task documents.

## Deploy

```powershell
firebase deploy --only firestore:rules,firestore:indexes,functions
```

The scheduled function uses Cloud Scheduler; Firebase may require the project to be on the Blaze plan and will prompt to enable Scheduler-related APIs on first deployment.

## Run

```powershell
flutter run -d windows
flutter build apk --release
```

Firestore task timestamps (`nextFireAt`) are UTC instants. Before relying on FCM, the signed-in client must upsert each FCM token at `users/{uid}/user_devices/{deviceId}` with `{ fcmToken, platform, enabled: true, updatedAt }`. The scheduler reads `tasks` with `status == "scheduled"` and `nextFireAt` within the preceding minute. A `notificationReceipts` document is created for each task occurrence to avoid duplicate delivery on scheduler retries.

## Current implementation boundary

The repository contains the app bootstrap, Windows tray/hotkey integration, overlay card, and scheduled FCM dispatcher. Task CRUD, Firebase sign-in/device-token persistence, recurrence advancement, and real Done/Snooze/Skip writes must be connected to the app's authenticated repository before release; the corresponding desktop action methods and quick-add save handler are intentionally visible integration points. The overlay is a persistent modal owned by the running Windows app; a force-quit or disabled app process cannot show a local Windows overlay. Android push delivery is independent while the Windows device is off.
