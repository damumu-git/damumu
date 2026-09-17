import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets('shows six featured categories, more, and custom other input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthController()
      ..token = 'test-token'
      ..user = const AuthUser(
        id: 'owner',
        nickname: 'Host',
        email: 'test@example.com',
        avatarUrl: 'system:sprout',
      );
    final client = MockClient((request) async {
      Object data;
      if (request.url.path == '/api/v1/categories') {
        data = [
          for (var index = 1; index <= 7; index++) ...[
            {
              'id': 'major$index',
              'code': 'major$index',
              'level': 1,
              'name_zh_cn': '分类$index',
              'is_featured': index <= 6,
            },
            {
              'id': 'leaf$index',
              'code': 'leaf$index',
              'level': 2,
              'parent_id': 'major$index',
              'name_zh_cn': '子类$index',
            },
          ],
          {
            'id': 'other',
            'code': 'other',
            'level': 1,
            'name_zh_cn': '其它',
            'icon_key': 'other',
          },
          {
            'id': 'other-custom',
            'code': 'other_custom',
            'level': 2,
            'parent_id': 'other',
            'name_zh_cn': '自定义',
          },
        ];
      } else if (request.url.path == '/api/v1/regions') {
        data = <Object>[];
      } else {
        throw StateError('Unexpected request ${request.url}');
      }
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          home: AuthScope(
            controller: auth,
            child: Scaffold(body: CreateEventPage(onCreated: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('major-category-major6')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('major-category-major7')), findsNothing);
      expect(
        find.byKey(const ValueKey('major-category-other')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('显示更多分类'));
      await tester.tap(find.text('显示更多分类'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('major-category-major7')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('major-category-other')),
      );
      await tester.tap(find.byKey(const ValueKey('major-category-other')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('custom-subcategory')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-subcategory')),
        '桌游',
      );
      expect(find.text('桌游'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-subcategory')),
        '一二三四五六七八九十十一十二十三十四十五十六',
      );
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('custom-subcategory')),
      );
      expect(input.controller!.text.characters.length, 15);
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
