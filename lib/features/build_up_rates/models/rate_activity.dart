import 'package:aqs/features/build_up_rates/models/rate_category.dart';

abstract final class RateActivities {
  static const Map<RateCategory, List<String>> byCategory = {
    RateCategory.walling: [
      '150 mm block wall',
      '230 mm block wall',
      'Half-brick wall',
      'One-brick wall',
      'Stone walling',
    ],
    RateCategory.concrete: [
      'Class 15 concrete',
      'Class 20 concrete',
      'Class 25 concrete',
      'Class 30 concrete',
      'Class 35 concrete',
      'Class 40 concrete',
      'Reinforced concrete',
      'Reinforcement steel fixing',
      'Mass concrete',
    ],
    RateCategory.formwork: ['Sawn formwork to vertical sides of columns'],
    RateCategory.finishes: [
      'Internal plastering',
      'External rendering',
      'Wall tiles',
      'Floor tiles',
      'Ceiling finishes',
      'Decoration',
      'Emulsion painting',
      'Silk painting',
      'Weatherguard painting',
      'Oil painting',
      'Varnish painting',
      'Textured coating',
    ],
    RateCategory.flooring: [
      '25 mm cement-sand floor screed',
      'Cement-sand screed',
      'Ceramic floor tiles',
      'Porcelain floor tiles',
      'Terrazzo flooring',
      'Vinyl flooring',
      'Timber flooring',
      'Polished concrete',
    ],
    RateCategory.roofing: [
      'Corrugated roofing sheets',
      'Standing-seam roofing',
      'Clay roof tiles',
      'Concrete roof tiles',
      'Timber roof structure',
      'Steel roof structure',
      'Roof insulation',
      'Rainwater goods',
    ],
    RateCategory.earthworks: [
      'Site clearance',
      'Excavate vegetable soil',
      'Excavate trench not exceeding 1.5 m deep',
      'Excavate trench over 1.5 m but not exceeding 3 m deep',
      'Excavate trench over 3 m but not exceeding 4.5 m deep',
      'Return, fill and compact excavated material',
      'Imported backfill',
      'Hardcore filling',
      'Anti-termite treatment',
      'Dispose excavated material away from site',
    ],
    RateCategory.externalWorks: [
      'Concrete paving blocks',
      'Kerbs',
      'Road base',
      'Asphalt surfacing',
      'Stormwater drainage',
      'Fencing',
      'Landscaping',
    ],
    RateCategory.services: [
      'Cold-water pipework',
      'Hot-water pipework',
      'Soil and waste pipework',
      'Drainage pipework',
      'Sanitary fittings',
      'Electrical conduit',
      'Electrical wiring',
      'Lighting points',
      'Power points',
      'Fire-fighting installation',
      'Air-conditioning installation',
    ],
    RateCategory.custom: ['Other / user-defined activity'],
  };

  static List<String> forCategory(RateCategory category) =>
      byCategory[category] ?? const ['Other / user-defined activity'];

  static String defaultFor(RateCategory category) =>
      forCategory(category).first;
}
