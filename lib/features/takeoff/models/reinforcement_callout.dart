class ReinforcementCallout {
  const ReinforcementCallout({
    required this.raw,
    required this.quantity,
    required this.diameterMm,
    required this.barMark,
    required this.spacingMm,
    required this.layer,
  });

  final String raw;
  final int quantity;
  final double diameterMm;
  final String barMark;
  final double spacingMm;
  final String layer;

  /// Standard reinforcement theoretical mass:
  /// kg/m = d² / 162
  double get kgPerM => (diameterMm * diameterMm) / 162.0;

  double totalLengthM(double barLengthM) {
    return quantity * barLengthM;
  }

  double totalWeightKg(double barLengthM) {
    return totalLengthM(barLengthM) * kgPerM;
  }

  String get diameterLabel => 'Y${diameterMm.toStringAsFixed(0)}';

  static ReinforcementCallout? tryParse(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('–', '-')
        .replaceAll('—', '-');

    final expression = RegExp(
      r'^(\d+)Y(\d+(?:\.\d+)?)-([A-Z0-9]+)-(\d+(?:\.\d+)?)([TB]\d+)$',
    );

    final match = expression.firstMatch(cleaned);

    if (match == null) return null;

    return ReinforcementCallout(
      raw: input,
      quantity: int.parse(match.group(1)!),
      diameterMm: double.parse(match.group(2)!),
      barMark: match.group(3)!,
      spacingMm: double.parse(match.group(4)!),
      layer: match.group(5)!,
    );
  }
}
