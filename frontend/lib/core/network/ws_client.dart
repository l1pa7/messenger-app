/// WsClient — WebSocket клиент с правильной аутентификацией.
///
/// ВАЖНО: токен передаётся в ПЕРВОМ ФРЕЙМЕ, НЕ в URL.
/// URL /ws?token=... логируется везде: Cloudflare, Nginx, системные логи.
/// Первый WS-фрейм — нет.
///
/// Поток:
///   1. connect() — подключиться к /ws (без токена в URL)
///   2. Немедленно отправить {type: "auth", token: "..."} первым фреймом
///   3. Сервер проверяет токен и начинает обмен сообщениями

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String _wsBaseUrl = String.fromEnvironment(
  'WS_URL',
  defaultValue: 'ws://localhost:8080',
);

class WsClient {
  WebSocketChannel? _channel;
  final _controller    = StreamController<Map<String, dynamic>>.broadcast();
  final _storage       = const FlutterSecureStorage();
  Timer?  _reconnectTimer;
  String? _lastToken;
  bool    _disposed = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String accessToken) async {
    _lastToken = accessToken;
    await _doConnect(accessToken);
  }

  Future<void> _doConnect(String token) async {
    try {
      // Подключаемся БЕЗ токена в URL
      _channel = WebSocketChannel.connect(
        Uri.parse('$_wsBaseUrl/ws'),
      );

      // Первый фрейм — аутентификация (не URL-параметр!)
      _sendRaw({
        'type':  'auth',
        'token': token,
      });

      _channel!.stream.listen(
        (raw) {
          if (_disposed) return;
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onDone:  () => _handleDisconnect(),
        onError: (_) => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _channel = null;
    if (!_disposed && _lastToken != null) {
      _reconnectTimer?.cancel();
      // Экспоненциальный backoff: 3с, потом 6с, потом 12с...
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (!_disposed && _lastToken != null) {
          _doConnect(_lastToken!);
        }
      });
    }
  }

  // ── Отправка сообщений ────────────────────────────────────────────────────

  /// Отправить зашифрованное E2EE сообщение.
  /// [ciphertext] — уже зашифрован на устройстве через CryptoService
  void sendEncryptedMessage(int chatId, String ciphertext) {
    _sendRaw({
      'type': 'message',
      'payload': {
        'chat_id': chatId,
        'content': ciphertext,
        'type':    'text',
        'is_e2e':  true,
      },
    });
  }

  /// Отправить обычное сообщение (server-side шифрование).
  void sendMessage(int chatId, String content) {
    _sendRaw({
      'type': 'message',
      'payload': {
        'chat_id': chatId,
        'content': content,
        'type':    'text',
        'is_e2e':  false,
      },
    });
  }

  /// Отправить индикатор набора.
  void sendTyping(int chatId) {
    _sendRaw({
      'type':    'typing',
      'payload': {'chat_id': chatId},
    });
  }

  void _sendRaw(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
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
