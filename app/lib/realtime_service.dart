import 'dart:async';
import 'dart:convert';

import 'package:web_socket/web_socket.dart';

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class RealtimeService {
  RealtimeService._();
  static final instance = RealtimeService._();

  final _events = StreamController<RealtimeEvent>.broadcast();
  WebSocket? _socket;
  StreamSubscription<WebSocketEvent>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  String? _token;
  int _generation = 0;
  int _reconnectAttempt = 0;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> start(String token) async {
    if (_token == token && _socket != null) return;
    await stop();
    _token = token;
    final generation = ++_generation;
    await _connect(generation);
  }

  Future<void> stop() async {
    _token = null;
    _generation++;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  Future<void> _connect(int generation) async {
    final token = _token;
    if (token == null || generation != _generation) return;
    try {
      final apiUri = Uri.parse(_apiBase);
      final socketUri = apiUri.replace(
        scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
        path: '${apiUri.path.replaceFirst(RegExp(r'/$'), '')}/realtime',
        query: null,
        fragment: null,
      );
      final socket = await WebSocket.connect(socketUri);
      if (generation != _generation || _token == null) {
        await socket.close();
        return;
      }
      _socket = socket;
      _reconnectAttempt = 0;
      socket.sendText(jsonEncode({'type': 'authenticate', 'token': token}));
      _socketSubscription = socket.events.listen(
        (event) => _handleSocketEvent(event, generation),
        onError: (_) => _scheduleReconnect(generation),
        onDone: () => _scheduleReconnect(generation),
        cancelOnError: true,
      );
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_socket == socket) {
          socket.sendText(jsonEncode({'type': 'ping'}));
        }
      });
    } catch (_) {
      _scheduleReconnect(generation);
    }
  }

  void _handleSocketEvent(WebSocketEvent event, int generation) {
    switch (event) {
      case TextDataReceived(:final text):
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) return;
          final json = decoded.cast<String, dynamic>();
          final type = json['type'];
          if (type is! String || type == 'connected' || type == 'pong') return;
          final rawData = json['data'];
          _events.add(
            RealtimeEvent(
              type,
              rawData is Map
                  ? rawData.cast<String, dynamic>()
                  : <String, dynamic>{},
            ),
          );
        } on FormatException {
          // Ignore malformed server events and keep the connection alive.
        }
      case BinaryDataReceived():
        break;
      case CloseReceived():
        _scheduleReconnect(generation);
    }
  }

  void _scheduleReconnect(int generation) {
    if (_token == null ||
        generation != _generation ||
        _reconnectTimer != null) {
      return;
    }
    _pingTimer?.cancel();
    _pingTimer = null;
    _socket = null;
    final seconds = 1 << _reconnectAttempt.clamp(0, 5);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      _connect(generation);
    });
  }
}
