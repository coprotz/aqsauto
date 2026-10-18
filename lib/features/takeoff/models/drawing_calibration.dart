class DrawingCalibration {
  const DrawingCalibration({
    required this.pointAX,
    required this.pointAY,
    required this.pointBX,
    required this.pointBY,
    required this.sceneDistance,
    required this.knownDistance,
    required this.unit,
    required this.unitsPerSceneUnit,
    this.calibration,
  });

  final double pointAX;
  final double pointAY;

  final double pointBX;
  final double pointBY;

  /// Distance between calibration points
  /// in PDF scene coordinates.
  final double sceneDistance;
  final DrawingCalibration? calibration;

  /// Actual known real-world distance.
  ///
  /// We currently store this in millimetres.
  final double knownDistance;

  /// Canonical unit.
  ///
  /// Current value should normally be:
  /// mm
  final String unit;

  /// Number of real-world millimetres represented
  /// by one PDF scene unit.
  ///
  /// Example:
  ///
  /// 1 scene unit = 18.52 mm
  final double unitsPerSceneUnit;

  Map<String, dynamic> toMap() {
    return {
      'pointAX': pointAX,
      'pointAY': pointAY,
      'pointBX': pointBX,
      'pointBY': pointBY,
      'sceneDistance': sceneDistance,
      'knownDistance': knownDistance,
      'unit': unit,
      'unitsPerSceneUnit': unitsPerSceneUnit,
    };
  }

  factory DrawingCalibration.fromMap(Map<String, dynamic> data) {
    double readDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DrawingCalibration(
      pointAX: readDouble(data['pointAX']),

      pointAY: readDouble(data['pointAY']),

      pointBX: readDouble(data['pointBX']),

      pointBY: readDouble(data['pointBY']),

      sceneDistance: readDouble(data['sceneDistance']),

      knownDistance: readDouble(data['knownDistance']),

      unit: (data['unit'] ?? 'mm').toString(),

      unitsPerSceneUnit: readDouble(data['unitsPerSceneUnit']),
      calibration: null,
    );
  }

  DrawingCalibration copyWith({
    double? pointAX,
    double? pointAY,
    double? pointBX,
    double? pointBY,
    double? sceneDistance,
    double? knownDistance,
    String? unit,
    double? unitsPerSceneUnit,
  }) {
    return DrawingCalibration(
      pointAX: pointAX ?? this.pointAX,

      pointAY: pointAY ?? this.pointAY,

      pointBX: pointBX ?? this.pointBX,

      pointBY: pointBY ?? this.pointBY,

      sceneDistance: sceneDistance ?? this.sceneDistance,

      knownDistance: knownDistance ?? this.knownDistance,

      unit: unit ?? this.unit,

      unitsPerSceneUnit: unitsPerSceneUnit ?? this.unitsPerSceneUnit,
      calibration: null,
    );
  }
}
