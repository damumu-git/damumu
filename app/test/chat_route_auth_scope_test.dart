import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/social_service.dart';

void main() {
  testWidgets('only messages over five lines can expand and collapse', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthController()
      ..token = 'test-token'
      ..user = const AuthUser(
        id: 'viewer',
        nickname: 'Viewer',
        email: 'viewer@example.com',
      );
    const five = 'First\nSecond\nThird\nFourth\nFifth';
    const six = '$five\nSixth';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/read')) {
        return http.Response('{"data":{}}', 200);
      }
      return http.Response(
        jsonEncode({
          'data': {
            'items': [
              for (final (id, body) in [('short', five), ('long', six)])
                {
                  'id': id,
                  'body': body,
                  'sender_user_id': 'viewer',
                  'created_at': '2026-11-13T10:00:00Z',
                },
            ],
            'hasMore': false,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            controller: auth,
            child: const ChatPage(
              conversation: ConversationItem(
                id: 'conversation-1',
                type: 'direct',
                title: 'Chat',
                unreadCount: 0,
                memberCount: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(six)).maxLines, 5);
      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(six)).maxLines, isNull);
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(six)).maxLines, 5);
    }, () => client);
  });

  testWidgets('chat route keeps access to the authenticated session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthController()
      ..token = 'test-token'
      ..user = const AuthUser(
        id: 'user-1',
        nickname: '测试用户',
        email: 'user@example.com',
      );
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.path, '/api/v1/conversations/conversation-1/messages');
      return http.Response(jsonEncode({'data': <Object>[]}), 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          authController: auth,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChatPage(
                      conversation: ConversationItem(
                        id: 'conversation-1',
                        type: 'event',
                        title: '测试活动',
                        unreadCount: 0,
                        memberCount: 1,
                      ),
                    ),
                  ),
                ),
                child: const Text('打开群聊'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开群聊'));
      // The authenticated app owns long-lived realtime retry timers, so this
      // route test advances the fetch explicitly instead of waiting for every
      // timer in the app to settle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('还没有消息，打个招呼吧'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('拍摄照片'), findsOneWidget);
      expect(find.text('从相册选择'), findsOneWidget);
      await tester.tap(find.text('从相册选择'));
      await tester.pump();
    }, () => client);
  });
}
