import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class EventServiceException implements Exception {
  const EventServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic> _decodeResponse(
  http.Response response,
  String fallbackMessage,
) {
  if (response.bodyBytes.isEmpty) {
    throw EventServiceException(fallbackMessage);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    throw EventServiceException(fallbackMessage);
  }

  if (decoded is! Map) {
    throw EventServiceException(fallbackMessage);
  }
  final envelope = decoded.cast<String, dynamic>();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final error = envelope['error'];
    final message = error is Map ? error['message'] : null;
    throw EventServiceException(
      message is String &&
              message.trim().isNotEmpty &&
              !_looksTechnical(message)
          ? message
          : fallbackMessage,
    );
  }
  return envelope;
}

bool _looksTechnical(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('npgsql') ||
      normalized.contains('syntaxerror') ||
      normalized.contains('formatexception') ||
      normalized.contains('sqlstate') ||
      normalized.contains('stack trace') ||
      normalized.contains('exception:') ||
      normalized.contains('is not valid json');
}

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
    final decoded = _decodeResponse(response, '地区暂时无法加载，请稍后再试');
    return (decoded['data'] as List)
        .map(
          (item) => AdministrativeRegion.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }
}

class ActivityPage {
  const ActivityPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool hasMore;
}

class EventService {
  static Future<Map<String, dynamic>> detail(
    String token,
    String eventId,
  ) async {
    final response = await http
        .get(
          Uri.parse('$_apiBase/events/$eventId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    final data = _decodeResponse(response, '活动暂时无法加载，请稍后再试')['data'];
    return (data['item'] as Map).cast<String, dynamic>();
  }

  static Future<ActivityPage> list({
    double? latitude,
    double? longitude,
    int radiusMeters = 10000,
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      'cursor': ?cursor,
    };
    if (latitude != null && longitude != null) {
      query.addAll({
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radiusMeters': radiusMeters.toString(),
      });
    }
    final response = await http
        .get(Uri.parse('$_apiBase/activities').replace(queryParameters: query))
        .timeout(const Duration(seconds: 10));
    final decoded = _decodeResponse(response, '活动暂时无法加载，请稍后再试');
    final data = decoded['data'];
    if (data is! Map ||
        data['items'] is! List ||
        data['hasMore'] is! bool ||
        (data['nextCursor'] != null && data['nextCursor'] is! String) ||
        (data['hasMore'] == true &&
            (data['nextCursor'] == null ||
                (data['nextCursor'] as String).isEmpty ||
                data['nextCursor'] == cursor ||
                (data['items'] as List).isEmpty))) {
      throw const EventServiceException('活动暂时无法加载，请稍后再试');
    }
    return ActivityPage(
      items: (data['items'] as List)
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList(),
      nextCursor: data['nextCursor'] as String?,
      hasMore: data['hasMore'] as bool,
    );
  }

  static Future<List<Map<String, dynamic>>> myActivities(String token) async {
    final response = await http
        .get(
          Uri.parse('$_apiBase/me/activities'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    final decoded = _decodeResponse(response, '我的活动暂时无法加载，请稍后再试');
    return (decoded['data'] as List)
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<List<Map<String, dynamic>>> applications(
    String token,
    String eventId,
  ) async {
    final response = await http
        .get(
          Uri.parse('$_apiBase/events/$eventId/members?status=applied'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    return _listResponse(response, '申请列表加载失败');
  }

  static Future<void> approveApplication(
    String token,
    String eventId,
    String userId,
  ) async {
    await _memberDecision(token, eventId, userId, 'approve');
  }

  static Future<void> rejectApplication(
    String token,
    String eventId,
    String userId,
    String reason,
  ) async {
    await _memberDecision(
      token,
      eventId,
      userId,
      'reject',
      body: {'reason': reason},
    );
  }

  static Future<void> _memberDecision(
    String token,
    String eventId,
    String userId,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/events/$eventId/members/$userId/$action'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 10));
    _decodeResponse(response, '操作没有成功，请稍后再试');
  }

  static List<Map<String, dynamic>> _listResponse(
    http.Response response,
    String fallbackMessage,
  ) {
    final decoded = _decodeResponse(response, fallbackMessage);
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
    final decoded = _decodeResponse(response, '活动发布没有成功，请稍后再试');
    return decoded['data']['id'] as String;
  }
}
