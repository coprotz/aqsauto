import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class InlinePaymentNotice extends StatelessWidget {
  const InlinePaymentNotice({
    super.key,
    required this.tone,
    required this.title,
    required this.message,
  });

  final PaymentNoticeTone tone;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      PaymentNoticeTone.success => const Color(0xFF039855),
      PaymentNoticeTone.error => const Color(0xFFD92D20),
      PaymentNoticeTone.info => AqsColors.primary,
    };
    final bg = switch (tone) {
      PaymentNoticeTone.success => const Color(0xFFECFDF3),
      PaymentNoticeTone.error => const Color(0xFFFEF3F2),
      PaymentNoticeTone.info => const Color(0xFFEFF4FF),
    };
    final icon = switch (tone) {
      PaymentNoticeTone.success => Icons.check_circle_outline_rounded,
      PaymentNoticeTone.error => Icons.error_outline_rounded,
      PaymentNoticeTone.info => Icons.info_outline_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
