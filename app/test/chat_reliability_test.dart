import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/social_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('message cursor page is stable and chronological in the app', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['cursor'], 'cursor-1');
      return http.Response(
        jsonEncode({
          'data': {
            'items': [
              {
                'id': 'newer',
                'body': 'newer',
                'message_type': 'text',
                'media_url': '/uploads/messages/original.jpg',
                'media_thumbnail_url': '/uploads/messages/thumbnail.webp',
                'created_at': '2026-10-01T10:00:01Z',
              },
              {
                'id': 'older',
                'body': 'older',
                'message_type': 'text',
                'created_at': '2026-10-01T10:00:00Z',
              },
            ],
            'nextCursor': 'cursor-2',
            'hasMore': true,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      final page = await SocialService.messages(
        'token',
        'conversation',
        cursor: 'cursor-1',
      );
      expect(page.items.map((item) => item.id), ['older', 'newer']);
      expect(
        page.items.last.mediaUrl,
        endsWith('/uploads/messages/original.jpg'),
      );
      expect(
        page.items.last.mediaThumbnailUrl,
        endsWith('/uploads/messages/thumbnail.webp'),
      );
      expect(page.nextCursor, 'cursor-2');
      expect(page.hasMore, isTrue);
    }, () => client);
  });

  test('client message id and reply target are sent for idempotency', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['clientMessageId'], '12345678-1234-4234-8234-123456789abc');
      expect(body['replyToMessageId'], 'reply-1');
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'server-id',
            'body': 'hello',
            'message_type': 'text',
            'client_message_id': body['clientMessageId'],
            'reply_to_message_id': body['replyToMessageId'],
            'created_at': '2026-10-01T10:00:00Z',
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      final message = await SocialService.sendMessage(
        'token',
        'conversation',
        'hello',
        '12345678-1234-4234-8234-123456789abc',
        replyToMessageId: 'reply-1',
      );
      expect(message.id, 'server-id');
      expect(message.clientMessageId, '12345678-1234-4234-8234-123456789abc');
    }, () => client);
  });

  test('pending messages survive locally until acknowledged', () async {
    final message = ChatMessage(
      id: 'pending-1',
      senderUserId: 'me',
      body: 'offline message',
      createdAt: DateTime.utc(2026, 10, 1),
      clientMessageId: 'pending-1',
      pending: true,
    );
    await SocialService.savePending('me', 'conversation', message);
    final pending = await SocialService.pendingMessages('me', 'conversation');
    expect(pending.single.body, 'offline message');
    expect(pending.single.failed, isTrue);
    await SocialService.removePending('me', 'conversation', 'pending-1');
    expect(await SocialService.pendingMessages('me', 'conversation'), isEmpty);
  });
}
