// Applies the native settings Hipersign needs on top of `flutter create` output.
// Idempotent: safe to run more than once.
//
//   dart run tool/patch_platforms.dart
//
// ignore_for_file: avoid_print
import 'dart:io';

int changes = 0;
final warnings = <String>[];

void main() {
  _androidManifest();
  _androidGradle();
  _androidMainActivity();
  _iosInfoPlist();
  _iosDeploymentTarget();
  _iosAppDelegate();
  print('\nPatched $changes item(s).');
  if (warnings.isNotEmpty) {
    print('\nManual steps needed:');
    for (final w in warnings) {
      print(' - $w');
    }
  }
}

String? _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    warnings.add('$path not found - run `flutter create --platforms android,ios .` first.');
    return null;
  }
  return f.readAsStringSync();
}

void _write(String path, String content, String what) {
  File(path).writeAsStringSync(content);
  changes++;
  print('ok  $what');
}

void _androidManifest() {
  const path = 'android/app/src/main/AndroidManifest.xml';
  var s = _read(path);
  if (s == null) return;
  final before = s;

  const perms = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.VIBRATE',
    'android.permission.REQUEST_INSTALL_PACKAGES', // in-app updates (sideloaded builds)
    'android.permission.CALL_PHONE', // place calls directly, no "choose an app" screen
  ];
  final current = s;
  final missing = perms.where((p) => !current.contains('"$p"')).map((p) => '    <uses-permission android:name="$p"/>').join('\n');
  if (missing.isNotEmpty) {
    s = s.replaceFirst('<application', '$missing\n    <application');
  }

  if (!s.contains('android.hardware.telephony')) {
    // Calling is optional so the app still installs on tablets without a SIM.
    s = s.replaceFirst('<application', '<uses-feature android:name="android.hardware.telephony" android:required="false"/>\n    <application');
  }

  if (!s.contains('ScheduledNotificationReceiver')) {
    const receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="hipersign_alerts" />
''';
    s = s.replaceFirst('</application>', '$receivers    </application>');
  }

  const intents = '''
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
''';
  if (!s.contains('android:scheme="tel"')) {
    if (s.contains('<queries>')) {
      s = s.replaceFirst('<queries>', '<queries>\n$intents');
    } else {
      s = s.replaceFirst('</manifest>', '    <queries>\n$intents    </queries>\n</manifest>');
    }
  }

  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Hipersign"');
  if (s != before) _write(path, s, 'AndroidManifest.xml (permissions, notification receivers, tel/https queries, label)');
}

void _androidGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final isKts = kts.existsSync();
  final file = isKts ? kts : groovy;
  if (!file.existsSync()) {
    warnings.add('android/app/build.gradle(.kts) not found.');
    return;
  }
  var s = file.readAsStringSync();
  final before = s;
  if (!s.contains('oreLibraryDesugaringEnabled')) {
    final flag = isKts ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
    if (s.contains('compileOptions {')) {
      s = s.replaceFirst('compileOptions {', 'compileOptions {\n        $flag');
    } else {
      warnings.add('Add `$flag` inside android { compileOptions { } } in ${file.path} (needed by flutter_local_notifications).');
    }
  }
  if (!s.contains('desugar_jdk_libs')) {
    final dep = isKts
        ? 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
        : "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'";
    if (RegExp(r'^dependencies\s*\{', multiLine: true).hasMatch(s)) {
      s = s.replaceFirst(RegExp(r'^dependencies\s*\{', multiLine: true), 'dependencies {\n    $dep');
    } else {
      s = '$s\ndependencies {\n    $dep\n}\n';
    }
  }
  if (isKts && !s.contains('HM_KEYSTORE_PATH')) {
    const signing = '''
    signingConfigs {
        create("hipersign") {
            val ks = System.getenv("HM_KEYSTORE_PATH")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("HM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("HM_KEY_ALIAS") ?: "hipersign"
                keyPassword = System.getenv("HM_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {''';
    if (s.contains('    buildTypes {')) {
      s = s.replaceFirst('    buildTypes {', signing.substring(1));
      s = s.replaceFirst(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = if (System.getenv("HM_KEYSTORE_PATH") != null) signingConfigs.getByName("hipersign") else signingConfigs.getByName("debug")',
      );
    } else {
      warnings.add('Could not add the Hipersign release signing config to ${file.path}.');
    }
  }
  if (s != before) _write(file.path, s, '${file.path} (desugaring, release signing)');
}

void _iosInfoPlist() {
  const path = 'ios/Runner/Info.plist';
  var s = _read(path);
  if (s == null) return;
  final before = s;
  final additions = StringBuffer();
  if (!s.contains('LSApplicationQueriesSchemes')) {
    additions.write('''
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>tel</string>
		<string>whatsapp</string>
		<string>https</string>
	</array>
''');
  }
  if (!s.contains('UIBackgroundModes')) {
    additions.write('''
	<key>UIBackgroundModes</key>
	<array>
		<string>remote-notification</string>
		<string>fetch</string>
	</array>
''');
  }
  if (additions.isNotEmpty) {
    final idx = s.lastIndexOf('</dict>');
    s = s.substring(0, idx) + additions.toString() + s.substring(idx);
  }
  s = s.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}Hipersign${m[2]}',
  );
  if (s != before) _write(path, s, 'Info.plist (URL schemes, background push, display name)');
}

void _iosDeploymentTarget() {
  // Firebase iOS SDK needs iOS 15+.
  const podfile = 'ios/Podfile';
  final p = File(podfile);
  if (p.existsSync()) {
    final s = p.readAsStringSync();
    final n = s.replaceFirst(RegExp(r"#?\s*platform :ios, '[\d.]+'"), "platform :ios, '15.0'");
    if (n != s) _write(podfile, n, 'Podfile (iOS 15.0)');
  }
  const pbx = 'ios/Runner.xcodeproj/project.pbxproj';
  final x = File(pbx);
  if (x.existsSync()) {
    final s = x.readAsStringSync();
    final n = s.replaceAllMapped(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (\d+)\.\d+;'), (m) {
      final v = int.parse(m[1]!);
      return v < 15 ? 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;' : m[0]!;
    });
    if (n != s) _write(pbx, n, 'Xcode deployment target (iOS 15.0)');
  }
}

void _iosAppDelegate() {
  const path = 'ios/Runner/AppDelegate.swift';
  final f = File(path);
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  if (s.contains('UNUserNotificationCenter.current().delegate')) return;
  const line = '    if #available(iOS 10.0, *) {\n'
      '      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n'
      '    }\n';
  final anchor = RegExp(r'^(\s*)GeneratedPluginRegistrant\.register\(', multiLine: true);
  final m = anchor.firstMatch(s);
  if (m == null || !s.contains('didFinishLaunchingWithOptions')) {
    warnings.add('In ios/Runner/AppDelegate.swift, inside didFinishLaunchingWithOptions add:\n$line'
        '(lets notifications show while the app is open on iOS).');
    return;
  }
  s = s.replaceRange(m.start, m.start, line);
  if (!s.contains('import UserNotifications')) {
    s = s.replaceFirst('import Flutter', 'import Flutter\nimport UserNotifications');
  }
  _write(path, s, 'AppDelegate.swift (foreground notifications)');
}

/// MainActivity with the "hipersign/phone" channel: places a call directly (ACTION_CALL),
/// asking for the Phone permission the first time. Falls back to the dialer in Dart if refused.
void _androidMainActivity() {
  final dir = Directory('android/app/src/main/kotlin');
  if (!dir.existsSync()) {
    warnings.add('android/app/src/main/kotlin not found - direct calling not installed.');
    return;
  }
  final file = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt'))
      .firstOrNull;
  if (file == null) {
    warnings.add('MainActivity.kt not found - direct calling not installed.');
    return;
  }
  final current = file.readAsStringSync();
  if (current.contains('hipersign/phone')) return;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(current)?[1] ?? 'com.hipersign.hipersign_mobile_app';
  final code = _mainActivity.replaceFirst('__PACKAGE__', pkg);
  _write(file.path, code, 'MainActivity.kt (direct calling)');
}

const _mainActivity = r'''
package __PACKAGE__

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNumber: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hipersign/phone").setMethodCallHandler { call, result ->
            if (call.method != "call") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val number = call.argument<String>("number")
            if (number.isNullOrBlank()) {
                result.success("failed")
                return@setMethodCallHandler
            }
            if (checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                result.success(placeCall(number))
            } else {
                pendingResult?.success("denied")
                pendingNumber = number
                pendingResult = result
                requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), CALL_REQUEST)
            }
        }
    }

    private fun placeCall(number: String): String = try {
        startActivity(Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)))
        "called"
    } catch (e: Exception) {
        "failed"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_REQUEST) return
        val result = pendingResult
        val number = pendingNumber
        pendingResult = null
        pendingNumber = null
        if (result == null || number == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            result.success(placeCall(number))
        } else if (shouldShowRequestPermissionRationale(Manifest.permission.CALL_PHONE)) {
            result.success("denied")
        } else {
            result.success("blocked")
        }
    }

    companion object {
        private const val CALL_REQUEST = 4711
    }
}
''';
