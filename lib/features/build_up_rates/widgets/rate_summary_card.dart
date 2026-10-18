import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/build_up_rates/controllers/rate_builder_controller.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class RateSummaryCard extends StatelessWidget {
  const RateSummaryCard({super.key, required this.controller});
  final RateBuilderController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final result = controller.calculation;
    final money = NumberFormat('#,##0.00');
    Widget row(String label, double value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                color: AqsColors.text,
              ),
            ),
          ),
          Text(
            '${controller.currency.value} ${money.format(value)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              color: strong ? AqsColors.ink : AqsColors.text,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rate Summary',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AqsColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (final type in RateComponentType.values)
            row(type.label, result.totals[type] ?? 0),
          const Divider(height: 24),
          row('Direct Cost', result.directCost, strong: true),
          _PercentField(
            label: 'Overheads %',
            value: controller.overheadsPercent.value,
            onChanged: (value) => controller.overheadsPercent.value = value,
          ),
          row('Overheads', result.overheadsAmount),
          row('Subtotal', result.subtotal, strong: true),
          _PercentField(
            label: 'Profit %',
            value: controller.profitPercent.value,
            onChanged: (value) => controller.profitPercent.value = value,
          ),
          row('Profit', result.profitAmount),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BUILT-UP RATE',
                  style: TextStyle(
                    color: AqsColors.primary,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${controller.currency.value} ${money.format(result.finalRate)} / ${controller.unit.value}',
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  });
}

class _PercentField extends StatelessWidget {
  const _PercentField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: TextFormField(
      initialValue: '$value',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        isDense: true,
      ),
      onChanged: (text) => onChanged(double.tryParse(text) ?? 0),
    ),
  );
}
