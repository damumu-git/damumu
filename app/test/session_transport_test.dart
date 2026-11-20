import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/session_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await SessionTransport.clear();
  });
  String token(int seconds) =>
      '00000000000000000000000000000001.${DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds}.nonce.signature';
  Map<String, dynamic> credentials(String access) => {
    'accessToken': access,
    'refreshToken': 'refresh-proof',
    'expiresAt': DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch,
  };
  test(
    'credentials persist in secure storage and legacy preferences are removed',
    () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'legacy'});
      final access = token(600);
      await SessionTransport.capture(credentials(access), true);
      expect(await SessionTransport.restore(), access);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      await SessionTransport.clear();
      expect(await SessionTransport.restore(), isNull);
    },
  );
  test(
    'concurrent calls rotate refresh credentials once and use fresh access',
    () async {
      final expired = token(-1);
      final renewed = token(900);
      await SessionTransport.capture(credentials(expired), true);
      var refreshes = 0;
      await http.runWithClient(
        () async {
          final requests = await Future.wait([
            SessionTransport.accessToken(expired),
            SessionTransport.accessToken(expired),
          ]);
          expect(requests, [renewed, renewed]);
          expect(refreshes, 1);
        },
        () => MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/refresh');
          expect(request.headers.containsKey('Authorization'), false);
          refreshes++;
          return http.Response(
            jsonEncode({
              'data': {
                'accessToken': renewed,
                'refreshToken': 'rotated-proof',
                'expiresAt': DateTime.now()
                    .add(const Duration(days: 30))
                    .millisecondsSinceEpoch,
              },
            }),
            200,
          );
        }),
      );
    },
  );
  test('logout during refresh prevents credential restoration', () async {
    final expired = token(-1);
    await SessionTransport.capture(credentials(expired), true);
    final started = Completer<void>();
    final response = Completer<http.Response>();
    await http.runWithClient(
      () async {
        final renewal = SessionTransport.accessToken(expired);
        final assertion = expectLater(
          renewal,
          throwsA(isA<SessionExpiredException>()),
        );
        await started.future;
        await SessionTransport.clear();
        response.complete(
          http.Response(jsonEncode({'data': credentials(token(900))}), 200),
        );
        await assertion;
        expect(await SessionTransport.restore(), isNull);
      },
      () => MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
  });
  test('transport rejects sending credentials to another origin', () async {
    final request = http.Request(
      'GET',
      Uri.parse('https://untrusted.invalid/private'),
    );
    request.headers['Authorization'] = 'Bearer proof';
    await expectLater(
      SessionTransport.client.send(request),
      throwsFormatException,
    );
  });
}
