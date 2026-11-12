import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/direct_contact.dart';
import 'package:zaihandazi/social_service.dart';

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'data': data}), 200);

void main() {
  testWidgets('profile sends an attendance request and opens mutual chat', (
    tester,
  ) async {
    var following = false;
    Map<String, dynamic>? sent;
    String? opened;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/options')) {
        return _ok({
          'following': following,
          'can_chat': following,
          'request_event_id': sent == null ? 'shared-event' : null,
        });
      }
      if (path.endsWith('/follows/peer')) {
        following = true;
        return _ok({'following': true});
      }
      if (path.endsWith('/conversations/direct')) return _ok({'id': 'thread'});
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _ok({'id': 'contact'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectContactActions(
              token: 'fixture',
              userId: 'peer',
              nickname: 'Peer',
              onOpen: (id, _) => opened = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request a chat'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'See you next time');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent, {
        'kind': 'attended',
        'eventId': 'shared-event',
        'userId': 'peer',
        'body': 'See you next time',
      });
      expect(find.text('Request a chat'), findsNothing);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();
      expect(opened, 'thread');
    }, () => client);
  });

  test(
    'group rows use activity categories and message avatars are retained',
    () {
      final event = ConversationItem.fromJson({
        'id': 'event',
        'conversation_type': 'event',
        'event_avatar': '/uploads/host.jpg',
        'event_starts_at': '2030-03-01T09:00:00Z',
        'event_major_category': '运动',
        'event_minor_category': '足球',
        'event_major_category_en': 'Sports',
      });
      final direct = ConversationItem.fromJson({
        'id': 'direct',
        'conversation_type': 'direct',
        'peer_avatar': '/uploads/peer.jpg',
      });
      final message = ChatMessage.fromJson({
        'id': 'message',
        'sender_user_id': 'sender',
        'sender_avatar': '/uploads/sender.jpg',
        'created_at': '2030-03-01T09:00:00Z',
      });
      expect(event.avatarUrl, isNull);
      expect(event.eventStartsAt?.isUtc, isTrue);
      expect(event.eventCategories['zh'], ['运动', '足球']);
      expect(event.eventCategories['en'], ['Sports', '足球']);
      expect(
        ChatMessage.fromJson(message.toJson()).senderAvatar,
        '/uploads/sender.jpg',
      );
      expect(direct.avatarUrl, '/uploads/peer.jpg');
    },
  );
}
