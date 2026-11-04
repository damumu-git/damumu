import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/app_permissions.dart';
import 'package:zaihandazi/location_service.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/onboarding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPermissions.channel, null);
  });
  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
  }

  Future<void> decline(WidgetTester tester) async {
    await tester.ensureVisible(find.text('暂不授权'));
    await tester.tap(find.text('暂不授权'));
    await tester.pumpAndSettle();
    await next(tester);
  }

  testWidgets('first run shows introduction before starting authentication', (
    tester,
  ) async {
    var ready = 0;
    await tester.pumpWidget(
      DaziApp(
        home: FirstRunGate(
          onReady: () async {
            ready++;
          },
          builder: (_) => const Text('LOGIN'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('一起，把日常变有趣'), findsOneWidget);
    expect(ready, 0);
    expect(find.text('LOGIN'), findsNothing);
  });

  testWidgets(
    'swipe left, explicitly decline every permission, then continue to login once',
    (tester) async {
      var ready = 0;
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppPermissions.channel, (_) async {
            requests++;
            return 'granted';
          });
      await tester.pumpWidget(
        DaziApp(
          home: FirstRunGate(
            onReady: () async {
              ready++;
            },
            builder: (_) => const Text('LOGIN'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('用照片记录相遇'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一页'))
            .onPressed,
        isNull,
      );
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 6'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await decline(tester);
      }
      await tester.tap(find.text('开始使用 · 前往登录'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
      expect(ready, 1);
      expect(requests, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(onboardingCompletedKey), isTrue);
      for (final permission in AppPermission.values) {
        expect(prefs.getBool(AppPermissions.key(permission)), isFalse);
      }
      // Recreating the gate does not replay the introduction.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        DaziApp(
          home: FirstRunGate(
            onReady: () async {
              ready++;
            },
            builder: (_) => const Text('LOGIN'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
      expect(ready, 2);
    },
  );

  testWidgets(
    'only agreeing requests native camera, system denial does not block progress',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppPermissions.channel, (call) async {
            calls.add(call.arguments as String);
            return 'denied';
          });
      await tester.pumpWidget(
        DaziApp(home: OnboardingPage(onFinished: () async {})),
      );
      await tester.pumpAndSettle();
      await next(tester);
      expect(calls, isEmpty);
      await tester.ensureVisible(find.text('同意并继续设置'));
      await tester.tap(find.text('同意并继续设置'));
      await tester.pumpAndSettle();
      expect(calls, ['camera']);
      expect(find.text('系统未允许权限，你仍可继续。'), findsOneWidget);
      expect(await AppPermissions.choice(AppPermission.camera), isFalse);
      await next(tester);
      expect(find.text('只分享你选中的照片'), findsOneWidget);
      await tester.ensureVisible(find.text('同意并继续设置'));
      await tester.tap(find.text('同意并继续设置'));
      await tester.pumpAndSettle();
      expect(calls, ['camera']);
      expect(await AppPermissions.choice(AppPermission.photos), isTrue);
    },
  );

  testWidgets(
    'permanent denial provides a settings action and still allows continuing',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AppPermissions.channel,
            (_) async => 'settings',
          );
      await tester.pumpWidget(
        DaziApp(home: OnboardingPage(onFinished: () async {})),
      );
      await tester.pumpAndSettle();
      await next(tester);
      await tester.ensureVisible(find.text('同意并继续设置'));
      await tester.tap(find.text('同意并继续设置'));
      await tester.pumpAndSettle();
      expect(find.text('打开系统设置'), findsOneWidget);
      await next(tester);
      expect(find.text('只分享你选中的照片'), findsOneWidget);
    },
  );

  testWidgets(
    'existing signed-in installation skips introduction and persists completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'existing-session',
      });
      var ready = false;
      await tester.pumpWidget(
        DaziApp(
          home: FirstRunGate(
            onReady: () async {
              ready = true;
            },
            builder: (_) => const Text('LOGIN'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ready, isTrue);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(onboardingCompletedKey),
        isTrue,
      );
    },
  );

  test(
    'declined location never queries GPS or requests OS permission',
    () async {
      await AppPermissions.decline(AppPermission.location);
      await expectLater(
        LocationService().locate(languageCode: 'en'),
        throwsA(
          isA<LocationFailure>().having(
            (e) => e.message,
            'message',
            contains('manually'),
          ),
        ),
      );
    },
  );

  test(
    'notification native authorization is separate from external Firebase consent',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AppPermissions.channel,
            (_) async => 'granted',
          );
      expect(
        await AppPermissions.request(AppPermission.notifications),
        PermissionOutcome.granted,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('external_push_20261021'), isNull);
      expect(await AppPermissions.choice(AppPermission.notifications), isTrue);
    },
  );

  testWidgets('declining a feature reconsideration never opens system prompt', (
    tester,
  ) async {
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPermissions.channel, (_) async {
          requests++;
          return 'granted';
        });
    await AppPermissions.decline(AppPermission.camera);
    bool? allowed;
    await tester.pumpWidget(
      DaziApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                allowed = await AppPermissions.ensure(
                  context,
                  AppPermission.camera,
                );
              },
              child: const Text('CAMERA'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CAMERA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不授权'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(requests, 0);
  });

  for (final language in ['zh', 'en', 'ko']) {
    testWidgets('intro fits 320px and large text in $language', (tester) async {
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
            child: OnboardingPage(onFinished: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
