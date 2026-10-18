class PresetChoice {
  final String label;
  final String boqCode;
  final String unit;
  final double? heightM;
  final String measureType; // 👈 new

  PresetChoice({
    required this.label,
    required this.boqCode,
    required this.unit,
    required this.measureType,
    this.heightM,
  });

  String get key => '$label|$boqCode|$unit';
}
