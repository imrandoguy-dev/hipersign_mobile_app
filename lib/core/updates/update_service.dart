import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';

class UpdateInfo {
  UpdateInfo({required this.available, this.versionCode = 0, this.versionName = '', this.notes = '', this.size = 0, this.mandatory = false, this.reason});

  final bool available;
  final int versionCode;
  final String versionName;
  final String notes;
  final int size;
  final bool mandatory;
  final String? reason;
}

/// In-app updates for Android pilot builds (installed outside the Play Store).
///
/// The ERP server tells the app whether a newer build exists and hands it a
/// short-lived download link; the app downloads the APK and opens Android's
/// installer, which updates in place (same signing key) and keeps the user signed in.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  DateTime? _lastCheck;
  bool _prompting = false;

  Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  Future<int> currentVersionCode() async => int.tryParse((await packageInfo()).buildNumber) ?? 0;

  Future<UpdateInfo> check(ApiClient api) async {
    if (!Platform.isAndroid) return UpdateInfo(available: false, reason: 'iOS updates come through TestFlight / App Store.');
    final data = Map<String, dynamic>.from(
      await api.get('updates.check', {'version_code': await currentVersionCode(), 'platform': 'Android'}) as Map,
    );
    return UpdateInfo(
      available: data['available'] == true,
      versionCode: (data['version_code'] as num?)?.toInt() ?? 0,
      versionName: data['version_name']?.toString() ?? '',
      notes: data['notes']?.toString() ?? '',
      size: (data['size'] as num?)?.toInt() ?? 0,
      mandatory: data['mandatory'] == true,
      reason: data['reason']?.toString(),
    );
  }

  /// Quiet check on launch / resume (at most every 3 hours); shows the prompt if needed.
  Future<void> autoCheck(BuildContext context, ApiClient api) async {
    if (!Platform.isAndroid || _prompting) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(hours: 3)) return;
    _lastCheck = now;
    try {
      final info = await check(api);
      if (info.available && context.mounted) await showUpdatePrompt(context, api, info);
    } catch (_) {
      // Never bother the user because an update check failed.
    }
  }

  Future<void> showUpdatePrompt(BuildContext context, ApiClient api, UpdateInfo info) async {
    if (_prompting) return;
    _prompting = true;
    try {
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: !info.mandatory,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Version ${info.versionName}${info.size > 0 ? ' (${(info.size / 1048576).toStringAsFixed(0)} MB)' : ''}'),
            if (info.notes.isNotEmpty) ...[const SizedBox(height: 10), Text(info.notes)],
            const SizedBox(height: 10),
            const Text('You will stay signed in.', style: TextStyle(fontSize: 13)),
          ]),
          actions: [
            if (!info.mandatory) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );
      if (go == true && context.mounted) await downloadAndInstall(context, api);
    } finally {
      _prompting = false;
    }
  }

  /// Downloads with a progress dialog, then opens the system installer.
  Future<void> downloadAndInstall(BuildContext context, ApiClient api) async {
    final progress = ValueNotifier<double?>(null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading update'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: p),
            const SizedBox(height: 10),
            Text(p == null ? 'Starting...' : '${(p * 100).toStringAsFixed(0)}%'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    void closeDialog() {
      if (!cancelled && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    final client = http.Client();
    try {
      final link = Map<String, dynamic>.from(await api.get('updates.get_download_url') as Map);
      final url = link['url'].toString();
      final versionCode = (link['version_code'] as num?)?.toInt() ?? 0;
      final file = File('${Directory.systemTemp.path}/Hipersign-$versionCode.apk');

      final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw ApiException('SERVER_ERROR', 'Download failed (${res.statusCode}).');
      final total = res.contentLength ?? (link['size'] as num?)?.toInt() ?? 0;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          if (cancelled) break;
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) progress.value = received / total;
        }
      } finally {
        await sink.close();
      }
      if (cancelled) {
        if (await file.exists()) await file.delete();
        return;
      }
      closeDialog();
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        messenger?.showSnackBar(SnackBar(
          content: Text(result.type == ResultType.permissionDenied
              ? 'Allow "Install unknown apps" for Hipersign in phone settings, then try again.'
              : 'Could not open the installer: ${result.message}'),
          duration: const Duration(seconds: 6),
        ));
      }
    } on ApiException catch (e) {
      closeDialog();
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      closeDialog();
      messenger?.showSnackBar(const SnackBar(content: Text('Download failed. Check your internet and try again.')));
    } finally {
      client.close();
      progress.dispose();
    }
  }
}
