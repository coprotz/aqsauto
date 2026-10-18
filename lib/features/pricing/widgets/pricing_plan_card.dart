import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:flutter/material.dart';

class PricingPlanCard extends StatelessWidget {
  const PricingPlanCard({
    required this.plan,
    required this.yearly,
    required this.priceText,
    required this.onSelect,
    this.isCurrentPlan = false,
  });

  final PricingPlan plan;
  final bool yearly;
  final String priceText;
  final VoidCallback onSelect;
  final bool isCurrentPlan;

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.highlight;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isCurrentPlan ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isCurrentPlan
                  ? const Color(0xFF12B76A)
                  : highlighted
                  ? const Color(0xFF155EEF)
                  : const Color(0xFFEAECF0),
          width: isCurrentPlan || highlighted ? 2 : 1,
        ),
        boxShadow:
            isCurrentPlan
                ? const [
                  BoxShadow(
                    color: Color(0x1A12B76A),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              if (isCurrentPlan)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Current plan',
                    style: TextStyle(
                      color: Color(0xFF027A48),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              else if (plan.badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        highlighted
                            ? const Color(0xFFEFF4FF)
                            : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    plan.badge,
                    style: TextStyle(
                      color:
                          highlighted
                              ? const Color(0xFF155EEF)
                              : const Color(0xFF475467),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            priceText,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),

          if (plan.id != 'free')
            Text(
              yearly ? '/ year' : '/ month',
              style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),

          const SizedBox(height: 16),

          Text(
            plan.description,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          _PlanMeta(icon: Icons.folder_outlined, text: plan.projects),

          _PlanMeta(icon: Icons.image_outlined, text: plan.drawings),

          _PlanMeta(icon: Icons.person_outline, text: plan.users),

          _PlanMeta(icon: Icons.calculate_outlined, text: plan.buildUpRates),

          const SizedBox(height: 16),

          const Divider(),

          const SizedBox(height: 14),

          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: Color(0xFF12B76A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child:
                isCurrentPlan
                    ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Current plan'),
                    )
                    : highlighted
                    ? FilledButton(
                      onPressed: onSelect,
                      child: Text(
                        plan.id == 'free'
                            ? 'Start free'
                            : 'Choose ${plan.name}',
                      ),
                    )
                    : OutlinedButton(
                      onPressed: onSelect,
                      child: Text(
                        plan.id == 'free'
                            ? 'Start free'
                            : 'Choose ${plan.name}',
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _PlanMeta extends StatelessWidget {
  const _PlanMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF155EEF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF344054),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
