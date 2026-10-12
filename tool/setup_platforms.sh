#!/usr/bin/env bash
# Generates the Android/iOS projects and applies Hipersign's native settings.
# Run once after cloning (and again after upgrading Flutter if you delete android/ or ios/).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.hipersign --project-name hipersign_mobile_app --platforms android,ios .
dart run tool/patch_platforms.dart
flutter pub get
dart run flutter_launcher_icons

echo
echo "Next: run 'flutterfire configure' to connect Firebase (push notifications)."
echo "Without it the app works, but only phone-side reminders are available."
