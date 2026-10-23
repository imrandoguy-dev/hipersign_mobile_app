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
  _androidHomeWidget();
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
    // Caller pop-up: who is calling / being called, shown over the call screen
    'android.permission.READ_PHONE_STATE',
    'android.permission.READ_CALL_LOG',
    'android.permission.PROCESS_OUTGOING_CALLS',
    'android.permission.SYSTEM_ALERT_WINDOW',
    'android.permission.RECORD_AUDIO', // WhatsApp voice messages
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

  if (!s.contains('hm-dial-handler')) {
    // Lets Hipersign open phone links (e.g. the Call button in Google Search / Maps):
    // Android then offers Hipersign next to the phone app.
    const dial = '''
            <!-- hm-dial-handler -->
            <intent-filter>
                <action android:name="android.intent.action.DIAL" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="tel" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <action android:name="android.intent.action.DIAL" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="tel" />
            </intent-filter>
''';
    s = s.replaceFirst('</activity>', '$dial        </activity>');
  }

  if (!s.contains('hm-share-handler')) {
    // "Share" a business from Google Search / Maps to Hipersign.
    const share = '''
            <!-- hm-share-handler -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
''';
    s = s.replaceFirst('</activity>', '$share        </activity>');
  }

  if (!s.contains('CallerIdReceiver')) {
    const receiver = '''
        <receiver android:name=".CallerIdReceiver" android:exported="true">
            <intent-filter android:priority="999">
                <action android:name="android.intent.action.PHONE_STATE" />
                <action android:name="android.intent.action.NEW_OUTGOING_CALL" />
            </intent-filter>
        </receiver>
''';
    s = s.replaceFirst('</application>', '$receiver    </application>');
  }

  if (!s.contains('HmFileProvider')) {
    const provider = '''
        <provider android:name=".HmFileProvider" android:authorities="\${applicationId}.hmfiles"
            android:exported="false" android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/hm_file_paths" />
        </provider>
''';
    s = s.replaceFirst('</application>', '$provider    </application>');
  }

  if (!s.contains('HmPushReceiver')) {
    const push = '''
        <receiver android:name=".HmPushReceiver" android:exported="true"
            android:permission="com.google.android.c2dm.permission.SEND">
            <intent-filter>
                <action android:name="com.google.android.c2dm.intent.RECEIVE" />
            </intent-filter>
        </receiver>
''';
    s = s.replaceFirst('</application>', '$push    </application>');
  }

  if (!s.contains('HipersignWidget')) {
    const widget = '''
        <receiver android:name=".HipersignWidget" android:exported="true" android:label="Hipersign calendar">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/hm_widget_info" />
        </receiver>
''';
    s = s.replaceFirst('</application>', '$widget    </application>');
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
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="hipersign_reminders" />
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

  if (!s.contains('<package android:name="com.whatsapp"')) {
    // Send quotations to the phone's WhatsApp / WhatsApp Business.
    const apps = '        <package android:name="com.whatsapp" />\n        <package android:name="com.whatsapp.w4b" />\n';
    if (s.contains('<queries>')) {
      s = s.replaceFirst('<queries>', '<queries>\n$apps');
    } else {
      s = s.replaceFirst('</manifest>', '    <queries>\n$apps    </queries>\n</manifest>');
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
  // WhatsApp chats: voice messages, photos.
  for (final entry in const {
    'NSMicrophoneUsageDescription': 'Hipersign records voice messages you send to customers on WhatsApp.',
    'NSCameraUsageDescription': 'Hipersign takes photos you send to customers on WhatsApp.',
    'NSPhotoLibraryUsageDescription': 'Hipersign sends photos you choose to customers on WhatsApp.',
  }.entries) {
    if (!s.contains(entry.key)) {
      additions.write('\t<key>${entry.key}</key>\n\t<string>${entry.value}</string>\n');
    }
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
  if (current.contains('shareFile')) return;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(current)?[1] ?? 'com.hipersign.hipersign_mobile_app';
  final code = _mainActivity.replaceFirst('__PACKAGE__', pkg);
  _write(file.path, code, 'MainActivity.kt (direct calling)');
  _write('${file.parent.path}/CallerId.kt', _callerId.replaceFirst('__PACKAGE__', pkg), 'CallerId.kt (caller pop-up)');
  _write('${file.parent.path}/HmFileProvider.kt', 'package $pkg\n\n// Own FileProvider class, so it never clashes with a plugin\'s provider.\nclass HmFileProvider : androidx.core.content.FileProvider()\n', 'HmFileProvider.kt (share files)');
  Directory('android/app/src/main/res/xml').createSync(recursive: true);
  _write('android/app/src/main/res/xml/hm_file_paths.xml', _filePaths, 'file paths for sharing');
}

const _filePaths = '''<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
</paths>
''';

const _mainActivity = r'''
package __PACKAGE__

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CallLog
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.telecom.TelecomManager
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
//  - takeDialIntent / dialIntent: a tel: link opened Hipersign (Google's Call button)
//  - takeShareIntent / shareIntent: text shared to Hipersign (a business from Google Search / Maps)
//  - takeOpenIntent / openParty: the caller pop-up was tapped
//  - callerIdStatus / requestCallerIdPermissions / openOverlaySettings / saveCallerDirectory / setCallerIdEnabled
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingDial: String? = null // number from a tel: link (e.g. Google's Call button)
    private var pendingShare: String? = null // text shared to Hipersign
    private var pendingOpen: Map<String, String>? = null // party to open (from the caller pop-up)
    private var pendingAfterCall: Map<String, Any?>? = null // a work call just ended
    private var pendingCallerIdResult: MethodChannel.Result? = null
    private var pendingNumber: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingAudioResult: MethodChannel.Result? = null
    private var pendingDocResult: MethodChannel.Result? = null

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun granted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hipersign/phone")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeDialIntent" -> {
                    result.success(pendingDial)
                    pendingDial = null
                }
                "takeShareIntent" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                "takeOpenIntent" -> {
                    result.success(pendingOpen)
                    pendingOpen = null
                }
                "takeAfterCallIntent" -> {
                    result.success(pendingAfterCall)
                    pendingAfterCall = null
                }
                "setAfterCallEnabled" -> {
                    CallerId.setAfterCallEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }
                "clearAfterCallNotification" -> {
                    CallerId.clearAfterCallNotification(applicationContext)
                    result.success(true)
                }
                "callerIdStatus" -> result.success(callerIdStatus())
                "listSims" -> result.success(
                    mapOf(
                        "sims" to CallerId.simAccounts(applicationContext),
                        "selected" to CallerId.workSims(applicationContext).toList(),
                    )
                )
                "setWorkSims" -> {
                    CallerId.setWorkSims(applicationContext, call.argument<List<String>>("ids") ?: emptyList())
                    result.success(true)
                }
                "readCallLog" -> {
                    val since = call.argument<Number>("since")?.toLong() ?: 0L
                    if (!granted(Manifest.permission.READ_CALL_LOG)) {
                        result.success(null)
                    } else {
                        Thread {
                            try {
                                val rows = readCallLog(since)
                                runOnUiThread { result.success(rows) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("CALL_LOG_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                }
                "requestCallerIdPermissions" -> {
                    val missing = CallerId.phonePermissions.filter { !granted(it) }
                    if (missing.isEmpty()) {
                        result.success(callerIdStatus())
                    } else {
                        pendingCallerIdResult?.success(callerIdStatus())
                        pendingCallerIdResult = result
                        requestPermissions(missing.toTypedArray(), CALLER_ID_REQUEST)
                    }
                }
                "openOverlaySettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveCallerDirectory" -> {
                    val json = call.argument<String>("json") ?: "{}"
                    Thread {
                        try {
                            CallerId.saveDirectory(applicationContext, json)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "setCallerIdEnabled" -> {
                    CallerId.setEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }
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
                "pickDocument" -> {
                    // WhatsApp: choose any file (PDF, Excel...) - copied into the app's cache.
                    pendingDocResult?.success(null)
                    pendingDocResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                        startActivityForResult(intent, DOC_REQUEST)
                    } catch (e: Exception) {
                        pendingDocResult = null
                        result.error("NO_PICKER", "No file picker on this phone", null)
                    }
                }
                "shareFile" -> {
                    // Share a file (e.g. a quotation PDF) - to the phone's WhatsApp when asked,
                    // straight into the customer's chat when their number is given.
                    try {
                        val path = call.argument<String>("path") ?: ""
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val text = call.argument<String>("text")
                        val digits = (call.argument<String>("phone") ?: "").filter { it.isDigit() }
                        val whatsapp = call.argument<Boolean>("whatsapp") ?: false
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this, "${packageName}.hmfiles", File(path)
                        )
                        val intent = Intent(Intent.ACTION_SEND)
                            .setType(mime)
                            .putExtra(Intent.EXTRA_STREAM, uri)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (!text.isNullOrBlank()) intent.putExtra(Intent.EXTRA_TEXT, text)
                        var app: String? = null
                        if (whatsapp) {
                            for (p in listOf("com.whatsapp", "com.whatsapp.w4b")) {
                                try {
                                    packageManager.getPackageInfo(p, 0)
                                    app = p
                                    break
                                } catch (e: Exception) {}
                            }
                            if (app == null) {
                                result.error("NO_WHATSAPP", "WhatsApp is not installed on this phone", null)
                                return@setMethodCallHandler
                            }
                            intent.setPackage(app)
                            if (digits.length >= 8) intent.putExtra("jid", "$digits@s.whatsapp.net")
                            startActivity(intent)
                        } else {
                            startActivity(Intent.createChooser(intent, "Share"))
                        }
                        result.success(app ?: "chooser")
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }
                "updateWidget" -> {
                    // Today's calendar for the home screen widget (JSON written by the app).
                    getSharedPreferences("hm_widget", MODE_PRIVATE).edit()
                        .putString("data", call.argument<String>("json") ?: "")
                        .apply()
                    HipersignWidget.renderAll(this)
                    result.success(true)
                }
                "pinWidget" -> {
                    val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                    if (Build.VERSION.SDK_INT >= 26 && mgr.isRequestPinAppWidgetSupported) {
                        mgr.requestPinAppWidget(android.content.ComponentName(this, HipersignWidget::class.java), null, null)
                        result.success(true)
                    } else {
                        result.success(false)
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dialNumberFrom(intent)?.let { pendingDial = it }
        sharedTextFrom(intent)?.let { pendingShare = it }
        openPartyFrom(intent)?.let { pendingOpen = it }
        afterCallFrom(intent)?.let { pendingAfterCall = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dialNumberFrom(intent)?.let {
            pendingDial = it
            channel?.invokeMethod("dialIntent", it)
        }
        sharedTextFrom(intent)?.let {
            pendingShare = it
            channel?.invokeMethod("shareIntent", it)
        }
        afterCallFrom(intent)?.let {
            pendingAfterCall = it
            channel?.invokeMethod("afterCall", it)
            return
        }
        openPartyFrom(intent)?.let {
            pendingOpen = it
            channel?.invokeMethod("openParty", it)
        }
    }

    private fun afterCallFrom(i: Intent?): Map<String, Any?>? {
        val number = i?.getStringExtra(CallerId.EXTRA_AFTER_CALL) ?: return null
        return mapOf(
            "number" to number,
            "direction" to (i.getStringExtra(CallerId.EXTRA_DIRECTION) ?: "outgoing"),
            "duration" to i.getLongExtra(CallerId.EXTRA_DURATION, 0L),
            "name" to i.getStringExtra(CallerId.EXTRA_NAME),
            "doctype" to i.getStringExtra(CallerId.EXTRA_DOCTYPE),
            "id" to i.getStringExtra(CallerId.EXTRA_ID),
        )
    }

    private fun sharedTextFrom(i: Intent?): String? {
        if (i?.action != Intent.ACTION_SEND) return null
        val subject = i.getStringExtra(Intent.EXTRA_SUBJECT)
        val text = i.getStringExtra(Intent.EXTRA_TEXT) ?: return subject
        return if (subject != null && !text.contains(subject)) "$subject\n$text" else text
    }

    private fun openPartyFrom(i: Intent?): Map<String, String>? {
        if (i?.hasExtra(CallerId.EXTRA_AFTER_CALL) == true) return null
        val doctype = i?.getStringExtra(CallerId.EXTRA_DOCTYPE) ?: return null
        val id = i.getStringExtra(CallerId.EXTRA_ID) ?: return null
        return mapOf("doctype" to doctype, "id" to id, "name" to (i.getStringExtra(CallerId.EXTRA_NAME) ?: id))
    }

    private fun callerIdStatus(): Map<String, Any> = mapOf(
        "phone" to CallerId.phonePermissions.all { granted(it) },
        "overlay" to Settings.canDrawOverlays(this),
        "enabled" to CallerId.isEnabled(applicationContext),
        "afterCall" to CallerId.afterCallEnabled(applicationContext),
        "entries" to CallerId.directorySize(applicationContext),
    )

    private fun dialNumberFrom(i: Intent?): String? {
        if (i == null) return null
        if (i.action != Intent.ACTION_DIAL && i.action != Intent.ACTION_VIEW) return null
        val data = i.data ?: return null
        if (data.scheme != "tel") return null
        return Uri.decode(data.schemeSpecificPart ?: "").trim().ifEmpty { null }
    }

    /** Phone call history since [since] (ms), with the ERPNext party when the number is known. */
    private fun readCallLog(since: Long): ArrayList<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val columns = arrayOf(
            CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE,
            CallLog.Calls.PHONE_ACCOUNT_ID,
        )
        val work = CallerId.workAliases(applicationContext)
        contentResolver.query(
            CallLog.Calls.CONTENT_URI, columns, "${CallLog.Calls.DATE} > ?", arrayOf(since.toString()),
            "${CallLog.Calls.DATE} ASC",
        )?.use { c ->
            while (c.moveToNext() && out.size < 2000) {
                val number = c.getString(1) ?: ""
                val known = CallerId.lookup(applicationContext, number)
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "number" to number,
                        "date" to c.getLong(2),
                        "duration" to c.getLong(3),
                        "type" to c.getInt(4),
                        "party" to known?.let { listOf(it.optString(2), it.optString(3), it.optString(0)) },
                        "sim" to c.getString(5),
                        "work" to CallerId.isWorkSim(c.getString(5), work),
                    )
                )
            }
        }
        return out
    }

    private fun placeCall(number: String): String = try {
        CallerId.noteAppCall(applicationContext, number)
        val intent = Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null))
        // One work SIM chosen in Settings: calls from Hipersign always go out on it.
        CallerId.workCallHandle(applicationContext)?.let { intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it) }
        startActivity(intent)
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

    @Deprecated("Uses the classic activity result API (FlutterActivity)")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DOC_REQUEST) return
        val result = pendingDocResult ?: return
        pendingDocResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                var name = "document"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
                }
                val dir = File(cacheDir, "wa_docs")
                dir.mkdirs()
                val safe = name.replace(Regex("[^A-Za-z0-9._ -]"), "_").ifBlank { "document" }
                val dest = File(dir, safe)
                val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("Cannot open the file")
                input.use { source -> dest.outputStream().use { target -> source.copyTo(target) } }
                runOnUiThread { result.success(dest.absolutePath) }
            } catch (e: Exception) {
                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
            }
        }.start()
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
            CALLER_ID_REQUEST -> {
                val result = pendingCallerIdResult ?: return
                pendingCallerIdResult = null
                result.success(callerIdStatus())
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
        private const val CALLER_ID_REQUEST = 4713
        private const val DOC_REQUEST = 4714
    }
}
''';

const _callerId = r'''
package __PACKAGE__

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.content.pm.PackageManager
import android.annotation.SuppressLint
import android.provider.CallLog
import android.provider.Settings
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Caller pop-up: when a call rings or is dialled (from any app), show the ERPNext
 * customer / lead / deal name over the call screen. Names come from a directory the app
 * syncs from ERPNext, so this works instantly and offline. The phone's own Phone app
 * keeps handling (and recording) the call.
 */
@Suppress("DEPRECATION")
object CallerId {
    const val EXTRA_DOCTYPE = "hm_open_doctype"
    const val EXTRA_ID = "hm_open_id"
    const val EXTRA_NAME = "hm_open_name"
    const val EXTRA_AFTER_CALL = "hm_after_call" // number of the call that just ended
    const val EXTRA_DIRECTION = "hm_after_direction" // incoming | outgoing | missed
    const val EXTRA_DURATION = "hm_after_duration" // seconds
    private const val AFTER_NOTIFICATION_ID = 7342
    private const val PREFS = "hm_caller_id"
    private const val FILE = "caller_directory.json"
    private const val CHANNEL = "hipersign_caller_id"
    private const val NOTIFICATION_ID = 7341

    val phonePermissions: List<String>
        get() = listOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.PROCESS_OUTGOING_CALLS,
        )

    private var cache: JSONObject? = null
    private var cacheStamp = 0L
    private var view: View? = null
    private val handler = Handler(Looper.getMainLooper())

    fun isEnabled(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", enabled).apply()
        if (!enabled) hide(context)
    }

    fun afterCallEnabled(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("after_call", true)

    fun setAfterCallEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("after_call", enabled).apply()
    }

    // ---- Work SIM: only calls on the chosen SIM(s) are recorded, uploaded and logged.

    fun workSims(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet("work_sims", null)?.toSet() ?: emptySet()

    fun setWorkSims(context: Context, ids: List<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet("work_sims", ids.toSet()).apply()
    }

    private fun hasPhoneState(context: Context) =
        context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

    /** The phone's SIMs that can make calls; null without the Phone permission. */
    @SuppressLint("MissingPermission", "HardwareIds")
    fun simAccounts(context: Context): List<Map<String, Any?>>? {
        if (!hasPhoneState(context)) return null
        return try {
            val telecom = context.getSystemService(TelecomManager::class.java) ?: return emptyList()
            val tm = context.getSystemService(TelephonyManager::class.java)
            val subs = try {
                context.getSystemService(SubscriptionManager::class.java)?.activeSubscriptionInfoList
            } catch (e: Exception) {
                null
            } ?: emptyList()
            telecom.callCapablePhoneAccounts.mapIndexed { i, h ->
                val account = try { telecom.getPhoneAccount(h) } catch (e: Exception) { null }
                var subId = -1
                if (Build.VERSION.SDK_INT >= 30) subId = try { tm?.getSubscriptionId(h) ?: -1 } catch (e: Exception) { -1 }
                val sub = subs.firstOrNull { it.subscriptionId == subId }
                    ?: subs.firstOrNull { s -> try { s.iccId == h.id } catch (e: Exception) { false } }
                    ?: subs.firstOrNull { it.subscriptionId.toString() == h.id }
                mapOf(
                    "id" to h.id,
                    "label" to (account?.label?.toString()?.takeIf { it.isNotBlank() }
                        ?: sub?.displayName?.toString() ?: "SIM ${i + 1}"),
                    "carrier" to sub?.carrierName?.toString(),
                    "slot" to ((sub?.simSlotIndex ?: i) + 1),
                    "sub_id" to (sub?.subscriptionId ?: subId).takeIf { it >= 0 }?.toString(),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** IDs the call history may use for the work SIM(s); null = no SIM chosen (all calls count). */
    fun workAliases(context: Context): Set<String>? {
        val chosen = workSims(context)
        if (chosen.isEmpty()) return null
        val out = HashSet(chosen)
        simAccounts(context)?.forEach { s ->
            val id = s["id"] as? String
            val subId = s["sub_id"] as? String
            if (id != null && subId != null && chosen.contains(id)) out.add(subId)
        }
        return out
    }

    fun isWorkSim(accountId: String?, aliases: Set<String>?): Boolean =
        aliases == null || accountId.isNullOrBlank() || accountId in aliases

    /** The SIM to place Hipersign calls on, when exactly one work SIM is chosen. */
    @SuppressLint("MissingPermission")
    fun workCallHandle(context: Context): PhoneAccountHandle? {
        val chosen = workSims(context)
        if (chosen.size != 1 || !hasPhoneState(context)) return null
        return try {
            context.getSystemService(TelecomManager::class.java)?.callCapablePhoneAccounts?.firstOrNull { it.id in chosen }
        } catch (e: Exception) {
            null
        }
    }

    /** Hipersign placed a call: remember it so its end opens the after-call screen. */
    fun noteAppCall(context: Context, number: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("last_app_call", number.filter { it.isDigit() }.takeLast(9))
            .putLong("last_app_call_at", System.currentTimeMillis())
            .apply()
    }

    /**
     * A call just ended (phone back to idle). If it was a work call - an ERPNext customer /
     * lead / deal, or a call placed from Hipersign - open Hipersign's after-call screen, which
     * saves the recording and logs the call even when the app was closed.
     */
    fun onCallEnded(context: Context) {
        if (!isEnabled(context) || !afterCallEnabled(context)) return
        if (context.checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cursor = context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(
                CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE,
                CallLog.Calls.PHONE_ACCOUNT_ID,
            ),
            null, null, "${CallLog.Calls.DATE} DESC",
        ) ?: return
        cursor.use { c ->
            if (!c.moveToFirst()) return
            val id = c.getLong(0)
            val number = c.getString(1) ?: return
            val date = c.getLong(2)
            val duration = c.getLong(3)
            val type = c.getInt(4)
            // Only the call that just ended (started recently, or long call that just finished).
            if (System.currentTimeMillis() - (date + duration * 1000L) > 3 * 60 * 1000L) return
            if (prefs.getLong("last_after_call_id", -1L) == id) return
            prefs.edit().putLong("last_after_call_id", id).apply()
            if (!isWorkSim(c.getString(5), workAliases(context))) return // personal SIM
            val direction = when (type) {
                CallLog.Calls.INCOMING_TYPE -> "incoming"
                CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                CallLog.Calls.MISSED_TYPE, CallLog.Calls.REJECTED_TYPE -> "missed"
                else -> return
            }
            val key = number.filter { it.isDigit() }.takeLast(9)
            val fromApp = prefs.getString("last_app_call", null) == key &&
                Math.abs(date - prefs.getLong("last_app_call_at", 0L)) < 5 * 60 * 1000L
            val entry = lookup(context, number)
            if (entry == null && !fromApp) return // personal call
            launchAfterCall(context.applicationContext, number, direction, duration, entry)
        }
    }

    private fun launchAfterCall(context: Context, number: String, direction: String, duration: Long, entry: JSONArray?) {
        val name = entry?.optString(0)?.takeIf { it.isNotBlank() } ?: number
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_AFTER_CALL, number)
            .putExtra(EXTRA_DIRECTION, direction)
            .putExtra(EXTRA_DURATION, duration)
            .putExtra(EXTRA_NAME, name)
        if (entry != null) {
            intent.putExtra(EXTRA_DOCTYPE, entry.optString(2)).putExtra(EXTRA_ID, entry.optString(3))
        }
        // Notification first (always works); the screen itself opens when Android allows it
        // ("Display over other apps" / Xiaomi "pop-up windows while running in background").
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Caller ID", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) }
            )
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        }
        val title = when (direction) {
            "missed" -> "Missed call: $name"
            else -> "Call with $name ended"
        }
        val pi = PendingIntent.getActivity(
            context, 9000 + (number.hashCode() and 0xfff), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            nm.notify(
                AFTER_NOTIFICATION_ID,
                builder.setSmallIcon(context.applicationInfo.icon)
                    .setContentTitle(title)
                    .setContentText(if (direction == "missed") "Tap to call back" else "Tap to save the recording and add a follow-up")
                    .setAutoCancel(true)
                    .setContentIntent(pi)
                    .build()
            )
        } catch (e: SecurityException) {
        }
        if (Settings.canDrawOverlays(context)) {
            try {
                context.startActivity(intent)
            } catch (e: Exception) {
            }
        }
    }

    fun clearAfterCallNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(AFTER_NOTIFICATION_ID)
    }

    fun saveDirectory(context: Context, json: String) {
        val tmp = File(context.filesDir, "$FILE.tmp")
        tmp.writeText(json)
        tmp.renameTo(File(context.filesDir, FILE))
        cache = null
    }

    fun directorySize(context: Context): Int = try {
        load(context)?.length() ?: 0
    } catch (e: Exception) {
        0
    }

    private fun load(context: Context): JSONObject? {
        val f = File(context.filesDir, FILE)
        if (!f.exists()) return null
        if (cache == null || cacheStamp != f.lastModified()) {
            cache = JSONObject(f.readText())
            cacheStamp = f.lastModified()
        }
        return cache
    }

    /** [name, kind, doctype, id, status] for a phone number, or null. */
    fun lookup(context: Context, number: String?): JSONArray? {
        val digits = (number ?: "").filter { it.isDigit() }
        if (digits.length < 9) return null
        return try {
            load(context)?.optJSONArray(digits.takeLast(9))
        } catch (e: Exception) {
            null
        }
    }

    fun show(context: Context, number: String?, outgoing: Boolean) {
        if (!isEnabled(context)) return
        val entry = lookup(context, number) ?: return
        val name = entry.optString(0)
        val kind = entry.optString(1)
        val doctype = entry.optString(2)
        val id = entry.optString(3)
        val status = entry.optString(4).takeIf { it.isNotBlank() && it != "null" }
        val subtitle = listOfNotNull(kind, status).joinToString(" · ")
        if (Settings.canDrawOverlays(context)) {
            showCard(context.applicationContext, name, subtitle, outgoing, doctype, id)
        } else {
            notify(context.applicationContext, name, subtitle, outgoing, doctype, id)
        }
    }

    private fun openIntent(context: Context, doctype: String, id: String, name: String): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra(EXTRA_DOCTYPE, doctype).putExtra(EXTRA_ID, id).putExtra(EXTRA_NAME, name)
        return PendingIntent.getActivity(
            context, id.hashCode(), launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun dp(context: Context, v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    private fun showCard(context: Context, name: String, subtitle: String, outgoing: Boolean, doctype: String, id: String) {
        hide(context)
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val navy = Color.parseColor("#0A3C6E")
        val blue = Color.parseColor("#1783C1")

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(context, 18f), dp(context, 14f), dp(context, 10f), dp(context, 14f))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(context, 20f).toFloat()
                setStroke(dp(context, 2f), blue)
            }
            elevation = dp(context, 8f).toFloat()
        }
        val texts = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        texts.addView(TextView(context).apply {
            text = if (outgoing) "Hipersign · Calling" else "Hipersign · Incoming call"
            setTextColor(blue)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
        })
        texts.addView(TextView(context).apply {
            text = name
            setTextColor(navy)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 2
        })
        texts.addView(TextView(context).apply {
            text = subtitle
            setTextColor(Color.parseColor("#333333"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        })
        card.addView(texts, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        card.addView(TextView(context).apply {
            text = "✕"
            setTextColor(Color.parseColor("#6B7785"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setPadding(dp(context, 12f), dp(context, 4f), dp(context, 8f), dp(context, 4f))
            setOnClickListener { hide(context) }
        })
        card.setOnClickListener {
            hide(context)
            try {
                openIntent(context, doctype, id, name).send()
            } catch (e: Exception) {
            }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
            y = dp(context, 110f)
            horizontalMargin = 0.04f
        }
        try {
            wm.addView(card, params)
            view = card
        } catch (e: Exception) {
            notify(context, name, subtitle, outgoing, doctype, id)
        }
    }

    private fun notify(context: Context, name: String, subtitle: String, outgoing: Boolean, doctype: String, id: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Caller ID", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Shows the ERPNext customer, lead or deal during calls"
                    setSound(null, null)
                }
            )
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val n = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(name)
            .setContentText((if (outgoing) "Calling · " else "Incoming · ") + subtitle)
            .setCategory(Notification.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(openIntent(context, doctype, id, name))
            .build()
        try {
            nm.notify(NOTIFICATION_ID, n)
        } catch (e: SecurityException) {
        }
    }

    fun hide(context: Context) {
        handler.removeCallbacksAndMessages(null)
        val v = view ?: return
        view = null
        try {
            (context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (e: Exception) {
        }
    }

    /** Call connected: keep the card a little longer so it doesn't cover the call buttons. */
    fun hideSoon(context: Context) {
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ hide(context) }, 8000)
    }

    fun clearNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
    }
}

@Suppress("DEPRECATION")
class CallerIdReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!CallerId.isEnabled(context)) return
        when (intent.action) {
            Intent.ACTION_NEW_OUTGOING_CALL -> {
                @Suppress("DEPRECATION") val number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                CallerId.show(context, number, outgoing = true)
            }
            TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
                    TelephonyManager.EXTRA_STATE_RINGING -> {
                        // Delivered twice on Android 9+; only the copy with READ_CALL_LOG carries the number.
                        @Suppress("DEPRECATION") val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                        if (number != null) CallerId.show(context, number, outgoing = false)
                    }
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> CallerId.hideSoon(context)
                    TelephonyManager.EXTRA_STATE_IDLE -> {
                        CallerId.hide(context)
                        CallerId.clearNotification(context)
                        // Give the phone a moment to write the call to its history, then open the
                        // after-call screen for work calls.
                        val pending = goAsync()
                        val app = context.applicationContext
                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                CallerId.onCallEnded(app)
                            } catch (e: Exception) {
                            } finally {
                                pending.finish()
                            }
                        }, 1500)
                    }
                }
            }
        }
    }
}
''';


/// Home screen widget: today's follow-ups and meetings (data comes from the app).
void _androidHomeWidget() {
  final dir = Directory('android/app/src/main/kotlin');
  if (!dir.existsSync()) return;
  final main = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('MainActivity.kt')).firstOrNull;
  if (main == null) return;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(main.readAsStringSync())?[1] ?? 'com.hipersign.hipersign_mobile_app';
  const res = 'android/app/src/main/res';
  for (final d in ['layout', 'xml', 'drawable']) {
    Directory('$res/$d').createSync(recursive: true);
  }
  _write('$res/drawable/hm_widget_bg.xml', _widgetBg, 'widget background');
  _write('$res/drawable/hm_widget_bg_alert.xml', _widgetBgAlert, 'widget background (no calls alert)');
  _write('$res/layout/hm_widget.xml', _widgetLayout, 'widget layout');
  _write('$res/layout/hm_widget_row.xml', _widgetRow, 'widget row layout');
  _write('$res/layout/hm_widget_day.xml', _widgetDay, 'widget day header');
  _write('$res/drawable/hm_widget_pill.xml', _widgetPill, 'widget row background');
  _write('$res/xml/hm_widget_info.xml', _widgetInfo, 'widget info');
  _write('${main.parent.path}/HipersignWidget.kt', _widgetKt.replaceFirst('__PACKAGE__', pkg), 'HipersignWidget.kt (home screen widget)');
  _write('${main.parent.path}/HmPushReceiver.kt', _pushReceiverKt.replaceFirst('__PACKAGE__', pkg), 'HmPushReceiver.kt (widget alert from push)');
}

const _pushReceiverKt = r'''
package __PACKAGE__

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/// Sees Hipersign's pushes next to Firebase (which still shows them): a "No calls for 45 min"
/// call-target alert turns the home screen widget red even while the app is closed.
class HmPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val extras = intent.extras ?: return
            if (extras.getString("event_type") != "Call Target") return
            val title = extras.getString("title") ?: return
            if (!title.startsWith("No calls")) return
            val alert = JSONObject()
                .put("title", title)
                .put("body", extras.getString("body") ?: "")
                .put("at", System.currentTimeMillis())
            context.getSharedPreferences("hm_widget", Context.MODE_PRIVATE).edit()
                .putString("alert", alert.toString()).apply()
            HipersignWidget.renderAll(context)
        } catch (e: Exception) {
        }
    }
}
''';

const _widgetBgAlert = '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FFFDE2E2" />
    <stroke android:width="3dp" android:color="#FFC62828" />
    <corners android:radius="20dp" />
</shape>
''';

const _widgetBg = '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FFFFFFFF" />
    <corners android:radius="20dp" />
</shape>
''';

const _widgetLayout = '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/hm_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="12dp"
    android:background="@drawable/hm_widget_bg">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <TextView
            android:id="@+id/hm_title"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Today"
            android:textColor="#FF0A3C6E"
            android:textSize="15sp"
            android:textStyle="bold"
            android:maxLines="1"
            android:ellipsize="end" />
        <TextView
            android:id="@+id/hm_count"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textColor="#FF6B7785"
            android:textSize="12sp" />
    </LinearLayout>
    <LinearLayout
        android:id="@+id/hm_rows"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="6dp"
        android:orientation="vertical" />
    <TextView
        android:id="@+id/hm_footer"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textColor="#FF6B7785"
        android:textSize="11sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
''';

const _widgetPill = '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FFE3ECF5" />
    <corners android:radius="12dp" />
</shape>
''';

const _widgetDay = '''<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/hm_day"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingTop="6dp"
    android:paddingBottom="3dp"
    android:paddingStart="4dp"
    android:textColor="#FF0A3C6E"
    android:textSize="13sp"
    android:textStyle="bold"
    android:maxLines="1" />
''';

const _widgetRow = '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:layout_marginTop="2dp"
    android:layout_marginBottom="2dp"
    android:paddingStart="10dp"
    android:paddingEnd="10dp"
    android:paddingTop="6dp"
    android:paddingBottom="6dp"
    android:background="@drawable/hm_widget_pill">
    <TextView
        android:id="@+id/hm_time"
        android:layout_width="64dp"
        android:layout_height="wrap_content"
        android:textColor="#FF0A3C6E"
        android:textSize="13sp"
        android:textStyle="bold"
        android:maxLines="1" />
    <TextView
        android:id="@+id/hm_text"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textColor="#FF333333"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
''';

const _widgetInfo = '''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="180dp"
    android:minResizeWidth="180dp"
    android:minResizeHeight="80dp"
    android:targetCellWidth="4"
    android:targetCellHeight="4"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/hm_widget"
    android:previewLayout="@layout/hm_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen" />
''';

const _widgetKt = r'''
package __PACKAGE__

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Home screen widget: today's follow-ups and meetings, pending first. The app writes the
/// list (SharedPreferences "hm_widget") whenever it syncs; tapping opens the calendar.
class HipersignWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context))
    }

    companion object {
        private const val MAX_ROWS = 14
        private const val MAX_OVERDUE_ROWS = 5

        fun renderAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, HipersignWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, build(context))
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.hm_widget)
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.hm_root, pi)
            }
            views.removeAllViews(R.id.hm_rows)
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val now = Date()
            val today = fmt.format(now)
            val tomorrow = fmt.format(Date(now.time + 24L * 3600 * 1000))
            views.setTextViewText(R.id.hm_title, SimpleDateFormat("d EEE", Locale.getDefault()).format(now))
            val raw = context.getSharedPreferences("hm_widget", Context.MODE_PRIVATE).getString("data", "") ?: ""
            val data = try { JSONObject(raw) } catch (e: Exception) { null }
            if (data == null) {
                views.setTextViewText(R.id.hm_count, "")
                views.setTextViewText(R.id.hm_footer, "Open Hipersign to show your calendar")
                return views
            }
            val fresh = data.optString("date") == today
            views.setTextViewText(R.id.hm_count, if (fresh) "${data.optInt("open_today", 0)} to do today" else "")

            var rows = 0
            var hidden = 0

            // Call target: "No calls for 45 min" turns the widget red. From the app's last sync,
            // or from the alarm push (saved by the app in the background, newer than the sync).
            val target = if (fresh) data.optJSONObject("target") else null
            var alertTitle: String? = null
            var alertBody = ""
            if (target != null && target.optBoolean("idle")) {
                alertTitle = target.optString("idle_title")
                alertBody = target.optString("line")
            }
            try {
                val raw2 = context.getSharedPreferences("hm_widget", Context.MODE_PRIVATE).getString("alert", null)
                if (raw2 != null) {
                    val a = JSONObject(raw2)
                    val at = a.optLong("at")
                    if (now.time - at < 35L * 60 * 1000 && at > data.optLong("updated_ms", 0)) {
                        alertTitle = a.optString("title")
                        alertBody = a.optString("body")
                    }
                }
            } catch (e: Exception) {}
            if (alertTitle != null) {
                views.setInt(R.id.hm_root, "setBackgroundResource", R.drawable.hm_widget_bg_alert)
                views.addView(R.id.hm_rows, row(context, "", "\u26A0 " + alertTitle, false, true))
                rows++
                if (alertBody.isNotBlank()) {
                    views.addView(R.id.hm_rows, row(context, "", alertBody, false, true))
                    rows++
                }
            } else if (target != null && target.optString("short").isNotBlank()) {
                views.setTextViewText(R.id.hm_count, target.optString("short"))
            }
            val days = data.optJSONArray("days")
            var hasToday = false
            for (d in 0 until (days?.length() ?: 0)) if (days!!.getJSONObject(d).optString("date") == today) hasToday = true
            // Old work still open (earlier days): listed first, in red, until it is done.
            val old = data.optJSONArray("overdue")
            val oldCount = old?.length() ?: 0
            if (fresh && oldCount > 0) {
                val header = RemoteViews(context.packageName, R.layout.hm_widget_day)
                header.setTextViewText(R.id.hm_day, "Overdue ($oldCount)")
                views.addView(R.id.hm_rows, header)
                rows++
                val shown = minOf(oldCount, MAX_OVERDUE_ROWS)
                for (i in 0 until shown) {
                    val item = old!!.getJSONObject(i)
                    views.addView(R.id.hm_rows, row(context, item.optString("time"), item.optString("text"), false, true))
                    rows++
                }
                hidden += oldCount - shown
            }
            if (!hasToday) {
                // Saved on an earlier day and nothing listed for today.
                val header = RemoteViews(context.packageName, R.layout.hm_widget_day)
                header.setTextViewText(R.id.hm_day, "Today")
                views.addView(R.id.hm_rows, header)
                views.addView(R.id.hm_rows, row(context, "", "Nothing scheduled", false, false))
                rows += 2
            }
            for (d in 0 until (days?.length() ?: 0)) {
                val day = days!!.getJSONObject(d)
                val date = day.optString("date")
                if (date < today) continue // the app hasn't refreshed since: skip days that are over
                val items = day.optJSONArray("items")
                val n = items?.length() ?: 0
                if (n == 0 && date != today) continue
                if (rows >= MAX_ROWS) { hidden += n; continue }
                val header = RemoteViews(context.packageName, R.layout.hm_widget_day)
                header.setTextViewText(
                    R.id.hm_day,
                    when (date) { today -> "Today"; tomorrow -> "Tomorrow"; else -> day.optString("label") }
                )
                views.addView(R.id.hm_rows, header)
                rows++
                if (n == 0) {
                    views.addView(R.id.hm_rows, row(context, "", "Nothing scheduled", false, false))
                    rows++
                }
                for (i in 0 until n) {
                    if (rows >= MAX_ROWS) { hidden += n - i; break }
                    val item = items!!.getJSONObject(i)
                    views.addView(
                        R.id.hm_rows,
                        row(context, item.optString("time"), item.optString("text"), item.optBoolean("done"),
                            item.optBoolean("overdue") && date == today)
                    )
                    rows++
                }
            }
            if (rows == 0) {
                views.addView(R.id.hm_rows, row(context, "", "Nothing scheduled in the next two weeks", false, false))
            }
            val parts = mutableListOf<String>()
            if (hidden > 0) parts.add("+$hidden more")
            parts.add(if (fresh) "Updated " + data.optString("updated", "") else "Open Hipersign to refresh")
            views.setTextViewText(R.id.hm_footer, parts.joinToString(" · "))
            return views
        }

        private fun row(context: Context, time: String, text: String, done: Boolean, overdue: Boolean): RemoteViews {
            val row = RemoteViews(context.packageName, R.layout.hm_widget_row)
            row.setTextViewText(R.id.hm_time, time)
            row.setTextViewText(R.id.hm_text, (if (done) "✓ " else "") + text)
            val color = when {
                done -> Color.parseColor("#FF9AA5B1")
                overdue -> Color.parseColor("#FFC62828")
                else -> Color.parseColor("#FF1F2A37")
            }
            row.setTextColor(R.id.hm_text, color)
            row.setTextColor(R.id.hm_time, if (done) color else if (overdue) color else Color.parseColor("#FF0A3C6E"))
            return row
        }
    }
}
''';
