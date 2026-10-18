import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/build_up_rates/services/rate_limit_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showRateLimitDialog(RateLimitResult result) async {
  await Get.dialog<void>(
    AlertDialog(
      icon: const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFFEEF4FF),
        child: Icon(
          Icons.workspace_premium_outlined,
          color: AqsColors.primary,
          size: 30,
        ),
      ),
      title: const Text('Build-up rate limit reached'),
      content: Text(result.message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Maybe later')),
        FilledButton.icon(
          onPressed: () {
            Get.back<void>();
            Future<void>.microtask(() => Get.toNamed(AppRoutes.pricing));
          },
          icon: const Icon(Icons.arrow_upward_rounded),
          label: const Text('Upgrade plan'),
        ),
      ],
    ),
  );
}
