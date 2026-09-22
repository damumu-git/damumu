import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/social_service.dart';

void main() {
  testWidgets('chat route keeps access to the authenticated session', (
    tester,
  ) async {
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
      await tester.pumpAndSettle();

      expect(find.text('还没有消息，打个招呼吧'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }, () => client);
  });
}
