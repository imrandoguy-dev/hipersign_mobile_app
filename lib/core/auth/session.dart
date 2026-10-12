import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/models.dart';
import '../api/api_client.dart';
import '../cache/cache_store.dart';
import '../notifications/notification_service.dart';
import '../repository.dart';

enum SessionStatus { restoring, signedOut, signedIn }

/// Sign-in state, the API client and the user's server-defined capabilities.
///
/// Secrets (session id) live in Keychain / Android Keystore-backed storage.
/// The role-based UI is a convenience only; the server enforces every permission.
class SessionController extends ChangeNotifier {
  static const defaultServer = 'https://nexus365.hipersignerp.cloud';
  static const _kServer = 'hm_server';
  static const _kSid = 'hm_sid';
  static const _kUser = 'hm_user';
  static const _kDeviceId = 'hm_device_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  SessionStatus status = SessionStatus.restoring;
  ApiClient? api;
  Profile? profile;
  String? server;
  String? deviceId;
  bool offline = false;
  String? notice; // e.g. "Your session ended"
  Map<String, dynamic> config = {};

  late CacheStore cache;

  /// Data access for screens. Only valid while signed in.
  Repository get repo => Repository(api!, cache);

  Future<void> restore() async {
    cache = await CacheStore.instance();
    deviceId = await _secure.read(key: _kDeviceId);
    if (deviceId == null) {
      deviceId = randomKey(16);
      await _secure.write(key: _kDeviceId, value: deviceId);
    }
    server = await _secure.read(key: _kServer);
    final sid = await _secure.read(key: _kSid);
    final user = await _secure.read(key: _kUser);
    if (server == null || sid == null || user == null) {
      _set(SessionStatus.signedOut);
      return;
    }
    api = ApiClient(baseUrl: server!, sid: sid, onSessionExpired: _sessionExpired);
    cache.setScope(server!, user);
    final cachedProfile = cache.read('profile');
    try {
      await _loadProfile();
      _set(SessionStatus.signedIn);
      _afterSignIn();
    } on ApiException catch (e) {
      if (e.isNetwork && cachedProfile != null) {
        // Offline start: show previously synced data read-only.
        profile = Profile.fromJson(Map<String, dynamic>.from(cachedProfile.data as Map));
        offline = true;
        _set(SessionStatus.signedIn);
      } else {
        await _clearLocal();
        _set(SessionStatus.signedOut);
      }
    }
  }

  /// Throws [ApiException] or [TwoFactorRequired].
  Future<void> signIn(String serverInput, String user, String password, {String? otp, String? tmpId}) async {
    final base = ApiClient.normalizeServer(serverInput);
    if (!base.startsWith('https://') && !kDebugMode) {
      throw ApiException('VALIDATION_ERROR', 'Use an https:// server address.');
    }
    // Validate the server has the backend app before sending credentials anywhere else.
    final probe = ApiClient(baseUrl: base);
    config = Map<String, dynamic>.from(await probe.get('auth.get_config') as Map);

    final sid = await ApiClient.login(base, user, password, otp: otp, tmpId: tmpId);
    server = base;
    api = ApiClient(baseUrl: base, sid: sid, onSessionExpired: _sessionExpired);
    await _loadProfile();
    await _secure.write(key: _kServer, value: base);
    await _secure.write(key: _kSid, value: sid);
    await _secure.write(key: _kUser, value: profile!.user);
    notice = null;
    _set(SessionStatus.signedIn);
    _afterSignIn();
  }

  Future<void> _loadProfile() async {
    final data = Map<String, dynamic>.from(await api!.get('auth.get_me') as Map);
    final fresh = Profile.fromJson(data);
    cache.setScope(server!, fresh.user);
    final previous = cache.read('profile');
    if (previous != null) {
      final old = Profile.fromJson(Map<String, dynamic>.from(previous.data as Map));
      if (old.accessKey != fresh.accessKey) {
        await cache.clearScope(); // access changed: drop anything they may no longer see
      }
    }
    await cache.write('profile', fresh.toJson());
    profile = fresh;
    offline = false;
  }

  /// Re-read roles/capabilities (pull-to-refresh, app resume).
  Future<void> refreshProfile() async {
    if (api == null) return;
    try {
      await _loadProfile();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        offline = true;
        notifyListeners();
      }
    }
  }

  void _afterSignIn() {
    final a = api;
    final id = deviceId;
    if (a == null || id == null) return;
    () async {
      await NotificationService.instance.requestPermission();
      try {
        await NotificationService.instance.registerDevice(a, id);
      } catch (_) {
        // Retried on next launch; the app works without push.
      }
      notifyListeners();
    }();
  }

  Future<void> signOut() async {
    final a = api;
    if (a != null) {
      try {
        await a.post('auth.logout_mobile', {'device_id': deviceId});
      } catch (_) {}
    }
    await NotificationService.instance.onSignedOut();
    await cache.clearScope();
    await _clearLocal();
    _set(SessionStatus.signedOut);
  }

  bool _expiring = false;
  void _sessionExpired() {
    if (_expiring || status != SessionStatus.signedIn) return;
    _expiring = true;
    () async {
      await NotificationService.instance.onSignedOut();
      await cache.clearScope();
      await _clearLocal();
      notice = 'Your session has ended. Please sign in again.';
      _set(SessionStatus.signedOut);
      _expiring = false;
    }();
  }

  Future<void> _clearLocal() async {
    await _secure.delete(key: _kSid);
    await _secure.delete(key: _kUser);
    api = null;
    profile = null;
  }

  void _set(SessionStatus s) {
    status = s;
    notifyListeners();
  }

  String debugDescribe() => jsonEncode({'server': server, 'user': profile?.user, 'offline': offline});
}
