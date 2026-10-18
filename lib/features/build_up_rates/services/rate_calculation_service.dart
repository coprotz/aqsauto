import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';

class RateCalculation {
  const RateCalculation({
    required this.totals,
    required this.directCost,
    required this.wasteAmount,
    required this.overheadsAmount,
    required this.subtotal,
    required this.profitAmount,
    required this.finalRate,
  });
  final Map<RateComponentType, double> totals;
  final double directCost;
  final double wasteAmount;
  final double overheadsAmount;
  final double subtotal;
  final double profitAmount;
  final double finalRate;
}

class RateCalculationService {
  const RateCalculationService();

  RateCalculation calculate(
    List<RateComponent> components, {
    required double overheadsPercent,
    required double profitPercent,
  }) {
    final totals = {for (final type in RateComponentType.values) type: 0.0};
    var waste = 0.0;
    for (final component in components) {
      totals[component.type] = totals[component.type]! + component.amount;
      waste += component.wasteAmount;
    }
    final direct = totals.values.fold<double>(0, (sum, value) => sum + value);
    final overheads = direct * _safePercent(overheadsPercent) / 100;
    final subtotal = direct + overheads;
    final profit = subtotal * _safePercent(profitPercent) / 100;
    return RateCalculation(
      totals: totals,
      directCost: direct,
      wasteAmount: waste,
      overheadsAmount: overheads,
      subtotal: subtotal,
      profitAmount: profit,
      finalRate: subtotal + profit,
    );
  }

  double _safePercent(double value) => value.isFinite && value >= 0 ? value : 0;
}
