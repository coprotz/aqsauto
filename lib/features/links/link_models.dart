import 'package:aqs/features/links/links.dart';

class QtySourceDoc {
  final QtySourceMode sourceKind;

  // one of these must be present depending on mode
  final String? docId; // when mode = doc (measurement doc id)
  final String? boqItemId; // when mode = boq (boq doc id)

  final String boqCode;
  final String boqDescription;
  final String unit;
  final double value;

  const QtySourceDoc({
    required this.sourceKind,
    required this.boqCode,
    required this.boqDescription,
    required this.unit,
    required this.value,
    this.docId,
    this.boqItemId,
  });

  factory QtySourceDoc.fromMeasured({
    required String docId,
    required String boqCode,
    required String boqDescription,
    required String unit,
    required double value,
  }) {
    return QtySourceDoc(
      sourceKind: QtySourceMode.measured,
      docId: docId,
      boqItemId: null,
      boqCode: boqCode,
      boqDescription: boqDescription,
      unit: unit,
      value: value,
    );
  }

  factory QtySourceDoc.fromBoqOverride({
    required String boqItemId,
    required String boqCode,
    required String boqDescription,
    required String unit,
    required double value,
  }) {
    return QtySourceDoc(
      sourceKind: QtySourceMode.boqOverride,
      docId: null,
      boqItemId: boqItemId,
      boqCode: boqCode,
      boqDescription: boqDescription,
      unit: unit,
      value: value,
    );
  }

  String get derivedFromMode =>
      sourceKind == QtySourceMode.measured ? 'Measured' : 'BOQ Override';

  String get sourceKey =>
      sourceKind == QtySourceMode.measured
          ? 'doc:${docId ?? ""}'
          : 'boq:${boqItemId ?? ""}';

  String get modeLabel =>
      sourceKind == QtySourceMode.boqOverride ? 'BOQ Override' : 'Measured';
}

class PickSourceOutcome {
  final QtySourceDoc? source;
  final String? error;

  const PickSourceOutcome._({this.source, this.error});
  factory PickSourceOutcome.ok(QtySourceDoc? s) =>
      PickSourceOutcome._(source: s);
  factory PickSourceOutcome.fail(String msg) => PickSourceOutcome._(error: msg);
}

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

class LinkSource {
  final LinkSourceMode mode;
  final String boqCode;
  final String boqDescription;
  final String unit;
  final double value;

  // identifiers
  final String? docId; // when mode=doc (measurement docId)
  final String? boqItemId; // when mode=boq (boq docId)

  const LinkSource._({
    required this.mode,
    required this.boqCode,
    required this.boqDescription,
    required this.unit,
    required this.value,
    this.docId,
    this.boqItemId,
  });

  factory LinkSource.doc({
    required String docId,
    required String boqCode,
    required String boqDescription,
    required String unit,
    required double value,
  }) {
    return LinkSource._(
      mode: LinkSourceMode.doc,
      docId: docId,
      boqItemId: null,
      boqCode: boqCode,
      boqDescription: boqDescription,
      unit: unit,
      value: value,
    );
  }

  factory LinkSource.boq({
    required String boqItemId,
    required String boqCode,
    required String boqDescription,
    required String unit,
    required double value,
  }) {
    return LinkSource._(
      mode: LinkSourceMode.boq,
      docId: null,
      boqItemId: boqItemId,
      boqCode: boqCode,
      boqDescription: boqDescription,
      unit: unit,
      value: value,
    );
  }

  String get sourceKey =>
      mode == LinkSourceMode.boq
          ? 'boq:${boqItemId ?? ""}'
          : 'doc:${docId ?? ""}';

  String get modeLabel =>
      mode == LinkSourceMode.boq ? 'BOQ Override' : 'Measured';
}
