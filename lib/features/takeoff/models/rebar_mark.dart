class RebarMark {
  final int quantity;
  final String? barType; // e.g. Y16
  final int diameterMm; // e.g. 16
  final String? shape;
  final double? spacingM;
  final String? barNo;

  final int? spacingMm; // e.g. 150
  final String? layer; // e.g. T1/B1

  RebarMark({
    required this.quantity,
    this.barType,
    required this.diameterMm,
    this.spacingMm,
    this.spacingM,
    this.layer,
    this.shape,
    this.barNo,
  });

  Map<String, dynamic> toMap() => {
    'quantity': quantity,
    'barType': barType,
    'diameterMm': diameterMm,
    'barNo': barNo,
    'spacingM': spacingM,
    'spacingMm': spacingMm,
    'layer': layer,
    'shape': shape,
  };

  static double _num(dynamic v, double fb) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fb;
  }

  static int _int(dynamic v, int fb) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? fb;
  }

  factory RebarMark.fromMap(Map<String, dynamic> m) => RebarMark(
    barType: (m['barType'] ?? '').toString(),
    quantity: _int(m['quantity'], 0),
    diameterMm: _int(m['diameterMm'], 0),
    barNo:
        (m['barNo'] ?? '').toString().isEmpty
            ? null
            : (m['barNo'] ?? '').toString(),
    spacingM: m['spacingM'] == null ? null : _num(m['spacingM'], 0.0),
    spacingMm: m['spacingMm'] == null ? null : _int(m['spacingMm'], 0),
    layer:
        (m['layer'] ?? '').toString().isEmpty
            ? null
            : (m['layer'] ?? '').toString(),
    shape:
        (m['shape'] ?? '').toString().isEmpty
            ? null
            : (m['shape'] ?? '').toString(),
  );

  bool get hasSpacing => spacingMm != null;

  factory RebarMark.parse(String raw) {
    final mark = raw.replaceAll(' ', '');
    final parts = mark.split('-');

    if (parts.isEmpty || parts[0].trim().isEmpty) {
      throw FormatException('Empty rebar mark: "$raw"');
    }

    final p1 = parts[0]; // "12Y16"

    final m1 = RegExp(r'^(\d+)([A-Za-z]\d+)$').firstMatch(p1);
    if (m1 == null) {
      throw FormatException('Cannot parse quantity/type from "$p1"');
    }
    final quantity = int.parse(m1.group(1)!);
    final barType = m1.group(2)!.toUpperCase(); // Y16, R10...

    final diaMatch = RegExp(r'(\d+)$').firstMatch(barType);
    if (diaMatch == null) {
      throw FormatException('Cannot parse diameter from "$barType"');
    }
    final diameterMm = int.parse(diaMatch.group(1)!);

    int? spacingMm;
    String? layer;

    // Spacing and an optional layer are read from the third part. Engineering
    // drawings commonly use both `8Y16-13-200` and `8Y16-13-200T1`.
    if (parts.length >= 3) {
      final p3 = parts[2]; // "150B1" or "200T1"
      final m3 = RegExp(r'^(\d+)([TBtb]\d+)?$').firstMatch(p3);
      if (m3 == null) {
        throw FormatException('Cannot parse spacing/layer from "$p3"');
      }
      spacingMm = int.parse(m3.group(1)!);
      layer = m3.group(2)?.toUpperCase();
    }

    return RebarMark(
      quantity: quantity,
      barType: barType,
      diameterMm: diameterMm,
      spacingMm: spacingMm,
      layer: layer,
    );
  }
}
