import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocation {
  const AppLocation({
    this.latitude,
    this.longitude,
    required this.label,
    this.cityCode,
    this.districtCode,
  });

  final double? latitude;
  final double? longitude;
  final String label;
  final String? cityCode;
  final String? districtCode;

  bool get isManual => cityCode != null;
}

class ManualRegionSelection {
  const ManualRegionSelection({required this.cityCode, this.districtCode});

  final String cityCode;
  final String? districtCode;
}

class LocationService {
  LocationService();

  // v3 separates labels by App language and invalidates older locale-agnostic
  // labels, which could keep showing Traditional Chinese after a language change.
  static const _cacheVersion = 'v3';
  static const _cacheLifetime = Duration(minutes: 30);

  static const _manualCityKey = 'manual_location_city_v1';
  static const _manualDistrictKey = 'manual_location_district_v1';

  Future<ManualRegionSelection?> readManualRegion() async {
    final preferences = await SharedPreferences.getInstance();
    final cityCode = preferences.getString(_manualCityKey);
    if (cityCode == null || cityCode.isEmpty) return null;
    return ManualRegionSelection(
      cityCode: cityCode,
      districtCode: preferences.getString(_manualDistrictKey),
    );
  }

  Future<void> saveManualRegion(ManualRegionSelection selection) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_manualCityKey, selection.cityCode);
    final districtCode = selection.districtCode;
    if (districtCode == null || districtCode.isEmpty) {
      await preferences.remove(_manualDistrictKey);
    } else {
      await preferences.setString(_manualDistrictKey, districtCode);
    }
  }

  Future<void> clearManualRegion() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_manualCityKey),
      preferences.remove(_manualDistrictKey),
    ]);
  }

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
    final result = AppLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      label: _currentLocationLabel(languageCode),
    );
    await _writeCache(result, languageCode);
    return result;
  }

  String _currentLocationLabel(String languageCode) => switch (languageCode) {
    'ko' => '현재 위치',
    'en' => 'Current location',
    _ => '当前位置',
  };

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
        location.latitude!,
      ),
      preferences.setDouble(
        _cacheKey('longitude', languageCode),
        location.longitude!,
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
