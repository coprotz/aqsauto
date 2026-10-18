import 'package:aqs/features/build_up_rates/models/rate_category.dart';

abstract final class RateUnits {
  static const all = <String>[
    'bag',
    'm',
    'm²',
    'm³',
    'litre',
    'tonne',
    'kg',
    'g',
    'item',
    'pc',
    'No.',
    'pair',
    'set',
    'box',
    'pack',
    'roll',
    'sheet',
    'length',
    'hr',
    'day',
    'week',
    'trip',
    'load',
    'lot',
    'sum',
  ];

  static String defaultFor(RateComponentType type) => switch (type) {
    RateComponentType.material => 'bag',
    RateComponentType.labour => 'hr',
    RateComponentType.plant => 'hr',
    RateComponentType.transport => 'trip',
    RateComponentType.subcontract => 'sum',
    RateComponentType.other => 'item',
  };

  static List<String> including(String unit) =>
      unit.isEmpty || all.contains(unit) ? all : [unit, ...all];
}
