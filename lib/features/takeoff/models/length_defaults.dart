class LengthDefaults {
  final String unit; // 'm' or 'm2'
  final double? heightM; // used when unit=='m2'
  final List<Map<String, String>> rows; // {label, boqCode, boqDescription}

  LengthDefaults({
    required this.unit,
    required this.heightM,
    required this.rows,
  });

  Map<String, dynamic> toJson() => {
    'unit': unit,
    'heightM': heightM,
    'rows': rows,
  };

  static LengthDefaults fromJson(Map<String, dynamic> j) => LengthDefaults(
    unit: (j['unit'] ?? 'm').toString(),
    heightM: (j['heightM'] is num) ? (j['heightM'] as num).toDouble() : null,
    rows:
        ((j['rows'] ?? const []) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList(),
  );
}
