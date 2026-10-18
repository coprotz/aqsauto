import 'package:aqs/features/pricing/data/pricing_plans.dart';
import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:aqs/features/pricing/widgets/pricing_plan_card.dart';
import 'package:flutter/material.dart';

class PricingPlansView extends StatefulWidget {
  const PricingPlansView({
    super.key,
    this.showCurrentPlan = false,
    this.currentPlanId,
    this.onSelectPlan,
  });

  final bool showCurrentPlan;
  final String? currentPlanId;
  final ValueChanged<String>? onSelectPlan;

  @override
  State<PricingPlansView> createState() => _PricingPlansViewState();
}

class _PricingPlansViewState extends State<PricingPlansView> {
  bool yearly = false;

  String _formatMoney(num value) {
    if (value == 0) return 'Free';

    final raw = value.round().toString();

    final result = raw.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );

    return 'TZS $result';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // =========================================
        // MONTHLY / YEARLY
        // =========================================
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
              _PricingPeriodButton(
                label: 'Monthly',
                selected: !yearly,
                onTap: () {
                  setState(() {
                    yearly = false;
                  });
                },
              ),

              _PricingPeriodButton(
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

        // =========================================
        // PLANS
        // =========================================
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth < 700
                    ? 1
                    : constraints.maxWidth < 1100
                    ? 2
                    : 4;

            final cardWidth =
                (constraints.maxWidth - ((columns - 1) * 16)) / columns;

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
                        yearly ? plan.yearlyPrice : plan.monthlyPrice,
                      ),

                      isCurrentPlan:
                          widget.showCurrentPlan &&
                          widget.currentPlanId == plan.id,

                      onSelect: () {
                        widget.onSelectPlan?.call(plan.id);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PricingPeriodButton extends StatelessWidget {
  const _PricingPeriodButton({
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
                          ? Colors.white.withOpacity(.17)
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
