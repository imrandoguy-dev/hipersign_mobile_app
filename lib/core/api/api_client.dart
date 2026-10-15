import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Error shown to the user. [code] follows the backend's categories:
/// UNAUTHENTICATED, FORBIDDEN, NOT_FOUND, VALIDATION_ERROR, CONFLICT,
/// RATE_LIMITED, SERVER_ERROR, plus NETWORK for "couldn't reach the server".
class ApiException implements Exception {
  ApiException(this.code, this.message, [this.status]);

  final String code;
  final String message;
  final int? status;

  bool get isNetwork => code == 'NETWORK';
  bool get isSessionProblem => code == 'UNAUTHENTICATED';
  bool get isConflict => code == 'CONFLICT';

  @override
  String toString() => message;
}

class TwoFactorRequired implements Exception {
  TwoFactorRequired(this.tmpId, this.prompt);
  final String tmpId;
  final String prompt;
}

String randomKey([int bytes = 16]) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Talks to the hipersign_mobile Frappe app.
///
/// Auth uses Frappe's own session: `/api/method/login` returns a `sid` cookie,
/// which is kept in secure storage and sent back as a Cookie header.
class ApiClient {
  ApiClient({required this.baseUrl, this.sid, this.onSessionExpired});

  final String baseUrl;
  String? sid;
  void Function()? onSessionExpired;

  static const _timeout = Duration(seconds: 20);
  static const apiPrefix = '/api/method/hipersign_mobile.api.';
  final http.Client _http = http.Client();

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (sid != null) 'Cookie': 'sid=$sid',
        'X-Request-ID': randomKey(8),
      };

  Uri _uri(String method, [Map<String, dynamic>? params]) {
    final q = <String, String>{};
    params?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('$baseUrl$apiPrefix$method').replace(queryParameters: q.isEmpty ? null : q);
  }

  /// Reads are retried once on a network blip; they are safe to repeat.
  Future<dynamic> get(String method, [Map<String, dynamic>? params]) async {
    for (var attempt = 1;; attempt++) {
      try {
        final r = await _wrap(() => _http.get(_uri(method, params), headers: _headers()).timeout(_timeout));
        return _handle(r);
      } on ApiException catch (e) {
        if (e.isNetwork && attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Writes are never retried automatically. Create/booking calls carry an
  /// idempotency key so the user can safely press "Try again".
  Future<dynamic> post(String method, Map<String, dynamic> body) async {
    final clean = Map<String, dynamic>.from(body)..removeWhere((k, v) => v == null);
    final r = await _wrap(() => _http
        .post(_uri(method), headers: _headers(json: true), body: jsonEncode(clean))
        .timeout(_timeout));
    return _handle(r);
  }

  /// Multipart upload (e.g. a call recording). Safe to retry when [fields] carry a client key.
  Future<dynamic> upload(String method, Map<String, dynamic> fields, String filePath, {String field = 'file'}) async {
    final r = await _wrap(() async {
      final req = http.MultipartRequest('POST', _uri(method))..headers.addAll(_headers());
      fields.forEach((k, v) {
        if (v != null) req.fields[k] = v.toString();
      });
      req.files.add(await http.MultipartFile.fromPath(field, filePath));
      final streamed = await _http.send(req).timeout(const Duration(minutes: 3));
      return http.Response.fromStream(streamed).timeout(const Duration(minutes: 3));
    });
    return _handle(r);
  }

  /// Downloads a file endpoint (not the JSON envelope) to [path].
  Future<File> downloadTo(String method, Map<String, dynamic> params, String path, {String what = 'recording'}) async {
    final r = await _wrap(() => _http.get(_uri(method, params), headers: _headers()).timeout(const Duration(minutes: 2)));
    final type = r.headers['content-type'] ?? '';
    if (r.statusCode == 200 && !type.contains('json')) {
      final f = File(path);
      await f.writeAsBytes(r.bodyBytes, flush: true);
      return f;
    }
    if (r.statusCode == 404) throw ApiException('NOT_FOUND', 'This $what is no longer available.', 404);
    if (r.statusCode == 403 || r.statusCode == 401) {
      throw ApiException('FORBIDDEN', 'You cannot open this $what.', r.statusCode);
    }
    throw ApiException('SERVER_ERROR', 'Could not download the $what (${r.statusCode}).', r.statusCode);
  }

  Future<http.Response> _wrap(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on TimeoutException {
      throw ApiException('NETWORK', 'The server took too long to answer. Your change may not have been saved - check and try again.');
    } on SocketException {
      throw ApiException('NETWORK', 'No connection to the server. Check your internet and try again.');
    } on http.ClientException {
      throw ApiException('NETWORK', 'No connection to the server. Check your internet and try again.');
    } on HandshakeException {
      throw ApiException('NETWORK', 'Secure connection to the server failed.');
    }
  }

  dynamic _handle(http.Response r) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    final msg = body?['message'];
    if (msg is Map && msg['success'] == true) return msg['data'];
    if (msg is Map && msg['success'] == false) {
      final err = Map<String, dynamic>.from((msg['error'] as Map?) ?? const {});
      final e = ApiException(err['code']?.toString() ?? 'SERVER_ERROR', err['message']?.toString() ?? 'Request failed.', r.statusCode);
      if (e.isSessionProblem) onSessionExpired?.call();
      throw e;
    }
    // Endpoint missing on the server: the app is newer than the server's Hipersign Mobile.
    final raw = utf8.decode(r.bodyBytes, allowMalformed: true);
    if ((r.statusCode == 417 || r.statusCode == 404) &&
        (raw.contains('Failed to get method') || raw.contains('has no attribute') || raw.contains('No module named'))) {
      throw ApiException('NOT_FOUND',
          'This needs the latest Hipersign Mobile update on the server. Ask your admin to update it (Press > Update Available).',
          r.statusCode);
    }
    // Not our envelope: Frappe refused before reaching the endpoint (session gone).
    if (r.statusCode == 401 || r.statusCode == 403) {
      onSessionExpired?.call();
      throw ApiException('UNAUTHENTICATED', 'Your session has ended. Please sign in again.', r.statusCode);
    }
    if (r.statusCode == 404) {
      throw ApiException('NOT_FOUND', 'This server does not have the Hipersign Mobile app installed.', 404);
    }
    if (r.statusCode == 429) {
      throw ApiException('RATE_LIMITED', 'Too many requests. Please wait a moment.', 429);
    }
    throw ApiException('SERVER_ERROR', 'The server returned an error (${r.statusCode}). Please try again.', r.statusCode);
  }

  // ------------------------------------------------------------- login

  /// Returns the session id. Throws [TwoFactorRequired] when the account uses 2FA.
  static Future<String> login(String baseUrl, String user, String password, {String? otp, String? tmpId}) async {
    final client = http.Client();
    try {
      final body = otp != null ? {'otp': otp, 'tmp_id': tmpId} : {'usr': user, 'pwd': password};
      final r = await client
          .post(Uri.parse('$baseUrl/api/method/login'),
              headers: {'Accept': 'application/json', 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
      Map<String, dynamic> json = {};
      try {
        json = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      } catch (_) {}
      if (r.statusCode == 200 && json['verification'] != null && json['tmp_id'] != null) {
        final v = json['verification'];
        final prompt = (v is Map ? v['prompt'] : null)?.toString() ?? 'Enter the verification code.';
        throw TwoFactorRequired(json['tmp_id'].toString(), prompt);
      }
      if (r.statusCode == 401 || r.statusCode == 417) {
        throw ApiException('UNAUTHENTICATED', 'Incorrect email or password.', r.statusCode);
      }
      if (r.statusCode == 429) {
        throw ApiException('RATE_LIMITED', 'Too many sign-in attempts. Please wait and try again.', 429);
      }
      if (r.statusCode != 200) {
        final m = json['message']?.toString();
        throw ApiException('UNAUTHENTICATED', m ?? 'Sign-in failed (${r.statusCode}).', r.statusCode);
      }
      final cookie = r.headers['set-cookie'] ?? '';
      final match = RegExp(r'(?:^|[;,\s])sid=([^;,\s]+)').firstMatch(cookie);
      final sid = match?.group(1);
      if (sid == null || sid == 'Guest') {
        throw ApiException('UNAUTHENTICATED', 'Sign-in failed: the server did not start a session.');
      }
      return sid;
    } on TimeoutException {
      throw ApiException('NETWORK', 'The server took too long to answer.');
    } on SocketException {
      throw ApiException('NETWORK', 'Cannot reach the server. Check the address and your internet.');
    } on http.ClientException {
      throw ApiException('NETWORK', 'Cannot reach the server. Check the address and your internet.');
    } on HandshakeException {
      throw ApiException('NETWORK', 'Secure connection to the server failed.');
    } finally {
      client.close();
    }
  }

  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
