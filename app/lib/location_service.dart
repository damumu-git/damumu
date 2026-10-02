import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class AppLocation {
  const AppLocation({
    required this.regionCode,
    required this.label,
    this.latitude,
    this.longitude,
  });

  final String regionCode;
  final String label;
  // Coordinates live in memory only long enough to request the first page. They
  // are never written to preferences or exposed in the activity UI.
  final double? latitude;
  final double? longitude;
}

class LocationService {
  LocationService({http.Client? client}) : _client = client ?? http.Client();

  static const _cacheVersion = 'v4_region_only';
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
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('请先开启设备定位服务');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('未获得定位权限，已使用你选择的地区');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('定位权限已关闭，已使用你选择的地区');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final result = await resolveRegion(
      position.latitude,
      position.longitude,
      languageCode: languageCode,
    );
    await _writeCache(result, languageCode);
    return AppLocation(
      regionCode: result.regionCode,
      label: result.label,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<AppLocation> resolveRegion(
    double latitude,
    double longitude, {
    required String languageCode,
  }) async {
    final response = await _client
        .get(
          Uri.parse('$_apiBase/regions/resolve').replace(
            queryParameters: {
              'latitude': latitude.toStringAsFixed(7),
              'longitude': longitude.toStringAsFixed(7),
            },
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw const LocationFailure('当前位置无法识别，已使用你选择的地区');
    }
    final envelope = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final data = (envelope['data'] as Map).cast<String, dynamic>();
    final nameKey = switch (languageCode) {
      'ko' => 'name_ko_kr',
      'en' => 'name_en_us',
      _ => 'name_zh_cn',
    };
    final cityKey = switch (languageCode) {
      'ko' => 'city_name_ko_kr',
      'en' => 'city_name_en_us',
      _ => 'city_name_zh_cn',
    };
    final city = data[cityKey]?.toString().trim();
    final district = data[nameKey]?.toString().trim();
    final label = [
      if (city != null && city.isNotEmpty && city != district) city,
      if (district != null && district.isNotEmpty) district,
    ].join(' · ');
    return AppLocation(
      regionCode: data['code'] as String,
      label: label.isEmpty ? '当前位置' : label,
      latitude: latitude,
      longitude: longitude,
    );
  }

  String _cacheKey(String field, String languageCode) =>
      'last_location_${field}_${_cacheVersion}_$languageCode';

  Future<AppLocation?> _readCache(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    final cachedAt = preferences.getInt(_cacheKey('cached_at', languageCode));
    final regionCode = preferences.getString(
      _cacheKey('region_code', languageCode),
    );
    final label = preferences.getString(_cacheKey('label', languageCode));
    if (cachedAt == null || regionCode == null || label == null) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAt),
    );
    if (age > _cacheLifetime) return null;
    return AppLocation(regionCode: regionCode, label: label);
  }

  Future<void> _writeCache(AppLocation location, String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(
        _cacheKey('region_code', languageCode),
        location.regionCode,
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
