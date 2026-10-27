import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/app_theme.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('light primary buttons retain readable foreground contrast', () {
    final a = AppPalette.primary.computeLuminance();
    final b = AppPalette.onPrimary.computeLuminance();
    expect((a + .05) / (b + .05), greaterThanOrEqualTo(4.5));
  });

  testWidgets('real pages keep navigation and fit a narrow viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthController()
      ..user = const AuthUser(
        id: 'preview-test',
        nickname: 'A long nickname for layout',
        email: 'preview@example.invalid',
        avatarUrl: '',
      );
    final event = EventItem(
      id: 120,
      emoji: '🌿',
      title: 'A long activity title with a real navigation callback',
      category: 'Outdoor walking',
      time: 'Saturday 16:30 — 18:30',
      area: 'Seoul · Yeongdeungpo-gu',
      distance: '2.1 km',
      host: 'A long organizer nickname',
      hostScore: 4.8,
      joined: 4,
      capacity: 6,
      beginnerFriendly: true,
    );
    await tester.pumpWidget(
      DaziApp(
        home: AuthScope(
          controller: auth,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 844),
              textScaler: TextScaler.linear(1.3),
            ),
            child: AppShell(initialEvents: [event], loadRemoteEvents: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final index in [1, 2, 3, 4, 0]) {
      await tester.tap(find.byKey(Key('main-nav-$index')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Navigation $index overflowed',
      );
    }
    await tester.scrollUntilVisible(
      find.text(event.title),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(event.title));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('render production pages for optional visual review', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('WRITE_UI_CAPTURE')) return;
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final family in ['Noto Sans SC', 'Noto Sans KR', 'Noto Emoji']) {
        final file = {
          'Noto Sans SC': 'NotoSansSC-VF.ttf',
          'Noto Sans KR': 'NotoSansKR-VF.ttf',
          'Noto Emoji': 'NotoEmoji-VF.ttf',
        }[family]!;
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$file'))).load();
      }
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthController()
      ..user = const AuthUser(
        id: 'capture-user',
        nickname: '小慕',
        email: 'preview@example.invalid',
        avatarUrl: '',
      );
    const boundary = Key('ui-capture');
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../.dev-data/ui-captures/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: DaziApp(
          home: AuthScope(
            controller: auth,
            child: AppShell(initialEvents: demoEvents, loadRemoteEvents: false),
          ),
        ),
      ),
    );
    await capture('app-home');
    await tester.tap(find.byKey(const Key('main-nav-2')));
    await capture('app-create');
    await tester.tap(find.byKey(const Key('main-nav-4')));
    await capture('app-profile');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: DaziApp(
          key: UniqueKey(),
          home: AuthPage(avatarLoader: (_) async => const []),
        ),
      ),
    );
    await capture('app-login');
  });
}
