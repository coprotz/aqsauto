import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AqsLogoMark extends StatelessWidget {
  const AqsLogoMark({super.key, this.size = 42, this.inverted = false});

  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.landing),

      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.24),
          border: Border.all(
            color: inverted ? Colors.white.withOpacity(0.22) : AqsColors.border,
            width: 1,
          ),
          boxShadow:
              inverted || size >= 38
                  ? [
                    BoxShadow(
                      color: AqsColors.primaryDark.withOpacity(0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                  : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(size * 0.10),
          child: Image.asset(
            'assets/images/logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class AqsBrand extends StatelessWidget {
  const AqsBrand({
    super.key,
    this.compact = false,
    this.onDark = false,
    this.markSize = 40,
  });

  final bool compact;
  final bool onDark;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : AqsColors.ink;
    final subtitleColor = onDark ? const Color(0xFFBFD2FA) : AqsColors.muted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AqsLogoMark(size: markSize, inverted: onDark),
        if (!compact) ...[
          const SizedBox(width: 11),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AQS',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'AUTOBOQ',
                style: TextStyle(
                  color: subtitleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class AqsStatusPill extends StatelessWidget {
  const AqsStatusPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AqsColors.successSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFA6F4C5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AqsColors.success),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF027A48),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AqsAppBarTitle extends StatelessWidget {
  const AqsAppBarTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AqsLogoMark(size: 32),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
