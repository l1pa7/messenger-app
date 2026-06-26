import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';

final profileProvider = FutureProvider.autoDispose<Map>((ref) async {
  final res = await ApiClient().get('/me');
  return res.data as Map;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.primary, size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Профиль',
                style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ]),
          ),

          Expanded(
            child: profileAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2,
                ),
              ),
              error: (_, __) => const Center(
                child: Text('Ошибка загрузки',
                  style: TextStyle(color: AppColors.textHint)),
              ),
              data: (user) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const SizedBox(height: 16),

                  // Avatar with gradient ring
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      gradient: kPrimaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.bg, shape: BoxShape.circle,
                      ),
                      child: AvatarWidget(
                        name: user['username'] ?? '?',
                        url: user['avatar_url'],
                        size: 90,
                      ),
                    ),
                  ).animate().scale(
                    begin: const Offset(0.7, 0.7),
                    duration: 400.ms, curve: Curves.elasticOut,
                  ),

                  const SizedBox(height: 16),

                  Text(user['username'] ?? '',
                    style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 80.ms),

                  const SizedBox(height: 4),

                  Text(user['email'] ?? '',
                    style: const TextStyle(
                      fontSize: 14, color: AppColors.textHint,
                    ),
                  ).animate().fadeIn(delay: 120.ms),

                  if ((user['bio'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(user['bio'],
                      style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 160.ms),
                  ],

                  const SizedBox(height: 32),

                  // Settings tiles
                  _SettingsTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Редактировать профиль',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Уведомления',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Конфиденциальность',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.color_lens_outlined,
                    label: 'Внешний вид',
                    onTap: () {},
                  ),

                  const SizedBox(height: 12),

                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    label: 'Выйти',
                    iconColor: AppColors.accent,
                    labelColor: AppColors.accent,
                    onTap: () async {
                      await ApiClient().clearTokens();
                      if (context.mounted) context.go('/auth/login');
                    },
                  ),
                ].map((w) => w.animate()
                  .fadeIn(delay: 200.ms)
                  .slideY(begin: 0.05, duration: 300.ms, curve: Curves.easeOut)
                ).toList()),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _SettingsTile({
    required this.icon, required this.label, required this.onTap,
    this.iconColor, this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.primary.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (iconColor ?? AppColors.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                  color: iconColor ?? AppColors.primary, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label,
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500,
                  color: labelColor ?? AppColors.textPrimary,
                ),
              )),
              Icon(Icons.chevron_right_rounded,
                color: iconColor ?? AppColors.textHint, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
