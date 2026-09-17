import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class ActivityCategory {
  const ActivityCategory({
    required this.id,
    required this.code,
    required this.level,
    required this.name,
    required this.icon,
    this.iconKey,
    this.isFeatured = false,
    this.parentId,
  });

  final String id;
  final String code;
  final int level;
  final String name;
  final String icon;
  final String? iconKey;
  final bool isFeatured;
  final String? parentId;

  factory ActivityCategory.fromJson(Map<String, dynamic> json) =>
      ActivityCategory(
        id: json['id'] as String,
        code: json['code'] as String,
        level: json['level'] as int,
        name: json['name_zh_cn'] as String,
        icon: (json['icon'] as String?) ?? '◇',
        iconKey: json['icon_key'] as String?,
        isFeatured: json['is_featured'] as bool? ?? false,
        parentId: json['parent_id'] as String?,
      );
}

class CategoryService {
  static Future<List<ActivityCategory>> load() async {
    final response = await http
        .get(Uri.parse('$_apiBase/categories'))
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '分类加载失败');
    }
    return (decoded['data'] as List)
        .map((item) => ActivityCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
