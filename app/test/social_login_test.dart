import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/social_login.dart';
import 'package:zaihandazi/social_registration.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'unconfigured native login fails closed without invoking an SDK',
    () async {
      for (final provider in SocialProvider.values) {
        await expectLater(
          SocialLogin.authorize(provider),
          throwsA(isA<SocialLoginException>()),
        );
      }
    },
  );

  Future<void> page(
    WidgetTester tester,
    AuthController controller,
    Future<SocialCredential?> Function(SocialProvider) authorize,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DaziApp(
        home: AuthScope(
          controller: controller,
          child: AuthPage(
            avatarLoader: (_) async => [],
            socialAuthorize: authorize,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'provider cancellation does not call API or create local session',
    (tester) async {
      var requests = 0;
      final controller = AuthController();
      await http.runWithClient(
        () async {
          await page(tester, controller, (_) async => null);
          final button = find.text('使用 Google 账号登录');
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(requests, 0);
          expect(controller.token, isNull);
          expect(controller.user, isNull);
        },
        () => MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
    },
  );

  testWidgets(
    'first login requires unchecked consent and nickname, then sends provider proof',
    (tester) async {
      var requests = 0;
      final controller = AuthController();
      await http.runWithClient(
        () async {
          await page(
            tester,
            controller,
            (_) async =>
                const SocialCredential(SocialProvider.kakao, 'test-proof'),
          );
          final button = find.text('使用 Kakao 账号登录');
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(controller.token, isNull);
          final dialog = find.byType(SocialRegistrationDialog);
          expect(dialog, findsOneWidget);
          final submit = find.descendant(
            of: dialog,
            matching: find.byType(FilledButton),
          );
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          for (final box in tester.widgetList<CheckboxListTile>(
            find.descendant(
              of: dialog,
              matching: find.byType(CheckboxListTile),
            ),
          )) {
            expect(box.value, isFalse);
          }
          await tester.enterText(
            find.descendant(of: dialog, matching: find.byType(TextFormField)),
            '新用户',
          );
          for (final box
              in find
                  .descendant(
                    of: dialog,
                    matching: find.byType(CheckboxListTile),
                  )
                  .evaluate()
                  .toList()) {
            await tester.ensureVisible(find.byWidget(box.widget));
            await tester.tap(find.byWidget(box.widget));
            await tester.pumpAndSettle();
          }
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(requests, 2);
          expect(controller.user?.id, 'test-user');
          expect(controller.token, 'test-local-session');
          expect(
            (await SharedPreferences.getInstance()).getString('auth_token'),
            'test-local-session',
          );
        },
        () => MockClient((request) async {
          requests++;
          expect(request.url.path, endsWith('/auth/social/kakao'));
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          expect(data['token'], 'test-proof');
          expect(data.containsKey('userId'), isFalse);
          expect(data.containsKey('email'), isFalse);
          if (requests == 1) {
            expect(data.containsKey('ageConfirmed'), isFalse);
            return http.Response(
              jsonEncode({
                'data': {'registrationRequired': true},
              }),
              200,
            );
          }
          expect(data['nickname'], '新用户');
          expect(data['ageConfirmed'], isTrue);
          expect(data['privacyAcknowledged'], isTrue);
          expect(data['privacyVersion'], '2026-10-21');
          return http.Response(
            jsonEncode({
              'data': {
                'accessToken': 'test-local-session',
                'user': {'id': 'test-user', 'nickname': '新用户'},
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    },
  );

  testWidgets('dismissing onboarding does not register an account', (
    tester,
  ) async {
    var requests = 0;
    final controller = AuthController();
    await http.runWithClient(
      () async {
        await page(
          tester,
          controller,
          (_) async =>
              const SocialCredential(SocialProvider.google, 'test-proof'),
        );
        final button = find.text('使用 Google 账号登录');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(controller.token, isNull);
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{"data":{"registrationRequired":true}}', 200);
      }),
    );
  });
}
