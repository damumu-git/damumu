import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets(
    'copies organizer content from UUID detail but requires new dates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthController()
        ..token = 'test-token'
        ..user = const AuthUser(
          id: 'owner',
          nickname: 'Host',
          email: 'test@example.com',
          avatarUrl: 'system:sprout',
        );
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        Object data;
        switch (request.url.path) {
          case '/api/v1/categories':
            data = [
              {
                'id': 'major',
                'code': 'major',
                'level': 1,
                'name_zh_cn': 'Major',
              },
              {
                'id': 'leaf',
                'code': 'leaf',
                'level': 2,
                'parent_id': 'major',
                'name_zh_cn': 'Leaf',
              },
              {
                'id': 'other-major',
                'code': 'other-major',
                'level': 1,
                'name_zh_cn': 'Other major',
              },
              {
                'id': 'other-leaf',
                'code': 'other-leaf',
                'level': 2,
                'parent_id': 'other-major',
                'name_zh_cn': 'Other leaf',
              },
            ];
          case '/api/v1/regions':
            data = [
              {'code': 'city', 'level': 1, 'name_zh_cn': 'City'},
              {
                'code': 'district',
                'level': 2,
                'parent_code': 'city',
                'name_zh_cn': 'District',
              },
            ];
          case '/api/v1/events/12345678-1234-1234-1234-123456789abc':
            expect(request.headers['Authorization'], 'Bearer test-token');
            data = {
              'item': {
                'organizer_user_id': 'owner',
                'title': 'Previous title',
                'description': 'Previous description',
                'category_id': 'leaf',
                'city_code': 'city',
                'district_code': 'district',
                'place_name': 'Private meeting point',
                'price_amount': 15000,
                'capacity': 12,
                'approval_mode': 'automatic',
                'starts_at': '2020-01-01T10:00:00Z',
                'ends_at': '2020-01-01T12:00:00Z',
              },
            };
          default:
            throw StateError('Unexpected request ${request.url}');
        }
        return http.Response(jsonEncode({'data': data}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          DaziApp(
            home: AuthScope(
              controller: auth,
              child: Scaffold(
                body: CreateEventPage(
                  sourceEventId: '12345678-1234-1234-1234-123456789abc',
                  onCreated: (_) => fail('Must not publish without new dates'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Previous title'), findsOneWidget);
        expect(find.text('Previous description'), findsOneWidget);
        expect(find.textContaining('Leaf'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('major-category-major')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('major-category-other-major')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('major-category-other-major')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Other leaf'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('major-category-major')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Leaf'), findsOneWidget);
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('major-category-other-major')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        expect(find.text('Private meeting point'), findsOneWidget);
        expect(find.text('请选择开始日期和时间'), findsOneWidget);
        expect(find.text('请选择结束日期和时间'), findsOneWidget);
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        expect(find.text('请选择活动的开始时间和结束时间'), findsOneWidget);
        expect(requests.where((p) => p == '/api/v1/events'), isEmpty);
      }, () => client);
    },
  );
}
