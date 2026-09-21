import 'dart:convert';

import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class SocialServiceException implements Exception {
  const SocialServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ConversationItem {
  const ConversationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.unreadCount,
    required this.memberCount,
    this.lastMessageId,
    this.lastMessageBody,
    this.lastMessageSender,
    this.lastMessageAt,
  });

  final String id;
  final String type;
  final String title;
  final int unreadCount;
  final int memberCount;
  final String? lastMessageId;
  final String? lastMessageBody;
  final String? lastMessageSender;
  final DateTime? lastMessageAt;

  factory ConversationItem.fromJson(Map<String, dynamic> json) =>
      ConversationItem(
        id: '${json['id']}',
        type: '${json['conversation_type']}',
        title: '${json['display_title'] ?? json['event_title'] ?? '会话'}',
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        lastMessageId: json['last_message_id']?.toString(),
        lastMessageBody: json['last_message_body'] as String?,
        lastMessageSender: json['last_message_sender'] as String?,
        lastMessageAt: DateTime.tryParse(
          '${json['last_message_at'] ?? ''}',
        )?.toLocal(),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
    this.senderName,
  });
  final String id;
  final String? senderUserId;
  final String body;
  final String? senderName;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: '${json['id']}',
    senderUserId: json['sender_user_id']?.toString(),
    body: '${json['body'] ?? ''}',
    senderName: json['sender_name'] as String?,
    createdAt: DateTime.parse('${json['created_at']}').toLocal(),
  );
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: '${json['id']}',
        type: '${json['notification_type']}',
        title: '${json['title']}',
        body: '${json['body']}',
        createdAt: DateTime.parse('${json['created_at']}').toLocal(),
        read: json['read_at'] != null,
      );
}

class UnreadSummary {
  const UnreadSummary(this.notifications, this.messages);
  final int notifications;
  final int messages;
  int get total => notifications + messages;
}

class SocialService {
  static Future<dynamic> _request(
    String token,
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_apiBase$path'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 10)),
    );
    if (response.statusCode == 204) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const SocialServiceException('消息服务暂时不可用，请稍后再试');
    }
    if (decoded is! Map) {
      throw const SocialServiceException('消息服务暂时不可用，请稍后再试');
    }
    final envelope = decoded.cast<String, dynamic>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = envelope['error'];
      throw SocialServiceException(
        error is Map && error['message'] is String
            ? error['message'] as String
            : '操作没有成功，请稍后再试',
      );
    }
    return envelope['data'];
  }

  static Future<List<ConversationItem>> conversations(String token) async {
    final data = await _request(token, '/conversations') as List;
    return data
        .map(
          (item) =>
              ConversationItem.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  static Future<List<NotificationItem>> notifications(String token) async {
    final data = await _request(token, '/me/notifications?limit=100') as List;
    return data
        .map(
          (item) =>
              NotificationItem.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  static Future<UnreadSummary> unreadSummary(String token) async {
    final data = (await _request(token, '/unread-summary') as Map)
        .cast<String, dynamic>();
    return UnreadSummary(
      (data['notification_count'] as num?)?.toInt() ?? 0,
      (data['message_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<ChatMessage>> messages(
    String token,
    String conversationId,
  ) async {
    final data =
        await _request(token, '/conversations/$conversationId/messages')
            as List;
    return data
        .map(
          (item) => ChatMessage.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList()
        .reversed
        .toList();
  }

  static Future<ChatMessage> sendMessage(
    String token,
    String conversationId,
    String body,
  ) async {
    final data =
        (await _request(
                  token,
                  '/conversations/$conversationId/messages',
                  method: 'POST',
                  body: {'messageType': 'text', 'body': body},
                )
                as Map)
            .cast<String, dynamic>();
    return ChatMessage.fromJson(data);
  }

  static Future<void> readConversation(
    String token,
    String conversationId,
    String messageId,
  ) => _request(
    token,
    '/conversations/$conversationId/read',
    method: 'POST',
    body: {'messageId': messageId},
  );

  static Future<void> readNotification(String token, String id) =>
      _request(token, '/me/notifications/$id/read', method: 'POST');

  static Future<void> deleteNotification(String token, String id) =>
      _request(token, '/me/notifications/$id', method: 'DELETE');

  static Future<void> readConversationLatest(
    String token,
    String conversationId,
  ) => _request(
    token,
    '/conversations/$conversationId/read-latest',
    method: 'POST',
  );

  static Future<void> removeConversation(String token, String conversationId) =>
      _request(token, '/conversations/$conversationId', method: 'DELETE');

  static Future<void> readAll(String token) async {
    await Future.wait([
      _request(token, '/conversations/read-all', method: 'POST'),
      _request(token, '/me/notifications/read-all', method: 'POST'),
    ]);
  }

  static Future<void> registerPushDevice(
    String token,
    String registrationToken,
    String platform,
  ) => _request(
    token,
    '/me/push-devices',
    method: 'POST',
    body: {'registrationToken': registrationToken, 'platform': platform},
  );

  static Future<void> unregisterPushDevice(
    String token,
    String registrationToken,
    String platform,
  ) => _request(
    token,
    '/me/push-devices/unregister',
    method: 'POST',
    body: {'registrationToken': registrationToken, 'platform': platform},
  );
}
