import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

class LocationService {
  LocationService({http.Client? client}) : _client = client ?? http.Client();

  // v3 separates labels by App language and invalidates older locale-agnostic
  // labels, which could keep showing Traditional Chinese after a language change.
  static const _cacheVersion = 'v3';
  static const _cacheLifetime = Duration(minutes: 30);

  final http.Client _client;

  Future<AppLocation> locate({
    required String languageCode,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCache(languageCode);
      if (cached != null) return cached;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationFailure('请先开启设备定位服务');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('未获得定位权限，点击可重试');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('定位权限已被永久关闭，请在系统设置中开启');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final label = await _reverseGeocode(
      position.latitude,
      position.longitude,
      languageCode,
    );
    final result = AppLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      label: label,
    );
    await _writeCache(result, languageCode);
    return result;
  }

  Future<String> _reverseGeocode(
    double latitude,
    double longitude,
    String languageCode,
  ) async {
    final acceptedLanguages = switch (languageCode) {
      'ko' => 'ko-KR,ko,en',
      'en' => 'en-US,en',
      _ => 'zh-CN,zh-Hans-CN,zh-Hans,en',
    };
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toStringAsFixed(7),
      'lon': longitude.toStringAsFixed(7),
      'zoom': '12',
      'addressdetails': '1',
      'accept-language': acceptedLanguages,
    });
    try {
      final response = await _client
          .get(
            uri,
            headers: const {'User-Agent': 'DAMUMU/0.1 (location@muda.app)'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return '当前位置';
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final address = json['address'] as Map<String, dynamic>? ?? const {};
      final city = _first(address, const [
        'city',
        'municipality',
        'state',
        'province',
      ]);
      final district = _first(address, const [
        'borough',
        'city_district',
        'suburb',
        'county',
        'town',
      ]);
      if (city != null && district != null && city != district) {
        return '$city · $district';
      }
      return district ?? city ?? (json['display_name'] as String?) ?? '当前位置';
    } catch (_) {
      return '当前位置';
    }
  }

  String? _first(Map<String, dynamic> address, List<String> keys) {
    for (final key in keys) {
      final value = address[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _cacheKey(String field, String languageCode) =>
      'last_location_${field}_${_cacheVersion}_$languageCode';

  Future<AppLocation?> _readCache(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    final cachedAt = preferences.getInt(_cacheKey('cached_at', languageCode));
    final latitude = preferences.getDouble(_cacheKey('latitude', languageCode));
    final longitude = preferences.getDouble(
      _cacheKey('longitude', languageCode),
    );
    final label = preferences.getString(_cacheKey('label', languageCode));
    if (cachedAt == null ||
        latitude == null ||
        longitude == null ||
        label == null) {
      return null;
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAt),
    );
    if (age > _cacheLifetime) return null;
    return AppLocation(latitude: latitude, longitude: longitude, label: label);
  }

  Future<void> _writeCache(AppLocation location, String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setDouble(
        _cacheKey('latitude', languageCode),
        location.latitude,
      ),
      preferences.setDouble(
        _cacheKey('longitude', languageCode),
        location.longitude,
      ),
      preferences.setString(_cacheKey('label', languageCode), location.label),
      preferences.setInt(
        _cacheKey('cached_at', languageCode),
        DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
  }
}

class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;
}
