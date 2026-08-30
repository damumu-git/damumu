import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class AdministrativeRegion {
  const AdministrativeRegion({
    required this.code,
    required this.level,
    required this.nameZhCn,
    this.parentCode,
  });

  final String code;
  final String? parentCode;
  final int level;
  final String nameZhCn;

  factory AdministrativeRegion.fromJson(Map<String, dynamic> json) =>
      AdministrativeRegion(
        code: json['code'] as String,
        parentCode: json['parent_code'] as String?,
        level: json['level'] as int,
        nameZhCn: json['name_zh_cn'] as String,
      );
}

class RegionService {
  static Future<List<AdministrativeRegion>> load() async {
    final response = await http
        .get(Uri.parse('$_apiBase/regions'))
        .timeout(const Duration(seconds: 8));
    if (response.bodyBytes.isEmpty) {
      throw Exception('地区加载失败 (${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '地区加载失败');
    }
    return (decoded['data'] as List)
        .map(
          (item) => AdministrativeRegion.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }
}

class EventService {
  static Future<List<Map<String, dynamic>>> list() async {
    final response = await http
        .get(Uri.parse('$_apiBase/events?limit=100'))
        .timeout(const Duration(seconds: 10));
    if (response.bodyBytes.isEmpty) {
      throw Exception('活动加载失败 (${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '活动加载失败');
    }
    return (decoded['data'] as List)
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<List<Map<String, dynamic>>> myActivities(String token) async {
    final response = await http
        .get(
          Uri.parse('$_apiBase/me/activities'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.bodyBytes.isEmpty) {
      throw Exception('我的活动加载失败 (${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '我的活动加载失败');
    }
    return (decoded['data'] as List)
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<String> create({
    required String token,
    required String categoryId,
    required String title,
    required String description,
    required String cityCode,
    required String districtCode,
    required DateTime startsAt,
    required DateTime endsAt,
    required int capacity,
    required int priceAmount,
    required bool approvalRequired,
    String? meetingPoint,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/events'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'categoryId': categoryId,
            'title': title,
            'description': description,
            'cityCode': cityCode,
            'districtCode': districtCode,
            'startsAt': startsAt.toUtc().toIso8601String(),
            'endsAt': endsAt.toUtc().toIso8601String(),
            'minParticipants': 2,
            'capacity': capacity,
            'approvalMode': approvalRequired ? 'manual' : 'automatic',
            'visibility': 'public',
            'minAge': 18,
            'priceMin': priceAmount,
            'priceMax': priceAmount,
            'priceCurrency': 'KRW',
            'languageCodes': ['zh-CN'],
            if (meetingPoint != null && meetingPoint.trim().isNotEmpty)
              'place': {
                'name': meetingPoint.trim(),
                'addressPublic': meetingPoint.trim(),
                'latitude': null,
                'longitude': null,
              },
          }),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '活动发布失败');
    }
    return decoded['data']['id'] as String;
  }
}
