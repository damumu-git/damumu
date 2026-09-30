import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/activity_interactions.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/social_service.dart';

http.Response jsonResponse(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('profile avatar opens a zoomable preview and closes', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => jsonResponse(
        jsonEncode({
          'data': {'nickname': 'Alice', 'avatar_url': null},
        }),
        200,
      ),
    );
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const DaziApp(home: PublicUserProfilePage(userId: 'member')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看大图'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭预览'));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarPreviewPage), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
    }, () => client);
  });

  testWidgets(
    'organizer cancellation validates, retries and refreshes status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempts = 0;
      var cancelled = false;
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path.endsWith('/cancel')) {
          attempts++;
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'reason': '天气原因'});
          if (attempts == 1) return jsonResponse('{}', 500);
          cancelled = true;
          return jsonResponse('{"data":{"status":"cancelled"}}', 200);
        }
        if (request.url.path.endsWith('/activities')) {
          return jsonResponse(
            jsonEncode({
              'data': [
                {
                  'id': 'event-uuid',
                  'title': 'Test activity',
                  'member_role': 'organizer',
                  'event_status': cancelled ? 'cancelled' : 'published',
                  'membership_status': 'approved',
                  'city_code': 'Seoul',
                  'district_code': 'Central',
                  'cancellation_reason': cancelled ? '天气原因' : null,
                },
              ],
            }),
            200,
          );
        }
        return jsonResponse('{"data":[]}', 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const DaziApp(home: MyActivitiesPage(token: 'test-token')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test activity'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消活动'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认取消活动'));
        await tester.pumpAndSettle();
        expect(attempts, 0);
        expect(find.text('请输入取消原因（最多 500 字）'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), '  天气原因  ');
        await tester.tap(find.text('确认取消活动'));
        await tester.pumpAndSettle();
        expect(find.text('取消未完成，请刷新活动状态后重试。'), findsOneWidget);
        expect(find.text('  天气原因  '), findsOneWidget);
        await tester.tap(find.text('确认取消活动'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(find.byType(CancelEventDialog), findsNothing);
        expect(find.text('取消原因：天气原因'), findsOneWidget);
        expect(find.text('取消活动'), findsNothing);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(find.text('活动取消 · Test activity'), findsOneWidget);
      }, () => client);
    },
  );

  testWidgets('participant has no cancel action', (tester) async {
    final client = MockClient(
      (_) async => jsonResponse(
        jsonEncode({
          'data': [
            {
              'id': 'event',
              'title': 'Joined activity',
              'member_role': 'member',
              'event_status': 'published',
              'membership_status': 'approved',
            },
          ],
        }),
        200,
      ),
    );
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const DaziApp(home: MyActivitiesPage(token: 'token')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我参加的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joined activity'));
      await tester.pumpAndSettle();
      expect(find.text('取消活动'), findsNothing);
    }, () => client);
  });

  testWidgets('group renders cancellation title and reason as a notice', (
    tester,
  ) async {
    final auth = AuthController()
      ..token = 'token'
      ..user = const AuthUser(
        id: 'member',
        nickname: 'Member',
        email: 'member@example.com',
      );
    final client = MockClient(
      (request) async => jsonResponse(
        jsonEncode({
          'data': request.method == 'GET'
              ? [
                  {
                    'id': 'notice',
                    'sender_user_id': null,
                    'message_type': 'event_cancelled',
                    'body': '天气原因',
                    'created_at': '2026-09-30T10:00:00Z',
                  },
                ]
              : {},
        }),
        200,
      ),
    );
    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          authController: auth,
          home: const ChatPage(
            conversation: ConversationItem(
              id: 'group',
              type: 'event',
              title: 'Activity',
              unreadCount: 1,
              memberCount: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EventCancellationNotice), findsOneWidget);
      expect(find.text('活动取消'), findsOneWidget);
      expect(find.text('取消原因：天气原因'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });
}
