import 'dart:async';

import 'package:aqs/features/pricing/data/pricing_plans.dart';
import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:aqs/features/pricing/widgets/pricing_plan_card.dart';
import 'package:aqs/features/subscription/dialogs/payment_receipt_dialog.dart';
import 'package:aqs/features/subscription/dialogs/qucklipa_checkout_dialog.dart';
import 'package:aqs/features/subscription/models/aqs_subscription.dart';
import 'package:aqs/features/subscription/services/aqs_payment_service.dart';
import 'package:aqs/features/subscription/services/aqs_subscription_service.dart';
import 'package:aqs/features/subscription/services/testing_subscription_activation_service.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PricingPlansPage extends StatefulWidget {
  const PricingPlansPage({
    super.key,
    this.initialPlanId,
    this.initialYearly = false,
  });

  final String? initialPlanId;
  final bool initialYearly;

  @override
  State<PricingPlansPage> createState() => _PricingPlansPageState();
}

class _PricingPlansPageState extends State<PricingPlansPage> {
  final AqsSubscriptionService _subscriptionService =
      AqsSubscriptionService();

  Stream<AqsSubscription?>? _subscriptionStream;
  bool yearly = false;
  bool _startingCheckout = false;
  final _testingActivation = TestingSubscriptionActivationService();

  @override
  void initState() {
    super.initState();
    yearly = widget.initialYearly;
    final user = FirebaseAuth.instance.currentUser;
    _subscriptionStream =
        user == null ? null : _subscriptionService.watch(user.uid);

    final requestedPlanId = widget.initialPlanId?.trim().toLowerCase();

    if (requestedPlanId != null && requestedPlanId != 'free') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openRequestedPlan(requestedPlanId);
      });
    }
  }

  Future<void> _openRequestedPlan(String requestedPlanId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final subscription = await _subscriptionService.get(user.uid);

        if (_currentPlanId(subscription) == requestedPlanId) {
          return;
        }
      } catch (error) {
        debugPrint('Could not check the current subscription: $error');
      }
    }

    if (!mounted) {
      return;
    }

    for (final plan in pricingPlans) {
      if (plan.id == requestedPlanId) {
        await _selectPlan(plan);
        return;
      }
    }
  }

  String _currentPlanId(AqsSubscription? subscription) {
    if (subscription == null || !subscription.isActive) {
      return 'free';
    }

    final planId = subscription.planId.trim().toLowerCase();

    if (pricingPlans.any((plan) => plan.id == planId)) {
      return planId;
    }

    final productCode = subscription.productCode.trim().toUpperCase();

    for (final plan in pricingPlans) {
      if (plan.monthlyProductCode?.toUpperCase() == productCode ||
          plan.yearlyProductCode?.toUpperCase() == productCode) {
        return plan.id;
      }
    }

    return 'free';
  }

  String _formatMoney(num value) {
    if (value == 0) {
      return 'Free';
    }

    final raw = value.round().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < raw.length; i++) {
      final position = raw.length - i;

      buffer.write(raw[i]);

      if (position > 1 && position % 3 == 1) {
        buffer.write(',');
      }
    }

    return 'TZS ${buffer.toString()}';
  }

  Future<void> _selectPlan(PricingPlan plan) async {
    if (_startingCheckout) {
      return;
    }

    if (plan.id == 'free') {
      Get.back();
      return;
    }

    setState(() => _startingCheckout = true);
    try {
      await _testingActivation.activate(plan, yearly: yearly);
      if (!mounted) return;
      Get.snackbar(
        '${plan.name} activated',
        'Your testing subscription is active. No payment was required.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFECFDF3),
        colorText: const Color(0xFF027A48),
      );
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        'Could not activate plan',
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => _startingCheckout = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pricing Plans',
          style: TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 50),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                children: [
                  // =================================================
                  // HEADER
                  // =================================================
                  const Text(
                    'Choose the plan that fits your work',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF101828),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(height: 12),

                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 700),
                    child: Text(
                      'Start free and upgrade when you need more projects, '
                      'drawings, measurement tools, build-up rates and '
                      'collaboration features.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  Container(
                    constraints: const BoxConstraints(maxWidth: 760),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFAEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFEC84B)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_outlined, color: Color(0xFFB54708)),
                        SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Testing access: choose any plan for immediate access without payment.',
                            style: TextStyle(
                              color: Color(0xFF93370D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // =================================================
                  // MONTHLY / YEARLY SWITCH
                  // =================================================
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEAECF0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BillingPeriodButton(
                          label: 'Monthly',
                          selected: !yearly,
                          onTap: () {
                            setState(() {
                              yearly = false;
                            });
                          },
                        ),

                        _BillingPeriodButton(
                          label: 'Yearly',
                          selected: yearly,
                          badge: 'Save 2 months',
                          onTap: () {
                            setState(() {
                              yearly = true;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 34),

                  // =================================================
                  // PRICING CARDS
                  // =================================================
                  StreamBuilder<AqsSubscription?>(
                    stream: _subscriptionStream,
                    builder: (context, subscriptionSnapshot) {
                      final isLoading =
                          _subscriptionStream != null &&
                          subscriptionSnapshot.connectionState ==
                              ConnectionState.waiting;
                      final currentPlanId =
                          isLoading
                              ? null
                              : _currentPlanId(subscriptionSnapshot.data);

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth < 700
                                  ? 1
                                  : constraints.maxWidth < 1100
                                  ? 2
                                  : 4;

                          final cardWidth =
                              (constraints.maxWidth - ((columns - 1) * 16)) /
                              columns;

                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final plan in pricingPlans)
                                SizedBox(
                                  width: cardWidth,
                                  child: PricingPlanCard(
                                    plan: plan,
                                    yearly: yearly,
                                    priceText: _formatMoney(
                                      yearly
                                          ? plan.yearlyPrice
                                          : plan.monthlyPrice,
                                    ),
                                    isCurrentPlan: currentPlanId == plan.id,
                                    onSelect: () {
                                      _selectPlan(plan);
                                    },
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Prices are shown in Tanzanian Shillings (TZS).',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartingPaymentDialog extends StatelessWidget {
  const _StartingPaymentDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 18),
          Flexible(child: Text('Sending payment request...')),
        ],
      ),
    );
  }
}

class _PaymentRequestDialog extends StatefulWidget {
  const _PaymentRequestDialog({
    required this.plan,
    required this.yearly,
    required this.result,
    required this.errorMessage,
    required this.errorDetails,
    required this.onRetry,
  });

  final PricingPlan plan;
  final bool yearly;
  final AqsPaymentResult? result;
  final String? errorMessage;
  final String? errorDetails;
  final Future<void> Function() onRetry;

  @override
  State<_PaymentRequestDialog> createState() =>
      _PaymentRequestDialogState();
}

class _PaymentRequestDialogState extends State<_PaymentRequestDialog> {
  StreamSubscription<AqsSubscription?>? _subscriptionListener;
  Timer? _confirmationTimer;
  late bool _confirmed;
  bool _confirmationTimedOut = false;

  @override
  void initState() {
    super.initState();
    _confirmed = widget.result?.isSuccessful == true;

    final user = FirebaseAuth.instance.currentUser;
    final waiting = widget.errorMessage == null && !_confirmed;
    if (user != null && waiting) {
      _subscriptionListener = AqsSubscriptionService()
          .watch(user.uid)
          .listen(_handleSubscription);
      _confirmationTimer = Timer(const Duration(seconds: 90), () {
        if (!mounted || _confirmed) return;
        setState(() => _confirmationTimedOut = true);
        _subscriptionListener?.cancel();
      });
    }
  }

  void _handleSubscription(AqsSubscription? subscription) {
    if (!mounted || subscription == null || !subscription.isActive) return;

    final expectedProductCode =
        (widget.yearly
                ? widget.plan.yearlyProductCode
                : widget.plan.monthlyProductCode)
            ?.toUpperCase();
    final planMatches =
        subscription.planId.trim().toLowerCase() ==
        widget.plan.id.trim().toLowerCase();
    final productMatches =
        expectedProductCode != null &&
        subscription.productCode.trim().toUpperCase() == expectedProductCode;

    if (!planMatches && !productMatches) return;

    _confirmationTimer?.cancel();
    _subscriptionListener?.cancel();
    setState(() {
      _confirmed = true;
      _confirmationTimedOut = false;
    });
  }

  Future<void> _retryPayment() async {
    final retry = widget.onRetry;
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    await retry();
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _subscriptionListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = widget.errorMessage != null || widget.result == null;
    final successful = _confirmed;
    final waiting = !failed && !successful && !_confirmationTimedOut;
    final reference = widget.result?.applicationReference.trim() ?? '';
    final status = widget.result?.status.trim() ?? '';

    return AlertDialog(
      icon: Icon(
        failed
            ? Icons.error_outline_rounded
            : successful
            ? Icons.check_circle_outline_rounded
            : _confirmationTimedOut
            ? Icons.schedule_rounded
            : Icons.phone_android_rounded,
        size: 42,
        color:
            failed
                ? const Color(0xFFD92D20)
                : successful
                ? const Color(0xFF039855)
                : _confirmationTimedOut
                ? const Color(0xFFF79009)
                : const Color(0xFF155EEF),
      ),
      title: Text(
        failed
            ? 'Payment request failed'
            : successful
            ? 'Payment successful'
            : _confirmationTimedOut
            ? 'Awaiting payment confirmation'
            : 'Payment request sent',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failed
                  ? widget.errorMessage ??
                      'The payment request could not be started.'
                  : successful
                  ? '${widget.plan.name} is active on your AQS account.'
                  : _confirmationTimedOut
                  ? 'Confirmation is taking longer than expected. You may close this window; your plan will update automatically when QuickLipa confirms the payment.'
                  : 'Approve the mobile-money prompt on your phone. Your subscription will activate after payment is confirmed.',
              textAlign: TextAlign.center,
            ),
            if ((widget.errorDetails ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.errorDetails!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
            ],
            if (!failed && !successful) ...[
              const SizedBox(height: 18),
              if (waiting) const LinearProgressIndicator(minHeight: 5),
              if (reference.isNotEmpty || status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    if (reference.isNotEmpty) 'Reference: $reference',
                    if (status.isNotEmpty) 'Status: $status',
                  ].join('  •  '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (failed)
          TextButton.icon(
            onPressed: _retryPayment,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        if (successful && widget.result?.isSuccessful == true)
          TextButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder:
                    (_) => PaymentReceiptDialog(
                      result: widget.result!,
                      plan: widget.plan,
                      yearly: widget.yearly,
                    ),
              );
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View receipt'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(failed ? 'Close' : 'Done'),
        ),
      ],
    );
  }
}

class _BillingPeriodButton extends StatelessWidget {
  const _BillingPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF155EEF) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),

            if (badge != null) ...[
              const SizedBox(width: 7),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? Colors.white.withOpacity(.16)
                          : const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF027A48),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
