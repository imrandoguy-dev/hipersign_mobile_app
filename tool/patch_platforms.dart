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
    'android.permission.READ_MEDIA_AUDIO', // find the phone's own call recordings (Android 13+)
  ];
  final current = s;
  final missing = perms.where((p) => !current.contains('"$p"')).map((p) => '    <uses-permission android:name="$p"/>').join('\n');
  if (missing.isNotEmpty) {
    s = s.replaceFirst('<application', '$missing\n    <application');
  }

  if (!s.contains('android.permission.READ_EXTERNAL_STORAGE')) {
    // Older Android (12 and below) uses this instead of READ_MEDIA_AUDIO.
    s = s.replaceFirst('<application', '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n    <application');
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

/// MainActivity with the "hipersign/phone" channel: direct calling and finding call recordings.
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
  if (current.contains('findRecordings')) return;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(current)?[1] ?? 'com.hipersign.hipersign_mobile_app';
  final code = _mainActivity.replaceFirst('__PACKAGE__', pkg);
  _write(file.path, code, 'MainActivity.kt (direct calling)');
}

const _mainActivity = r'''
package __PACKAGE__

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Hipersign native helpers (channel "hipersign/phone"):
//  - call:            place a call directly (ACTION_CALL), asking for the Phone permission once
//  - audioPermission: check / request access to audio files (to find the phone's call recordings)
//  - findRecordings:  audio files added or changed in a time window (MediaStore)
//  - copyRecording:   copy one recording into the app cache for upload / playback
//  - openAppSettings: open this app's system settings page
class MainActivity : FlutterActivity() {
    private var pendingNumber: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingAudioResult: MethodChannel.Result? = null

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun granted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hipersign/phone").setMethodCallHandler { call, result ->
            when (call.method) {
                "call" -> {
                    val number = call.argument<String>("number")
                    if (number.isNullOrBlank()) {
                        result.success("failed")
                    } else if (granted(Manifest.permission.CALL_PHONE)) {
                        result.success(placeCall(number))
                    } else {
                        pendingCallResult?.success("denied")
                        pendingNumber = number
                        pendingCallResult = result
                        requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), CALL_REQUEST)
                    }
                }
                "audioPermission" -> {
                    val request = call.argument<Boolean>("request") ?: false
                    if (granted(audioPermission)) {
                        result.success("granted")
                    } else if (!request) {
                        result.success("denied")
                    } else {
                        pendingAudioResult?.success("denied")
                        pendingAudioResult = result
                        requestPermissions(arrayOf(audioPermission), AUDIO_REQUEST)
                    }
                }
                "findRecordings" -> {
                    val since = call.argument<Number>("since")?.toLong() ?: 0L
                    val until = call.argument<Number>("until")?.toLong() ?: System.currentTimeMillis()
                    if (!granted(audioPermission)) {
                        result.success(ArrayList<Map<String, Any?>>())
                    } else {
                        Thread {
                            try {
                                val found = findRecordings(since, until)
                                runOnUiThread { result.success(found) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("FIND_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                }
                "copyRecording" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name") ?: "recording.m4a"
                    if (uri.isNullOrBlank()) {
                        result.error("BAD_URI", "No recording", null)
                    } else {
                        Thread {
                            try {
                                val path = copyRecording(uri, name)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                }
                "openAppSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun placeCall(number: String): String = try {
        startActivity(Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)))
        "called"
    } catch (e: Exception) {
        "failed"
    }

    private fun findRecordings(since: Long, until: Long): ArrayList<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val pathColumn = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.RELATIVE_PATH
        else MediaStore.Audio.Media.DATA
        val columns = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.DURATION,
            pathColumn,
        )
        val s = (since / 1000).toString()
        val u = (until / 1000).toString()
        val added = MediaStore.Audio.Media.DATE_ADDED
        val modified = MediaStore.Audio.Media.DATE_MODIFIED
        val selection = "(($added >= ? AND $added <= ?) OR ($modified >= ? AND $modified <= ?))"
        contentResolver.query(collection, columns, selection, arrayOf(s, u, s, u), "$added ASC")?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val addedCol = c.getColumnIndexOrThrow(added)
            val modifiedCol = c.getColumnIndexOrThrow(modified)
            val durationCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val pathCol = c.getColumnIndexOrThrow(pathColumn)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                out.add(
                    mapOf(
                        "uri" to ContentUris.withAppendedId(collection, id).toString(),
                        "name" to (c.getString(nameCol) ?: ""),
                        "size" to c.getLong(sizeCol),
                        "added" to c.getLong(addedCol) * 1000L,
                        "modified" to c.getLong(modifiedCol) * 1000L,
                        "duration" to c.getLong(durationCol),
                        "path" to (c.getString(pathCol) ?: ""),
                    )
                )
            }
        }
        return out
    }

    private fun copyRecording(uriString: String, name: String): String {
        val dir = File(cacheDir, "recordings")
        dir.mkdirs()
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "recording.m4a" }
        val dest = File(dir, safe)
        val input = contentResolver.openInputStream(Uri.parse(uriString))
            ?: throw IllegalStateException("Cannot open the recording")
        input.use { source -> dest.outputStream().use { target -> source.copyTo(target) } }
        return dest.absolutePath
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            CALL_REQUEST -> {
                val result = pendingCallResult
                val number = pendingNumber
                pendingCallResult = null
                pendingNumber = null
                if (result == null || number == null) return
                when {
                    ok -> result.success(placeCall(number))
                    shouldShowRequestPermissionRationale(Manifest.permission.CALL_PHONE) -> result.success("denied")
                    else -> result.success("blocked")
                }
            }
            AUDIO_REQUEST -> {
                val result = pendingAudioResult ?: return
                pendingAudioResult = null
                when {
                    ok -> result.success("granted")
                    shouldShowRequestPermissionRationale(audioPermission) -> result.success("denied")
                    else -> result.success("blocked")
                }
            }
        }
    }

    companion object {
        private const val CALL_REQUEST = 4711
        private const val AUDIO_REQUEST = 4712
    }
}
''';
