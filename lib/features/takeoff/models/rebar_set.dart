import 'package:aqs/features/takeoff/models/rebar_mark.dart';

class RebarSet {
  final String rawMark;
  final RebarMark mark;
  final String direction; // 'horizontal'/'vertical'
  final double clearSpanM;
  final double embedEachEndM;
  final double extraLengthM;

  final String? boqCode;
  final String? boqDescription;

  final double barLengthM;
  final double totalLengthM;
  final double unitWeightKgPerM;
  final double totalWeightKg;

  RebarSet({
    required this.rawMark,
    required this.mark,
    required this.direction,
    required this.clearSpanM,
    required this.embedEachEndM,
    required this.extraLengthM,
    required this.barLengthM,
    required this.totalLengthM,
    required this.unitWeightKgPerM,
    required this.totalWeightKg,
    this.boqCode,
    this.boqDescription,
  });

  Map<String, dynamic> toMap() => {
    'rawMark': rawMark,
    'direction': direction,
    'clearSpanM': clearSpanM,
    'embedEachEndM': embedEachEndM,
    'extraLengthM': extraLengthM,
    'barLengthM': barLengthM,
    'totalLengthM': totalLengthM,
    'unitWeightKgPerM': unitWeightKgPerM,
    'totalWeightKg': totalWeightKg,
    'boqCode': boqCode,
    'boqDescription': boqDescription,
    'mark': mark.toMap(),
  };

  static double _num(dynamic v, double fb) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fb;
  }

  factory RebarSet.fromMap(Map<String, dynamic> m) {
    return RebarSet(
      rawMark: (m['rawMark'] ?? '').toString(),
      direction: (m['direction'] ?? '').toString(),
      clearSpanM: _num(m['clearSpanM'], 0.0),
      embedEachEndM: _num(m['embedEachEndM'], 0.0),
      extraLengthM: _num(m['extraLengthM'], 0.0),
      barLengthM: _num(m['barLengthM'], 0.0),
      totalLengthM: _num(m['totalLengthM'], 0.0),
      unitWeightKgPerM: _num(m['unitWeightKgPerM'], 0.0),
      totalWeightKg: _num(m['totalWeightKg'], 0.0),
      boqCode:
          (m['boqCode'] ?? '').toString().trim().isEmpty
              ? null
              : (m['boqCode'] ?? '').toString().trim(),
      boqDescription:
          (m['boqDescription'] ?? '').toString().trim().isEmpty
              ? null
              : (m['boqDescription'] ?? '').toString().trim(),
      mark: RebarMark.fromMap(Map<String, dynamic>.from(m['mark'] ?? {})),
    );
  }
}
// class RebarSet {
//   final String rawMark;
//   final RebarMark mark;
//   final String direction; // 'horizontal'/'vertical'
//   final double clearSpanM;
//   final double embedEachEndM;
//   final double extraLengthM;
//   final String? boqCode;
//   final String? boqDescription;

//   final double barLengthM;
//   final double totalLengthM;
//   final double unitWeightKgPerM;
//   final double totalWeightKg;

//   RebarSet({
//     required this.rawMark,
//     required this.mark,
//     required this.direction,
//     required this.clearSpanM,
//     required this.embedEachEndM,
//     required this.extraLengthM,
//     required this.barLengthM,
//     required this.totalLengthM,
//     required this.unitWeightKgPerM,
//     required this.totalWeightKg,
//     this.boqCode,
//     this.boqDescription,
//   });

//   Map<String, dynamic> toMap() => {
//     'rawMark': rawMark,
//     'direction': direction,
//     'clearSpanM': clearSpanM,
//     'embedEachEndM': embedEachEndM,
//     'extraLengthM': extraLengthM,
//     'barLengthM': barLengthM,
//     'totalLengthM': totalLengthM,
//     'unitWeightKgPerM': unitWeightKgPerM,
//     'totalWeightKg': totalWeightKg,
//     'mark': mark.toMap(), // ✅ also add toMap to RebarMark (below)
//   };

//   static double _num(dynamic v, double fb) {
//     if (v is num) return v.toDouble();
//     return double.tryParse('${v ?? ''}') ?? fb;
//   }

//   factory RebarSet.fromMap(Map<String, dynamic> m) {
//     return RebarSet(
//       rawMark: (m['rawMark'] ?? '').toString(),
//       direction: (m['direction'] ?? '').toString(),
//       clearSpanM: _num(m['clearSpanM'], 0.0),
//       embedEachEndM: _num(m['embedEachEndM'], 0.0),
//       extraLengthM: _num(m['extraLengthM'], 0.0),
//       barLengthM: _num(m['barLengthM'], 0.0),
//       totalLengthM: _num(m['totalLengthM'], 0.0),
//       unitWeightKgPerM: _num(m['unitWeightKgPerM'], 0.0),
//       totalWeightKg: _num(m['totalWeightKg'], 0.0),
//       mark: RebarMark.fromMap(Map<String, dynamic>.from(m['mark'] ?? {})),
//     );
//   }
// }
