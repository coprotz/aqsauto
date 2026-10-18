// class BeamTypeTotals {
//   final String beamType;
//   final int beamCount;

//   final double totalLengthM;

//   final double concreteM3;
//   final double sideFormworkM2;
//   final double soffitFormworkM2;

//   final double rebarMainWeightKg;
//   final double rebarMainLengthM;

//   final double rebarSegWeightKg;
//   final double rebarSegLengthM;

//   final double rebarStirrupsWeightKg;
//   final double rebarStirrupsLengthM;

//   const BeamTypeTotals({
//     required this.beamType,
//     required this.beamCount,
//     required this.totalLengthM,
//     required this.concreteM3,
//     required this.sideFormworkM2,
//     required this.soffitFormworkM2,
//     required this.rebarMainWeightKg,
//     required this.rebarMainLengthM,
//     required this.rebarSegWeightKg,
//     required this.rebarSegLengthM,
//     required this.rebarStirrupsWeightKg,
//     required this.rebarStirrupsLengthM,
//   });

//   double get rebarTotalWeightKg =>
//       rebarMainWeightKg + rebarSegWeightKg + rebarStirrupsWeightKg;
//   double get rebarTotalLengthM =>
//       rebarMainLengthM + rebarSegLengthM + rebarStirrupsLengthM;
// }
class BeamTypeTotals {
  final String beamType; // ✅ add this

  final int beamsCount;
  final double totalLengthM;

  final double concreteM3;
  final double sideFormworkM2;
  final double soffitFormworkM2;

  final double rebarTotalWeightKg;
  final double rebarTotalLengthM;

  const BeamTypeTotals({
    required this.beamType,
    required this.beamsCount,
    required this.totalLengthM,
    required this.concreteM3,
    required this.sideFormworkM2,
    required this.soffitFormworkM2,
    required this.rebarTotalWeightKg,
    required this.rebarTotalLengthM,
  });
}
