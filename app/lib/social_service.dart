import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.status = 'active',
    this.lastMessageId,
    this.lastMessageBody,
    this.lastMessageSender,
    this.lastMessageAt,
    this.lastMessageType,
  });

  final String id;
  final String type;
  final String title;
  final int unreadCount;
  final int memberCount;
  final String status;
  final String? lastMessageId;
  final String? lastMessageBody;
  final String? lastMessageSender;
  final DateTime? lastMessageAt;
  final String? lastMessageType;

  factory ConversationItem.fromJson(Map<String, dynamic> json) =>
      ConversationItem(
        id: '${json['id']}',
        type: '${json['conversation_type']}',
        title: '${json['display_title'] ?? json['event_title'] ?? '会话'}',
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        status: '${json['status'] ?? 'active'}',
        lastMessageId: json['last_message_id']?.toString(),
        lastMessageBody: json['last_message_body'] as String?,
        lastMessageType: json['last_message_type'] as String?,
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
    this.messageType = 'text',
    this.replyToMessageId,
    this.replyToBody,
    this.clientMessageId,
    this.editedAt,
    this.recalledAt,
    this.mediaAssetId,
    this.mediaUrl,
    this.pending = false,
    this.failed = false,
  });
  final String id;
  final String? senderUserId;
  final String body;
  final String? senderName;
  final String messageType;
  final DateTime createdAt;
  final String? replyToMessageId;
  final String? replyToBody;
  final String? clientMessageId;
  final DateTime? editedAt;
  final DateTime? recalledAt;
  final String? mediaAssetId;
  final String? mediaUrl;
  final bool pending;
  final bool failed;

  ChatMessage copyWith({bool? pending, bool? failed}) => ChatMessage(
    id: id,
    senderUserId: senderUserId,
    body: body,
    createdAt: createdAt,
    senderName: senderName,
    messageType: messageType,
    replyToMessageId: replyToMessageId,
    replyToBody: replyToBody,
    clientMessageId: clientMessageId,
    editedAt: editedAt,
    recalledAt: recalledAt,
    mediaAssetId: mediaAssetId,
    mediaUrl: mediaUrl,
    pending: pending ?? this.pending,
    failed: failed ?? this.failed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_user_id': senderUserId,
    'body': body,
    'sender_name': senderName,
    'message_type': messageType,
    'created_at': createdAt.toUtc().toIso8601String(),
    'reply_to_message_id': replyToMessageId,
    'reply_to_body': replyToBody,
    'client_message_id': clientMessageId,
    'edited_at': editedAt?.toUtc().toIso8601String(),
    'recalled_at': recalledAt?.toUtc().toIso8601String(),
    'media_asset_id': mediaAssetId,
    'media_url': mediaUrl,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: '${json['id']}',
    senderUserId: json['sender_user_id']?.toString(),
    body: '${json['body'] ?? ''}',
    senderName: json['sender_name'] as String?,
    messageType: '${json['message_type'] ?? 'text'}',
    createdAt: DateTime.parse('${json['created_at']}').toLocal(),
    replyToMessageId: json['reply_to_message_id']?.toString(),
    replyToBody: json['reply_to_body'] as String?,
    clientMessageId: json['client_message_id']?.toString(),
    editedAt: DateTime.tryParse('${json['edited_at'] ?? ''}')?.toLocal(),
    recalledAt: DateTime.tryParse('${json['recalled_at'] ?? ''}')?.toLocal(),
    mediaAssetId: json['media_asset_id']?.toString(),
    mediaUrl: _absoluteMediaUrl(json['media_url']?.toString()),
  );
}

String? _absoluteMediaUrl(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.parse(value);
  if (uri.hasScheme) return value;
  final api = Uri.parse(_apiBase);
  return api.replace(path: value, query: null, fragment: null).toString();
}

class ChatMessagePage {
  const ChatMessagePage({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });
  final List<ChatMessage> items;
  final String? nextCursor;
  final bool hasMore;
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

  static Future<ChatMessagePage> messages(
    String token,
    String conversationId, {
    String? cursor,
  }) async {
    final query = cursor == null
        ? ''
        : '?cursor=${Uri.encodeQueryComponent(cursor)}';
    final raw = await _request(
      token,
      '/conversations/$conversationId/messages$query',
    );
    final envelope = raw is Map
        ? raw.cast<String, dynamic>()
        : <String, dynamic>{'items': raw};
    final data = (envelope['items'] as List?) ?? const [];
    final items = data
        .map(
          (item) => ChatMessage.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList()
        .reversed
        .toList();
    return ChatMessagePage(
      items: items,
      nextCursor: envelope['nextCursor']?.toString(),
      hasMore: envelope['hasMore'] == true,
    );
  }

  static Future<ChatMessage> sendMessage(
    String token,
    String conversationId,
    String body,
    String clientMessageId, {
    String? replyToMessageId,
    String? mediaAssetId,
  }) async {
    final data =
        (await _request(
                  token,
                  '/conversations/$conversationId/messages',
                  method: 'POST',
                  body: {
                    'messageType': mediaAssetId == null ? 'text' : 'image',
                    'body': body,
                    'clientMessageId': clientMessageId,
                    'replyToMessageId': replyToMessageId,
                    'mediaAssetId': mediaAssetId,
                  },
                )
                as Map)
            .cast<String, dynamic>();
    return ChatMessage.fromJson(data);
  }

  static Future<Map<String, String>> uploadChatImage(
    String token,
    String conversationId,
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/conversations/$conversationId/media'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    );
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 20)),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw const SocialServiceException('图片上传失败，请稍后重试');
    }
    final data = (decoded['data'] as Map).cast<String, dynamic>();
    return {
      'mediaAssetId': '${data['mediaAssetId']}',
      'mediaUrl': '${data['mediaUrl']}',
    };
  }

  static Future<void> deleteChatMedia(
    String token,
    String conversationId,
    String mediaAssetId,
  ) => _request(
    token,
    '/conversations/$conversationId/media/$mediaAssetId',
    method: 'DELETE',
  );

  static Future<ChatMessage> recallMessage(
    String token,
    String conversationId,
    String messageId,
  ) async => ChatMessage.fromJson(
    ((await _request(
              token,
              '/conversations/$conversationId/messages/$messageId/recall',
              method: 'POST',
            ))
            as Map)
        .cast<String, dynamic>(),
  );

  static Future<ChatMessage> editMessage(
    String token,
    String conversationId,
    String messageId,
    String body,
  ) async => ChatMessage.fromJson(
    ((await _request(
              token,
              '/conversations/$conversationId/messages/$messageId',
              method: 'PATCH',
              body: {'body': body},
            ))
            as Map)
        .cast<String, dynamic>(),
  );

  static Future<void> reportMessage(
    String token,
    String conversationId,
    String messageId,
    String categoryCode,
    String? description,
  ) => _request(
    token,
    '/conversations/$conversationId/messages/$messageId/report',
    method: 'POST',
    body: {'categoryCode': categoryCode, 'description': description},
  );

  static String newClientMessageId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _cacheKey(String userId, String conversationId) =>
      'chat_cache_${userId}_$conversationId';
  static String _pendingKey(String userId, String conversationId) =>
      'chat_pending_${userId}_$conversationId';

  static Future<List<ChatMessage>> cachedMessages(
    String userId,
    String conversationId,
  ) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _cacheKey(userId, conversationId),
    );
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) =>
                ChatMessage.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  static Future<void> cacheMessages(
    String userId,
    String conversationId,
    List<ChatMessage> messages,
  ) async {
    final recent = messages.length > 100
        ? messages.sublist(messages.length - 100)
        : messages;
    await (await SharedPreferences.getInstance()).setString(
      _cacheKey(userId, conversationId),
      jsonEncode(recent.map((item) => item.toJson()).toList()),
    );
  }

  static Future<List<ChatMessage>> pendingMessages(
    String userId,
    String conversationId,
  ) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _pendingKey(userId, conversationId),
    );
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((item) {
        final message = ChatMessage.fromJson(
          (item as Map).cast<String, dynamic>(),
        );
        return message.copyWith(pending: true, failed: true);
      }).toList();
    } on FormatException {
      return const [];
    }
  }

  static Future<void> savePending(
    String userId,
    String conversationId,
    ChatMessage message,
  ) async {
    final items = await pendingMessages(userId, conversationId);
    final updated = [
      ...items.where((item) => item.clientMessageId != message.clientMessageId),
      message,
    ];
    await (await SharedPreferences.getInstance()).setString(
      _pendingKey(userId, conversationId),
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> removePending(
    String userId,
    String conversationId,
    String clientMessageId,
  ) async {
    final items = await pendingMessages(userId, conversationId);
    final updated = items
        .where((item) => item.clientMessageId != clientMessageId)
        .toList();
    await (await SharedPreferences.getInstance()).setString(
      _pendingKey(userId, conversationId),
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
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
