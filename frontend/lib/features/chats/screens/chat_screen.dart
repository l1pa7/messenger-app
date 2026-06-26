import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, List<Map>, int>(
  (ref, chatId) => MessagesNotifier(chatId, ref),
);

class MessagesNotifier extends StateNotifier<List<Map>> {
  final int chatId;
  final Ref ref;
  final _api = ApiClient();
  StreamSubscription? _wsSub;

  MessagesNotifier(this.chatId, this.ref) : super([]) {
    _loadMessages();
    _subscribeWs();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await _api.get('/chats/$chatId/messages');
      final list = (res.data as List).cast<Map>();
      state = list;
    } catch (_) {}
  }

  void _subscribeWs() {
    final ws = ref.read(wsClientProvider);
    _wsSub = ws.stream.listen((data) {
      if (data['type'] == 'message') {
        final msg = data['payload'] as Map;
        if (msg['chat_id'] == chatId) {
          state = [...state, msg];
        }
      }
    });
  }

  void addMessage(Map msg) => state = [...state, msg];

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}

final typingProvider =
    StateProvider.family<bool, int>((ref, chatId) => false);

// ─── Screen ──────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final int chatId;
  final String chatName;
  final String avatarUrl;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.avatarUrl,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _storage     = const FlutterSecureStorage();
  Timer? _typingTimer;
  int? _myUserId;
  bool _isOnline = false;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadMyId();
    _subscribePresence();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMyId() async {
    // Decode user_id from stored token (simple approach)
    // In production, store user_id separately after login
    final api = ApiClient();
    try {
      final res = await api.get('/me');
      if (mounted) setState(() => _myUserId = res.data['id']);
    } catch (_) {}
  }

  void _subscribePresence() {
    final ws = ref.read(wsClientProvider);
    _wsSub = ws.stream.listen((data) {
      if (!mounted) return;
      if (data['type'] == 'online') {
        // Could check specific user here
        setState(() => _isOnline = data['payload']['online'] as bool? ?? false);
      }
      if (data['type'] == 'typing') {
        final chatId = data['payload']['chat_id'];
        if (chatId == widget.chatId) {
          ref.read(typingProvider(widget.chatId).notifier).state = true;
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              ref.read(typingProvider(widget.chatId).notifier).state = false;
            }
          });
        }
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();

    final ws = ref.read(wsClientProvider);
    ws.sendMessage(widget.chatId, text);
    _scrollToBottom();
  }

  void _onTyping() {
    _typingTimer?.cancel();
    final ws = ref.read(wsClientProvider);
    ws.sendTyping(widget.chatId);
    _typingTimer = Timer(const Duration(seconds: 4), () {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.chatId));
    final isTyping = ref.watch(typingProvider(widget.chatId));

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Custom AppBar ──
          _ChatAppBar(
            name: widget.chatName,
            avatarUrl: widget.avatarUrl,
            isOnline: _isOnline,
          ),

          // ── Messages ──
          Expanded(
            child: messages.isEmpty
                ? _EmptyChat(name: widget.chatName)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length + (isTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (isTyping && i == messages.length) {
                        return const TypingIndicator();
                      }
                      final msg    = messages[i];
                      final isOwn  = msg['user_id'] == _myUserId;
                      final isLast = i == messages.length - 1 ||
                          messages[i + 1]['user_id'] != msg['user_id'];
                      final isFirst = i == 0 ||
                          messages[i - 1]['user_id'] != msg['user_id'];

                      return MessageBubble(
                        content: msg['content'] ?? '',
                        authorName: msg['author']?['username'] ?? '',
                        authorAvatar: msg['author']?['avatar_url'],
                        createdAt: DateTime.tryParse(msg['created_at'] ?? '') ??
                            DateTime.now(),
                        isOwn: isOwn,
                        showAuthor: isFirst && !isOwn,
                        isFirst: isFirst,
                        isLast: isLast,
                      );
                    },
                  ),
          ),

          // ── Input bar ──
          _InputBar(
            controller: _inputCtrl,
            onSend: _sendMessage,
            onTyping: _onTyping,
          ),
        ]),
      ),
    );
  }
}

// ─── Custom AppBar ────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool isOnline;

  const _ChatAppBar({
    required this.name, required this.avatarUrl, required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(children: [
        // Back
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primary, size: 20,
          ),
        ),
        const SizedBox(width: 8),

        // Avatar
        AvatarWidget(
          name: name, url: avatarUrl, size: 40, online: isOnline,
        ),
        const SizedBox(width: 12),

        // Name + status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              Text(
                isOnline ? 'В сети' : 'Был(а) недавно',
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline ? AppColors.online : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),

        // Actions
        _AppBarAction(icon: Icons.call_outlined, onTap: () {}),
        const SizedBox(width: 4),
        _AppBarAction(icon: Icons.more_vert_rounded, onTap: () {}),
      ]),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _AppBarAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppColors.surface2, borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 18),
    ),
  );
}

// ─── Input bar ───────────────────────────────────────────────────────────────

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onTyping;

  const _InputBar({
    required this.controller, required this.onSend, required this.onTyping,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final has = widget.controller.text.isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(children: [
        // Attach button
        GestureDetector(
          onTap: () {},
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface2, borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.attach_file_rounded,
              color: AppColors.textSecondary, size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Text field
        Expanded(
          child: TextField(
            controller: widget.controller,
            onChanged: (_) => widget.onTyping(),
            onSubmitted: (_) => widget.onSend(),
            maxLines: 5, minLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 15, height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Написать...',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              fillColor: AppColors.surface3,
              filled: true,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send button
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: _hasText ? kPrimaryGradient : null,
            color: _hasText ? null : AppColors.surface3,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _hasText
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 12, offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            onPressed: _hasText ? widget.onSend : null,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim, child: child,
              ),
              child: Icon(
                _hasText
                    ? Icons.send_rounded
                    : Icons.mic_none_rounded,
                key: ValueKey(_hasText),
                color: _hasText ? Colors.white : AppColors.textHint,
                size: 20,
              ),
            ),
            padding: EdgeInsets.zero,
          ),
        ),
      ]),
    );
  }
}

// ─── Empty chat ───────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  final String name;
  const _EmptyChat({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Начни общение с $name 👋',
            style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 14,
            ),
          ),
        ).animate().fadeIn(delay: 200.ms).scale(
          begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.elasticOut,
        ),
      ]),
    );
  }
}
