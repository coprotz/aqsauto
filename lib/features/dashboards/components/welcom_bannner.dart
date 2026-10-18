import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({
    super.key,
    required this.user,
    required this.onViewPlans,
  });

  final User user;
  final VoidCallback onViewPlans;

  @override
  Widget build(BuildContext context) {
    final displayName = (user.displayName ?? '').trim();

    final firstName =
        displayName.isEmpty ? 'there' : displayName.split(RegExp(r'\s+')).first;

    return StreamBuilder<AqsSubscription>(
      stream: SubscriptionService.instance.watchSubscription(user: user),
      initialData: AqsSubscription.free,
      builder: (context, snapshot) {
        final subscription = snapshot.data ?? AqsSubscription.free;

        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AqsColors.primaryDark, Color(0xFF17448A)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24155EEF),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 620;

              final tablet =
                  constraints.maxWidth >= 620 && constraints.maxWidth < 900;

              if (mobile) {
                return _MobileWelcomeBanner(
                  firstName: firstName,
                  subscription: subscription,
                  loading: loading,
                  onViewPlans: onViewPlans,
                );
              }

              return _WideWelcomeBanner(
                firstName: firstName,
                subscription: subscription,
                loading: loading,
                tablet: tablet,
                onViewPlans: onViewPlans,
              );
            },
          ),
        );
      },
    );
  }
}

class _MobileWelcomeBanner extends StatelessWidget {
  const _MobileWelcomeBanner({
    required this.firstName,
    required this.subscription,
    required this.loading,
    required this.onViewPlans,
  });

  final String firstName;
  final AqsSubscription subscription;
  final bool loading;
  final VoidCallback onViewPlans;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _WelcomeIcon(compact: true),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, $firstName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    'Your take-off workspace is ready.',
                    style: TextStyle(color: Color(0xFFCBD9F5), height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        _SubscriptionSummary(
          subscription: subscription,
          loading: loading,
          fullWidth: true,
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: _PlanActionButton(
            subscription: subscription,
            onPressed: onViewPlans,
          ),
        ),
      ],
    );
  }
}

class _WideWelcomeBanner extends StatelessWidget {
  const _WideWelcomeBanner({
    required this.firstName,
    required this.subscription,
    required this.loading,
    required this.tablet,
    required this.onViewPlans,
  });

  final String firstName;
  final AqsSubscription subscription;
  final bool loading;
  final bool tablet;
  final VoidCallback onViewPlans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _WelcomeIcon(),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                tablet
                    ? 'Continue your take-offs and BOQs.'
                    : 'Continue your take-offs, BOQs, and project measurements.',
                style: const TextStyle(color: Color(0xFFCBD9F5)),
              ),
            ],
          ),
        ),

        const SizedBox(width: 22),

        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SubscriptionSummary(subscription: subscription, loading: loading),

            const SizedBox(height: 10),

            _PlanActionButton(
              subscription: subscription,
              onPressed: onViewPlans,
            ),
          ],
        ),
      ],
    );
  }
}

class _WelcomeIcon extends StatelessWidget {
  const _WelcomeIcon({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 46.0 : 52.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Icon(
        Icons.engineering_outlined,
        color: const Color(0xFFBFD2FA),
        size: compact ? 23 : 26,
      ),
    );
  }
}

class _SubscriptionSummary extends StatelessWidget {
  const _SubscriptionSummary({
    required this.subscription,
    required this.loading,
    this.fullWidth = false,
  });

  final AqsSubscription subscription;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final style = _PlanBadgeStyle.forPlan(subscription.plan);

    return Semantics(
      label: 'Subscription: ${subscription.displayName}',
      child: Container(
        width: fullWidth ? double.infinity : null,
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(style.icon, size: 17, color: style.foreground),

            const SizedBox(width: 8),

            Expanded(
              flex: fullWidth ? 1 : 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURRENT PLAN',
                    style: TextStyle(
                      color: Color(0xFFAFC4E9),
                      fontSize: 9,
                      letterSpacing: .7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    loading ? 'Loading...' : _planLabel(subscription),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: loading ? Colors.white : style.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  if (!loading &&
                      subscription.isActivePaid &&
                      subscription.billingCycleLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),

                    Text(
                      subscription.billingCycleLabel,
                      style: const TextStyle(
                        color: Color(0xFFCBD9F5),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _planLabel(AqsSubscription subscription) {
    return subscription.displayName;
  }
}

class _PlanActionButton extends StatelessWidget {
  const _PlanActionButton({
    required this.subscription,
    required this.onPressed,
  });

  final AqsSubscription subscription;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final canUpgrade =
        subscription.plan == AqsPlan.free ||
        subscription.plan == AqsPlan.basic ||
        subscription.plan == AqsPlan.pro;

    final label = canUpgrade ? 'Upgrade plan' : 'View plans';

    final icon = canUpgrade ? Icons.upgrade_rounded : Icons.visibility_outlined;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.30)),
        backgroundColor: Colors.white.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PlanBadgeStyle {
  const _PlanBadgeStyle({
    required this.label,
    required this.icon,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color foreground;

  static _PlanBadgeStyle forPlan(AqsPlan plan) {
    switch (plan) {
      case AqsPlan.free:
        return const _PlanBadgeStyle(
          label: 'Free',
          icon: Icons.account_circle_outlined,
          foreground: Colors.white,
        );

      case AqsPlan.basic:
        return const _PlanBadgeStyle(
          label: 'Basic',
          icon: Icons.local_offer_outlined,
          foreground: Color(0xFFD8E5FF),
        );

      case AqsPlan.pro:
        return const _PlanBadgeStyle(
          label: 'Pro',
          icon: Icons.workspace_premium_outlined,
          foreground: Color(0xFFFFD37A),
        );

      case AqsPlan.business:
        return const _PlanBadgeStyle(
          label: 'Business',
          icon: Icons.business_outlined,
          foreground: Color(0xFFA6F4C5),
        );
    }
  }
}
