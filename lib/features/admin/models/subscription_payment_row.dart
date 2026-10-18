import 'package:aqs/features/admin/models/payment_row.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class SubscriptionPaymentRow {
  const SubscriptionPaymentRow({
    required this.id,
    required this.uid,
    required this.userName,
    required this.email,
    required this.phone,
    required this.plan,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.status,
    required this.stage,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.callbackReceivedAt,
    required this.delay,
    required this.isSuccessful,
    required this.isFailed,
    required this.isPending,
    required this.isDelayed,
    required this.attempts,
  });

  final String id;
  final String uid;
  final String userName;
  final String email;
  final String phone;
  final String plan;
  final num? amount;
  final String currency;
  final String provider;
  final String status;
  final String stage;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? callbackReceivedAt;
  final Duration? delay;
  final bool isSuccessful;
  final bool isFailed;
  final bool isPending;
  final bool isDelayed;
  final List<PaymentAttemptRow> attempts;

  int get attemptCount => attempts.length;

  int get successAttempts =>
      attempts.where((attempt) => attempt.success == true).length;

  int get failedAttempts =>
      attempts.where((attempt) => attempt.isFailed).length;

  String get userLabel {
    if (userName.trim().isNotEmpty) return userName.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    return 'Unknown user';
  }

  String get contactLabel {
    final pieces = <String>[];
    if (email.trim().isNotEmpty) pieces.add(email.trim());
    if (phone.trim().isNotEmpty) pieces.add(phone.trim());
    pieces.add(uid.trim().isEmpty ? 'No UID' : 'UID: ${uid.trim()}');
    return pieces.join(' • ');
  }

  String get planLabel =>
      plan.trim().isEmpty ? 'No plan' : titleCaseStatus(plan);

  String get amountLabel => formatMoney(amount, currency);

  String get providerLabel {
    final gateway =
        provider.trim().isEmpty ? 'Payment provider unknown' : provider;
    final currentStage =
        stage.trim().isEmpty ? '' : ' • ${titleCaseStatus(stage)}';
    return '$gateway$currentStage';
  }

  String get statusLabel => titleCaseStatus(status);

  String get delayLabel =>
      isDelayed
          ? 'Delayed ${formatDuration(delay)}'
          : 'Delay ${formatDuration(delay)}';

  String get attemptSummary {
    if (attemptCount == 0) return 'No attempts';
    return '$attemptCount attempts';
  }

  IconData get statusIcon {
    if (isSuccessful) return Icons.check_circle_outline_rounded;
    if (isFailed) return Icons.error_outline_rounded;
    if (isDelayed) return Icons.timer_outlined;
    return Icons.pending_outlined;
  }
}
