# Cycle Companion

Cycle Companion is a Flutter app for sharing menstrual-cycle and daily mood
updates with a paired partner.

## What works today

- Create an account or sign in with Firebase Authentication.
- Pair two accounts using an eight-character invite code. The person who creates
  the invite chooses whether they will track or view; the joining account gets
  the other role.
- The tracker can mark period days and log a mood, symptoms, and an optional
  note for each day.
- Both paired accounts see entries update live while the app is open. The
  partner account is read-only.
- The home screen keeps an unclaimed invite code visible, and the profile page
  shows account role, partner display name, pairing status, and connection date.
- Entries appear on a calendar and in a recent-entry list.

Pairing gives both accounts access to the shared cycle and mood entries. The
app explains this before pairing, and the tracker sees a reminder when saving
an entry. Push notifications when the app is closed are not implemented yet.
Each person chooses a display name when creating or joining an invite and can
change it later in Profile & pairing. Partner email addresses are not shared.

## Requirements

- Flutter SDK with a Dart version matching the constraint in `pubspec.yaml`.
- A Firebase project with Email/Password sign-in enabled and Cloud Firestore initialized.

Firebase app configuration is currently included for Android and web. Other platforms are not configured yet. If you use your own Firebase project, configure it with the FlutterFire CLI and replace the Android Firebase configuration as appropriate.

## Run locally

From the repository root:

```powershell
cd "Cycle Companion"
flutter pub get
flutter run
```

Select an Android device/emulator or a configured web browser when prompted.

## Firestore security

The app stores daily check-ins at
`couples/{coupleId}/dailyLogs/{yyyy-MM-dd}`. The included `firestore.rules`
restricts reads to paired members and writes to the tracker account. Invite
codes are stored as individual documents so the app does not need to list
couples or expose other invite codes.

Deploy the rules to the configured Firebase project before entering real
health data:

```powershell
firebase deploy --only firestore:rules --project cycle-companion-9df05
```

The Firebase client configuration is not an access-control mechanism.
Unpairing and data deletion controls are not yet available; only pair with
someone who should have access to the shared entries.
