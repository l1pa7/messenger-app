import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final String content;
  final String authorName;
  final String? authorAvatar;
  final DateTime createdAt;
  final bool isOwn;
  final bool showAuthor;
  final bool isFirst;
  final bool isLast;

  const MessageBubble({
    super.key,
    required this.content,
    required this.authorName,
    this.authorAvatar,
    required this.createdAt,
    required this.isOwn,
    this.showAuthor = false,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isOwn ? 60 : 12,
        right: isOwn ? 12 : 60,
        bottom: isLast ? 4 : 2,
      ),
      child: Column(
        crossAxisAlignment:
            isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showAuthor && !isOwn)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                authorName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          Row(
            mainAxisAlignment:
                isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  decoration: BoxDecoration(
                    gradient: isOwn ? kMsgGradient : null,
                    color: isOwn ? null : AppColors.msgOther,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isOwn ? 18 : (isLast ? 4 : 18)),
                      bottomRight: Radius.circular(isOwn ? (isLast ? 4 : 18) : 18),
                    ),
                    boxShadow: isOwn
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm').format(createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(isOwn ? 0.7 : 0.45),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(
          begin: 0.15,
          end: 0,
          duration: 200.ms,
          curve: Curves.easeOut,
        );
  }
}
