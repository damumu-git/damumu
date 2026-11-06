import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/login_preferences.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/social_login.dart';

http.Response loginResponse() => http.Response(
  jsonEncode({
    'data': {
      'accessToken': 'local-session',
      'user': {'id': 'u1', 'nickname': 'Test', 'email': 'test@example.invalid'},
    },
  }),
  200,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'unchecked auto login keeps only in-memory session, survives foreground and not restart',
    () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          final auth = AuthController();
          await auth.login(
            'test@example.invalid',
            'Password1',
            autoLogin: false,
          );
          expect(auth.user?.id, 'u1');
          expect(auth.token, 'local-session');
          expect(
            (await SharedPreferences.getInstance()).getString('auth_token'),
            isNull,
          );
          await auth.restore(background: true);
          expect(auth.user?.id, 'u1');
          expect(auth.token, 'local-session');
          final restarted = AuthController();
          await restarted.restore();
          expect(restarted.user, isNull);
          expect(calls, 2);
          auth.dispose();
          restarted.dispose();
        },
        () => MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/me')) {
            return http.Response(
              jsonEncode({
                'data': {'id': 'u1', 'nickname': 'Test'},
              }),
              200,
            );
          }
          return loginResponse();
        }),
      );
    },
  );

  test(
    'remember ID is independent of automatic login and never stores password',
    () async {
      await http.runWithClient(() async {
        final auth = AuthController();
        await auth.login(
          ' test@example.invalid ',
          'Password1',
          autoLogin: false,
          rememberId: true,
        );
        final options = await LoginPreferences.load();
        expect(options.autoLogin, isFalse);
        expect(options.rememberId, isTrue);
        expect(options.email, 'test@example.invalid');
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys(),
          unorderedEquals([
            LoginPreferences.autoKey,
            LoginPreferences.rememberKey,
            LoginPreferences.emailKey,
          ]),
        );
        await auth.logout();
        expect((await LoginPreferences.load()).email, 'test@example.invalid');
        await LoginPreferences.saveId('', false);
        expect(prefs.getString(LoginPreferences.emailKey), isNull);
        auth.dispose();
      }, () => MockClient((_) async => loginResponse()));
    },
  );

  test(
    'social sign-in obeys automatic-login choice without storing provider proof',
    () async {
      await http.runWithClient(() async {
        final auth = AuthController();
        await auth.loginSocial(
          const SocialCredential(SocialProvider.google, 'provider-proof'),
          autoLogin: false,
        );
        expect(auth.user?.id, 'u1');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_token'), isNull);
        expect(prefs.getKeys(), [LoginPreferences.autoKey]);
        auth.dispose();
      }, () => MockClient((_) async => loginResponse()));
    },
  );

  test('account deletion clears remembered personal email', () async {
    await http.runWithClient(
      () async {
        final auth = AuthController();
        await auth.login('test@example.invalid', 'Password1', rememberId: true);
        await auth.deleteAccount();
        expect((await LoginPreferences.load()).email, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString(
            LoginPreferences.emailKey,
          ),
          isNull,
        );
        auth.dispose();
      },
      () => MockClient(
        (request) async => request.method == 'DELETE'
            ? http.Response('{}', 200)
            : loginResponse(),
      ),
    );
  });

  testWidgets(
    'login options restore ID and unchecking removes remembered ID immediately',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LoginPreferences.autoKey: false,
        LoginPreferences.rememberKey: true,
        LoginPreferences.emailKey: 'saved@example.invalid',
      });
      await tester.pumpWidget(
        DaziApp(home: AuthPage(avatarLoader: (_) async => [])),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved@example.invalid'), findsOneWidget);
      final auto = find.descendant(
        of: find.byKey(const Key('auto-login-option')),
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(auto).value, isFalse);
      await tester.ensureVisible(find.byKey(const Key('remember-id-option')));
      await tester.tap(find.byKey(const Key('remember-id-option')));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString(
          LoginPreferences.emailKey,
        ),
        isNull,
      );
    },
  );

  testWidgets('checkbox choices reach email login and only remember ID', (
    tester,
  ) async {
    final auth = AuthController();
    final pendingLogin = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          home: AuthScope(
            controller: auth,
            child: AuthPage(avatarLoader: (_) async => []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.invalid',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Password1');
      for (final key in ['auto-login-option', 'remember-id-option']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
      await tester.showKeyboard(find.byType(TextFormField).at(1));
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(auth.user, isNull);
      pendingLogin.complete(loginResponse());
      await tester.pumpAndSettle();
      expect(auth.user?.id, 'u1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(
        prefs.getString(LoginPreferences.emailKey),
        'test@example.invalid',
      );
    }, () => MockClient((_) => pendingLogin.future));
    auth.dispose();
  });

  for (final language in ['zh', 'en', 'ko']) {
    testWidgets(
      'login checkbox layout supports narrow screens and large $language text',
      (tester) async {
        SharedPreferences.setMockInitialValues({'app_locale': language});
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          DaziApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.5),
              ),
              child: AuthPage(avatarLoader: (_) async => []),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('remember-id-option')));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
