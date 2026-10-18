import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:aqs/features/build_up_rates/services/rate_calculation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates waste, overheads and profit deterministically', () {
    const service = RateCalculationService();
    const components = [
      RateComponent(
        componentId: 'material',
        type: RateComponentType.material,
        name: 'Blocks',
        unit: 'No.',
        quantity: 10,
        unitRate: 1000,
        wastePercent: 5,
      ),
      RateComponent(
        componentId: 'labour',
        type: RateComponentType.labour,
        name: 'Mason',
        unit: 'hr',
        quantity: 2,
        unitRate: 2500,
      ),
    ];

    final result = service.calculate(
      components,
      overheadsPercent: 10,
      profitPercent: 15,
    );

    expect(result.totals[RateComponentType.material], 10500);
    expect(result.totals[RateComponentType.labour], 5000);
    expect(result.wasteAmount, 500);
    expect(result.directCost, 15500);
    expect(result.overheadsAmount, 1550);
    expect(result.subtotal, 17050);
    expect(result.profitAmount, 2557.5);
    expect(result.finalRate, 19607.5);
  });
}
