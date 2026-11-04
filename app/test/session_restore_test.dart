import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/social_login.dart';

String session(Duration remaining) =>
    '00000000000000000000000000000001.${DateTime.now().add(remaining).millisecondsSinceEpoch ~/ 1000}.signature';
http.Response profile() => http.Response(
  jsonEncode({
    'data': {
      'id': 'user-1',
      'nickname': 'Test',
      'email': 'test@example.invalid',
    },
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fresh install never silently logs into the developer account',
    () async {
      await http.runWithClient(() async {
        final controller = AuthController();
        await controller.restore();
        expect(controller.user, isNull);
        expect(controller.loading, isFalse);
        controller.dispose();
      }, () => MockClient((_) async => throw StateError('Unexpected request')));
    },
  );

  for (final provider in ['email', 'google', 'kakao']) {
    test(
      '$provider session survives restart without password or SDK',
      () async {
        final token = session(const Duration(days: 30));
        var requests = 0;
        await http.runWithClient(
          () async {
            final first = AuthController();
            if (provider == 'email') {
              await first.login('test@example.invalid', 'password');
            } else {
              await first.loginSocial(
                SocialCredential(
                  provider == 'google'
                      ? SocialProvider.google
                      : SocialProvider.kakao,
                  'provider-proof',
                ),
              );
            }
            first.dispose();
            final restarted = AuthController();
            await restarted.restore();
            expect(restarted.token, token);
            expect(restarted.user?.id, 'user-1');
            expect(requests, 2);
            restarted.dispose();
          },
          () => MockClient((request) async {
            requests++;
            if (request.url.path.endsWith('/me')) {
              expect(request.headers['Authorization'], 'Bearer $token');
              return profile();
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'accessToken': token,
                  'user': {'id': 'user-1', 'nickname': 'Test'},
                },
              }),
              200,
            );
          }),
        );
      },
    );
  }

  test(
    'expired session is removed before making any network request',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': session(const Duration(seconds: -1)),
      });
      await http.runWithClient(() async {
        final controller = AuthController();
        await controller.restore();
        expect(controller.token, isNull);
        expect(controller.user, isNull);
        expect(
          (await SharedPreferences.getInstance()).getString('auth_token'),
          isNull,
        );
        controller.dispose();
      }, () => MockClient((_) async => throw StateError('Unexpected request')));
    },
  );

  for (final status in [401, 403, 404]) {
    test(
      'server rejection $status removes session, even without JSON',
      () async {
        SharedPreferences.setMockInitialValues({
          'auth_token': session(const Duration(days: 1)),
        });
        await http.runWithClient(() async {
          final controller = AuthController();
          await controller.restore();
          expect(controller.token, isNull);
          expect(controller.restoreFailed, isFalse);
          expect(
            (await SharedPreferences.getInstance()).getString('auth_token'),
            isNull,
          );
          controller.dispose();
        }, () => MockClient((_) async => http.Response('Rejected', status)));
      },
    );
  }

  for (final failure in ['offline', 'server', 'timeout']) {
    test('$failure retains credential and retry restores session', () async {
      final token = session(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({'auth_token': token});
      var calls = 0;
      await http.runWithClient(
        () async {
          final controller = AuthController();
          await controller.restore();
          expect(controller.restoreFailed, isTrue);
          expect(controller.user, isNull);
          expect(
            (await SharedPreferences.getInstance()).getString('auth_token'),
            token,
          );
          await controller.restore();
          expect(controller.restoreFailed, isFalse);
          expect(controller.user?.id, 'user-1');
          controller.dispose();
        },
        () => MockClient((_) async {
          if (calls++ > 0) return profile();
          if (failure == 'offline') throw http.ClientException('Offline');
          if (failure == 'timeout') throw TimeoutException('Timed out');
          return http.Response('Unavailable', 503);
        }),
      );
    });
  }

  test(
    'foreground recheck preserves current page and form during network failures',
    () async {
      final token = session(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({'auth_token': token});
      var calls = 0;
      await http.runWithClient(
        () async {
          final controller = AuthController();
          await controller.restore();
          final checking = controller.restore(background: true);
          expect(controller.loading, isFalse);
          expect(controller.user?.id, 'user-1');
          await checking;
          expect(controller.user?.id, 'user-1');
          expect(controller.restoreFailed, isFalse);
          expect(controller.token, token);
          controller.dispose();
        },
        () => MockClient((_) async {
          if (calls++ == 0) return profile();
          throw http.ClientException('Offline');
        }),
      );
    },
  );

  test(
    'logout wins over an in-flight restore and stays logged out after restart',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': session(const Duration(days: 1)),
      });
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      await http.runWithClient(
        () async {
          final controller = AuthController();
          final restoring = controller.restore();
          await started.future;
          await controller.logout();
          pending.complete(profile());
          await restoring;
          expect(controller.user, isNull);
          expect(controller.token, isNull);
          controller.dispose();
          final restarted = AuthController();
          await restarted.restore();
          expect(restarted.user, isNull);
          expect(restarted.token, isNull);
          restarted.dispose();
        },
        () => MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
    },
  );
}
