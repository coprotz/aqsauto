import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/admin/models/payment_row.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class PaymentAttemptLine extends StatelessWidget {
  const PaymentAttemptLine({super.key, required this.attempt});

  final PaymentAttemptRow attempt;

  @override
  Widget build(BuildContext context) {
    final tone =
        attempt.success == true
            ? PillTone.green
            : attempt.isFailed
            ? PillTone.red
            : PillTone.grey;
    final colors = pillColors(tone);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(attempt.icon, color: colors.fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attempt.stageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (attempt.detailLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    attempt.detailLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatDateTime(attempt.createdAt),
            style: const TextStyle(color: AqsColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
