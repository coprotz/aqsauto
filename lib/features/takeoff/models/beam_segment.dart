import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

@immutable
class BeamSegment {
  final String id;
  final String beamName; // GB01, GB02...
  final String concreteBoqCode;
  final String sideFormworkBoqCode;
  final String soffitFormworkBoqCode;

  /// Points in image/canvas coordinates (not meters)
  final Offset p1;
  final Offset p2;

  /// Computed
  final double lengthM;
  final double concreteVolM3;
  final double formworkAreaM2;

  const BeamSegment({
    required this.id,
    required this.beamName,
    required this.concreteBoqCode,
    required this.soffitFormworkBoqCode,
    required this.sideFormworkBoqCode,
    required this.p1,
    required this.p2,
    required this.lengthM,
    required this.concreteVolM3,
    required this.formworkAreaM2,
  });

  factory BeamSegment.create({
    required String beamName,
    required String concreteBoqCode,
    required String sideFormworkBoqCode,
    required String soffitFormworkBoqCode,
    required Offset p1,
    required Offset p2,
    required double lengthM,
    required double concreteVolM3,
    required double formworkAreaM2,
  }) {
    return BeamSegment(
      id: const Uuid().v4(),
      beamName: beamName,
      concreteBoqCode: concreteBoqCode,
      sideFormworkBoqCode: sideFormworkBoqCode,
      soffitFormworkBoqCode: soffitFormworkBoqCode,
      p1: p1,
      p2: p2,
      lengthM: lengthM,
      concreteVolM3: concreteVolM3,
      formworkAreaM2: formworkAreaM2,
    );
  }
}

class BeamGroupSummary {
  final String beamName;
  final String concreteBoqCode;
  final String sideFormworkBoqCode;
  final String soffitFormworkBoqCode;

  final int count;
  final double totalLengthM;
  final double totalConcreteM3;
  final double totalFormworkM2;

  const BeamGroupSummary({
    required this.beamName,
    required this.concreteBoqCode,
    required this.sideFormworkBoqCode,
    required this.soffitFormworkBoqCode,
    required this.count,
    required this.totalLengthM,
    required this.totalConcreteM3,
    required this.totalFormworkM2,
  });
}
