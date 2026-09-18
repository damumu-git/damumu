import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';

void main() {
  test('avatar upload sends the JPEG MIME type required by the API', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/me/avatar');
      expect(request.headers['content-type'], contains('multipart/form-data'));
      expect(
        latin1.decode(request.bodyBytes),
        contains('content-type: image/jpeg'),
      );
      return http.Response(
        jsonEncode({
          'data': {'avatarUrl': '/uploads/avatars/test.jpg'},
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      final url = await AuthApi.uploadAvatar(
        'test-token',
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      );
      expect(url, '/uploads/avatars/test.jpg');
    }, () => client);
  });
}
