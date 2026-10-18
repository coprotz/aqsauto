import 'dart:async';
import 'dart:js_interop';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/takeoff/controllers/poly_draw_controller.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/models/beam_type_total_model.dart';
import 'package:aqs/features/takeoff/models/iron_mongeries_model.dart';
import 'package:aqs/features/takeoff/models/length_defaults.dart';
import 'package:aqs/features/takeoff/models/linked_boq_target.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/rebar_mark.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

double rebarUnitWeightKgPerM(int diaMm) {
  switch (diaMm) {
    case 6:
      return 0.222;
    case 8:
      return 0.395;
    case 10:
      return 0.617;
    case 12:
      return 0.888;
    case 16:
      return 1.58;
    case 20:
      return 2.47;
    case 25:
      return 3.85;
    case 32:
      return 6.31;
    default:
      // generic formula ≈ 0.006165 * φ²
      return 0.006165 * diaMm * diaMm;
  }
}

double _polygonAreaPx(List<Offset> pts) {
  if (pts.length < 3) return 0.0;
  double sum = 0.0;
  for (int i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += (a.dx * b.dy) - (b.dx * a.dy);
  }
  return sum / 2.0; // signed
}

class AreaBoqTemplateRow {
  final String label;
  final String boqCode;
  final String boqDesc;

  AreaBoqTemplateRow({
    required this.label,
    required this.boqCode,
    required this.boqDesc,
  });

  Map<String, dynamic> toMap() => {
    'label': label,
    'boqCode': boqCode,
    'boqDesc': boqDesc,
  };

  static AreaBoqTemplateRow fromMap(Map<String, dynamic> m) =>
      AreaBoqTemplateRow(
        label: (m['label'] ?? '').toString(),
        boqCode: (m['boqCode'] ?? '').toString(),
        boqDesc: (m['boqDesc'] ?? '').toString(),
      );
}

class AreaTemplate {
  final bool isRoofCovering;
  final double roofAngleDeg;
  final List<AreaBoqTemplateRow> rows;

  // ✅ NEW
  final bool asVolume;
  final double depthM;

  AreaTemplate({
    required this.isRoofCovering,
    required this.roofAngleDeg,
    required this.rows,
    this.asVolume = false,
    this.depthM = 0.15,
  });

  Map<String, dynamic> toMap() => {
    'isRoofCovering': isRoofCovering,
    'roofAngleDeg': roofAngleDeg,
    'rows': rows.map((r) => r.toMap()).toList(),
    // ✅ NEW
    'asVolume': asVolume,
    'depthM': depthM,
  };

  factory AreaTemplate.fromMap(Map<String, dynamic> m) {
    double _num(dynamic v, double fb) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? fb;
    }

    final rowsRaw = (m['rows'] as List?) ?? const [];
    return AreaTemplate(
      isRoofCovering: (m['isRoofCovering'] == true),
      roofAngleDeg: _num(m['roofAngleDeg'], 30),
      rows:
          rowsRaw
              .whereType<Map>()
              .map(
                (x) => AreaBoqTemplateRow.fromMap(Map<String, dynamic>.from(x)),
              )
              .toList(),
      // ✅ NEW
      asVolume: (m['asVolume'] == true),
      depthM: _num(m['depthM'], 0.15),
    );
  }
}

class _AreaBoqRow {
  final TextEditingController labelCtrl;
  final TextEditingController boqCodeCtrl;
  final TextEditingController boqDescCtrl;

  _AreaBoqRow({
    required String label,
    required String boqCode,
    required String boqDesc,
  }) : labelCtrl = TextEditingController(text: label),
       boqCodeCtrl = TextEditingController(text: boqCode),
       boqDescCtrl = TextEditingController(text: boqDesc);

  void dispose() {
    labelCtrl.dispose();
    boqCodeCtrl.dispose();
    boqDescCtrl.dispose();
  }
}

BeamTypeTotals computeSameTypeTotals({
  required String beamType,
  required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  beamDocsByBeamId,

  // ✅ NEW: rebar saved/shared by beamType
  required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  rebarDocsByBeamType,
}) {
  double concreteM3 = 0;
  double sideFwM2 = 0;
  double soffitFwM2 = 0;
  double totalLenM = 0;

  double rebarWtKg = 0;
  double rebarLenM = 0;

  final seenBeamIds = <String>{};

  double asDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;

  // ----------------------------
  // A) totals by beamId (length + conc + formwork)
  // ----------------------------
  for (final entry in beamDocsByBeamId.entries) {
    final beamId = entry.key;
    final docs = entry.value;
    if (docs.isEmpty) continue;

    final first = docs.first.data();
    final bt = (first['beamType'] ?? '').toString().trim();
    if (bt != beamType) continue;

    if (!seenBeamIds.add(beamId)) continue;

    // length once per beam
    double len = 0;
    for (final d in docs) {
      final m = d.data();
      len = asDouble(m['beamLengthM'] ?? m['lengthM'] ?? m['spanM'] ?? 0);
      if (len > 0) break;
    }
    totalLenM += len;

    // sum conc + formwork
    for (final d in docs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString();

      if (type == 'beamConcrete') {
        concreteM3 += asDouble(m['value']);
      } else if (type == 'beamFormworkSide') {
        sideFwM2 += asDouble(m['value']);
      } else if (type == 'beamFormworkSoffit') {
        soffitFwM2 += asDouble(m['value']);
      }
    }
  }

  // ----------------------------
  // B) totals by beamType (REBARS shared across same type)
  // ----------------------------
  final rebarDocs = rebarDocsByBeamType[beamType] ?? const [];

  for (final d in rebarDocs) {
    final m = d.data();
    final type = (m['type'] ?? '').toString();

    if (type == 'rebarBeamMain' || type == 'rebarBeamMainSegment') {
      rebarLenM += asDouble(m['totalLengthAllBarsM'] ?? m['totalLengthM'] ?? 0);
      rebarWtKg += asDouble(m['totalWeightKg'] ?? m['value'] ?? 0);
    } else if (type == 'rebarBeamStirrups') {
      rebarLenM += asDouble(
        m['totalLengthAllStirrupsM'] ?? m['totalLengthM'] ?? 0,
      );
      rebarWtKg += asDouble(m['totalWeightKg'] ?? m['value'] ?? 0);
    }
  }

  return BeamTypeTotals(
    beamType: beamType,
    beamsCount: seenBeamIds.length,
    totalLengthM: totalLenM,
    concreteM3: concreteM3,
    sideFormworkM2: sideFwM2,
    soffitFormworkM2: soffitFwM2,
    rebarTotalWeightKg: rebarWtKg,
    rebarTotalLengthM: rebarLenM,
  );
}

class BeamLongRebarSet {
  final String rawMark; // e.g. 4Y16-01-150T1
  final RebarMark mark;
  final double clearSpanM;
  final double embedEachEndM;
  final double extraLengthM;
  final double barLengthM;
  final double totalLengthAllBeamsM;
  final double unitWeightKgPerM;
  final double totalWeightKg;
  final String boqCode; // 👈 separate BOQ per mark

  BeamLongRebarSet({
    required this.rawMark,
    required this.mark,
    required this.clearSpanM,
    required this.embedEachEndM,
    required this.extraLengthM,
    required this.barLengthM,
    required this.totalLengthAllBeamsM,
    required this.unitWeightKgPerM,
    required this.totalWeightKg,
    required this.boqCode,
  });
}

class BeamRingRebarSet {
  final String rawMark; // e.g. R8-@150
  final int diameterMm;
  final double spacingMm;
  final double clearSpanM;
  final double ringLengthM; // perimeter + hooks (m)
  final int ringsPerBeam;
  final int nBeams;
  final double totalLengthAllBeamsM;
  final double unitWeightKgPerM;
  final double totalWeightKg;
  final String boqCode;

  BeamRingRebarSet({
    required this.rawMark,
    required this.diameterMm,
    required this.spacingMm,
    required this.clearSpanM,
    required this.ringLengthM,
    required this.ringsPerBeam,
    required this.nBeams,
    required this.totalLengthAllBeamsM,
    required this.unitWeightKgPerM,
    required this.totalWeightKg,
    required this.boqCode,
  });
}

class MeasurementItemSelection {
  final String label;
  final String? boqCode; // null for composite types
  final String unit;
  final double? wallHeightM; // only for walling m²
  final String measureType; // e.g. 'walling', 'slabComposite', ...

  MeasurementItemSelection({
    required this.label,
    required this.unit,
    required this.measureType,
    this.boqCode,
    this.wallHeightM,
  });
}

String inferMeasureTypeFromLabel(String label) {
  final l = label.toLowerCase().trim();

  if (l.contains('slab') && l.contains('reinforcement')) {
    return 'slabRebarAi';
  }

  // 🔹 composites (keep these FIRST so they don't get captured by "wall" => walling)
  if (l.contains('slab') && l.contains('composite')) return 'compositeSlab';
  if (l.contains('stair') && l.contains('composite')) return 'compositeStair';
  if (l.contains('lift') && l.contains('shaft')) return 'liftShaft';
  if ((l.contains('underground') && l.contains('structure')) || l.contains('water tank') || l.contains('septic tank') || l.contains('manhole')) return 'undergroundStructure';
  if (l.contains('ramp') && l.contains('composite')) return 'compositeRamp';
  if (l.contains('roof') && l.contains('composite')) return 'compositeRoofing';
  if (l.contains('civi') && l.contains('work')) return 'civilWork';
  if (l.contains('openings') && l.contains('windowandwindow')) {
    return 'openings';
  }

  if (l.contains('retaining') && l.contains('composite')) {
    return 'compositeretainingWall';
  }
  if (l.contains('ceiling') && l.contains('ceilings')) {
    return 'ceiling';
  }
  if (l.contains('roofsheetingandtimber') && l.contains('rooftimber')) {
    return 'roofsheeting';
  }

  // ✅ ADD: foundation wall composite
  if ((l.contains('foundation') || l.contains('fdn')) &&
      l.contains('composite')) {
    return 'foundationWallComposite';
  }

  if (l.contains('footing') && l.contains('composite')) {
    return 'compositeFooting';
  }
  if (l.contains('roofingcomposite') && l.contains('steel')) {
    return 'compositeRoofing';
  }

  if (l.contains('beam') && l.contains('composite')) return 'compositeBeam';
  if (l.contains('truss') && l.contains('template')) return 'trussTemplate';

  // 🔹 column composite (you have it in UI list, but it wasn't mapped)
  if (l.contains('column') && l.contains('composite')) return 'compositeColumn';

  // 🔹 simple types
  // IMPORTANT: keep 'walling' after composite-wall checks above
  if (l.contains('wall')) return 'walling';
  if (l.contains('count')) return 'count';
  return l.replaceAll(' ', '');
}

TakeoffMode modeForMeasureType(String t) {
  final lower = t.trim().toLowerCase();

  // LENGTH-based types
  const lengthTypes = {
    'walling',
    'beam',
    'compositebeam',
    'compositeretainingwall',
    'civilwork',
    'trusstemlate',
    'compositestair',
    'compositeramp',
    'slabedge',
    'pipe',
    'count',
    'door', // if you measure door frames, etc. by length/no.
  };

  // AREA-based types
  const areaTypes = {
    'tiling',
    'plinth',
    'compositeslab',
    'slabcomposite',
    'compositefooting',
    'compositecolumn',
    'openings',
    'ceiling',
    'roofsheetingandtimber',

    'window', // if you measure window openings by m2
  };

  if (lengthTypes.contains(lower)) return TakeoffMode.measureLength;
  if (areaTypes.contains(lower)) return TakeoffMode.measureArea;

  // default
  return TakeoffMode.measureLength;
}

double metersPerPixelFromDrawing(Map<String, dynamic> d) {
  final ppuNum = d['pixelsPerUnit'];
  final ppu = (ppuNum is num) ? ppuNum.toDouble() : 0.0; // pixels per unit
  if (ppu <= 0) return 0.0;

  final unit = (d['unit'] ?? 'm').toString(); // your doc uses 'm'
  final metersPerUnit = switch (unit) {
    'm' => 1.0,
    'cm' => 0.01,
    'mm' => 0.001,
    _ => 1.0,
  };

  return metersPerUnit / ppu; // meters per pixel
}

String prettyUnit(String u) {
  switch (u) {
    case 'm2':
      return 'm²';
    case 'm3':
      return 'm³';
    default:
      return u;
  }
}

double distancePointToPolyline(
  Offset p,
  List<Offset> pts, {
  bool closed = true,
}) {
  if (pts.length < 2) return double.infinity;
  double best = double.infinity;

  for (int i = 0; i < pts.length - 1; i++) {
    best = math.min(best, distancePointToSegment(p, pts[i], pts[i + 1]));
  }
  if (closed) {
    best = math.min(best, distancePointToSegment(p, pts.last, pts.first));
  }
  return best;
}

double distancePointToSegment(Offset p, Offset a, Offset b) {
  final ap = p - a;
  final ab = b - a;
  final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (ab2 == 0) return (p - a).distance;

  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / ab2).clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

double polygonAreaAbs(List<Offset> pts) {
  if (pts.length < 3) return 0.0;
  double sum = 0.0;
  for (int i = 0; i < pts.length; i++) {
    final j = (i + 1) % pts.length;
    sum += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
  }
  return sum.abs() * 0.5;
}

Map<String, dynamic> parseBarsMark(String raw) {
  final m = RegExp(
    r'^\s*(\d+)\s*[Yy]\s*(\d+)(?:\s*-\s*([A-Za-z0-9]+))?\s*$',
  ).firstMatch(raw);

  if (m == null) throw FormatException('Use mark like 3Y12-ES1');

  return {
    'barsPerSegment': int.parse(m.group(1)!),
    'diameterMm': int.parse(m.group(2)!),
    'markCode': (m.group(3) ?? '').trim(),
  };
}

double unitWeightKgPerM(int diaMm) => 0.00617 * diaMm * diaMm;

class StrokeItem extends StatelessWidget {
  final String name;
  final double min;
  final double max;
  final bool active;

  const StrokeItem({
    required this.name,
    required this.min,
    required this.max,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(active ? Icons.check_circle : Icons.circle_outlined, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(name)),
        Text('${min.toStringAsFixed(1)}–${max.toStringAsFixed(1)}'),
      ],
    );
  }
}

bool _near(Offset a, Offset b, double r) => (a - b).distance <= r;

SegHandle hitTestHandle(Offset tap, MeasuredSegment seg, double r) {
  if (_near(tap, seg.p1, r)) return SegHandle.p1;
  if (_near(tap, seg.p2, r)) return SegHandle.p2;

  // midpoint for move
  final mid = Offset((seg.p1.dx + seg.p2.dx) / 2, (seg.p1.dy + seg.p2.dy) / 2);
  if (_near(tap, mid, r)) return SegHandle.move;

  // if close to line: treat as move
  if (distancePointToSegment(tap, seg.p1, seg.p2) <= r) return SegHandle.move;

  return SegHandle.none;
}

TakeoffMode defaultModeForMeasureType(String? type) {
  final lower = (type ?? '').trim().toLowerCase();

  // --- VIEW TYPES ---
  if (lower == 'view') return TakeoffMode.view;

  // --- SEGMENT/LENGTH TYPES ---
  if (lower == 'walling' ||
      lower == 'length' ||
      lower == 'count' ||
      lower == 'door' ||
      lower == 'beam' ||
      lower == 'compositebeam' ||
      lower == 'beamcomposite' ||
      lower == 'compositeroofing' ||
      lower == 'retainingwall' ||
      lower == 'compositeramp' ||
      lower == 'slabrebarai' ||
      lower == 'civilwork' ||
      lower == 'drainage' ||
      lower == 'compositestair' ||
      lower == 'liftshaft' ||
      lower == 'compositeretainingwall') {
    return TakeoffMode.measureLength;
  }

  // --- AREA/POLYGON TYPES ---
  if (lower == 'slabcomposite' ||
      lower == 'compositeslab' ||
      lower == 'area' ||
      lower == 'volume' ||
      lower == 'plinth' ||
      lower == 'groundpreparation' ||
      lower == 'tiling' ||
      lower == 'compositefooting' ||
      lower == 'footingcomposite' ||
      lower == 'ceiling' ||
      lower == 'openings' ||
      lower == 'roofsheetingandtimber' ||
      lower == 'roofsheeting' ||
      lower == 'pavement' ||
      lower == 'roofingsteel' ||
      lower == 'compositecolumn' ||
      lower == 'columncomposite' ||
      lower == 'concretebenchworktop') {
    return TakeoffMode.measureArea;
  }

  // fallback
  return TakeoffMode.measureLength;
}

double distanceInMeters(Offset a, Offset b, Map<String, dynamic> drawingData) {
  // Preferred if you already store pixelsPerUnit (pixels per meter)
  final ppu =
      (drawingData['pixelsPerUnit'] ?? drawingData['pixelsPerMeter'] ?? 0)
          .toDouble();
  if (ppu > 0) {
    final dx = (a.dx - b.dx);
    final dy = (a.dy - b.dy);
    final px = (dx * dx + dy * dy).sqrt(); // can't call sqrt without dart:math
    // We'll do manual:
  }

  // If you already have your own distanceInMeters(...) in controller/project,
  // REPLACE this whole function body with that call.
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  final distPx = (dx * dx + dy * dy);
  // fallback: if no calibration, return 0 to block saving
  final pixelsPerUnit = (drawingData['pixelsPerUnit'] ?? 0).toDouble();
  if (pixelsPerUnit <= 0) return 0.0;
  return (distPx).sqrt() / pixelsPerUnit;
}

extension _Sqrt on double {
  double sqrt() {
    // Newton method (avoid importing dart:math)
    if (this <= 0) return 0;
    double x = this;
    double y = 1;
    const double e = 0.0000001;
    while ((x - y).abs() > e) {
      x = (x + y) / 2;
      y = this / x;
    }
    return x;
  }
}

// String s(dynamic v) => (v ?? '').toString();

bool _isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

List<String> _parenTokens(String code) {
  return RegExp(r'\(([^)]+)\)')
      .allMatches(code)
      .map((m) => (m.group(1) ?? '').trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

String extractSectionCode(String boqCode) {
  final s0 = boqCode.trim();
  if (s0.isEmpty) return '';
  final idx = s0.indexOf('(');
  final head = (idx == -1) ? s0 : s0.substring(0, idx);
  final m = RegExp(r'^\d+(?:\.\d+)*').firstMatch(head.trim());
  return m?.group(0) ?? head.trim();
}

/// Prefer Firestore minorCode, else infer for patterns 3.7(i)(A)(i)
String inferMinorCodeFromBoqCode(String boqCode) {
  final toks = _parenTokens(boqCode);
  if (toks.length >= 2 && _isRoman(toks[0]) && _isLetter(toks[1])) {
    return toks[0].toLowerCase();
  }
  return '';
}

class BoqParts {
  final String section; // 3.7
  final String minor; // i (optional)
  final String main; // A/B/C
  final String sub; // i/ii/1/2 (optional)
  const BoqParts({
    required this.section,
    required this.minor,
    required this.main,
    required this.sub,
  });
}

BoqParts parseBoqCode(String code, {String? forcedMinorFromDb}) {
  final section = extractSectionCode(code);
  final toks = _parenTokens(code);

  // prefer DB minor, else infer from the code
  String minor = (forcedMinorFromDb ?? '').trim().toLowerCase();
  if (minor.isEmpty) {
    minor = inferMinorCodeFromBoqCode(code); // e.g. 3.7(i)(A)(i) -> i
  }

  String main = '';
  String sub = '';

  if (toks.isEmpty) {
    return BoqParts(section: section, minor: minor, main: main, sub: sub);
  }

  // ✅ CASE 1: Code has minor first: 3.7(i)(A) or 3.7(i)(C)(ii)
  // toks: [i, A] or [i, C, ii]
  // if minor exists and first token is roman -> treat token[1] as main
  if (minor.isNotEmpty &&
      toks.length >= 2 &&
      _isRoman(toks[0]) &&
      _isLetter(toks[1])) {
    main = toks[1].toUpperCase();
    if (toks.length >= 3) sub = toks[2].toLowerCase();
    return BoqParts(section: section, minor: minor, main: main, sub: sub);
  }

  // ✅ CASE 2: Normal (no minor): 3.1(B)(i)
  // toks: [B, i]
  if (_isLetter(toks[0])) {
    main = toks[0].toUpperCase();
    if (toks.length >= 2) sub = toks[1].toLowerCase();
    return BoqParts(section: section, minor: minor, main: main, sub: sub);
  }

  // Fallback (rare)
  main = toks[0];
  if (toks.length >= 2) sub = toks[1];
  return BoqParts(section: section, minor: minor, main: main, sub: sub);
}

String displayItemCodeFromParts(BoqParts p) {
  if (p.main.isEmpty) return '';
  return p.sub.isEmpty ? p.main : '${p.main}.${p.sub}';
}

int indentLevelFromParts(BoqParts p) {
  // no minor: A => 1, B.i => 2
  if (p.minor.isEmpty) return p.sub.isEmpty ? 1 : 2;
  // with minor: (i) A => 2, (i) A.i => 3
  return p.sub.isEmpty ? 2 : 3;
}

class BoqCodeParts {
  final String section; // 3.7
  final String minor; // i (optional)
  final String main; // C or A/B...
  final String sub; // ii (optional)
  BoqCodeParts({
    required this.section,
    required this.minor,
    required this.main,
    required this.sub,
  });
}

bool isRoman(String s) =>
    RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(s.trim());

bool isLetter(String s) => RegExp(r'^[A-Za-z]$').hasMatch(s.trim());

List<String> parenTokens(String code) {
  return RegExp(r'\(([^)]+)\)')
      .allMatches(code)
      .map((m) => (m.group(1) ?? '').trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

String displayItemCode(BoqCodeParts p) {
  if (p.main.isEmpty) return '';
  return p.sub.isEmpty ? p.main : '${p.main}.${p.sub}'; // A or A.i
}

int indentLevel(BoqCodeParts p) {
  // No minor group: A => 1, B.i => 2
  if (p.minor.isEmpty) return p.sub.isEmpty ? 1 : 2;

  // With minor group: (i) A => 2, (i) A.i => 3
  return p.sub.isEmpty ? 2 : 3;
}

int _safeInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString()) ?? fallback;
}

List<int> _sectionParts(String section) {
  // "3.7" -> [3,7], "10.2.1" -> [10,2,1]
  return section.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
}

int _cmpListInt(List<int> a, List<int> b) {
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final ai = i < a.length ? a[i] : 0;
    final bi = i < b.length ? b[i] : 0;
    if (ai != bi) return ai.compareTo(bi);
  }
  return 0;
}

int _letterRank(String x) {
  final t = x.trim().toUpperCase();
  if (t.isEmpty) return 999;
  final c = t.codeUnitAt(0);
  if (c >= 65 && c <= 90) return c - 65; // A=0
  return 999;
}

int _romanToInt(String roman) {
  final s = roman.trim().toUpperCase();
  if (s.isEmpty) return 999;

  const map = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};

  int total = 0;
  int prev = 0;
  for (var i = s.length - 1; i >= 0; i--) {
    final v = map[s[i]] ?? 0;
    if (v < prev)
      total -= v;
    else
      total += v;
    prev = v;
  }
  return total == 0 ? 999 : total;
}

int _subRank(String sub) {
  final t = sub.trim();
  if (t.isEmpty) return 999;

  // roman?
  if (_isRoman(t)) return _romanToInt(t);

  // numeric?
  final n = int.tryParse(t);
  if (n != null) return n;

  // else fallback
  return 999;
}

int compareBoqDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aStruct = _s(a['structure']).trim().toLowerCase();
  final bStruct = _s(b['structure']).trim().toLowerCase();
  final cs = aStruct.compareTo(bStruct);
  if (cs != 0) return cs;

  final aBill = _safeInt(a['billCode'], 999);
  final bBill = _safeInt(b['billCode'], 999);
  if (aBill != bBill) return aBill.compareTo(bBill);

  final aCode = _s(a['boqCode']).trim();
  final bCode = _s(b['boqCode']).trim();

  final aMinor = _s(a['minorCode']).trim().toLowerCase();
  final bMinor = _s(b['minorCode']).trim().toLowerCase();

  final ap = parseBoqCode(aCode, forcedMinorFromDb: aMinor);
  final bp = parseBoqCode(bCode, forcedMinorFromDb: bMinor);

  final c0 = _cmpListInt(_sectionParts(ap.section), _sectionParts(bp.section));
  if (c0 != 0) return c0;

  final c1 = _subRank(ap.minor).compareTo(_subRank(bp.minor));
  if (c1 != 0) return c1;

  final c2 = _letterRank(ap.main).compareTo(_letterRank(bp.main));
  if (c2 != 0) return c2;

  final c3 = _subRank(ap.sub).compareTo(_subRank(bp.sub));
  if (c3 != 0) return c3;

  return aCode.compareTo(bCode);
}

final qtyFmt = NumberFormat('#,##0.000'); // Qty: 3 dp (change if you want)
final moneyFmt = NumberFormat('#,##0.00'); // Rate/Amount: 2 dp

class TplPickResult {
  final String templateId;
  final String templateName;
  final String templateScope;

  const TplPickResult({
    required this.templateId,
    required this.templateName,
    this.templateScope = '',
  });
}

String extractBillCode(String boqCode) {
  final m = RegExp(r'^\s*(\d+)').firstMatch(boqCode);
  return (m?.group(1) ?? '').trim();
}

String extractSubHeadingNo(String boqCode) {
  // from 3.1(B)(i) -> 3.1
  // from 3.7(i)(C)(ii) -> 3.7
  final head = boqCode.split('(').first.trim();
  final m = RegExp(r'^\d+(?:\.\d+)?').firstMatch(head);
  return (m?.group(0) ?? head).trim();
}

// -----------------------------
// Helpers (drop-in)
// -----------------------------
String _s(dynamic v) => (v ?? '').toString().trim();

bool _isRoman(String s) =>
    RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(s.trim());

/// A single-letter that is ALSO a roman letter (I,V,X,L,C,D,M)
bool _isSingleRomanLetter(String s) {
  final t = s.trim().toUpperCase();
  return t.length == 1 && 'IVXLCDM'.contains(t);
}

/// Extracts first number from "BILL NO. 3:-SUBSTRUCTURE" => "3"
String billFromLabel(String label) {
  final m = RegExp(r'\b(\d+)\b').firstMatch(label);
  return (m?.group(1) ?? '').trim();
}

class ParsedShortCode {
  final String mainNo; // A,B,C...
  final String subNo; // i, ii...
  final String
  lastMainOut; // updated lastMain (only when a main letter is explicitly present)
  const ParsedShortCode({
    required this.mainNo,
    required this.subNo,
    required this.lastMainOut,
  });
}

ParsedShortCode parseTemplateShortCode(String raw, String lastMainIn) {
  final c = raw.trim();

  // 1) roman-only first (so "v" doesn't become letter "V")
  if (_isRoman(c) ||
      (_isSingleRomanLetter(c) && lastMainIn.trim().isNotEmpty)) {
    final sub = c.toLowerCase();
    return ParsedShortCode(
      mainNo: lastMainIn.trim().toUpperCase(),
      subNo: sub,
      lastMainOut: lastMainIn.trim().toUpperCase(),
    );
  }

  // 2) letter + roman (B. i / B.i / B i)
  final m = RegExp(
    r'^([A-Za-z])\s*\.?\s*([ivxlcdm]+)$',
    caseSensitive: false,
  ).firstMatch(c.replaceAll(' ', ''));
  if (m != null) {
    final main = (m.group(1) ?? '').toUpperCase();
    final sub = (m.group(2) ?? '').toLowerCase();
    return ParsedShortCode(mainNo: main, subNo: sub, lastMainOut: main);
  }

  // 3) letter-only (A/B/C)
  final m2 = RegExp(r'^([A-Za-z])$').firstMatch(c);
  if (m2 != null) {
    final main = (m2.group(1) ?? '').toUpperCase();
    return ParsedShortCode(mainNo: main, subNo: '', lastMainOut: main);
  }

  // fallback: keep as-is (no update to lastMain)
  return ParsedShortCode(
    mainNo: lastMainIn.trim().toUpperCase(),
    subNo: '',
    lastMainOut: lastMainIn.trim().toUpperCase(),
  );
}

/// Builds FULL boq code using carried context.
/// Example:
///  subHeadingNo=3.1, minorNo='', main=B, sub=ii => 3.1(B)(ii)
///  subHeadingNo=3.7, minorNo=i, main=C, sub=ii => 3.7(i)(C)(ii)
String buildFullBoqCode({
  required String subHeadingNo,
  required String minorNo,
  required String mainNo,
  required String subNo,
}) {
  final sb = StringBuffer();
  sb.write(subHeadingNo.trim());
  if (minorNo.trim().isNotEmpty) sb.write('(${minorNo.trim()})');
  if (mainNo.trim().isNotEmpty) sb.write('(${mainNo.trim().toUpperCase()})');
  if (subNo.trim().isNotEmpty) sb.write('(${subNo.trim().toLowerCase()})');
  return sb.toString();
}

/// If the raw code already looks like a full code (starts with digit),
/// we keep it and just compute orderKey from it.
bool looksFullCode(String code) => RegExp(r'^\d').hasMatch(code.trim());

bool pointInPolygon(Offset p, List<Offset> poly) {
  bool inside = false;
  for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i].dx;
    final yi = poly[i].dy;
    final xj = poly[j].dx;
    final yj = poly[j].dy;

    final intersect =
        ((yi > p.dy) != (yj > p.dy)) &&
        (p.dx <
            (xj - xi) * (p.dy - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) + xi);

    if (intersect) inside = !inside;
  }
  return inside;
}

String? findFootingGroupIdAtTap({
  required Offset tapPosImage,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
}) {
  // Prefer polygons first; only consider docs that belong to composite footing
  for (final doc in docs) {
    final d = doc.data();
    final groupId = (d['footingGroupId'] ?? '').toString().trim();
    final polyRaw = d['polygon'];

    if (groupId.isEmpty || polyRaw is! List) continue;

    final poly =
        polyRaw
            .map(
              (e) => Offset(
                (e['x'] as num).toDouble(),
                (e['y'] as num).toDouble(),
              ),
            )
            .toList();

    if (poly.length < 3) continue;

    if (pointInPolygon(tapPosImage, poly)) {
      return groupId;
    }
  }
  return null;
}

Stream<QuerySnapshot<Map<String, dynamic>>> footingGroupStream({
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required String footingGroupId,
}) {
  return measurementsRef
      .where('footingGroupId', isEqualTo: footingGroupId)
      .snapshots();
}

double polygonAreaPx(List<Offset> pts) {
  double sum = 0;
  for (int i = 0; i < pts.length; i++) {
    final p1 = pts[i];
    final p2 = pts[(i + 1) % pts.length];
    sum += p1.dx * p2.dy - p2.dx * p1.dy;
  }
  return 0.5 * sum;
}

List<Offset>? _readPolygon(dynamic d) {
  final raw = (d is Map) ? d['polygon'] : null;
  if (raw is! List || raw.length < 3) return null;

  try {
    return raw.map((e) {
      final ex = (e['x'] as num).toDouble();
      final ey = (e['y'] as num).toDouble();
      return Offset(ex, ey);
    }).toList();
  } catch (_) {
    return null;
  }
}

FootingSection sectionOf(Map<String, dynamic> d) {
  final type = (d['type'] ?? '').toString().toLowerCase();
  final label = (d['label'] ?? '').toString().toLowerCase();

  bool has(String s) => type.contains(s) || label.contains(s);

  // footing components
  if (has('footingconcrete') ||
      has('footingformwork') ||
      has('rebarfooting') ||
      has('footing')) {
    // BUT avoid column that also contains footingGroupId
    if (has('column')) return FootingSection.column;
    return FootingSection.footing;
  }

  // column components
  if (has('column') || has('stirrups') || has('mainrebar')) {
    return FootingSection.column;
  }

  // earthworks
  if (has('excav') ||
      has('backfill') ||
      has('disposal') ||
      has('surplus') ||
      has('blinding')) {
    return FootingSection.earthworks;
  }

  return FootingSection.other;
}

// bool pointInPolygon(Offset p, List<Offset> poly) {
//   bool inside = false;
//   for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
//     final xi = poly[i].dx, yi = poly[i].dy;
//     final xj = poly[j].dx, yj = poly[j].dy;

//     final intersect =
//         ((yi > p.dy) != (yj > p.dy)) &&
//         (p.dx <
//             (xj - xi) * (p.dy - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
//                 xi);

//     if (intersect) inside = !inside;
//   }
//   return inside;
// }

String? hitFootingGroupId(
  Offset imagePos,
  Map<String, List<dynamic>> footingCompositeDocsByGroupId,
) {
  String? bestId;
  double bestArea = double.infinity;

  footingCompositeDocsByGroupId.forEach((groupId, docs) {
    if (docs.isEmpty) return;
    final poly = _readPolygon(
      docs.first is Map ? docs.first : (docs.first.data()),
    );
    if (poly == null) return;

    if (pointInPolygon(imagePos, poly)) {
      final a = polygonAreaPx(poly);
      if (a < bestArea) {
        bestArea = a;
        bestId = groupId;
      }
    }
  });

  return bestId;
}

// -----------------------------
// MakeOrderKey (bring from your BoqTemplateController or share it)
// -----------------------------
final ironItems = <IronItem>[
  IronItem(key: 'lockset', title: 'Lockset', unit: 'item'),
  IronItem(key: 'lockCylinder', title: 'Lock cylinder', unit: 'item'),
  IronItem(key: 'doorCloser', title: 'Door closer', unit: 'item'),
  IronItem(key: 'kickPlate', title: 'Kick plate', unit: 'item'),
  IronItem(key: 'pushPlate', title: 'Push plate', unit: 'item'),
  IronItem(key: 'pullPlate', title: 'Pull plate', unit: 'item'),
  IronItem(key: 'pullHandle', title: 'Pull handle', unit: 'item'),
  IronItem(key: 'doorStop', title: 'Door stop', unit: 'item'),
  IronItem(key: 'signage', title: 'Signage', unit: 'item'),
  IronItem(
    key: 'wcIndicator',
    title: 'WC red/green indicator disc',
    unit: 'item',
  ),
];

Map<String, dynamic> lastFoundationDefaults = {
  'trenchWidth': 0.6,
  'trenchDepth': 1.2,
  'workingSpace': 0.0,

  'blindingWidth': 0.6,

  'footingWidth': 0.6,
  'footingThk': 0.2,

  'wallThk': 0.2,
  'wallHeight': 0.6,

  'reuseForBackfill': true, // disposal = exc - backfill
  'includeWallVolInBackfill': true,
  'includeFootingVolInBackfill': true,
};

List<BoqPick> filterBoqs(List<BoqPick> all, String q) {
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return all;
  final parts = s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();

  return all.where((b) {
    final text = ('${b.code} ${b.description}').toLowerCase();
    return parts.every(text.contains); // all tokens must match
  }).toList();
}

Future<void> saveWithLinkedMirrors({
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Map<String, dynamic>
  sourceData, // must include unit/value + geometry + other fields
  required String sourceDocId, // create this once, pass in
  required List<LinkedBoqTarget> targets, // from controller
}) async {
  final batch = FirebaseFirestore.instance.batch();
  final now = FieldValue.serverTimestamp();

  final srcRef = measurementsRef.doc(sourceDocId);
  batch.set(srcRef, {
    ...sourceData,
    'isDerived': false,
    'updatedAt': now,
    'createdAt': sourceData['createdAt'] ?? now,
  });

  for (final t in targets) {
    final derivedId = measurementsRef.doc().id;
    final ref = measurementsRef.doc(derivedId);

    batch.set(ref, {
      ...sourceData,

      // override BOQ
      'boqItemId': t.boq.id,
      'boqCode': t.boq.code,
      'boqDescription': t.boq.description,

      // mark derived + linkage
      'isDerived': true,
      'derivedFromDocId': sourceDocId,
      'derivedRule': 'linear',
      'derivedFactor': t.factor,
      'derivedOffset': t.offset,

      // immediately apply derived value once (function will keep it synced)
      'value': ((sourceData['value'] as num).toDouble() * t.factor) + t.offset,

      'createdAt': now,
      'updatedAt': now,
    });
  }

  await batch.commit();
}

FoundationWallSection sectionOfFoundation(Map<String, dynamic> d) {
  final t = (d['type'] ?? '').toString().toLowerCase();

  // earthworks
  if (t.contains('excav') ||
      t.contains('backfill') ||
      t.contains('disposal') ||
      t.contains('surplus')) {
    return FoundationWallSection.earthworks;
  }

  // formwork / rebar / concrete
  if (t.contains('formwork')) return FoundationWallSection.formwork;
  if (t.contains('rebar') || t.contains('reinforcement') || t.contains('stirr'))
    return FoundationWallSection.rebar;
  if (t.contains('concrete') || t.contains('blinding'))
    return FoundationWallSection.concrete;

  // default "wall items"
  if (t.contains('foundationwall') ||
      t.contains('foundation wall') ||
      t.contains('wall')) {
    return FoundationWallSection.wall;
  }

  return FoundationWallSection.other;
}

int orderOfFoundation(Map<String, dynamic> d) {
  final t = (d['type'] ?? '').toString().toLowerCase();
  if (t.contains('excav')) return 1;
  if (t.contains('backfill')) return 2;
  if (t.contains('disposal') || t.contains('surplus')) return 3;

  if (t.contains('blinding')) return 1;
  if (t.contains('concrete')) return 2;
  if (t.contains('formwork')) return 3;
  if (t.contains('rebar') || t.contains('stirr')) return 4;

  return 99;
}

double _asNum(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? def;
}

double polygonAreaM2(List<Offset> poly, Map<String, dynamic> drawingData) {
  final ppu = _asNum(drawingData['pixelsPerUnit']);
  if (ppu <= 0 || poly.length < 3) return 0;
  double sum = 0;
  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    sum += (a.dx * b.dy) - (b.dx * a.dy);
  }
  final areaPx2 = sum.abs() * 0.5;
  return areaPx2 / (ppu * ppu);
}

double polygonPerimeterM(List<Offset> poly, Map<String, dynamic> drawingData) {
  final ppu = _asNum(drawingData['pixelsPerUnit']);
  if (ppu <= 0 || poly.length < 2) return 0;
  double s = 0;
  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    s += math.sqrt(dx * dx + dy * dy);
  }
  return s / ppu;
}

// kg per meter (approx): d^2/162  (d in mm)
double kgPerM(double diaMm) => (diaMm * diaMm) / 162.0;

Future<BoqPick?> findLastBoqPick({
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required String drawingId,
  required String type,
  required String measureType,
}) async {
  final qs =
      await measurementsRef
          .where('drawingId', isEqualTo: drawingId)
          .where('type', isEqualTo: type)
          .where('measureType', isEqualTo: measureType)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

  if (qs.docs.isEmpty) return null;

  final m = qs.docs.first.data();
  final id = (m['boqItemId'] ?? '').toString().trim();
  final code = (m['boqCode'] ?? m['boqCode'] ?? '').toString().trim();
  final desc = (m['boqDescription'] ?? '').toString().trim();

  if (id.isEmpty && code.isEmpty) return null;

  return BoqPick(id: id, code: code, description: desc);
}

double clampD(num v, double lo, double hi) => v.clamp(lo, hi).toDouble();

double asNum(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? def;
}

BoqPick? lastColConcBoq;
BoqPick? lastColFwBoq;
BoqPick? lastColMainBoq;
BoqPick? lastColStirBoq;

Map<String, dynamic> lastColDefaults = {
  'heightM': 3.00,
  'qty': 1,
  'label': 'C1',

  // main bars
  'mainCount': 4,
  'mainDia': 16,
  'mainMark': '01',
  'mainDevExtraM': 0.60, // add dev/lap allowance (m)
  // stirrups
  'stirDia': 10,
  'stirMark': '05',
  'stirSpacingMm': 200,
  'coverMm': 25,
  'hookM': 0.10, // per end
};

final Map<String, LengthDefaults> _lengthDefaultsByType = {};

String _keyType(String? t) => (t ?? '').trim().toLowerCase();

void rememberLengthDefaults({
  required String? activeMeasureType,
  required String unit,
  required double? heightM,
  required List<Map<String, String>> rows,
}) {
  final k = _keyType(activeMeasureType);
  if (k.isEmpty) return;
  _lengthDefaultsByType[k] = LengthDefaults(
    unit: unit,
    heightM: heightM,
    rows: rows,
  );
}

LengthDefaults? getLengthDefaults(String? activeMeasureType) {
  final k = _keyType(activeMeasureType);
  if (k.isEmpty) return null;
  return _lengthDefaultsByType[k];
}

OpeningScope scopeFrom(dynamic v) {
  final s = (v ?? '').toString().toLowerCase().trim();
  return (s == 'external') ? OpeningScope.external : OpeningScope.internal;
}

String scopeName(OpeningScope s) =>
    s == OpeningScope.external ? 'external' : 'internal';

final _moneyFmt = NumberFormat(
  '#,##0.00',
); // 1,234.00 // 1,234 (you can swap to currency)

// String _fmtQty(double v) => _qtyFmt.format(v);
String fmtMoney(double v) => _moneyFmt.format(v);

xl.ExcelColor xc(String argb) => xl.ExcelColor.fromHexString(argb);

@JS('pdfFirstPageToPngDataUrl')
external JSPromise<JSString> _pdfFirstPageToPngDataUrl(
  JSString base64Pdf,
  JSNumber scale,
);

@JS('pdfPageToPngDataUrl')
external JSPromise<JSString> _pdfPageToPngDataUrl(
  JSString base64Pdf,
  JSNumber pageNumber,
  JSNumber scale,
);

@JS('pdfPageCount')
external JSPromise<JSString> _pdfPageCount(JSString base64Pdf);

@JS('recognizeRebarMark')
external JSPromise<JSString> _recognizeRebarMark(
  JSString imageUrl,
  JSNumber minX,
  JSNumber minY,
  JSNumber maxX,
  JSNumber maxY,
  JSNumber drawingWidth,
  JSNumber drawingHeight,
);

JSPromise<JSString> pdfFirstPageToPngDataUrl(String base64Pdf, double scale) =>
    _pdfFirstPageToPngDataUrl(base64Pdf.toJS, scale.toJS);

JSPromise<JSString> pdfPageToPngDataUrl(
  String base64Pdf,
  int pageNumber,
  double scale,
) => _pdfPageToPngDataUrl(base64Pdf.toJS, pageNumber.toJS, scale.toJS);

JSPromise<JSString> pdfPageCount(String base64Pdf) =>
    _pdfPageCount(base64Pdf.toJS);

Future<String> promiseToFutureString(JSPromise<JSString> p) async =>
    (await p.toDart).toDart;

Future<String> recognizeRebarMark({
  required String imageUrl,
  required double minX,
  required double minY,
  required double maxX,
  required double maxY,
  required double drawingWidth,
  required double drawingHeight,
}) => promiseToFutureString(
  _recognizeRebarMark(
    imageUrl.toJS,
    minX.toJS,
    minY.toJS,
    maxX.toJS,
    maxY.toJS,
    drawingWidth.toJS,
    drawingHeight.toJS,
  ),
);

Map<String, dynamic> lastFootingDefaults = {};
Map<String, dynamic> lastBeamDefaults = {};
Map<String, dynamic> lastSlabDefaults = {};
Map<String, dynamic> lastColumnDefaults = {};
Map<String, dynamic> lastTrussDefaults = {};

// double clampD(double v, double lo, double hi) {
//   if (v < lo) return lo;
//   if (v > hi) return hi;
//   return v;
// }

Map<String, dynamic>? pickToMap(BoqPick? p) {
  if (p == null) return null;
  return {'code': p.code, 'description': p.description, 'id': p.id};
}

BoqPick? pickFromMap(dynamic v) {
  if (v is! Map) return null;
  final m = Map<String, dynamic>.from(v);
  final code = (m['code'] ?? '').toString().trim();
  final desc = (m['description'] ?? '').toString().trim();
  final id = (m['id'] ?? '').toString().trim();
  if (code.isEmpty && desc.isEmpty && id.isEmpty) return null;
  return BoqPick(id: id, code: code, description: desc);
}

class ColumnMainBarSet {
  final String raw;
  final int quantityBars;
  final int diameterMm;
  final double heightM;
  final double embedTopM;
  final double embedBotM;
  final double extraM;

  final double barLengthM;
  final double totalLengthM;
  final double unitWeightKgPerM;
  final double totalWeightKg;
  final String substructureBoqCode;
  final String substructureBoqDescription;
  final String superstructureBoqCode;
  final String superstructureBoqDescription;

  ColumnMainBarSet({
    required this.raw,
    required this.quantityBars,
    required this.diameterMm,
    required this.heightM,
    required this.embedTopM,
    required this.embedBotM,
    required this.extraM,
    required this.barLengthM,
    required this.totalLengthM,
    required this.unitWeightKgPerM,
    required this.totalWeightKg,
    this.substructureBoqCode = '',
    this.substructureBoqDescription = '',
    this.superstructureBoqCode = '',
    this.superstructureBoqDescription = '',
  });
}

class ColumnMainMarkParsed {
  final int quantity;
  final String barType;
  final int diameterMm;

  ColumnMainMarkParsed({
    required this.quantity,
    required this.barType,
    required this.diameterMm,
  });
}

ColumnMainMarkParsed parseColumnMainMark(String raw) {
  final s = raw.replaceAll(' ', '').trim();
  if (s.isEmpty) {
    throw FormatException('Enter main bar mark e.g. 8Y16');
  }
  final head = s.split('-').first; // "8Y16"
  final m = RegExp(r'^(\d+)([A-Za-z]\d+)$').firstMatch(head);
  if (m == null) {
    throw FormatException('Invalid mark "$raw". Use e.g. 8Y16');
  }
  final qty = int.parse(m.group(1)!);
  final barType = m.group(2)!.toUpperCase(); // Y16
  final diaMatch = RegExp(r'(\d+)$').firstMatch(barType);
  if (diaMatch == null) {
    throw FormatException('Cannot read diameter from "$barType"');
  }
  final dia = int.parse(diaMatch.group(1)!);
  return ColumnMainMarkParsed(quantity: qty, barType: barType, diameterMm: dia);
}

/// Stirrups calc for rectangular column
Map<String, dynamic> calcColumnStirrups({
  required double colL,
  required double colW,
  required double colH,
  required double coverM,
  required double spacingM,
  required int diaMm,
  required double hookExtraM, // total hooks add
  required double Function(int) unitWeightKgPerM,
}) {
  if (colL <= 0 || colW <= 0 || colH <= 0 || spacingM <= 0)
    return {'ok': false};

  final wClear = (colW - 2 * coverM).clamp(0.0, double.infinity);
  final lClear = (colL - 2 * coverM).clamp(0.0, double.infinity);

  final oneLenM = 2 * (wClear + lClear) + hookExtraM;
  final count = (colH / spacingM).ceil() + 1;

  final totalLenM = oneLenM * count;
  final uw = unitWeightKgPerM(diaMm);
  final totalKg = totalLenM * uw;

  return {
    'ok': true,
    'count': count,
    'oneLenM': oneLenM,
    'totalLenM': totalLenM,
    'uwKgPerM': uw,
    'totalKg': totalKg,
  };
}

Map<String, dynamic> lastRampDefaults = {};
Map<String, dynamic> lastStairDefaults = {};
Map<String, dynamic> lastDoorDefaults = {};
Map<String, dynamic> lastWindowDefaults = {};
Map<String, dynamic> lastRetWallDefaults = {};

class EdgeSel {
  final int index;
  final double lengthM;
  bool exposed;
  EdgeSel({required this.index, required this.lengthM, this.exposed = false});
}

double polygonAreaPx2(List<Offset> pts) {
  double sum = 0;
  for (int i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += (a.dx * b.dy) - (b.dx * a.dy);
  }
  return (sum / 2.0).abs();
}

String? draftOpeningsGroupId;
String? draftStairGroupId;

class WallPick {
  final String id; // wallGroupId
  final String name; // display
  final String side; // 'internal' or 'external' (optional but helpful)
  WallPick({required this.id, required this.name, required this.side});
}

// class AreaBoqTemplateRow {
//   final String label;
//   final String boqCode;
//   final String boqDesc;

//   AreaBoqTemplateRow({
//     required this.label,
//     required this.boqCode,
//     required this.boqDesc,
//   });
// }

// class AreaTemplate {
//   final bool isRoofCovering;
//   final double roofAngleDeg; // valid when isRoofCovering
//   final List<AreaBoqTemplateRow> rows;

//   AreaTemplate({
//     required this.isRoofCovering,
//     required this.roofAngleDeg,
//     required this.rows,
//   });
// }

// ✅ remember last saved inputs
AreaTemplate? lastAreaTemplate;

final List<Offset> draftLenPoints = <Offset>[];
double draftLenTotalPx = 0.0;
String? draftLenGroupId;

double distPx(Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}

String? currentWallId; // group id for currently drawn retaining wall
String? boqCode;

final isRetainingWallActive = false.obs;
String? retainingWallGroupId;
final List<Offset> lenDraftPoints = <Offset>[]; // includes corners
double lenDraftTotalM = 0.0; // accumulated length in meters
String? lenDraftId;

// final List<Offset> draftLenPoints = <Offset>[];
// double draftLenTotalPx = 0.0;
// String? draftLenGroupId;

double _distPx(Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}

bool samePoint(Offset a, Offset b, {double tol = 0.5}) => distPx(a, b) <= tol;
Map<String, dynamic> lastRoofDefaults = {}; // remember settings, not geometry
String? draftRoofGroupId;
double polygonPerimeterPx(List<Offset> pts) {
  if (pts.length < 2) return 0;
  double p = 0;
  for (int i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    p += _distPx(a, b);
  }
  return p;
}

int parseFactor(TextEditingController c) {
  final v = int.tryParse(c.text.trim()) ?? 1;
  return v.clamp(1, 999999);
}

double applyFactor(double perBuilding, int factor) => perBuilding * factor;
int? lastRetWallFactor = 1;
String? lastRetWallBoqRebar;
double? lastRetWallRebarKgEach;

final List<Offset> lengthPoints = <Offset>[];

bool isMeasuringLength = false;
bool finishRequested = false;

double? activeMultiplyFactor; // remember last used factor (optional)
double? activeHeightM; // you already have this

bool get canFinish => lengthPoints.length >= 2;

void addPoint(Offset p) {
  lengthPoints.add(p);
  // update viewer if needed
  // update(['viewer']) or setState(() {});
}

void clearPoints() {
  lengthPoints.clear();
  finishRequested = false;
  // update viewer if needed
}

int calcPanelsCount(double areaM2, int panelMm) {
  final sideM = (panelMm <= 0 ? 600 : panelMm) / 1000.0;
  final panelArea = sideM * sideM;
  if (panelArea <= 0) return 0;
  return (areaM2 / panelArea).ceil();
}

Map<String, dynamic> lastCeilingDefaults = {};
Map<String, dynamic> lastRetainingWallDefaults = {};
Map<String, dynamic> lastVolumeTemplate = {};

// astRetainingWallDefaults,
String? draftCeilingGroupId;
String? draftRampGroupId;

class AreaLabel {
  final String id;
  final Offset at;
  final String text;
  final Color color;
  final String? groupId;
  AreaLabel({
    required this.id,
    required this.at,
    required this.text,
    required this.color,
    this.groupId,
  });
}

double _num(dynamic v, double fb) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? fb;
}

double pxPerMFromDrawing(Map<String, dynamic> drawingData) {
  // adapt if your key is different
  return _num(drawingData['pixelsPerUnit'], 0); // px per meter
}

double distM(Offset aWorld, Offset bWorld, Map<String, dynamic> drawingData) {
  final pxPerM = pxPerMFromDrawing(drawingData);
  if (pxPerM <= 0) return 0;
  final dx = bWorld.dx - aWorld.dx;
  final dy = bWorld.dy - aWorld.dy;
  final dPx = (dx * dx + dy * dy).sqrt();
  return dPx / pxPerM;
}

Offset toWorld({
  required Offset local,
  required TransformationController tCtrl,
}) {
  final vm.Matrix4 inv = vm.Matrix4.inverted(tCtrl.value);
  final vm.Vector3 v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
  return Offset(v.x, v.y);
}

Future<void> savePolylineMeasurement({
  required Offset p1World,
  required Offset p2World,
  required Map<String, dynamic> drawingData,

  required String projectId,
  required String buildingId,
  required String drawingId,

  required String measureType, // e.g. roofSheetingAndTimber
  required String type, // e.g. roofRidgeCapping, roofValleys, roofRafters150x50
  required String unit, // "m"
  required Color color,

  required CollectionReference<Map<String, dynamic>> measurementsRef,

  // grouping (optional but recommended)
  String? groupId,

  // tagging (optional)
  String? edgeTag, // "ridge" | "hip" | "valley" | "eave" | "barge"
  // remember previous picks/settings
  required Map<String, dynamic> lastLineDefaults,
  required Future<BoqPick?> Function(BuildContext ctx) showBoqPickerDialog,
  BuildContext? ctx,

  // UI label fields
  String? label,
  String? lineLabel,
}) async {
  // validate calibration
  final calibrated = drawingData['calibrated'] == true;
  final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
  if (!calibrated || pxPerM <= 0) {
    Get.snackbar('Not calibrated', 'Calibrate drawing first (pixelsPerUnit).');
    return;
  }

  // compute length
  final lengthM = distM(p1World, p2World, drawingData);
  if (lengthM <= 0) {
    Get.snackbar('Invalid', 'Length is zero. Check points/calibration.');
    return;
  }

  // restore last BOQ pick (auto)
  BoqPick? boqPick = pickFromMap(lastLineDefaults['lastBoqPick']);

  // if no pick and UI available -> ask pick (optional)
  final bctx = ctx ?? Get.context;
  if (boqPick == null && bctx != null) {
    final pick = await showBoqPickerDialog(bctx);
    if (pick != null) boqPick = pick;
  }

  final now = FieldValue.serverTimestamp();
  final docId = measurementsRef.doc().id;

  try {
    await measurementsRef.doc(docId).set({
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,

      'measureType': measureType,
      'type': type,
      'unit': unit,
      'value': lengthM,

      'p1': {'x': p1World.dx, 'y': p1World.dy},
      'p2': {'x': p2World.dx, 'y': p2World.dy},

      'groupId': (groupId ?? '').toString().trim(),
      'edgeTag': (edgeTag ?? '').toString().trim(),

      'label': (label ?? '').toString(),
      'lineLabel': (lineLabel ?? '').toString(),

      'color': color.value,

      if (boqPick != null) ...{
        'boqItemId': boqPick.id,
        'boqCode': boqPick.code,
        'boqDescription': boqPick.description,
      },

      'createdAt': now,
      'updatedAt': now,
    });

    // remember BOQ for faster next time
    lastLineDefaults['lastBoqPick'] = pickToMap(boqPick);
    lastLineDefaults['lastMeasureType'] = measureType;
    lastLineDefaults['lastType'] = type;
    lastLineDefaults['lastUnit'] = unit;

    Get.snackbar('Saved', '$type: ${lengthM.toStringAsFixed(3)} m');
  } catch (e) {
    Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
  }
}

class BeamMainRebarGroup {
  String name; // Top/Bottom/Extra/Side...
  int diaMm;
  int bars;
  double embedEachEndM;
  double lapExtraM;
  BoqPick? boq;

  BeamMainRebarGroup({
    required this.name,
    required this.diaMm,
    required this.bars,
    required this.embedEachEndM,
    required this.lapExtraM,
    this.boq,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'diaMm': diaMm,
    'bars': bars,
    'embedEachEndM': embedEachEndM,
    'lapExtraM': lapExtraM,
    'boq':
        boq == null
            ? null
            : {
              'id': boq!.id,
              'code': boq!.code,
              'description': boq!.description,
            },
  };

  static BeamMainRebarGroup fromMap(Map<String, dynamic> m) {
    BoqPick? _pickFromMap(dynamic v) {
      if (v is! Map) return null;
      final mm = Map<String, dynamic>.from(v);
      final id = (mm['id'] ?? '').toString();
      final code = (mm['code'] ?? '').toString();
      final desc = (mm['description'] ?? '').toString();
      if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
      return BoqPick(id: id, code: code, description: desc);
    }

    return BeamMainRebarGroup(
      name: (m['name'] ?? 'Main').toString(),
      diaMm: (m['diaMm'] is num) ? (m['diaMm'] as num).toInt() : 16,
      bars: (m['bars'] is num) ? (m['bars'] as num).toInt() : 2,
      embedEachEndM:
          (m['embedEachEndM'] is num)
              ? (m['embedEachEndM'] as num).toDouble()
              : 0.30,
      lapExtraM:
          (m['lapExtraM'] is num) ? (m['lapExtraM'] as num).toDouble() : 0.0,
      boq: _pickFromMap(m['boq']),
    );
  }
}

class BeamStirrupZone {
  String name; // Ends/Mid/Full...
  int diaMm;
  double spacingM;
  double coverM;
  double hookExtraM;
  double zoneLengthM; // 0 => full beam length
  BoqPick? boq;

  BeamStirrupZone({
    required this.name,
    required this.diaMm,
    required this.spacingM,
    required this.coverM,
    required this.hookExtraM,
    required this.zoneLengthM,
    this.boq,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'diaMm': diaMm,
    'spacingM': spacingM,
    'coverM': coverM,
    'hookExtraM': hookExtraM,
    'zoneLengthM': zoneLengthM,
    'boq':
        boq == null
            ? null
            : {
              'id': boq!.id,
              'code': boq!.code,
              'description': boq!.description,
            },
  };

  static BeamStirrupZone fromMap(Map<String, dynamic> m) {
    BoqPick? _pickFromMap(dynamic v) {
      if (v is! Map) return null;
      final mm = Map<String, dynamic>.from(v);
      final id = (mm['id'] ?? '').toString();
      final code = (mm['code'] ?? '').toString();
      final desc = (mm['description'] ?? '').toString();
      if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
      return BoqPick(id: id, code: code, description: desc);
    }

    return BeamStirrupZone(
      name: (m['name'] ?? 'Stirrups').toString(),
      diaMm: (m['diaMm'] is num) ? (m['diaMm'] as num).toInt() : 10,
      spacingM:
          (m['spacingM'] is num) ? (m['spacingM'] as num).toDouble() : 0.20,
      coverM: (m['coverM'] is num) ? (m['coverM'] as num).toDouble() : 0.04,
      hookExtraM:
          (m['hookExtraM'] is num) ? (m['hookExtraM'] as num).toDouble() : 0.20,
      zoneLengthM:
          (m['zoneLengthM'] is num)
              ? (m['zoneLengthM'] as num).toDouble()
              : 0.0,
      boq: _pickFromMap(m['boq']),
    );
  }
}

Future<bool> commitBatchWithVerify({
  required WriteBatch batch,
  required List<DocumentReference<Map<String, dynamic>>> verifyRefs,
  required String successMessage,
}) async {
  // show progress overlay
  Get.dialog(
    const AlertDialog(
      content: SizedBox(
        height: 80,
        child: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Saving… please wait')),
          ],
        ),
      ),
    ),
    barrierDismissible: false,
  );

  try {
    await batch.commit();

    // ✅ verify: read back at least 1–3 docs that MUST exist
    for (final ref in verifyRefs) {
      final snap = await ref.get();
      if (!snap.exists) {
        throw Exception('Save verification failed: ${ref.path} not found.');
      }
    }

    // close progress
    if (Get.isDialogOpen == true) Get.back();

    Get.snackbar('Saved', successMessage);
    return true;
  } catch (e, st) {
    // close progress
    if (Get.isDialogOpen == true) Get.back();

    debugPrint('❌ SAVE FAILED: $e\n$st');
    Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    return false;
  }
}

double? lastStairSlopingLenM;
double? lastStairWidthM;
double? lastLandingTopM;
double? lastLandingBottomM;

// Offset toWorld({
//   required Offset local,
//   required TransformationController tCtrl,
// }) {
//   final Matrix4 m = tCtrl.value;
//   final Matrix4 inv = Matrix4.inverted(m);
//   final vm.Vector3 v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
//   return Offset(v.x, v.y);
// }
// double distM(Offset aWorld, Offset bWorld, Map<String, dynamic> drawingData) {
//   final calibrated = drawingData['calibrated'] == true;
//   final pxPerM = _num(drawingData['pixelsPerUnit'], 0);
//   if (!calibrated || pxPerM <= 0) return 0.0;

//   final dx = bWorld.dx - aWorld.dx;
//   final dy = bWorld.dy - aWorld.dy;
//   final px = math.sqrt(dx * dx + dy * dy);
//   return px / pxPerM;
// }

extension OffsetMap on Offset {
  Map<String, double> toMap() => {'x': dx, 'y': dy};
}

class VolumeTemplate {
  final double depthM;
  final List<AreaBoqTemplateRow> rows;

  const VolumeTemplate({required this.depthM, required this.rows});

  Map<String, dynamic> toMap() => {
    'depthM': depthM,
    'rows': rows.map((r) => r.toMap()).toList(),
  };

  factory VolumeTemplate.fromMap(Map<String, dynamic> m) {
    final rowsRaw = (m['rows'] as List?) ?? const [];
    return VolumeTemplate(
      depthM:
          (m['depthM'] is num)
              ? (m['depthM'] as num).toDouble()
              : double.tryParse('${m['depthM'] ?? ''}') ?? 0.15,
      rows:
          rowsRaw
              .whereType<Map>()
              .map(
                (x) => AreaBoqTemplateRow.fromMap(Map<String, dynamic>.from(x)),
              )
              .toList(),
    );
  }
}

const String kBoqSubcol = 'boq';

class ProjectCounts {
  final int buildings;
  final int drawings;
  final int measurements;
  final int boqItems;

  const ProjectCounts({
    required this.buildings,
    required this.drawings,
    required this.measurements,
    required this.boqItems,
  });
}

class PolylinePainter extends CustomPainter {
  final List<Offset> pointsWorld;
  final Offset? hoverWorld;
  final Offset Function(Offset world) toScreen;
  final Color color;
  final double stroke;

  PolylinePainter({
    required this.pointsWorld,
    required this.hoverWorld,
    required this.toScreen,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pointsWorld.isEmpty) return;

    final paintLine =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;

    final paintDot =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final path = Path();
    final first = toScreen(pointsWorld.first);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < pointsWorld.length; i++) {
      final p = toScreen(pointsWorld[i]);
      path.lineTo(p.dx, p.dy);
    }

    // preview to hover
    if (hoverWorld != null && pointsWorld.isNotEmpty) {
      final h = toScreen(hoverWorld!);
      path.lineTo(h.dx, h.dy);
    }

    canvas.drawPath(path, paintLine);

    // draw vertices
    for (final w in pointsWorld) {
      final s = toScreen(w);
      canvas.drawCircle(s, 3.5, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant PolylinePainter old) {
    return old.pointsWorld != pointsWorld ||
        old.hoverWorld != hoverWorld ||
        old.color != color ||
        old.stroke != stroke;
  }
}

class PolylineDrawOverlay extends StatelessWidget {
  final PolylineDrawController c;
  final Offset Function(Offset local) toWorld;
  final Offset Function(Offset world) toScreen;

  final Color color;
  final double stroke;

  const PolylineDrawOverlay({
    super.key,
    required this.c,
    required this.toWorld,
    required this.toScreen,
    this.color = Colors.red,
    this.stroke = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (!c.enabled) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      // ✅ tap = add point
      onTapDown: (d) {
        final w = toWorld(d.localPosition);
        c.addPoint(w);
      },

      // ✅ hover/drag preview
      onPanStart: (d) => c.updateHover(toWorld(d.localPosition)),
      onPanUpdate: (d) => c.updateHover(toWorld(d.localPosition)),
      onPanEnd: (_) => c.updateHover(null),

      // ✅ double tap = finish (we’ll handle in “Save” step)
      onDoubleTap: () {
        // just stop hover preview; saving handled outside
        c.updateHover(null);
      },

      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          return CustomPaint(
            painter: PolylinePainter(
              pointsWorld: c.pointsWorld,
              hoverWorld: c.hover,
              toScreen: toScreen,
              color: color,
              stroke: stroke,
            ),
          );
        },
      ),
    );
  }
}

ProjectStage stageFromStatus(String? s) {
  final v = (s ?? '').trim().toLowerCase();
  if (v == 'tender') return ProjectStage.tender;
  if (v == 'progress') return ProjectStage.progress;
  if (v == 'valuation') return ProjectStage.valuation;
  // allow multiple possible labels for verification
  if (v.contains('verification') ||
      v.contains('re-measure') ||
      v.contains('remeasure') ||
      v.contains('review')) {
    return ProjectStage.verification;
  }
  return ProjectStage.tender; // default
}

String stageToStatus(ProjectStage s) {
  switch (s) {
    case ProjectStage.tender:
      return 'Tender';
    case ProjectStage.progress:
      return 'Progress';
    case ProjectStage.valuation:
      return 'Valuation';
    case ProjectStage.verification:
      return 'BOQ Verification';
  }
}

extension ProjectStageX on ProjectStage {
  String get label {
    switch (this) {
      case ProjectStage.tender:
        return 'Tender';
      case ProjectStage.progress:
        return 'Progress';
      case ProjectStage.valuation:
        return 'Valuation';
      case ProjectStage.verification:
        return 'BOQ Verification';
    }
  }

  String get hint {
    switch (this) {
      case ProjectStage.tender:
        return 'Pre-contract BOQ for bidding & pricing.';
      case ProjectStage.progress:
        return 'Track work done during construction.';
      case ProjectStage.valuation:
        return 'IPC / Payment certification mode.';
      case ProjectStage.verification:
        return 'Review an existing BOQ by re-measuring & comparing.';
    }
  }

  Color background(ColorScheme cs) {
    switch (this) {
      case ProjectStage.tender:
        return const Color(0xFFFFF7ED);
      case ProjectStage.progress:
        return const Color(0xFFEFF6FF);
      case ProjectStage.valuation:
        return const Color(0xFFECFDF5);
      case ProjectStage.verification:
        return const Color(0xFFF3F4F6);
    }
  }

  Color foreground(ColorScheme cs) {
    switch (this) {
      case ProjectStage.tender:
        return const Color(0xFF9A3412);
      case ProjectStage.progress:
        return const Color(0xFF1D4ED8);
      case ProjectStage.valuation:
        return const Color(0xFF047857);
      case ProjectStage.verification:
        return const Color(0xFF111827);
    }
  }
}

final CollectionReference<Map<String, dynamic>> projectsRef = FirebaseFirestore
    .instance
    .collection('projects');

Query<Map<String, dynamic>> baseQuery() {
  return FirebaseFirestore.instance
      .collection('projects')
      .orderBy('createdAt', descending: true);
}

int page = 1;
final int pageSize = 10;
final Map<String, Future<ProjectCounts>> countsInFlight = {};
final TextEditingController search = TextEditingController();
final ValueNotifier<int> selectedNav = ValueNotifier<int>(0);
// final RxInt selectedNav = 0.obs;

// ✅ filter by stage (null = all)
ProjectStage? stageFilter;

const List<String> tzRegions = [
  // Mainland (26)
  'Arusha',
  'Dar es Salaam',
  'Dodoma',
  'Geita',
  'Iringa',
  'Kagera',
  'Katavi',
  'Kigoma',
  'Kilimanjaro',
  'Lindi',
  'Manyara',
  'Mara',
  'Mbeya',
  'Morogoro',
  'Mtwara',
  'Mwanza',
  'Njombe',
  'Pwani',
  'Rukwa',
  'Ruvuma',
  'Shinyanga',
  'Simiyu',
  'Singida',
  'Songwe',
  'Tabora',
  'Tanga',

  // Zanzibar (5)
  'Mjini Magharibi',
  'Unguja North',
  'Unguja South',
  'Pemba North',
  'Pemba South',
];

String _clientDocIdFromName(String value) {
  final cleaned = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'unknown-client' : cleaned;
}

Future<void> openNewProjectDialog(BuildContext context) async {
  final nameCtl = TextEditingController();
  final clientCtl = TextEditingController();
  final locationCtl = TextEditingController();
  final districtCtl = TextEditingController();
  final currencyCtl = TextEditingController(text: 'TZS');
  String? selectedRegion;
  ProjectStage stage = ProjectStage.tender;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
        actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        title: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF102A56), Color(0xFF155EEF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: const Row(
            children: [
              Icon(Icons.add_business_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create new project',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Project setup and client directory link',
                      style: TextStyle(color: Color(0xFFD6E4FF), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'Project name',
                    hintText: 'e.g. Inala Bus Terminal',
                    prefixIcon: Icon(Icons.folder_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientCtl,
                  decoration: const InputDecoration(
                    labelText: 'Client / Employer',
                    hintText: 'e.g. Government / Agency',
                    prefixIcon: Icon(Icons.business_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtl,
                  decoration: const InputDecoration(
                    labelText: 'Client location',
                    hintText: 'e.g. Tabora Municipality',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedRegion,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Region',
                          prefixIcon: Icon(Icons.map_outlined),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                        items:
                            tzRegions
                                .map(
                                  (region) => DropdownMenuItem(
                                    value: region,
                                    child: Text(
                                      region,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => selectedRegion = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: districtCtl,
                        decoration: const InputDecoration(
                          labelText: 'District',
                          prefixIcon: Icon(Icons.place_outlined),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: currencyCtl,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          hintText: 'TZS',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ProjectStage>(
                        value: stage,
                        isExpanded: true,
                        selectedItemBuilder:
                            (context) =>
                                ProjectStage.values
                                    .map(
                                      (s) => Text(
                                        s.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                    .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Stage',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                        items:
                            ProjectStage.values
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 420,
                                      ),
                                      child: Text(
                                        '${s.label} — ${s.hint}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => stage = v ?? stage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD6E4FF)),
                  ),
                  child: const Text(
                    'Client details will be created in the Clients Directory and linked to this project.',
                    style: TextStyle(
                      color: Color(0xFF17448A),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tip: Choose “BOQ Verification” if the original BOQ was prepared elsewhere and you are re-measuring for comparison.',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.60),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Get.back(result: true),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create'),
          ),
        ],
      );
    },
  );

  // nameCtl.dispose();
  // clientCtl.dispose();

  try {
    if (result != true) return;

    final name = nameCtl.text.trim();
    final client = clientCtl.text.trim();
    final clientLocation = locationCtl.text.trim();
    final clientDistrict = districtCtl.text.trim();
    final clientRegion = (selectedRegion ?? '').trim();
    final currency =
        currencyCtl.text.trim().isEmpty ? 'TZS' : currencyCtl.text.trim();

    if (name.isEmpty || client.isEmpty) {
      Get.snackbar(
        'Missing info',
        'Project name and client name are required.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final canCreateProject = await SubscriptionService.instance
        .canCreateProject(user: user);
    if (!canCreateProject) {
      Get.snackbar(
        'Subscription required',
        'Free plan allows 1 project only. Please subscribe to add more projects.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final projectRef = projectsRef.doc();
    final clientId = _clientDocIdFromName(client);
    final clientRef = FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId);

    await projectRef.set({
      'projectId': projectRef.id,
      'name': name,
      'clientId': clientId,
      'clientName': client.isEmpty ? null : client,
      'client': client.isEmpty ? null : client,
      'region': clientRegion.isEmpty ? null : clientRegion,
      'currency': currency,
      'status': stageToStatus(stage),
      'ownerId': user?.uid,
      'members': user == null ? <String>[] : [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final clientSnap = await clientRef.get();
    await clientRef.set({
      if (!clientSnap.exists) 'clientName': client,
      'sourceClientName': client,
      if (clientLocation.isNotEmpty) 'location': clientLocation,
      if (clientRegion.isNotEmpty) 'region': clientRegion,
      if (clientDistrict.isNotEmpty) 'district': clientDistrict,
      'projectIds': FieldValue.arrayUnion([projectRef.id]),
      'projectNames': FieldValue.arrayUnion([name]),
      'createdFromProjects': true,
      if (!clientSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    Get.snackbar(
      'Project created',
      '$name has been created and linked to $client.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green[50],
      colorText: Colors.green,
    );
  } catch (e) {
    Get.snackbar(
      'Saving Error',
      'Error $e',
      colorText: Colors.red,
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.red[100],
    );
  } finally {
    nameCtl.dispose();
    clientCtl.dispose();
    locationCtl.dispose();
    districtCtl.dispose();
    currencyCtl.dispose();
  }
}

enum PaymentNoticeTone { info, success, error }

class CheckoutInput {
  const CheckoutInput({required this.phone, required this.provider});

  final String phone;
  final String provider;
}

String subToolLabel(String toolId) {
  switch (toolId) {
    case 'blockwork':
      return 'Blockwork / Brickwork';

    case 'plaster':
      return 'Plaster / Render';

    case 'painting':
      return 'Painting';

    case 'wall_tiles':
      return 'Wall Tiles';

    case 'skirting':
      return 'Skirting';

    case 'dpc':
      return 'DPC';

    case 'beam_concrete':
      return 'Beam Concrete';

    case 'beam_formwork':
      return 'Beam Formwork';

    case 'beam_reinforcement':
      return 'Beam Reinforcement';

    case 'lintels':
      return 'Lintels';

    case 'slab_concrete':
      return 'Concrete Slab';

    case 'slab_formwork':
      return 'Slab Formwork';

    case 'slab_reinforcement':
      return 'Slab Reinforcement';

    case 'floor_finish':
      return 'Floor Finish';

    case 'screed':
      return 'Screed';

    case 'excavation':
      return 'Excavation';

    case 'blinding':
      return 'Blinding';

    case 'strip_footing':
      return 'Strip Footing';

    case 'pad_footing':
      return 'Pad Footing';

    case 'raft_foundation':
      return 'Raft Foundation';

    case 'ground_beam':
      return 'Ground Beam';

    case 'backfilling':
      return 'Backfilling';

    case 'roof_covering':
      return 'Roof Covering';

    case 'ridge':
      return 'Ridge';

    case 'valley':
      return 'Valley';

    case 'flashing':
      return 'Flashing';

    case 'gutters':
      return 'Gutters';

    case 'trusses':
      return 'Trusses';

    case 'rafters':
      return 'Rafters';

    case 'purlins':
      return 'Purlins';

    case 'battens':
      return 'Battens';

    case 'bracing':
      return 'Bracing';

    case 'doors':
      return 'Doors';

    case 'windows':
      return 'Windows';

    case 'frames':
      return 'Frames';

    case 'ironmongery':
      return 'Ironmongery';

    case 'pipe_length':
      return 'Pipe Length';

    case 'fittings':
      return 'Fittings';

    case 'fixtures':
      return 'Fixtures';

    case 'cable_conduit':
      return 'Cable / Conduit';

    default:
      return toolId.replaceAll('_', ' ');
  }
}

double distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;

  final abSquared = (ab.dx * ab.dx) + (ab.dy * ab.dy);

  if (abSquared == 0) {
    return (point - a).distance;
  }

  var t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / abSquared;

  t = t.clamp(0.0, 1.0);

  final nearest = Offset(a.dx + (ab.dx * t), a.dy + (ab.dy * t));

  return (point - nearest).distance;
}

String titleCaseStatus(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (normalized.isEmpty) return 'Unknown';
  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.length == 1) return part.toUpperCase();
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String formatDate(DateTime? date) {
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  return '$day/$month/$year';
}

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

String formatMoney(num? amount, String currency) {
  if (amount == null) return '—';
  final code = currency.trim().isEmpty ? 'TZS' : currency.trim().toUpperCase();
  return '$code ${formatNumber(amount)}';
}

String formatNumber(num value) {
  final decimals = value % 1 == 0 ? 0 : 2;
  final text = value.toStringAsFixed(decimals);
  final parts = text.split('.');
  var whole = parts.first;
  final negative = whole.startsWith('-');
  if (negative) whole = whole.substring(1);

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }

  final formattedWhole = negative ? '-$buffer' : buffer.toString();
  if (parts.length == 1) return formattedWhole;
  return '$formattedWhole.${parts[1]}';
}

String formatDuration(Duration? duration) {
  if (duration == null) return '—';
  final milliseconds = duration.inMilliseconds.abs();
  final value = Duration(milliseconds: milliseconds);
  if (value.inDays > 0) {
    final hours = value.inHours.remainder(24);
    return hours == 0 ? '${value.inDays}d' : '${value.inDays}d ${hours}h';
  }
  if (value.inHours > 0) {
    final minutes = value.inMinutes.remainder(60);
    return minutes == 0 ? '${value.inHours}h' : '${value.inHours}h ${minutes}m';
  }
  if (value.inMinutes > 0) {
    final seconds = value.inSeconds.remainder(60);
    return seconds == 0
        ? '${value.inMinutes}m'
        : '${value.inMinutes}m ${seconds}s';
  }
  return '${value.inSeconds}s';
}

String formatPercent(double value) {
  final decimals = value == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)}%';
}

String asString(Object? value) => (value ?? '').toString().trim();

String firstText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = asString(data[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

int? firstInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

num? firstNum(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.replaceAll(',', '').trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

DateTime? readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

bool isSuccessfulPaymentStatus(String status) {
  final value = status.trim().toLowerCase();
  return const {
    'active',
    'approved',
    'complete',
    'completed',
    'paid',
    'success',
    'successful',
  }.contains(value);
}

bool isFailedPaymentStatus(String status) {
  final value = status.trim().toLowerCase();
  return const {
    'cancelled',
    'canceled',
    'checkout_failed',
    'declined',
    'error',
    'expired',
    'failed',
    'failure',
    'rejected',
  }.contains(value);
}

Set<String> projectMemberIds(Map<String, dynamic> data) {
  final memberIds = <String>{};
  for (final key in ['members', 'memberIds', 'memberUids']) {
    final value = data[key];
    if (value is Iterable) {
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) {
          memberIds.add(item.trim());
        } else if (item is Map && item['uid'] is String) {
          final uid = (item['uid'] as String).trim();
          if (uid.isNotEmpty) memberIds.add(uid);
        }
      }
    }
  }
  return memberIds;
}

({Color bg, Color fg, Color border}) pillColors(PillTone tone) {
  return switch (tone) {
    PillTone.blue => (
      bg: AqsColors.primarySoft,
      fg: AqsColors.primary,
      border: const Color(0xFFD1E0FF),
    ),
    PillTone.green => (
      bg: AqsColors.successSoft,
      fg: AqsColors.success,
      border: const Color(0xFFA6F4C5),
    ),
    PillTone.grey => (
      bg: const Color(0xFFF2F4F7),
      fg: AqsColors.muted,
      border: const Color(0xFFE4E7EC),
    ),
    PillTone.red => (
      bg: const Color(0xFFFFF1F3),
      fg: const Color(0xFFC01048),
      border: const Color(0xFFFECDD6),
    ),
    PillTone.amber => (
      bg: const Color(0xFFFFFAEB),
      fg: const Color(0xFFB54708),
      border: const Color(0xFFFEDF89),
    ),
  };
}
