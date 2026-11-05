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
- Mood choices include feelings and communication preferences such as needing
  space, wanting company, or asking for support.
- Both paired accounts see entries update live while the app is open. The
  partner account is read-only.
- On Android, the partner can receive push notifications when the tracker adds,
  edits, or deletes a daily entry, including while the app is closed. Push
  delivery uses a Cloudflare Worker and Firebase Cloud Messaging (FCM); it does
  not use Firebase Cloud Functions.
- The home screen keeps an unclaimed invite code visible, and the profile page
  shows account role, partner display name, pairing status, and connection date.
- Entries appear on a calendar and in a recent-entry list.

Pairing gives both accounts access to the shared cycle and mood entries. The
app explains this before pairing, and the tracker sees a reminder when saving
an entry. Each person chooses a display name when creating or joining an invite
and can change it later in Profile & pairing. Partner email addresses are not
shared.

## Requirements

- Flutter SDK with a Dart version matching the constraint in `pubspec.yaml`.
- A Firebase project with Email/Password sign-in enabled and Cloud Firestore initialized.

Firebase App configuration is currently included for Android and web. Push notifications
are currently supported on Android only; other platforms are not configured yet.
If you use your own Firebase project, configure it with the FlutterFire CLI and
replace the Android Firebase configuration as appropriate.

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
couples or expose other invite codes. Each signed-in user can write only their
own FCM device token under `users/{uid}/devices`; clients cannot read those
tokens.

Deploy the rules to the configured Firebase project before entering real
health data:

```powershell
firebase deploy --only firestore:rules --project cycle-companion-9df05
```

## Push notification setup

FCM delivery is free. The Worker runs on Cloudflare's free tier (subject to its
current usage limits), and Firebase Cloud Functions/Blaze are not required.
Notifications are sent only for daily-log changes and summarize changed fields
such as period status, mood, symptoms, flow, and pain level. Note contents are
never included; a note change is labeled only as "note updated".

1. Enable the **Firebase Cloud Messaging API** and **Cloud Firestore API** in
   the Google Cloud project used by the app.
2. Create a Google Cloud service account for the Worker. Grant it
   `Cloud Datastore User` access for Firestore and
   `Firebase Cloud Messaging API Admin` access to send FCM messages. Create a
   JSON key, and keep it private.
3. From `Cycle Companion/cloudflare-worker`, authenticate Wrangler and save the
   service account credentials as Worker secrets:

   ```powershell
   npx wrangler login
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
   npx wrangler deploy
   ```

   For the private-key secret, paste the service account JSON's
   `private_key` value. Never commit the key or put it in the Flutter app.
   The Worker verifies Firebase ID tokens, checks that the caller is the
   tracker in the requested pairing, and obtains the viewer's device tokens
   from Firestore before sending.
4. Run/build the Android app with the deployed Worker URL:

   ```powershell
   cd "Cycle Companion"
   flutter run --dart-define=PUSH_API_URL=https://cycle-companion-push.<your-account>.workers.dev/notify
   ```

   Use the same `--dart-define` when building a release. The viewer must open
   the app and allow notifications once so the app can register its FCM token.
   The tracker then notifies the Worker after each successful daily-log change.
   Local Flutter web origins on `localhost` and `127.0.0.1` are allowed for
   development. If the tracker app is hosted on the web, set the exact site
   origin in the Worker `ALLOWED_ORIGINS` variable before deploying.

Deploy updated Firestore rules before testing, and do not add the service
account key to source control.

The Firebase client configuration is not an access-control mechanism.
Unpairing and data deletion controls are not yet available; only pair with
someone who should have access to the shared entries.
