import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool online;

  const AvatarWidget({
    super.key,
    this.url,
    required this.name,
    this.size = 46,
    this.online = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: url == null || url!.isEmpty
                ? LinearGradient(
                    colors: [
                      _colorFromName(name),
                      _colorFromName(name).withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: url != null && url!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _initials(),
                )
              : _initials(),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _initials() {
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Color _colorFromName(String name) {
    const palette = [
      Color(0xFF7C6EFA),
      Color(0xFFFA6E7C),
      Color(0xFF6EE2FA),
      Color(0xFFFA9B6E),
      Color(0xFF6EFAB8),
      Color(0xFFD46EFA),
    ];
    if (name.isEmpty) return palette[0];
    final idx = name.codeUnitAt(0) % palette.length;
    return palette[idx];
  }
}
