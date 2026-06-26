import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String _wsUrl = String.fromEnvironment(
  'WS_URL',
  defaultValue: 'ws://localhost:8080/ws',
);

class WsClient {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect(String token) {
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsUrl?token=$token'),
    );

    _channel!.stream.listen(
      (raw) {
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        _controller.add(data);
      },
      onDone: () => _scheduleReconnect(token),
      onError: (_) => _scheduleReconnect(token),
    );
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void sendMessage(int chatId, String content) {
    send({'type': 'message', 'payload': {'chat_id': chatId, 'content': content, 'type': 'text'}});
  }

  void sendTyping(int chatId) {
    send({'type': 'typing', 'payload': {'chat_id': chatId}});
  }

  void _scheduleReconnect(String token) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () => connect(token));
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}

final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});
