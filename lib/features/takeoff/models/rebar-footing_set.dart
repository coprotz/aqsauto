import 'package:aqs/features/takeoff/models/rebar_mark.dart';

class RebarFootingSet {
  final String rawMark;
  final RebarMark mark;
  final String direction; // 'horizontal' or 'vertical'
  final int footingCount;

  final double clearSpanM;
  final double embedEachEndM;
  final double extraLengthM;

  final double barLengthM;
  final double totalLengthPerFootingM;
  final double totalLengthAllFootingsM;

  final double unitWeightKgPerM;
  final double totalWeightPerFootingKg;
  final double totalWeightAllFootingsKg;

  RebarFootingSet({
    required this.rawMark,
    required this.mark,
    required this.direction,
    required this.footingCount,
    required this.clearSpanM,
    required this.embedEachEndM,
    required this.extraLengthM,
    required this.barLengthM,
    required this.totalLengthPerFootingM,
    required this.totalLengthAllFootingsM,
    required this.unitWeightKgPerM,
    required this.totalWeightPerFootingKg,
    required this.totalWeightAllFootingsKg,
  });
}
