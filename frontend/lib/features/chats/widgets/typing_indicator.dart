import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.msgOther,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: List.generate(3, (i) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  decoration: const BoxDecoration(
                    color: AppColors.textSecondary,
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(
                      delay: Duration(milliseconds: i * 160),
                      duration: 300.ms,
                    )
                    .then()
                    .fadeOut(duration: 300.ms);
              }),
            ),
          ),
        ],
      ),
    );
  }
}
