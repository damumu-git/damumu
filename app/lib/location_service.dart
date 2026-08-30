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

  // v2 invalidates labels cached before the Simplified Chinese locale fix.
  static const _labelKey = 'last_location_label_v2';
  static const _latitudeKey = 'last_location_latitude_v2';
  static const _longitudeKey = 'last_location_longitude_v2';
  static const _cachedAtKey = 'last_location_cached_at_v2';
  static const _cacheLifetime = Duration(minutes: 30);

  final http.Client _client;

  Future<AppLocation> locate({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _readCache();
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
    final label = await _reverseGeocode(position.latitude, position.longitude);
    final result = AppLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      label: label,
    );
    await _writeCache(result);
    return result;
  }

  Future<String> _reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toStringAsFixed(7),
      'lon': longitude.toStringAsFixed(7),
      'zoom': '12',
      'addressdetails': '1',
      'accept-language': 'zh-Hans-CN,zh-Hans,zh-CN,ko,en',
    });
    try {
      final response = await _client
          .get(
            uri,
            headers: const {'User-Agent': 'MUDA/0.1 (location@muda.app)'},
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

  Future<AppLocation?> _readCache() async {
    final preferences = await SharedPreferences.getInstance();
    final cachedAt = preferences.getInt(_cachedAtKey);
    final latitude = preferences.getDouble(_latitudeKey);
    final longitude = preferences.getDouble(_longitudeKey);
    final label = preferences.getString(_labelKey);
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

  Future<void> _writeCache(AppLocation location) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setDouble(_latitudeKey, location.latitude),
      preferences.setDouble(_longitudeKey, location.longitude),
      preferences.setString(_labelKey, location.label),
      preferences.setInt(_cachedAtKey, DateTime.now().millisecondsSinceEpoch),
    ]);
  }
}

class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;
}
