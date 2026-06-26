import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/chats/screens/chats_list_screen.dart';
import '../../features/chats/screens/chat_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

final _storage = const FlutterSecureStorage();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final token = await _storage.read(key: 'access_token');
      final isAuth = token != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isAuth && !isAuthRoute) return '/auth/login';
      if (isAuth && isAuthRoute) return '/chats';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/chats'),
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/chats',
        builder: (_, __) => const ChatsListScreen(),
      ),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) {
          final chatId  = int.parse(state.pathParameters['id']!);
          final name    = state.extra as Map<String, dynamic>?;
          return ChatScreen(
            chatId:    chatId,
            chatName:  name?['name']  ?? '',
            avatarUrl: name?['avatar'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
    ],
  );
});
