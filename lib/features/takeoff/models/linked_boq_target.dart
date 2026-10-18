import 'package:aqs/features/boq/models/boq_pick.dart';

class LinkedBoqTarget {
  final BoqPick boq;
  final double factor; // derived = source * factor + offset
  final double offset;

  const LinkedBoqTarget({
    required this.boq,
    this.factor = 1.0,
    this.offset = 0.0,
  });

  LinkedBoqTarget copyWith({BoqPick? boq, double? factor, double? offset}) {
    return LinkedBoqTarget(
      boq: boq ?? this.boq,
      factor: factor ?? this.factor,
      offset: offset ?? this.offset,
    );
  }
}
