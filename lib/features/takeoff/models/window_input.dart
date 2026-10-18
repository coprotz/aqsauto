import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/foundation.dart';

@immutable
class WindowInput {
  String openingKey;
  final String name;
  final double widthM;
  final double heightM;
  final int qty;

  // existing
  final String boqCode;

  final String scope; // ✅ NEW

  // ✅ NEW: boq doc id for sync
  final String boqItemId;

  // grill (optional)
  final bool includeGrill;
  final String boqGrill;
  final String boqGrillId; // ✅ NEW

  WindowInput({
    required this.openingKey,
    required this.name,
    required this.widthM,
    required this.heightM,
    required this.qty,
    required this.scope,
    this.boqCode = '',
    this.boqItemId = '',
    this.includeGrill = false,
    this.boqGrill = '',
    this.boqGrillId = '',
  });

  WindowInput copyWith({
    String? openingKey,
    String? name,
    double? widthM,
    double? heightM,
    int? qty,
    String? boqCode,
    String? boqItemId,
    bool? includeGrill,
    String? boqGrill,
    String? boqGrillId,
  }) {
    return WindowInput(
      openingKey: openingKey ?? this.openingKey,
      name: name ?? this.name,
      widthM: widthM ?? this.widthM,
      heightM: heightM ?? this.heightM,
      qty: qty ?? this.qty,
      scope: scope ?? this.scope,
      boqCode: boqCode ?? this.boqCode,
      boqItemId: boqItemId ?? this.boqItemId,
      includeGrill: includeGrill ?? this.includeGrill,
      boqGrill: boqGrill ?? this.boqGrill,
      boqGrillId: boqGrillId ?? this.boqGrillId,
    );
  }
}
