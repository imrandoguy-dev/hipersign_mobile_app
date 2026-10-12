# Hipersign — mobile app (Flutter)

Role-based employee app for Android and iOS, connected to ERPNext through the
[`hipersign_mobile`](../hipersign_mobile) Frappe app. The first workspace is **Sales**:

- **Calendar** (home): day / week / month. Today's assigned work comes first (light
  blue), then pending work carried over (yellow-orange). Overdue items stay visible
  until they are done.
- **Follow-ups**: Pending (yellow-orange) / Completed (green) / Rescheduled (violet),
  with WhatsApp and Call buttons on every card.
- **Meetings**: the same three tabs, plus meeting links and locations.
- **Customers**: search by name, phone or email across Customers and Leads, with
  WhatsApp and Call buttons.
- **Trials**: book a customer trial or training into a trainer's free slot; reschedule,
  cancel or complete it.
- **Notifications**: push for assignments, reschedules, reminders and trial updates.
  Phone-side reminders act as a backup.
- **+ button**: new follow-up, schedule meeting or book a trial. Only the actions the
  user's role allows are shown.

Everything is saved to ERPNext. The app only caches data for reading offline; any
change needs a connection and is confirmed only after the server accepts it.

## Requirements

- Flutter **3.38.1 or newer** (stable), Dart 3.10+
- Android Studio / SDK (Android), Xcode 16+ (iOS), JDK 17
- A site with the `hipersign_mobile` backend installed

## First-time setup

```bash
git clone https://github.com/imrandoguy-dev/hipersign_mobile_app
cd hipersign_mobile_app
bash tool/setup_platforms.sh     # flutter create + native settings (permissions, desugaring, iOS 15)
flutter run
```

`tool/setup_platforms.sh` generates `android/` and `ios/` and applies what the plugins
need: notification permissions and receivers, the default notification channel,
`tel:`/WhatsApp URL schemes, core-library desugaring, iOS 15, and background push. It
is safe to run again. It prints any step it could not apply automatically.

The default server is `https://nexus365.hipersignerp.cloud`. Users can change it on the
sign-in screen with the server button.

## Push notifications (Firebase)

The app works without Firebase, but then it can only use phone-side reminders. To
enable push:

```bash
dart pub global activate flutterfire_cli
flutterfire configure          # pick/create the Firebase project, select android + ios
```

This adds `google-services.json`, `GoogleService-Info.plist` and the Gradle plugin.
These files are git-ignored.

On the server, set up the service-account key as described in the backend README.

**iOS only, in Xcode** (`ios/Runner.xcworkspace` → Runner → *Signing & Capabilities*):

1. Add **Push Notifications**.
2. Add **Background Modes** and tick **Remote notifications**.
3. In Firebase → Cloud Messaging, upload your **APNs auth key** (.p8).

## Build

```bash
flutter build apk --release        # Android pilot build
flutter build appbundle            # Play Store
flutter build ipa                  # iOS (needs Apple signing)
```

For Play Store releases, add your own signing config in `android/app/build.gradle.kts`.
The template signs release builds with debug keys, which is fine for a pilot APK.

**CI**: every push runs `.github/workflows/build.yml`, which does analyze, tests, the
Android APK (downloadable as a workflow artifact) and an unsigned iOS compile.

## Making notifications reliable on Android

Phones from Xiaomi/Redmi, Oppo, Vivo, Realme and OnePlus kill background apps. **Settings →
Notifications** in the app explains the fix to each user: battery set to *Unrestricted*,
*Autostart* on, and the app locked in recents. Test on those phones before the rollout.

## Project layout

```
lib/
  app/            theme (PRD colours), navigation, refresh signal
  core/api/       HTTP client: envelope, error codes, Frappe login (sid)
  core/auth/      session, secure storage, role/capability profile
  core/cache/     per-user read cache (cleared on logout or role change)
  core/notifications/  FCM + local reminders, deep links
  core/repository.dart  all backend calls
  features/       calendar, activities, customers, trials, notifications, settings, shell
  shared/         models, cards, call/WhatsApp buttons
tool/             native project setup
```

## Adding the next workspaces

Roles map to *capabilities* on the server (`auth.get_me`). A new workspace (Cold
Caller, Trainer, HR, Manager) is a new capability set in
`hipersign_mobile/services/permissions.py`, plus a new tab set in
`features/shell/home_shell.dart`. Nothing in the app is hard-coded to job titles.
