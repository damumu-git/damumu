import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _api = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.damumu.com/api/v1',
);

class SessionExpiredException implements Exception {}

class SessionTransport extends http.BaseClient {
  static final http.Client client = SessionTransport();
  static const _storage = FlutterSecureStorage();
  static const _key = 'damumu_session_v2';
  static String? _anchor;
  static String? _access;
  static String? _refresh;
  static int? _expiresAt;
  static bool _persistent = false;
  static Future<void>? _renewing;
  static int _generation = 0;
  static Future<void>? _saving;

  static Future<void> capture(
    Map<String, dynamic> result,
    bool persistent,
  ) async {
    _generation++;
    _anchor = result['accessToken'] as String?;
    _access = _anchor;
    _refresh = result['refreshToken'] as String?;
    final parts = _anchor?.split('.');
    final signedExpiry = parts != null && parts.length >= 2
        ? int.tryParse(parts[1])
        : null;
    _expiresAt =
        (result['expiresAt'] as num?)?.toInt() ??
        (signedExpiry == null ? null : signedExpiry * 1000);
    _persistent = persistent && !kIsWeb;
    await _save();
  }

  static bool get expired =>
      _expiresAt != null &&
      _expiresAt! <= DateTime.now().millisecondsSinceEpoch;

  static Future<String?> restore() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('auth_token');
    if (kIsWeb) return null;
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      final result = (jsonDecode(value) as Map).cast<String, dynamic>();
      _anchor = result['anchor'] as String?;
      _access = result['access'] as String?;
      _refresh = result['refresh'] as String?;
      _expiresAt = (result['expiresAt'] as num?)?.toInt();
      _persistent = true;
      if (expired) {
        await clear();
        return null;
      }
      return _anchor;
    } on FormatException {
      await clear();
      return null;
    }
  }

  static Future<void> _save() async {
    if (kIsWeb) return;
    final generation = _generation;
    final value = !_persistent || _anchor == null
        ? null
        : jsonEncode({
            'anchor': _anchor,
            'access': _access,
            'refresh': _refresh,
            'expiresAt': _expiresAt,
          });
    while (_saving != null) {
      try {
        await _saving;
      } catch (_) {
        /* The next operation can clear failed writes. */
      }
    }
    if (generation != _generation) return;
    final operation = value == null
        ? _storage.delete(key: _key)
        : _storage.write(key: _key, value: value);
    _saving = operation;
    try {
      await operation;
    } finally {
      if (identical(_saving, operation)) _saving = null;
    }
  }

  static Future<void> clear() async {
    _generation++;
    _anchor = null;
    _access = null;
    _refresh = null;
    _expiresAt = null;
    _persistent = false;
    await _save();
  }

  static String resolve(String token) =>
      token == _anchor ? _access ?? token : token;

  static Future<String> accessToken(String token) async {
    if (token != _anchor && token != _access) return token;
    final parts = _access?.split('.');
    final deadline = parts != null && parts.length >= 2
        ? int.tryParse(parts[1])
        : null;
    if (deadline != null &&
        deadline * 1000 <= DateTime.now().millisecondsSinceEpoch + 60000 &&
        _refresh != null) {
      _renewing ??= _renew().whenComplete(() => _renewing = null);
      await _renewing;
    }
    if (_access == null) throw SessionExpiredException();
    return _access!;
  }

  static Future<void> _renew() async {
    final generation = _generation;
    final response = await http
        .post(
          Uri.parse('$_api/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': _refresh}),
        )
        .timeout(const Duration(seconds: 10));
    if (generation != _generation) return;
    if (response.statusCode == 401) {
      await clear();
      throw SessionExpiredException();
    }
    if (response.statusCode != 200) {
      throw const FormatException('Session temporarily unavailable');
    }
    final data =
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['data'] as Map;
    _access = data['accessToken'] as String;
    _refresh = data['refreshToken'] as String;
    await _save();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final value = request.headers['Authorization'];
    if (value?.startsWith('Bearer ') == true) {
      final api = Uri.parse(_api);
      if (request.url.origin != api.origin) {
        throw const FormatException('Untrusted API origin');
      }
      request.headers['Authorization'] =
          'Bearer ${await accessToken(value!.substring(7))}';
    }
    return request.send();
  }
}
