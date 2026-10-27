import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.damumu.com/api/v1',
);

String _normalized(String value) =>
    value.replaceAll('\uFE0F', '').replaceAll('\uFE0E', '');

/// Only the artwork map is cached. Production categories still come from the API.
abstract final class EmojiAssets {
  static final urls = ValueNotifier<Map<String, String>>({});
  static Future<void>? _loading;
  static Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  static Future<void> _load() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBase/emoji-assets'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      urls.value = {
        for (final item in body['data'] as List)
          _normalized(item['emoji'] as String): item['image_url'] as String,
      };
    } catch (_) {
      // Old servers, offline startup and unknown Emoji retain a readable fallback.
    }
  }
}

class EmojiPicture extends StatelessWidget {
  const EmojiPicture(
    this.emoji, {
    this.url,
    this.size = 24,
    this.label,
    super.key,
  });
  final String emoji;
  final String? url;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, String>>(
        valueListenable: EmojiAssets.urls,
        builder: (context, urls, _) {
          final resolved = url ?? urls[_normalized(emoji)];
          final fallback = Text(emoji, style: TextStyle(fontSize: size));
          if (resolved == null || resolved.isEmpty) return fallback;
          final uri = Uri.tryParse(resolved);
          if (uri == null || !['http', 'https'].contains(uri.scheme)) {
            return fallback;
          }
          return Image.network(
            resolved,
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: 64,
            cacheHeight: 64,
            semanticLabel: label ?? emoji,
            errorBuilder: (_, _, _) => fallback,
          );
        },
      );
}
