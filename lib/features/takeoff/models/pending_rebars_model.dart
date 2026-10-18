class PendingMainBar {
  PendingMainBar({
    required this.rawMark,
    required this.boqCode,
    required this.embedEachEndM,
    required this.extraM,
    required this.note,
  });

  String rawMark; // e.g. 8Y16
  String boqCode;
  double embedEachEndM;
  double extraM;
  String note;
}

class PendingRing {
  PendingRing({
    required this.rawLabel,
    required this.boqCode,
    required this.diaMm,
    required this.spacingMm,
    required this.countOverride,
    required this.coverM,
    required this.hookM,
    required this.note,
  });

  String rawLabel; // e.g. R10-150
  String boqCode;
  int diaMm;
  int spacingMm; // 0 if using countOverride
  int countOverride; // 0 means auto by spacing
  double coverM;
  double hookM;
  String note;
}
