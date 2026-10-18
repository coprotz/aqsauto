class SlabExtraRebarSegmentDraft {
  SlabExtraRebarSegmentDraft({
    required this.rawMark,
    required this.clearLengthM,
    required this.embedEachEndM,
    required this.extraLengthM,
    required this.segmentCount,
    required this.boqCode,
    required this.note,
    required this.barsPerSegment,
    required this.diameterMm,
    required this.barLengthM,
    required this.totalBars,
    required this.totalLengthM,
    required this.totalWeightKg,
    required this.unitWeightKgPerM,
  });

  final String rawMark;
  final double clearLengthM;
  final double embedEachEndM;
  final double extraLengthM;
  final int segmentCount;
  final String boqCode;
  final String note;

  final int barsPerSegment;
  final int diameterMm;

  final double barLengthM;
  final int totalBars;
  final double totalLengthM;
  final double totalWeightKg;
  final double unitWeightKgPerM;
}
