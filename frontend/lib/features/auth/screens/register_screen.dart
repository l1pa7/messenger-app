import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../shared/widgets/gradient_button.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _api          = ApiClient();
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.post('/auth/register', data: {
        'username': _usernameCtrl.text.trim(),
        'email':    _emailCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      await _api.saveTokens(
        res.data['access_token'],
        res.data['refresh_token'],
      );
      final ws = ref.read(wsClientProvider);
      ws.connect(res.data['access_token']);
      if (mounted) context.go('/chats');
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['error'] ?? 'Ошибка регистрации';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Back button
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary, size: 18,
                  ),
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 32),

              // Logo
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B9D), Color(0xFFFF9B6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4),
                      blurRadius: 24, offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 32,
                ),
              ).animate().scale(
                begin: const Offset(0.6, 0.6),
                duration: 400.ms, curve: Curves.elasticOut,
              ),

              const SizedBox(height: 28),

              Text('Создать аккаунт',
                style: Theme.of(context).textTheme.displayLarge,
              ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.2, duration: 300.ms, curve: Curves.easeOut),

              const SizedBox(height: 6),
              Text('Присоединяйся — это быстро',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(delay: 120.ms),

              const SizedBox(height: 36),

              // Username
              _Field(
                ctrl: _usernameCtrl, hint: 'Имя пользователя',
                icon: Icons.alternate_email_rounded,
              ).animate().fadeIn(delay: 160.ms).slideX(begin: -0.1),
              const SizedBox(height: 12),

              // Email
              _Field(
                ctrl: _emailCtrl, hint: 'Email',
                icon: Icons.mail_outline_rounded,
                type: TextInputType.emailAddress,
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),
              const SizedBox(height: 12),

              // Password
              _Field(
                ctrl: _passCtrl, hint: 'Пароль',
                icon: Icons.lock_outline_rounded,
                obscure: !_showPass,
                suffix: GestureDetector(
                  onTap: () => setState(() => _showPass = !_showPass),
                  child: Icon(
                    _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppColors.textHint, size: 20,
                  ),
                ),
                onSubmit: _register,
              ).animate().fadeIn(delay: 240.ms).slideX(begin: -0.1),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                      style: const TextStyle(color: AppColors.accent, fontSize: 13),
                    )),
                  ]),
                ).animate().fadeIn().shakeX(hz: 3, amount: 4),
              ],

              const SizedBox(height: 24),

              GradientButton(
                label: 'Зарегистрироваться',
                onTap: _loading ? null : _register,
                loading: _loading,
              ).animate().fadeIn(delay: 280.ms),

              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: () => context.pop(),
                  child: const Text.rich(TextSpan(
                    text: 'Уже есть аккаунт? ',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    children: [
                      TextSpan(
                        text: 'Войти',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )),
                ),
              ).animate().fadeIn(delay: 320.ms),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? type;
  final Widget? suffix;
  final VoidCallback? onSubmit;

  const _Field({
    required this.ctrl, required this.hint, required this.icon,
    this.obscure = false, this.type, this.suffix, this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    obscureText: obscure,
    keyboardType: type,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
    onSubmitted: onSubmit != null ? (_) => onSubmit!() : null,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.textHint, size: 20),
      suffixIcon: suffix != null
          ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix)
          : null,
    ),
  );
}
