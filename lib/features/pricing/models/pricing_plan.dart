class PricingPlan {
  const PricingPlan({
    required this.id,
    required this.name,

    required this.monthlyProductCode,
    required this.yearlyProductCode,

    required this.monthlyPrice,
    required this.yearlyPrice,

    required this.description,
    required this.badge,
    required this.projects,
    // required this.rates,
    required this.drawings,
    required this.users,
    required this.features,
    required this.highlight,
    required this.buildUpRates,
  });

  final String id;
  final String name;

  final String? monthlyProductCode;
  final String? yearlyProductCode;

  final int monthlyPrice;
  final int yearlyPrice;

  final String buildUpRates;

  final String description;
  final String badge;

  final String projects;
  // final String rates;
  final String drawings;
  final String users;

  final List<String> features;

  final bool highlight;

  String productCodeFor({required bool yearly}) {
    return yearly ? yearlyProductCode ?? '' : monthlyProductCode ?? '';
  }

  int priceFor({required bool yearly}) {
    return yearly ? yearlyPrice : monthlyPrice;
  }
}
