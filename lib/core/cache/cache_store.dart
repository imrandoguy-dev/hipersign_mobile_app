import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedEntry {
  CachedEntry(this.data, this.syncedAt);
  final dynamic data;
  final DateTime syncedAt;
}

/// Read-only cache of server responses, isolated per server + user.
///
/// Policy (PRD 8.5): cached data is shown immediately and refreshed from the
/// server; writes never touch the cache until the server confirms them; the
/// whole cache for a user is dropped on logout or when their access changes.
class CacheStore {
  CacheStore._(this._prefs);

  final SharedPreferences _prefs;
  String _scope = 'none';

  static CacheStore? _instance;
  static Future<CacheStore> instance() async {
    return _instance ??= CacheStore._(await SharedPreferences.getInstance());
  }

  void setScope(String server, String user) {
    _scope = '${Uri.parse(server).host}::$user';
  }

  String _k(String key) => 'hm_cache::$_scope::$key';

  CachedEntry? read(String key) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(m['d'], DateTime.fromMillisecondsSinceEpoch(m['t'] as int));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, dynamic data) async {
    await _prefs.setString(_k(key), jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'd': data}));
  }

  Future<void> clearScope() async {
    final prefix = 'hm_cache::$_scope::';
    for (final k in _prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await _prefs.remove(k);
    }
  }

  // Small non-sensitive preferences (not scoped to a user)
  String? getPref(String key) => _prefs.getString('hm_pref::$key');
  Future<void> setPref(String key, String? value) async {
    if (value == null) {
      await _prefs.remove('hm_pref::$key');
    } else {
      await _prefs.setString('hm_pref::$key', value);
    }
  }
}
