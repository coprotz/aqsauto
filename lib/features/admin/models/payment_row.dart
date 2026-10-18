import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class PaymentAttemptRow {
  const PaymentAttemptRow({
    required this.id,
    required this.stage,
    required this.success,
    required this.errorMessage,
    required this.statusCode,
    required this.createdAt,
  });

  final String id;
  final String stage;
  final bool? success;
  final String errorMessage;
  final String statusCode;
  final DateTime? createdAt;

  bool get isFailed => success == false || errorMessage.trim().isNotEmpty;

  String get stageLabel =>
      stage.trim().isEmpty ? 'Payment attempt' : titleCaseStatus(stage);

  String get detailLabel {
    final details = <String>[];
    if (success == true) details.add('Successful checkout request');
    if (isFailed) {
      details.add(
        errorMessage.trim().isEmpty ? 'Failed attempt' : errorMessage.trim(),
      );
    }
    if (statusCode.trim().isNotEmpty) details.add('Status $statusCode');
    return details.join(' • ');
  }

  IconData get icon {
    if (success == true) return Icons.check_circle_outline_rounded;
    if (isFailed) return Icons.error_outline_rounded;
    return Icons.radio_button_unchecked_rounded;
  }
}
