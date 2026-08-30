import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('注册页面快照', (tester) async {
    await tester.runAsync(() async {
      final chineseBytes = await File(
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      ).readAsBytes();
      final iconBytes = await File(
        '/Users/dahai/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
      ).readAsBytes();
      final chineseFont = FontLoader('PingFang SC')
        ..addFont(Future.value(ByteData.sublistView(chineseBytes)));
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconBytes)));
      await Future.wait([chineseFont.load(), iconFont.load()]);
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      DaziApp(home: AuthPage(avatarLoader: (_) async => const [])),
    );
    await tester.tap(find.text('还没有账号？立即注册'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AuthPage),
      matchesGoldenFile('goldens/register_page.png'),
    );
  });
}
