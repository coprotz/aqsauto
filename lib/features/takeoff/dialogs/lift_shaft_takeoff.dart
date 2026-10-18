import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';

// -----------------------------------------------------------------------------
// AQS LIFT SHAFT TAKE-OFF
// -----------------------------------------------------------------------------
// Expected to already exist in the AQS project:
//   class BoqPick { String id; String code; String description; }
//   Future<BoqPick?> showBoqPickerDialog({required BuildContext context})
//   double rebarUnitWeightKgPerM(int diaMm)
//
// p1 and p2 are opposite corners of the SHAFT WALL outer rectangle drawn on the PDF.
// The pit/foundation and excavation footprints are entered separately because
// they may be larger than the shaft wall footprint.
// drawingData['pixelsPerUnit'] is expected to be pixels per metre.
// -----------------------------------------------------------------------------

enum LiftShaftSaveAction { cancel, addMore, finish }

class _LiftZone {
  _LiftZone({
    required this.fromCtrl,
    required this.toCtrl,
    required this.heightCtrl,
    required this.thicknessCtrl,
    required this.vertDiaCtrl,
    required this.vertSpacingCtrl,
    required this.horizDiaCtrl,
    required this.horizSpacingCtrl,
    required this.facesCtrl,
    required this.section,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController thicknessCtrl;
  final TextEditingController vertDiaCtrl;
  final TextEditingController vertSpacingCtrl;
  final TextEditingController horizDiaCtrl;
  final TextEditingController horizSpacingCtrl;
  final TextEditingController facesCtrl;
  String section; // 'substructure' or 'superstructure'

  void dispose() {
    fromCtrl.dispose();
    toCtrl.dispose();
    heightCtrl.dispose();
    thicknessCtrl.dispose();
    vertDiaCtrl.dispose();
    vertSpacingCtrl.dispose();
    horizDiaCtrl.dispose();
    horizSpacingCtrl.dispose();
    facesCtrl.dispose();
  }
}

class _LiftOpening {
  _LiftOpening({
    required this.zoneCtrl,
    required this.widthCtrl,
    required this.heightCtrl,
    required this.qtyCtrl,
  });

  // 1-based zone number to keep the UI simple.
  final TextEditingController zoneCtrl;
  final TextEditingController widthCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController qtyCtrl;

  void dispose() {
    zoneCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
    qtyCtrl.dispose();
  }
}

Future<LiftShaftSaveAction> openLiftShaftTakeoffFromRectangle({
  required Offset p1,
  required Offset p2,
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Map<String, dynamic> lastDefaults,
  required Future<BoqPick?> Function(BuildContext ctx) showBoqPicker,
  String? activeLabel,
  VoidCallback? onCloseDraft,
  VoidCallback? onUpdateViewer,
}) async {
  final ctx = Get.context;
  if (ctx == null) return LiftShaftSaveAction.cancel;

  double numD(dynamic v, double fb) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fb;
  }

  int numI(dynamic v, int fb) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? fb;
  }

  double parseD(TextEditingController c, double fb) =>
      double.tryParse(c.text.trim()) ?? fb;
  int parseI(TextEditingController c, int fb) =>
      int.tryParse(c.text.trim()) ?? fb;

  TextEditingController defCtrl(String key, String fallback) {
    final v = lastDefaults[key];
    return TextEditingController(text: v == null ? fallback : '$v');
  }

  Map<String, dynamic>? pickToMap(BoqPick? p) => p == null
      ? null
      : {'id': p.id, 'code': p.code, 'description': p.description};

  BoqPick? pickFromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = '${m['id'] ?? ''}'.trim();
    final code = '${m['code'] ?? ''}'.trim();
    final desc = '${m['description'] ?? ''}'.trim();
    if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
    return BoqPick(id: id, code: code, description: desc);
  }

  bool boolDef(String key, bool fb) {
    final v = lastDefaults[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '${v ?? ''}'.toLowerCase();
    if (['true', '1', 'yes', 'y'].contains(s)) return true;
    if (['false', '0', 'no', 'n'].contains(s)) return false;
    return fb;
  }

  InputDecoration deco(String label, {String? suffix, String? hint}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  final pxPerM = numD(drawingData['pixelsPerUnit'], 0);
  final calibrated = drawingData['calibrated'] == true || pxPerM > 0;
  if (!calibrated || pxPerM <= 0) {
    Get.snackbar('Not calibrated', 'Calibrate the drawing first.');
    return LiftShaftSaveAction.cancel;
  }

  final measuredX = (p2.dx - p1.dx).abs() / pxPerM;
  final measuredY = (p2.dy - p1.dy).abs() / pxPerM;
  if (measuredX <= 0 || measuredY <= 0) {
    Get.snackbar('Invalid rectangle', 'Draw the lift shaft outer rectangle again.');
    return LiftShaftSaveAction.cancel;
  }

  final labelCtrl = defCtrl('label', (activeLabel ?? 'Lift shaft').trim());
  // Always start shaft geometry from the rectangle just measured on this drawing.
  // Do not reuse the previous shaft dimensions for a new measurement.
  final extLengthCtrl = TextEditingController(text: measuredX.toStringAsFixed(3));
  final extWidthCtrl = TextEditingController(text: measuredY.toStringAsFixed(3));

  // Earthworks / pit foundation. The pit/base plan dimensions are independent
  // of the shaft rectangle measured above. Excavation is derived by adding
  // working space to the pit/base dimensions.
  final excavationDepthCtrl = defCtrl('excavationDepthM', '1.50');
  final workingSpaceCtrl = defCtrl('workingSpaceM', '0.50');
  final baseLengthCtrl = defCtrl('baseLengthM', '');
  final baseWidthCtrl = defCtrl('baseWidthM', '');
  final baseThicknessCtrl = defCtrl('baseThicknessM', '0.300');
  final blindingThicknessCtrl = defCtrl('blindingThicknessM', '0.050');
  final hardcoreThicknessCtrl = defCtrl('hardcoreThicknessM', '0.150');
  final bulkingFactorCtrl = defCtrl('bulkingFactor', '1.00');
  final haulDistanceCtrl = defCtrl('haulDistanceKm', '0');

  // Base reinforcement.
  final baseCoverCtrl = defCtrl('baseCoverMm', '50');
  final baseBottomXDiaCtrl = defCtrl('baseBottomXDiaMm', '12');
  final baseBottomXSpCtrl = defCtrl('baseBottomXSpacingMm', '200');
  final baseBottomYDiaCtrl = defCtrl('baseBottomYDiaMm', '12');
  final baseBottomYSpCtrl = defCtrl('baseBottomYSpacingMm', '200');
  final baseTopXDiaCtrl = defCtrl('baseTopXDiaMm', '12');
  final baseTopXSpCtrl = defCtrl('baseTopXSpacingMm', '200');
  final baseTopYDiaCtrl = defCtrl('baseTopYDiaMm', '12');
  final baseTopYSpCtrl = defCtrl('baseTopYSpacingMm', '200');
  final rebarWasteCtrl = defCtrl('rebarWastePercent', '5');

  bool includeExcavation = boolDef('includeExcavation', true);
  bool includeBackfill = boolDef('includeBackfill', true);
  bool reuseExcavatedForBackfill = boolDef('reuseExcavatedForBackfill', true);
  bool disposeAllExcavated = boolDef('disposeAllExcavated', false);
  bool includeDisposal = boolDef('includeDisposal', true);
  bool includeBlinding = boolDef('includeBlinding', true);
  bool includeHardcore = boolDef('includeHardcore', false);
  bool includeBaseConcrete = boolDef('includeBaseConcrete', true);
  bool includeWallConcrete = boolDef('includeWallConcrete', true);
  bool includeFormwork = boolDef('includeFormwork', true);
  bool includeWallRebar = boolDef('includeWallRebar', true);
  bool includeBaseRebar = boolDef('includeBaseRebar', true);

  final zones = <_LiftZone>[];
  final openings = <_LiftOpening>[];

  _LiftZone newZone({
    String from = 'Foundation',
    String to = 'GFL',
    String height = '3.000',
    String thickness = '0.200',
    String vDia = '12',
    String vSp = '200',
    String hDia = '12',
    String hSp = '200',
    String faces = '2',
    String section = 'substructure',
  }) =>
      _LiftZone(
        fromCtrl: TextEditingController(text: from),
        toCtrl: TextEditingController(text: to),
        heightCtrl: TextEditingController(text: height),
        thicknessCtrl: TextEditingController(text: thickness),
        vertDiaCtrl: TextEditingController(text: vDia),
        vertSpacingCtrl: TextEditingController(text: vSp),
        horizDiaCtrl: TextEditingController(text: hDia),
        horizSpacingCtrl: TextEditingController(text: hSp),
        facesCtrl: TextEditingController(text: faces),
        section: section,
      );

  _LiftOpening newOpening({
    String zone = '1',
    String width = '1.000',
    String height = '2.100',
    String qty = '1',
  }) =>
      _LiftOpening(
        zoneCtrl: TextEditingController(text: zone),
        widthCtrl: TextEditingController(text: width),
        heightCtrl: TextEditingController(text: height),
        qtyCtrl: TextEditingController(text: qty),
      );

  final savedZones = lastDefaults['zones'];
  if (savedZones is List && savedZones.isNotEmpty) {
    for (final z in savedZones) {
      if (z is! Map) continue;
      zones.add(newZone(
        from: '${z['from'] ?? 'Foundation'}',
        to: '${z['to'] ?? 'GFL'}',
        height: '${z['heightM'] ?? 3.0}',
        thickness: '${z['thicknessM'] ?? 0.2}',
        vDia: '${z['vertDiaMm'] ?? 12}',
        vSp: '${z['vertSpacingMm'] ?? 200}',
        hDia: '${z['horizDiaMm'] ?? 12}',
        hSp: '${z['horizSpacingMm'] ?? 200}',
        faces: '${z['faces'] ?? 2}',
        section: '${z['section'] ?? ((zones.isEmpty) ? 'substructure' : 'superstructure')}',
      ));
    }
  }
  if (zones.isEmpty) {
    zones.add(newZone(section: 'substructure'));
  }

  final savedOpenings = lastDefaults['openings'];
  if (savedOpenings is List) {
    for (final o in savedOpenings) {
      if (o is! Map) continue;
      openings.add(newOpening(
        zone: '${o['zone'] ?? 1}',
        width: '${o['widthM'] ?? 1.0}',
        height: '${o['heightM'] ?? 2.1}',
        qty: '${o['qty'] ?? 1}',
      ));
    }
  }

  // BOQ selections. Excavation is measured in 1.5 m depth bands.
  const double excavationBandDepthM = 1.5;
  const int maxExcavationBands = 20; // supports excavation up to 30 m
  final savedExcavationBandBoqs = lastDefaults['boqExcavationBands'];
  final List<BoqPick?> boqExcavationBands = List<BoqPick?>.generate(
    maxExcavationBands,
    (i) {
      if (savedExcavationBandBoqs is List && i < savedExcavationBandBoqs.length) {
        return pickFromMap(savedExcavationBandBoqs[i]);
      }
      return null;
    },
  );
  BoqPick? boqBackfill = pickFromMap(lastDefaults['boqBackfill']);
  BoqPick? boqImportedFill = pickFromMap(lastDefaults['boqImportedFill']);
  BoqPick? boqDisposal = pickFromMap(lastDefaults['boqDisposal']);
  BoqPick? boqHardcore = pickFromMap(lastDefaults['boqHardcore']);
  BoqPick? boqBlinding = pickFromMap(lastDefaults['boqBlinding']);
  BoqPick? boqBaseConcrete = pickFromMap(lastDefaults['boqBaseConcrete']);
  BoqPick? boqSubWallConcrete = pickFromMap(lastDefaults['boqSubWallConcrete'] ?? lastDefaults['boqWallConcrete']);
  BoqPick? boqSuperWallConcrete = pickFromMap(lastDefaults['boqSuperWallConcrete']);
  BoqPick? boqSubFormwork = pickFromMap(lastDefaults['boqSubFormwork'] ?? lastDefaults['boqFormwork']);
  BoqPick? boqSuperFormwork = pickFromMap(lastDefaults['boqSuperFormwork']);
  BoqPick? boqSubWallRebar = pickFromMap(lastDefaults['boqSubWallRebar'] ?? lastDefaults['boqWallRebar']);
  BoqPick? boqSuperWallRebar = pickFromMap(lastDefaults['boqSuperWallRebar']);
  BoqPick? boqBaseRebar = pickFromMap(lastDefaults['boqBaseRebar']);

  Future<void> pickBoq(
    BuildContext c,
    void Function(BoqPick p) apply,
    StateSetter setState,
  ) async {
    final p = await showBoqPicker(c);
    if (p == null) return;
    setState(() => apply(p));
  }

  Widget boqLine(
    String title,
    BoqPick? boq,
    VoidCallback onPick,
    VoidCallback onClear,
    bool enabled,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                boq == null
                    ? 'BOQ item not selected'
                    : '${boq.code}  ${boq.description}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: boq == null ? Colors.orange.shade800 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: enabled ? onPick : null,
          child: Text(boq == null ? 'Select BOQ' : 'Change'),
        ),
        if (boq != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: enabled ? onClear : null,
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
          ),
        ],
      ],
    );
  }

  Widget panel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // Returned by live calculator and reused for save.
  Map<String, dynamic> calc() {
    final L = parseD(extLengthCtrl, measuredX);
    final W = parseD(extWidthCtrl, measuredY);
    final baseL = math.max(0.0, parseD(baseLengthCtrl, 0));
    final baseW = math.max(0.0, parseD(baseWidthCtrl, 0));
    final baseT = parseD(baseThicknessCtrl, 0.3);
    final excD = parseD(excavationDepthCtrl, 1.5);
    final ws = parseD(workingSpaceCtrl, 0.5);
    final blindT = includeBlinding ? parseD(blindingThicknessCtrl, 0.05) : 0.0;
    final hardT = includeHardcore ? parseD(hardcoreThicknessCtrl, 0.15) : 0.0;
    final bulk = math.max(0.0, parseD(bulkingFactorCtrl, 1.0));

    // Excavation footprint = pit/base footprint + working space on both sides.
    final excL = math.max(0.0, baseL + 2 * ws);
    final excW = math.max(0.0, baseW + 2 * ws);
    final excavationArea = excL * excW;
    final excavation = includeExcavation ? excavationArea * math.max(0.0, excD) : 0.0;
    final excavationBands = <Map<String, dynamic>>[];
    if (includeExcavation && excD > 0) {
      final bandCount = math.min(maxExcavationBands, (excD / excavationBandDepthM).ceil());
      for (var i = 0; i < bandCount; i++) {
        final start = i * excavationBandDepthM;
        final end = math.min((i + 1) * excavationBandDepthM, excD);
        final thickness = math.max(0.0, end - start);
        excavationBands.add({
          'index': i,
          'startDepthM': start,
          'endDepthM': end,
          'thicknessM': thickness,
          'quantityM3': excavationArea * thickness,
        });
      }
    }
    final blinding = includeBlinding ? baseL * baseW * blindT : 0.0;
    final hardcore = includeHardcore ? baseL * baseW * hardT : 0.0;
    final baseConcrete = includeBaseConcrete ? baseL * baseW * baseT : 0.0;

    double wallConcrete = 0;
    double wallFormwork = 0;
    double wallRebarKg = 0;
    double subWallConcrete = 0;
    double subWallFormwork = 0;
    double subWallRebarKg = 0;
    double superWallConcrete = 0;
    double superWallFormwork = 0;
    double superWallRebarKg = 0;
    double belowGroundWallConcrete = 0;
    final zoneRows = <Map<String, dynamic>>[];
    final wasteFactor = 1 + parseD(rebarWasteCtrl, 5).clamp(0, 100) / 100.0;

    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      final H = math.max(0.0, parseD(z.heightCtrl, 0));
      final t = math.max(0.0, parseD(z.thicknessCtrl, 0.2));
      final faces = parseI(z.facesCtrl, 2).clamp(1, 2);

      final innerL = math.max(0.0, L - 2 * t);
      final innerW = math.max(0.0, W - 2 * t);
      final outerP = 2 * (L + W);
      final innerP = 2 * (innerL + innerW);
      final clP = 2 * (math.max(0.0, L - t) + math.max(0.0, W - t));

      double openingArea = 0;
      double openingVol = 0;
      double reveals = 0;
      for (final o in openings) {
        if (parseI(o.zoneCtrl, 1) != i + 1) continue;
        final ow = math.max(0.0, parseD(o.widthCtrl, 0));
        final oh = math.max(0.0, parseD(o.heightCtrl, 0));
        final oq = math.max(0, parseI(o.qtyCtrl, 0));
        openingArea += ow * oh * oq;
        openingVol += ow * oh * t * oq;
        // Two jambs + head. Bottom sill is normally not formed as a reveal.
        reveals += (2 * oh + ow) * t * oq;
      }

      final grossWallV = clP * t * H;
      final netWallV = math.max(0.0, grossWallV - openingVol);
      final grossFaceFwk = (outerP + innerP) * H;
      final netFaceFwk = math.max(0.0, grossFaceFwk - 2 * openingArea);
      final fwk = netFaceFwk + reveals;

      // Approximate wall reinforcement. Openings are intentionally not deducted;
      // local trimming bars around openings normally offset the simple deduction.
      final vDia = parseI(z.vertDiaCtrl, 12).clamp(6, 50);
      final vSp = math.max(1.0, parseD(z.vertSpacingCtrl, 200));
      final hDia = parseI(z.horizDiaCtrl, 12).clamp(6, 50);
      final hSp = math.max(1.0, parseD(z.horizSpacingCtrl, 200));
      final nVertPerFace = (clP * 1000 / vSp).floor() + 1;
      final nHorizPerFace = (H * 1000 / hSp).floor() + 1;
      final vKg = nVertPerFace * H * rebarUnitWeightKgPerM(vDia) * faces;
      final hKg = nHorizPerFace * clP * rebarUnitWeightKgPerM(hDia) * faces;
      final rbKg = includeWallRebar ? (vKg + hKg) * wasteFactor : 0.0;

      if (includeWallConcrete) wallConcrete += netWallV;
      if (includeFormwork) wallFormwork += fwk;
      if (includeWallRebar) wallRebarKg += rbKg;

      final isSubstructure = z.section == 'substructure';
      if (isSubstructure) {
        if (includeWallConcrete) subWallConcrete += netWallV;
        if (includeFormwork) subWallFormwork += fwk;
        if (includeWallRebar) subWallRebarKg += rbKg;
        belowGroundWallConcrete += netWallV;
      } else {
        if (includeWallConcrete) superWallConcrete += netWallV;
        if (includeFormwork) superWallFormwork += fwk;
        if (includeWallRebar) superWallRebarKg += rbKg;
      }

      zoneRows.add({
        'zone': i + 1,
        'section': z.section,
        'from': z.fromCtrl.text.trim(),
        'to': z.toCtrl.text.trim(),
        'heightM': H,
        'thicknessM': t,
        'concreteM3': netWallV,
        'formworkM2': fwk,
        'rebarKg': rbKg,
        'vertDiaMm': vDia,
        'vertSpacingMm': vSp,
        'horizDiaMm': hDia,
        'horizSpacingMm': hSp,
        'faces': faces,
      });
    }

    // Permanent works occupying the excavation. This deliberately includes only
    // below-ground items. If the first wall zone extends above ground, split it.
    final permanentBelowGround =
        baseConcrete + blinding + hardcore + belowGroundWallConcrete;
    final backfill = includeBackfill
        ? math.max(0.0, excavation - permanentBelowGround)
        : 0.0;

    double reusedBackfill = 0;
    double importedBackfill = 0;
    if (includeBackfill) {
      if (reuseExcavatedForBackfill && !disposeAllExcavated) {
        reusedBackfill = math.min(backfill, excavation);
        importedBackfill = math.max(0.0, backfill - reusedBackfill);
      } else {
        importedBackfill = backfill;
      }
    }

    double disposalBankM3 = 0;
    if (includeDisposal) {
      disposalBankM3 = disposeAllExcavated
          ? excavation
          : math.max(0.0, excavation - reusedBackfill);
    }
    final disposalLooseM3 = disposalBankM3 * bulk;

    // Base reinforcement: four mats/directions can have different diameters.
    double baseBarSetKg(
      int dia,
      double spacingMm,
      double barRunM,
      double distributionM,
      double coverM,
    ) {
      if (spacingMm <= 0 || barRunM <= 2 * coverM || distributionM <= 2 * coverM) {
        return 0;
      }
      final n = (((distributionM - 2 * coverM) * 1000) / spacingMm).floor() + 1;
      final len = barRunM - 2 * coverM;
      return n * len * rebarUnitWeightKgPerM(dia);
    }

    final coverM = parseD(baseCoverCtrl, 50) / 1000.0;
    double baseRebarKg = 0;
    if (includeBaseRebar) {
      baseRebarKg += baseBarSetKg(
        parseI(baseBottomXDiaCtrl, 12).clamp(6, 50),
        parseD(baseBottomXSpCtrl, 200),
        baseL,
        baseW,
        coverM,
      );
      baseRebarKg += baseBarSetKg(
        parseI(baseBottomYDiaCtrl, 12).clamp(6, 50),
        parseD(baseBottomYSpCtrl, 200),
        baseW,
        baseL,
        coverM,
      );
      baseRebarKg += baseBarSetKg(
        parseI(baseTopXDiaCtrl, 12).clamp(6, 50),
        parseD(baseTopXSpCtrl, 200),
        baseL,
        baseW,
        coverM,
      );
      baseRebarKg += baseBarSetKg(
        parseI(baseTopYDiaCtrl, 12).clamp(6, 50),
        parseD(baseTopYSpCtrl, 200),
        baseW,
        baseL,
        coverM,
      );
      baseRebarKg *= wasteFactor;
    }

    return {
      'externalLengthM': L,
      'externalWidthM': W,
      'baseLengthM': baseL,
      'baseWidthM': baseW,
      'baseThicknessM': baseT,
      'excavationLengthM': excL,
      'excavationWidthM': excW,
      'excavationDepthM': excD,
      'workingSpaceM': ws,
      'excavationM3': excavation,
      'excavationAreaM2': excavationArea,
      'excavationBands': excavationBands,
      'backfillM3': backfill,
      'reusedBackfillM3': reusedBackfill,
      'importedBackfillM3': importedBackfill,
      'disposalBankM3': disposalBankM3,
      'disposalLooseM3': disposalLooseM3,
      'bulkingFactor': bulk,
      'hardcoreM3': hardcore,
      'blindingM3': blinding,
      'baseConcreteM3': baseConcrete,
      'wallConcreteM3': wallConcrete,
      'wallFormworkM2': wallFormwork,
      'wallRebarKg': wallRebarKg,
      'subWallConcreteM3': subWallConcrete,
      'subWallFormworkM2': subWallFormwork,
      'subWallRebarKg': subWallRebarKg,
      'superWallConcreteM3': superWallConcrete,
      'superWallFormworkM2': superWallFormwork,
      'superWallRebarKg': superWallRebarKg,
      'baseRebarKg': baseRebarKg,
      'permanentBelowGroundM3': permanentBelowGround,
      'zoneRows': zoneRows,
    };
  }

  bool geometryReady() {
    final shaftL = math.max(0.0, parseD(extLengthCtrl, 0));
    final shaftW = math.max(0.0, parseD(extWidthCtrl, 0));
    if (shaftL <= 0 || shaftW <= 0) return false;

    final needsPitGeometry = includeExcavation ||
        includeBackfill ||
        includeDisposal ||
        includeHardcore ||
        includeBlinding ||
        includeBaseConcrete ||
        includeBaseRebar;
    if (!needsPitGeometry) return true;

    final baseL = math.max(0.0, parseD(baseLengthCtrl, 0));
    final baseW = math.max(0.0, parseD(baseWidthCtrl, 0));
    if (baseL <= 0 || baseW <= 0) return false;

    if (includeExcavation || includeBackfill || includeDisposal) {
      if (math.max(0.0, parseD(excavationDepthCtrl, 0)) <= 0) return false;
    }
    return true;
  }

  bool boqsReady() {
    if (includeExcavation) {
      final depth = math.max(0.0, parseD(excavationDepthCtrl, 0));
      final bandCount = math.min(maxExcavationBands, (depth / excavationBandDepthM).ceil());
      if (depth <= 0 || depth > maxExcavationBands * excavationBandDepthM) return false;
      for (var i = 0; i < bandCount; i++) {
        if (boqExcavationBands[i] == null) return false;
      }
    }
    if (includeBackfill && reuseExcavatedForBackfill && boqBackfill == null) {
      return false;
    }
    if (includeBackfill && (!reuseExcavatedForBackfill || disposeAllExcavated) &&
        boqImportedFill == null) return false;
    if (includeDisposal && boqDisposal == null) return false;
    if (includeHardcore && boqHardcore == null) return false;
    if (includeBlinding && boqBlinding == null) return false;
    if (includeBaseConcrete && boqBaseConcrete == null) return false;
    final hasSubZones = zones.any((z) => z.section == 'substructure');
    final hasSuperZones = zones.any((z) => z.section == 'superstructure');
    if (includeWallConcrete && hasSubZones && boqSubWallConcrete == null) return false;
    if (includeWallConcrete && hasSuperZones && boqSuperWallConcrete == null) return false;
    if (includeFormwork && hasSubZones && boqSubFormwork == null) return false;
    if (includeFormwork && hasSuperZones && boqSuperFormwork == null) return false;
    if (includeWallRebar && hasSubZones && boqSubWallRebar == null) return false;
    if (includeWallRebar && hasSuperZones && boqSuperWallRebar == null) return false;
    if (includeBaseRebar && boqBaseRebar == null) return false;
    return true;
  }

  bool saving = false;

  final action = await showDialog<LiftShaftSaveAction>(
        context: ctx,
        barrierDismissible: false,
        builder: (dCtx) => StatefulBuilder(
          builder: (dCtx, setState) {
            final q = calc();

            Widget numberField(
              TextEditingController c,
              String label, {
              String? suffix,
            }) {
              return TextField(
                controller: c,
                enabled: !saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: deco(label, suffix: suffix),
                onChanged: (_) => setState(() {}),
              );
            }

            Widget metric(String label, String value) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 3),
                      Text(value,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                );

            return AlertDialog(
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.elevator_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labelCtrl.text.trim().isEmpty
                                ? 'Lift shaft take-off'
                                : labelCtrl.text.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Earthworks, backfill, disposal, concrete, formwork and reinforcement',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 1040,
                child: SingleChildScrollView(
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        panel(
                          title: 'Shaft geometry',
                          subtitle:
                              'Measure the external RC shaft wall rectangle only; pit/foundation dimensions are entered separately.',
                          icon: Icons.crop_square_rounded,
                          child: Column(
                            children: [
                              Row(children: [
                                Expanded(child: numberField(extLengthCtrl, 'External length', suffix: 'm')),
                                const SizedBox(width: 10),
                                Expanded(child: numberField(extWidthCtrl, 'External width', suffix: 'm')),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: labelCtrl,
                                    enabled: !saving,
                                    decoration: deco('Label'),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'Earthworks and pit foundation',
                          subtitle:
                              'Backfill is the excavation void left after permanent below-ground work.',
                          icon: Icons.landscape_rounded,
                          child: Column(
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  FilterChip(label: const Text('Excavation'), selected: includeExcavation, onSelected: saving ? null : (v) => setState(() => includeExcavation = v)),
                                  FilterChip(label: const Text('Backfill'), selected: includeBackfill, onSelected: saving ? null : (v) => setState(() => includeBackfill = v)),
                                  FilterChip(label: const Text('Disposal'), selected: includeDisposal, onSelected: saving ? null : (v) => setState(() => includeDisposal = v)),
                                  FilterChip(label: const Text('Hardcore'), selected: includeHardcore, onSelected: saving ? null : (v) => setState(() => includeHardcore = v)),
                                  FilterChip(label: const Text('Blinding'), selected: includeBlinding, onSelected: saving ? null : (v) => setState(() => includeBlinding = v)),
                                  FilterChip(label: const Text('RC base'), selected: includeBaseConcrete, onSelected: saving ? null : (v) => setState(() => includeBaseConcrete = v)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Pit / foundation geometry',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(child: numberField(baseLengthCtrl, 'Excavation pit/base length', suffix: 'm')),
                                const SizedBox(width: 8),
                                Expanded(child: numberField(baseWidthCtrl, 'Excavation pit/base width', suffix: 'm')),
                                const SizedBox(width: 8),
                                Expanded(child: numberField(baseThicknessCtrl, 'RC base thickness', suffix: 'm')),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(child: numberField(excavationDepthCtrl, 'Excavation depth', suffix: 'm')),
                                const SizedBox(width: 8),
                                Expanded(child: numberField(workingSpaceCtrl, 'Working space each side', suffix: 'm')),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: metric(
                                    'Calculated excavation footprint',
                                    '${(q['excavationLengthM'] as double).toStringAsFixed(3)} × ${(q['excavationWidthM'] as double).toStringAsFixed(3)} m',
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(child: numberField(blindingThicknessCtrl, 'Blinding thickness', suffix: 'm')),
                                const SizedBox(width: 8),
                                Expanded(child: numberField(hardcoreThicknessCtrl, 'Hardcore thickness', suffix: 'm')),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Excavation size is calculated from pit/base dimensions plus working space on both sides.',
                                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text('Reuse suitable excavated material for backfill'),
                                    value: reuseExcavatedForBackfill,
                                    onChanged: saving ? null : (v) => setState(() => reuseExcavatedForBackfill = v),
                                  ),
                                ),
                                Expanded(
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text('Dispose ALL excavated material'),
                                    value: disposeAllExcavated,
                                    onChanged: saving ? null : (v) => setState(() {
                                      disposeAllExcavated = v;
                                      if (v) reuseExcavatedForBackfill = false;
                                    }),
                                  ),
                                ),
                              ]),
                              Row(children: [
                                Expanded(child: numberField(bulkingFactorCtrl, 'Disposal bulking factor')),
                                const SizedBox(width: 8),
                                Expanded(child: numberField(haulDistanceCtrl, 'Haul distance (optional)', suffix: 'km')),
                                const Spacer(flex: 2),
                              ]),
                              const SizedBox(height: 12),
                              if (includeExcavation) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('Excavation depth breakdown', style: TextStyle(fontWeight: FontWeight.w800)),
                                ),
                                const SizedBox(height: 6),
                                for (final band in (q['excavationBands'] as List<Map<String, dynamic>>))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(children: [
                                      Expanded(child: Text(
                                        '${(band['startDepthM'] as double).toStringAsFixed(1)}–${(band['endDepthM'] as double).toStringAsFixed(1)} m',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      )),
                                      Text('${(band['quantityM3'] as double).toStringAsFixed(3)} m³'),
                                    ]),
                                  ),
                              ],
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(child: metric('Excavation', '${(q['excavationM3'] as double).toStringAsFixed(3)} m³')),
                                const SizedBox(width: 8),
                                Expanded(child: metric('Backfill', '${(q['backfillM3'] as double).toStringAsFixed(3)} m³')),
                                const SizedBox(width: 8),
                                Expanded(child: metric('Disposal', '${(q['disposalLooseM3'] as double).toStringAsFixed(3)} m³')),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'Wall zones',
                          subtitle:
                              'Split the shaft wherever floor height, wall thickness or reinforcement changes.',
                          icon: Icons.view_in_ar_rounded,
                          child: Column(
                            children: [
                              for (var i = 0; i < zones.length; i++) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(children: [
                                    Row(children: [
                                      Text('Zone ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      const Spacer(),
                                      if (zones.length > 1)
                                        IconButton(
                                          onPressed: saving ? null : () => setState(() {
                                            final z = zones.removeAt(i);
                                            z.dispose();
                                          }),
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                    ]),
                                    Row(
                                      children: [
                                        const Text('Bill section:', style: TextStyle(fontWeight: FontWeight.w700)),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('Substructure'),
                                          selected: zones[i].section == 'substructure',
                                          onSelected: saving ? null : (_) => setState(() => zones[i].section = 'substructure'),
                                        ),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('Superstructure / Frame'),
                                          selected: zones[i].section == 'superstructure',
                                          onSelected: saving ? null : (_) => setState(() => zones[i].section = 'superstructure'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    Row(children: [
                                      Expanded(child: TextField(controller: zones[i].fromCtrl, enabled: !saving, decoration: deco('From'), onChanged: (_) => setState(() {}))),
                                      const SizedBox(width: 6),
                                      Expanded(child: TextField(controller: zones[i].toCtrl, enabled: !saving, decoration: deco('To'), onChanged: (_) => setState(() {}))),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].heightCtrl, 'Height', suffix: 'm')),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].thicknessCtrl, 'Wall thickness', suffix: 'm')),
                                    ]),
                                    const SizedBox(height: 7),
                                    Row(children: [
                                      Expanded(child: numberField(zones[i].vertDiaCtrl, 'Vertical dia', suffix: 'mm')),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].vertSpacingCtrl, 'Vertical spacing', suffix: 'mm')),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].horizDiaCtrl, 'Horizontal dia', suffix: 'mm')),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].horizSpacingCtrl, 'Horizontal spacing', suffix: 'mm')),
                                      const SizedBox(width: 6),
                                      Expanded(child: numberField(zones[i].facesCtrl, 'Faces')),
                                    ]),
                                  ]),
                                ),
                              ],
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: saving ? null : () => setState(() {
                                    final previousTo = zones.last.toCtrl.text.trim();
                                    zones.add(newZone(from: previousTo.isEmpty ? 'GFL' : previousTo, to: 'Next level', section: 'superstructure'));
                                  }),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add wall zone'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'Door / wall openings',
                          subtitle:
                              'Concrete and wall-face formwork are deducted; jamb and head reveals are added.',
                          icon: Icons.door_front_door_rounded,
                          child: Column(
                            children: [
                              for (var i = 0; i < openings.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: Row(children: [
                                    Expanded(child: numberField(openings[i].zoneCtrl, 'Zone no.')),
                                    const SizedBox(width: 6),
                                    Expanded(child: numberField(openings[i].widthCtrl, 'Width', suffix: 'm')),
                                    const SizedBox(width: 6),
                                    Expanded(child: numberField(openings[i].heightCtrl, 'Height', suffix: 'm')),
                                    const SizedBox(width: 6),
                                    Expanded(child: numberField(openings[i].qtyCtrl, 'Qty')),
                                    IconButton(
                                      onPressed: saving ? null : () => setState(() {
                                        final o = openings.removeAt(i);
                                        o.dispose();
                                      }),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ]),
                                ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: saving ? null : () => setState(() => openings.add(newOpening())),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add opening'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'Base reinforcement',
                          subtitle: 'Top and bottom bars in both directions.',
                          icon: Icons.grid_4x4_rounded,
                          child: Column(children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                FilterChip(label: const Text('Wall reinforcement'), selected: includeWallRebar, onSelected: saving ? null : (v) => setState(() => includeWallRebar = v)),
                                FilterChip(label: const Text('Base reinforcement'), selected: includeBaseRebar, onSelected: saving ? null : (v) => setState(() => includeBaseRebar = v)),
                                FilterChip(label: const Text('Wall concrete'), selected: includeWallConcrete, onSelected: saving ? null : (v) => setState(() => includeWallConcrete = v)),
                                FilterChip(label: const Text('Wall formwork'), selected: includeFormwork, onSelected: saving ? null : (v) => setState(() => includeFormwork = v)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: numberField(baseCoverCtrl, 'Cover', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(rebarWasteCtrl, 'Rebar waste', suffix: '%')),
                              const Spacer(flex: 2),
                            ]),
                            const SizedBox(height: 7),
                            Row(children: [
                              Expanded(child: numberField(baseBottomXDiaCtrl, 'Bottom X dia', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseBottomXSpCtrl, 'Bottom X spacing', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseBottomYDiaCtrl, 'Bottom Y dia', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseBottomYSpCtrl, 'Bottom Y spacing', suffix: 'mm')),
                            ]),
                            const SizedBox(height: 7),
                            Row(children: [
                              Expanded(child: numberField(baseTopXDiaCtrl, 'Top X dia', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseTopXSpCtrl, 'Top X spacing', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseTopYDiaCtrl, 'Top Y dia', suffix: 'mm')),
                              const SizedBox(width: 6),
                              Expanded(child: numberField(baseTopYSpCtrl, 'Top Y spacing', suffix: 'mm')),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'Live quantities',
                          subtitle: 'Calculated from the current lift-shaft inputs.',
                          icon: Icons.analytics_rounded,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SizedBox(width: 220, child: metric('Base concrete', '${(q['baseConcreteM3'] as double).toStringAsFixed(3)} m³')),
                              SizedBox(width: 220, child: metric('Substructure wall concrete', '${(q['subWallConcreteM3'] as double).toStringAsFixed(3)} m³')),
                              SizedBox(width: 220, child: metric('Superstructure wall concrete', '${(q['superWallConcreteM3'] as double).toStringAsFixed(3)} m³')),
                              SizedBox(width: 220, child: metric('Substructure wall formwork', '${(q['subWallFormworkM2'] as double).toStringAsFixed(3)} m²')),
                              SizedBox(width: 220, child: metric('Superstructure wall formwork', '${(q['superWallFormworkM2'] as double).toStringAsFixed(3)} m²')),
                              SizedBox(width: 220, child: metric('Substructure wall reinforcement', '${(q['subWallRebarKg'] as double).toStringAsFixed(2)} kg')),
                              SizedBox(width: 220, child: metric('Superstructure wall reinforcement', '${(q['superWallRebarKg'] as double).toStringAsFixed(2)} kg')),
                              SizedBox(width: 220, child: metric('Base reinforcement', '${(q['baseRebarKg'] as double).toStringAsFixed(2)} kg')),
                              SizedBox(width: 220, child: metric('Blinding', '${(q['blindingM3'] as double).toStringAsFixed(3)} m³')),
                              SizedBox(width: 220, child: metric('Hardcore', '${(q['hardcoreM3'] as double).toStringAsFixed(3)} m³')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        panel(
                          title: 'BOQ mapping',
                          subtitle: 'Select a BOQ item for each enabled output.',
                          icon: Icons.receipt_long_rounded,
                          child: Column(children: [
                            if (includeExcavation)
                              for (final band in (q['excavationBands'] as List<Map<String, dynamic>>))
                                boqLine(
                                  'Excavation ${(band['startDepthM'] as double).toStringAsFixed(1)}–${(band['endDepthM'] as double).toStringAsFixed(1)} m (m³)',
                                  boqExcavationBands[band['index'] as int],
                                  () => pickBoq(dCtx, (p) => boqExcavationBands[band['index'] as int] = p, setState),
                                  () => setState(() => boqExcavationBands[band['index'] as int] = null),
                                  !saving,
                                ),
                            if (includeBackfill && reuseExcavatedForBackfill && !disposeAllExcavated) boqLine('Return, fill and compact excavated material (m³)', boqBackfill, () => pickBoq(dCtx, (p) => boqBackfill = p, setState), () => setState(() => boqBackfill = null), !saving),
                            if (includeBackfill && (!reuseExcavatedForBackfill || disposeAllExcavated)) boqLine('Imported selected fill and compact (m³)', boqImportedFill, () => pickBoq(dCtx, (p) => boqImportedFill = p, setState), () => setState(() => boqImportedFill = null), !saving),
                            if (includeDisposal) boqLine('Dispose excavated material away from site (m³)', boqDisposal, () => pickBoq(dCtx, (p) => boqDisposal = p, setState), () => setState(() => boqDisposal = null), !saving),
                            if (includeHardcore) boqLine('Hardcore / granular fill (m³)', boqHardcore, () => pickBoq(dCtx, (p) => boqHardcore = p, setState), () => setState(() => boqHardcore = null), !saving),
                            if (includeBlinding) boqLine('Concrete blinding (m³)', boqBlinding, () => pickBoq(dCtx, (p) => boqBlinding = p, setState), () => setState(() => boqBlinding = null), !saving),
                            if (includeBaseConcrete) boqLine('RC lift pit/base (m³)', boqBaseConcrete, () => pickBoq(dCtx, (p) => boqBaseConcrete = p, setState), () => setState(() => boqBaseConcrete = null), !saving),
                            if (includeWallConcrete && zones.any((z) => z.section == 'substructure')) boqLine('RC lift shaft walls — Substructure (m³)', boqSubWallConcrete, () => pickBoq(dCtx, (p) => boqSubWallConcrete = p, setState), () => setState(() => boqSubWallConcrete = null), !saving),
                            if (includeWallConcrete && zones.any((z) => z.section == 'superstructure')) boqLine('RC lift shaft walls — Superstructure / Frame (m³)', boqSuperWallConcrete, () => pickBoq(dCtx, (p) => boqSuperWallConcrete = p, setState), () => setState(() => boqSuperWallConcrete = null), !saving),
                            if (includeFormwork && zones.any((z) => z.section == 'substructure')) boqLine('Formwork to lift shaft walls/reveals — Substructure (m²)', boqSubFormwork, () => pickBoq(dCtx, (p) => boqSubFormwork = p, setState), () => setState(() => boqSubFormwork = null), !saving),
                            if (includeFormwork && zones.any((z) => z.section == 'superstructure')) boqLine('Formwork to lift shaft walls/reveals — Superstructure / Frame (m²)', boqSuperFormwork, () => pickBoq(dCtx, (p) => boqSuperFormwork = p, setState), () => setState(() => boqSuperFormwork = null), !saving),
                            if (includeWallRebar && zones.any((z) => z.section == 'substructure')) boqLine('Reinforcement to shaft walls — Substructure (kg)', boqSubWallRebar, () => pickBoq(dCtx, (p) => boqSubWallRebar = p, setState), () => setState(() => boqSubWallRebar = null), !saving),
                            if (includeWallRebar && zones.any((z) => z.section == 'superstructure')) boqLine('Reinforcement to shaft walls — Superstructure / Frame (kg)', boqSuperWallRebar, () => pickBoq(dCtx, (p) => boqSuperWallRebar = p, setState), () => setState(() => boqSuperWallRebar = null), !saving),
                            if (includeBaseRebar) boqLine('Reinforcement to lift base (kg)', boqBaseRebar, () => pickBoq(dCtx, (p) => boqBaseRebar = p, setState), () => setState(() => boqBaseRebar = null), !saving),
                            if (!boqsReady())
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Select BOQ items for all enabled outputs before saving.',
                                    style: TextStyle(color: Color(0xFFB54708), fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Get.back(result: LiftShaftSaveAction.cancel),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: saving || !geometryReady() || !boqsReady() ? null : () => Get.back(result: LiftShaftSaveAction.addMore),
                  child: const Text('Save & Add another'),
                ),
                FilledButton.icon(
                  onPressed: saving || !geometryReady() || !boqsReady() ? null : () => Get.back(result: LiftShaftSaveAction.finish),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save & Finish'),
                ),
              ],
            );
          },
        ),
      ) ??
      LiftShaftSaveAction.cancel;

  if (action == LiftShaftSaveAction.cancel) {
    labelCtrl.dispose();
    extLengthCtrl.dispose();
    extWidthCtrl.dispose();
    excavationDepthCtrl.dispose();
    workingSpaceCtrl.dispose();
    baseLengthCtrl.dispose();
    baseWidthCtrl.dispose();
    baseThicknessCtrl.dispose();
    blindingThicknessCtrl.dispose();
    hardcoreThicknessCtrl.dispose();
    bulkingFactorCtrl.dispose();
    haulDistanceCtrl.dispose();
    baseCoverCtrl.dispose();
    baseBottomXDiaCtrl.dispose();
    baseBottomXSpCtrl.dispose();
    baseBottomYDiaCtrl.dispose();
    baseBottomYSpCtrl.dispose();
    baseTopXDiaCtrl.dispose();
    baseTopXSpCtrl.dispose();
    baseTopYDiaCtrl.dispose();
    baseTopYSpCtrl.dispose();
    rebarWasteCtrl.dispose();
    for (final z in zones) z.dispose();
    for (final o in openings) o.dispose();
    return LiftShaftSaveAction.cancel;
  }

  final q = calc();
  final label = labelCtrl.text.trim().isEmpty ? 'Lift shaft' : labelCtrl.text.trim();
  final assemblyId = measurementsRef.doc().id;
  final now = FieldValue.serverTimestamp();
  final p1m = {'x': p1.dx, 'y': p1.dy};
  final p2m = {'x': p2.dx, 'y': p2.dy};
  final polygon = [
    p1m,
    {'x': p2.dx, 'y': p1.dy},
    p2m,
    {'x': p1.dx, 'y': p2.dy},
  ];
  final sourceExternalLengthM = (q['externalLengthM'] as num).toDouble();
  final sourceExternalWidthM = (q['externalWidthM'] as num).toDouble();

  Map<String, dynamic> baseCommon() => {
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,
        'measureType': 'liftShaftAssembly',
        'typeGroup': 'liftShaftAssembly',
        'assemblyId': assemblyId,
        'label': label,
        'p1': p1m,
        'p2': p2m,
        'polygon': polygon,
        'rectangleSource': 'oppositeCorners',
        'sourceRectangleWidthPx': (p2.dx - p1.dx).abs(),
        'sourceRectangleHeightPx': (p2.dy - p1.dy).abs(),
        'sourceExternalLengthM': sourceExternalLengthM,
        'sourceExternalWidthM': sourceExternalWidthM,
        'sourceExternalAreaM2':
            sourceExternalLengthM * sourceExternalWidthM,
        'externalLengthM': q['externalLengthM'],
        'externalWidthM': q['externalWidthM'],
        'baseLengthM': q['baseLengthM'],
        'baseWidthM': q['baseWidthM'],
        'baseThicknessM': q['baseThicknessM'],
        'excavationLengthM': q['excavationLengthM'],
        'excavationWidthM': q['excavationWidthM'],
        'excavationDepthM': q['excavationDepthM'],
        'workingSpaceM': q['workingSpaceM'],
        'reuseExcavatedForBackfill': reuseExcavatedForBackfill,
        'disposeAllExcavated': disposeAllExcavated,
        'bulkingFactor': q['bulkingFactor'],
        'haulDistanceKm': parseD(haulDistanceCtrl, 0),
        'zones': q['zoneRows'],
        'openings': openings.map((o) => {
              'zone': parseI(o.zoneCtrl, 1),
              'widthM': parseD(o.widthCtrl, 0),
              'heightM': parseD(o.heightCtrl, 0),
              'qty': parseI(o.qtyCtrl, 0),
            }).toList(),
        'color': currentColor.value,
        'createdAt': now,
        'updatedAt': now,
      };

  void setQty(
    WriteBatch batch,
    String suffix,
    String type,
    String unit,
    double value,
    BoqPick boq, {
    Map<String, dynamic>? extra,
  }) {
    if (value <= 0) return;
    batch.set(measurementsRef.doc('$assemblyId-$suffix'), {
      ...baseCommon(),
      'type': type,
      'unit': unit,
      'value': value,
      'boqItemId': boq.id,
      'boqCode': boq.code,
      'boqDescription': boq.description,
      if (extra != null) ...extra,
    });
  }

  try {
    Get.dialog(
      const AlertDialog(
        content: SizedBox(
          width: 320,
          child: Row(children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator()),
            SizedBox(width: 12),
            Expanded(child: Text('Saving lift shaft take-off...')),
          ]),
        ),
      ),
      barrierDismissible: false,
    );

    final batch = FirebaseFirestore.instance.batch();

    if (includeExcavation) {
      final bands = q['excavationBands'] as List<Map<String, dynamic>>;
      for (final band in bands) {
        final i = band['index'] as int;
        final boq = boqExcavationBands[i];
        if (boq == null) continue;
        setQty(
          batch,
          'exc-band-${i + 1}',
          'liftShaftExcavationBand',
          'm3',
          band['quantityM3'] as double,
          boq,
          extra: {
            'excavationBandIndex': i + 1,
            'startDepthM': band['startDepthM'],
            'endDepthM': band['endDepthM'],
            'bandThicknessM': band['thicknessM'],
            'excavationAreaM2': q['excavationAreaM2'],
          },
        );
      }
    }
    if (includeBackfill && reuseExcavatedForBackfill && !disposeAllExcavated && boqBackfill != null) {
      setQty(batch, 'backfill-reuse', 'liftShaftBackfillReuse', 'm3', q['reusedBackfillM3'] as double, boqBackfill!);
    }
    if (includeBackfill && (!reuseExcavatedForBackfill || disposeAllExcavated) && boqImportedFill != null) {
      setQty(batch, 'backfill-imported', 'liftShaftBackfillImported', 'm3', q['importedBackfillM3'] as double, boqImportedFill!);
    }
    if (includeDisposal && boqDisposal != null) {
      setQty(
        batch,
        'disposal',
        'liftShaftDisposalOffSite',
        'm3',
        q['disposalLooseM3'] as double,
        boqDisposal!,
        extra: {'bankVolumeM3': q['disposalBankM3']},
      );
    }
    if (includeHardcore && boqHardcore != null) {
      setQty(batch, 'hardcore', 'liftShaftHardcore', 'm3', q['hardcoreM3'] as double, boqHardcore!);
    }
    if (includeBlinding && boqBlinding != null) {
      setQty(batch, 'blinding', 'liftShaftBlinding', 'm3', q['blindingM3'] as double, boqBlinding!);
    }
    if (includeBaseConcrete && boqBaseConcrete != null) {
      setQty(batch, 'base-conc', 'liftShaftBaseConcrete', 'm3', q['baseConcreteM3'] as double, boqBaseConcrete!);
    }
    if (includeWallConcrete && boqSubWallConcrete != null) {
      setQty(batch, 'wall-conc-sub', 'liftShaftWallConcreteSubstructure', 'm3', q['subWallConcreteM3'] as double, boqSubWallConcrete!, extra: {'billSection': 'substructure'});
    }
    if (includeWallConcrete && boqSuperWallConcrete != null) {
      setQty(batch, 'wall-conc-super', 'liftShaftWallConcreteSuperstructure', 'm3', q['superWallConcreteM3'] as double, boqSuperWallConcrete!, extra: {'billSection': 'superstructure'});
    }
    if (includeFormwork && boqSubFormwork != null) {
      setQty(batch, 'wall-fwk-sub', 'liftShaftWallFormworkSubstructure', 'm2', q['subWallFormworkM2'] as double, boqSubFormwork!, extra: {'billSection': 'substructure'});
    }
    if (includeFormwork && boqSuperFormwork != null) {
      setQty(batch, 'wall-fwk-super', 'liftShaftWallFormworkSuperstructure', 'm2', q['superWallFormworkM2'] as double, boqSuperFormwork!, extra: {'billSection': 'superstructure'});
    }
    if (includeWallRebar && boqSubWallRebar != null) {
      setQty(batch, 'wall-rb-sub', 'liftShaftWallRebarSubstructure', 'kg', q['subWallRebarKg'] as double, boqSubWallRebar!, extra: {'wastePercent': parseD(rebarWasteCtrl, 5), 'billSection': 'substructure'});
    }
    if (includeWallRebar && boqSuperWallRebar != null) {
      setQty(batch, 'wall-rb-super', 'liftShaftWallRebarSuperstructure', 'kg', q['superWallRebarKg'] as double, boqSuperWallRebar!, extra: {'wastePercent': parseD(rebarWasteCtrl, 5), 'billSection': 'superstructure'});
    }
    if (includeBaseRebar && boqBaseRebar != null) {
      setQty(batch, 'base-rb', 'liftShaftBaseRebar', 'kg', q['baseRebarKg'] as double, boqBaseRebar!, extra: {
        'coverMm': parseD(baseCoverCtrl, 50),
        'wastePercent': parseD(rebarWasteCtrl, 5),
      });
    }

    await batch.commit();
    if (Get.isDialogOpen == true) Get.back();

    lastDefaults
      ..['label'] = label
      ..['externalLengthM'] = q['externalLengthM']
      ..['externalWidthM'] = q['externalWidthM']
      ..['excavationDepthM'] = q['excavationDepthM']
      ..['workingSpaceM'] = q['workingSpaceM']
      ..['baseLengthM'] = q['baseLengthM']
      ..['baseWidthM'] = q['baseWidthM']
      ..['excavationLengthM'] = q['excavationLengthM']
      ..['excavationWidthM'] = q['excavationWidthM']
      ..['baseThicknessM'] = q['baseThicknessM']
      ..['blindingThicknessM'] = parseD(blindingThicknessCtrl, 0.05)
      ..['hardcoreThicknessM'] = parseD(hardcoreThicknessCtrl, 0.15)
      ..['bulkingFactor'] = q['bulkingFactor']
      ..['haulDistanceKm'] = parseD(haulDistanceCtrl, 0)
      ..['rebarWastePercent'] = parseD(rebarWasteCtrl, 5)
      ..['includeExcavation'] = includeExcavation
      ..['includeBackfill'] = includeBackfill
      ..['reuseExcavatedForBackfill'] = reuseExcavatedForBackfill
      ..['disposeAllExcavated'] = disposeAllExcavated
      ..['includeDisposal'] = includeDisposal
      ..['includeHardcore'] = includeHardcore
      ..['includeBlinding'] = includeBlinding
      ..['includeBaseConcrete'] = includeBaseConcrete
      ..['includeWallConcrete'] = includeWallConcrete
      ..['includeFormwork'] = includeFormwork
      ..['includeWallRebar'] = includeWallRebar
      ..['includeBaseRebar'] = includeBaseRebar
      ..['zones'] = q['zoneRows']
      ..['openings'] = openings.map((o) => {
            'zone': parseI(o.zoneCtrl, 1),
            'widthM': parseD(o.widthCtrl, 0),
            'heightM': parseD(o.heightCtrl, 0),
            'qty': parseI(o.qtyCtrl, 0),
          }).toList()
      ..['boqExcavationBands'] = boqExcavationBands.map(pickToMap).toList()
      ..['boqBackfill'] = pickToMap(boqBackfill)
      ..['boqImportedFill'] = pickToMap(boqImportedFill)
      ..['boqDisposal'] = pickToMap(boqDisposal)
      ..['boqHardcore'] = pickToMap(boqHardcore)
      ..['boqBlinding'] = pickToMap(boqBlinding)
      ..['boqBaseConcrete'] = pickToMap(boqBaseConcrete)
      ..['boqSubWallConcrete'] = pickToMap(boqSubWallConcrete)
      ..['boqSuperWallConcrete'] = pickToMap(boqSuperWallConcrete)
      ..['boqSubFormwork'] = pickToMap(boqSubFormwork)
      ..['boqSuperFormwork'] = pickToMap(boqSuperFormwork)
      ..['boqSubWallRebar'] = pickToMap(boqSubWallRebar)
      ..['boqSuperWallRebar'] = pickToMap(boqSuperWallRebar)
      ..['boqBaseRebar'] = pickToMap(boqBaseRebar);

    Get.snackbar('Saved', 'Lift shaft take-off saved.');
    onUpdateViewer?.call();
    onCloseDraft?.call();
  } catch (e) {
    if (Get.isDialogOpen == true) Get.back();
    Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    return LiftShaftSaveAction.cancel;
  } finally {
    labelCtrl.dispose();
    extLengthCtrl.dispose();
    extWidthCtrl.dispose();
    excavationDepthCtrl.dispose();
    workingSpaceCtrl.dispose();
    baseLengthCtrl.dispose();
    baseWidthCtrl.dispose();
    baseThicknessCtrl.dispose();
    blindingThicknessCtrl.dispose();
    hardcoreThicknessCtrl.dispose();
    bulkingFactorCtrl.dispose();
    haulDistanceCtrl.dispose();
    baseCoverCtrl.dispose();
    baseBottomXDiaCtrl.dispose();
    baseBottomXSpCtrl.dispose();
    baseBottomYDiaCtrl.dispose();
    baseBottomYSpCtrl.dispose();
    baseTopXDiaCtrl.dispose();
    baseTopXSpCtrl.dispose();
    baseTopYDiaCtrl.dispose();
    baseTopYSpCtrl.dispose();
    rebarWasteCtrl.dispose();
    for (final z in zones) z.dispose();
    for (final o in openings) o.dispose();
  }

  return action;
}
