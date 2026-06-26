import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../shared/widgets/gradient_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _api       = ApiClient();
  bool _loading    = false;
  bool _showPass   = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.post('/auth/login', data: {
        'email': _emailCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      await _api.saveTokens(
        res.data['access_token'],
        res.data['refresh_token'],
      );
      // Connect WebSocket
      final ws = ref.read(wsClientProvider);
      ws.connect(res.data['access_token']);

      if (mounted) context.go('/chats');
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['error'] ?? 'Ошибка соединения';
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
              const SizedBox(height: 64),

              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: kPrimaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ).animate().scale(
                    begin: const Offset(0.6, 0.6),
                    duration: 400.ms,
                    curve: Curves.elasticOut,
                  ),

              const SizedBox(height: 32),

              Text(
                'С возвращением',
                style: Theme.of(context).textTheme.displayLarge,
              ).animate().fadeIn(delay: 100.ms).slideY(
                    begin: 0.2,
                    duration: 350.ms,
                    curve: Curves.easeOut,
                  ),

              const SizedBox(height: 6),

              Text(
                'Войди, чтобы продолжить',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 40),

              // Email field
              _InputField(
                controller: _emailCtrl,
                hint: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

              const SizedBox(height: 12),

              // Password field
              _InputField(
                controller: _passCtrl,
                hint: 'Пароль',
                icon: Icons.lock_outline_rounded,
                obscure: !_showPass,
                suffix: GestureDetector(
                  onTap: () => setState(() => _showPass = !_showPass),
                  child: Icon(
                    _showPass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                ),
                onSubmit: _login,
              ).animate().fadeIn(delay: 240.ms).slideX(begin: -0.1),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.accent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shakeX(hz: 3, amount: 4),
              ],

              const SizedBox(height: 24),

              GradientButton(
                label: 'Войти',
                onTap: _loading ? null : _login,
                loading: _loading,
              ).animate().fadeIn(delay: 280.ms),

              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: () => context.push('/auth/register'),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Нет аккаунта? ',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                      children: [
                        TextSpan(
                          text: 'Зарегистрироваться',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 320.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final VoidCallback? onSubmit;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      onSubmitted: onSubmit != null ? (_) => onSubmit!() : null,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textHint, size: 20),
        suffixIcon: suffix != null ? Padding(
          padding: const EdgeInsets.only(right: 12),
          child: suffix,
        ) : null,
      ),
    );
  }
}
