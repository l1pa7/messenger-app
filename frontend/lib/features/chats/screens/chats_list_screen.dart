import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final chatsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final api = ApiClient();
  final res = await api.get('/chats');
  return res.data as List;
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});
  @override
  ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<dynamic> _searchResults = [];
  bool _searchLoading = false;
  final _api = ApiClient();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() { _searching = true; _searchLoading = true; });
    try {
      final res = await _api.get('/users/search', params: {'q': q});
      setState(() { _searchResults = res.data as List; });
    } on DioException {
      setState(() { _searchResults = []; });
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _openOrCreateChat(Map user) async {
    try {
      final res = await _api.post('/chats', data: {
        'member_ids': [user['id']],
        'is_group': false,
      });
      final chatId = res.data['id'];
      if (mounted) {
        context.push('/chats/$chatId', extra: {
          'name': user['username'],
          'avatar': user['avatar_url'] ?? '',
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final chatsAsync = ref.watch(chatsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(children: [
              Expanded(
                child: Text('Сообщения',
                  style: Theme.of(context).textTheme.displayLarge!
                      .copyWith(fontSize: 28),
                ),
              ),
              // New chat button
              _IconBtn(
                icon: Icons.edit_outlined,
                onTap: () => _focusSearch(),
              ),
              const SizedBox(width: 4),
              // Profile
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: const AvatarWidget(name: 'Me', size: 36),
              ),
            ]).animate().fadeIn(duration: 250.ms),
          ),

          const SizedBox(height: 16),

          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              onChanged: _searchUsers,
              decoration: InputDecoration(
                hintText: 'Поиск людей...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textHint, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() { _searching = false; _searchResults = []; });
                        },
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.textHint, size: 18),
                      )
                    : null,
              ),
            ),
          ).animate().fadeIn(delay: 60.ms),

          const SizedBox(height: 8),

          // ── Content ──
          Expanded(
            child: _searching
                ? _SearchResults(
                    results: _searchResults,
                    loading: _searchLoading,
                    onTap: _openOrCreateChat,
                  )
                : chatsAsync.when(
                    loading: () => const _ChatSkeleton(),
                    error: (e, _) => _EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: 'Нет соединения',
                      subtitle: 'Проверь интернет и попробуй снова',
                    ),
                    data: (chats) => chats.isEmpty
                        ? _EmptyState(
                            icon: Icons.forum_outlined,
                            title: 'Пока пусто',
                            subtitle: 'Найди кого-нибудь через поиск выше',
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: () => ref.refresh(chatsProvider.future),
                            child: ListView.builder(
                              padding: const EdgeInsets.only(top: 4, bottom: 80),
                              itemCount: chats.length,
                              itemBuilder: (ctx, i) => _ChatTile(
                                chat: chats[i],
                                index: i,
                                onTap: () => context.push(
                                  '/chats/${chats[i]['id']}',
                                  extra: {
                                    'name': chats[i]['name'] ?? '',
                                    'avatar': chats[i]['avatar_url'] ?? '',
                                  },
                                ),
                              ),
                            ),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  void _focusSearch() {
    FocusScope.of(context).requestFocus(FocusNode());
  }
}

// ─── Chat tile ────────────────────────────────────────────────────────────────

class _ChatTile extends StatelessWidget {
  final Map chat;
  final int index;
  final VoidCallback onTap;

  const _ChatTile({required this.chat, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lastMsg = chat['last_message'] as Map? ?? {};
    final content = lastMsg['content'] as String? ?? '';
    final time    = lastMsg['created_at'] != null
        ? timeago.format(DateTime.parse(lastMsg['created_at']),
            locale: 'ru')
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            splashColor: AppColors.primary.withOpacity(0.08),
            highlightColor: AppColors.surface2.withOpacity(0.5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                AvatarWidget(
                  name: chat['name'] ?? '?',
                  url: chat['avatar_url'],
                  size: 50,
                  online: chat['online'] ?? false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            chat['name'] ?? 'Диалог',
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(time,
                          style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        content.isEmpty ? 'Начни общение' : content,
                        style: TextStyle(
                          fontSize: 13,
                          color: content.isEmpty
                              ? AppColors.textHint
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 40 * index)).slideX(
      begin: 0.05, duration: 300.ms, curve: Curves.easeOut,
    );
  }
}

// ─── Search results ───────────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final List results;
  final bool loading;
  final void Function(Map) onTap;

  const _SearchResults({required this.results, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text('Никого не найдено',
          style: TextStyle(color: AppColors.textHint, fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final user = results[i] as Map;
        return ListTile(
          onTap: () => onTap(user),
          leading: AvatarWidget(
            name: user['username'] ?? '?',
            url: user['avatar_url'],
            size: 44,
          ),
          title: Text(user['username'] ?? '',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500, fontSize: 15,
            ),
          ),
          subtitle: Text(user['bio'] ?? '',
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Написать',
              style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: AppColors.textHint, size: 36),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          Text(title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17, fontWeight: FontWeight.w600,
            ),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 6),
          Text(subtitle,
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 160.ms),
        ],
      ),
    );
  }
}

// ─── Skeleton loader ──────────────────────────────────────────────────────────

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 8,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          _Shimmer(width: 50, height: 50, radius: 25),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Shimmer(width: double.infinity, height: 14, radius: 7),
              const SizedBox(height: 6),
              _Shimmer(width: 180, height: 12, radius: 6),
            ],
          )),
        ]),
      ).animate(delay: Duration(milliseconds: i * 60))
        .fadeIn(duration: 300.ms),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer({required this.width, required this.height, required this.radius});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            colors: const [Color(0xFF1C1D2E), Color(0xFF252636), Color(0xFF1C1D2E)],
            stops: [0, _ctrl.value, 1],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface2, borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 20),
    ),
  );
}
