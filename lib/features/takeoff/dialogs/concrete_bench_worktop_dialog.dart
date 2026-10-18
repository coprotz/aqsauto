import 'dart:math' as math;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _BoqTarget {
  _BoqTarget(this.title);
  final String title;
  final code = TextEditingController();
  final description = TextEditingController();

  void dispose() {
    code.dispose();
    description.dispose();
  }
}

class _SupportInput {
  _SupportInput({int index = 1})
      : name = TextEditingController(text: 'Support $index'),
        quantity = TextEditingController(text: '2'),
        lengthM = TextEditingController(text: '0.80'),
        thicknessM = TextEditingController(text: '0.15'),
        heightM = TextEditingController(text: '0.50');

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController lengthM;
  final TextEditingController thicknessM;
  final TextEditingController heightM;

  void dispose() {
    name.dispose();
    quantity.dispose();
    lengthM.dispose();
    thicknessM.dispose();
    heightM.dispose();
  }
}

class _OpeningInput {
  _OpeningInput({int index = 1})
      : name = TextEditingController(text: 'Opening $index'),
        quantity = TextEditingController(text: '1'),
        lengthM = TextEditingController(text: '0.60'),
        widthM = TextEditingController(text: '0.45');

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController lengthM;
  final TextEditingController widthM;

  void dispose() {
    name.dispose();
    quantity.dispose();
    lengthM.dispose();
    widthM.dispose();
  }
}

class _RebarInput {
  _RebarInput({int index = 1})
      : name = TextEditingController(text: 'R$index'),
        diameterMm = TextEditingController(text: '10'),
        spacingMm = TextEditingController(text: '150'),
        coverMm = TextEditingController(text: '25'),
        manualCount = TextEditingController(text: '1'),
        manualLengthM = TextEditingController(text: '1.00'),
        extraLengthM = TextEditingController(text: '0.00'),
        boqTarget = _BoqTarget('Reinforcement set $index');

  final TextEditingController name;
  final TextEditingController diameterMm;
  final TextEditingController spacingMm;
  final TextEditingController coverMm;
  final TextEditingController manualCount;
  final TextEditingController manualLengthM;
  final TextEditingController extraLengthM;
  final _BoqTarget boqTarget;

  String component = 'top';
  String layer = 'bottom';
  String supportFace = 'both';
  String direction = 'longitudinal';
  String countMode = 'auto';
  String lengthMode = 'auto';
  int supportIndex = 0;

  void dispose() {
    name.dispose();
    diameterMm.dispose();
    spacingMm.dispose();
    coverMm.dispose();
    manualCount.dispose();
    manualLengthM.dispose();
    extraLengthM.dispose();
    boqTarget.dispose();
  }
}

Future<bool> showConcreteBenchWorktopDialog({
  required List<Offset> polygon,
  required Map<String, dynamic> drawingData,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required Color currentColor,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Future<BoqPick?> Function(BuildContext context) pickBoq,
  String? activeLabel,
}) async {
  if (polygon.length < 3) return false;

  final calibrated = drawingData['calibrated'] == true;
  final pxPerM = drawingData['pixelsPerUnit'] is num
      ? (drawingData['pixelsPerUnit'] as num).toDouble()
      : double.tryParse('${drawingData['pixelsPerUnit'] ?? ''}') ?? 0;
  if (!calibrated || pxPerM <= 0) {
    Get.snackbar('Calibration required', 'Calibrate the drawing before measuring the bench/worktop.');
    return false;
  }

  double polygonAreaPx2(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return (sum / 2).abs();
  }

  double polygonPerimeterPx(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      sum += (pts[(i + 1) % pts.length] - pts[i]).distance;
    }
    return sum;
  }

  ({int count, double totalLengthM}) scanBars({
    required bool barsRunHorizontally,
    required double spacingMm,
    required double coverMm,
  }) {
    if (spacingMm <= 0 || polygon.length < 3) {
      return (count: 0, totalLengthM: 0);
    }
    final spacingPx = spacingMm / 1000.0 * pxPerM;
    final coverPx = math.max(0, coverMm) / 1000.0 * pxPerM;
    final xs = polygon.map((p) => p.dx).toList();
    final ys = polygon.map((p) => p.dy).toList();
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final scanMin = (barsRunHorizontally ? minY : minX) + coverPx;
    final scanMax = (barsRunHorizontally ? maxY : maxX) - coverPx;
    if (scanMax < scanMin) return (count: 0, totalLengthM: 0);

    final span = math.max(0, scanMax - scanMin);
    final spaces = math.max(1, (span / spacingPx).ceil());
    final actualSpacing = spaces == 0 ? 0.0 : span / spaces;
    var count = 0;
    var totalPx = 0.0;

    for (var i = 0; i <= spaces; i++) {
      final scan = scanMin + actualSpacing * i;
      final hits = <double>[];
      for (var j = 0; j < polygon.length; j++) {
        final a = polygon[j];
        final b = polygon[(j + 1) % polygon.length];
        if (barsRunHorizontally) {
          if ((a.dy <= scan && b.dy > scan) || (b.dy <= scan && a.dy > scan)) {
            final t = (scan - a.dy) / (b.dy - a.dy);
            hits.add(a.dx + t * (b.dx - a.dx));
          }
        } else {
          if ((a.dx <= scan && b.dx > scan) || (b.dx <= scan && a.dx > scan)) {
            final t = (scan - a.dx) / (b.dx - a.dx);
            hits.add(a.dy + t * (b.dy - a.dy));
          }
        }
      }
      hits.sort();
      for (var h = 0; h + 1 < hits.length; h += 2) {
        final segment = math.max(0, hits[h + 1] - hits[h] - 2 * coverPx);
        if (segment > 0) {
          totalPx += segment;
          count++;
        }
      }
    }
    return (count: count, totalLengthM: totalPx / pxPerM);
  }

  double d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  final grossTopAreaM2 = polygonAreaPx2(polygon) / (pxPerM * pxPerM);
  final topPerimeterM = polygonPerimeterPx(polygon) / pxPerM;
  final polygonData = polygon.map((p) => {'x': p.dx, 'y': p.dy}).toList();

  final nameCtrl = TextEditingController(text: activeLabel?.trim().isNotEmpty == true ? activeLabel!.trim() : 'Concrete bench / worktop');
  final topThicknessCtrl = TextEditingController(text: '0.15');
  final identicalQtyCtrl = TextEditingController(text: '1');
  final wasteCtrl = TextEditingController(text: '0');
  final supports = <_SupportInput>[_SupportInput()];
  final openings = <_OpeningInput>[];
  final rebars = <_RebarInput>[];

  final concreteBoq = _BoqTarget('Concrete');
  final formworkBoq = _BoqTarget('Formwork');
  final topFinishBoq = _BoqTarget('Top finish');
  final supportFinishBoq = _BoqTarget('Support finish');
  final allTargets = [concreteBoq, formworkBoq, topFinishBoq, supportFinishBoq];

  var includeConcrete = true;
  var includeFormwork = true;
  var includeRebar = false;
  var includeTopFinish = false;
  var includeSupportFinish = false;
  var includeSoffitFormwork = true;
  var includeTopEdgesFormwork = true;
  var includeSupportFormwork = true;
  var includeOpeningEdgesFormwork = true;
  String? errorText;

  Map<String, double> calcRebarSet(_RebarInput r) {
    final dia = math.max(0, d(r.diameterMm)).toDouble();
    final spacing = math.max(0, d(r.spacingMm)).toDouble();
    final cover = math.max(0, d(r.coverMm)).toDouble();
    final extraPerBar = math.max(0, d(r.extraLengthM)).toDouble();
    final layerFactor = r.component == 'top'
        ? (r.layer == 'both' ? 2.0 : 1.0)
        : (r.supportFace == 'both' ? 2.0 : 1.0);
    final identicalQty = math.max(1, n(identicalQtyCtrl)).toDouble();
    final wasteFactor = 1 + math.max(0, d(wasteCtrl)).toDouble() / 100.0;

    var countOne = 0.0;
    var totalLengthOne = 0.0;

    if (r.component == 'top') {
      final xs = polygon.map((p) => p.dx).toList();
      final ys = polygon.map((p) => p.dy).toList();
      final widthPx = xs.reduce(math.max) - xs.reduce(math.min);
      final heightPx = ys.reduce(math.max) - ys.reduce(math.min);
      final majorIsHorizontal = widthPx >= heightPx;
      final runHorizontal = r.direction == 'longitudinal'
          ? majorIsHorizontal
          : !majorIsHorizontal;
      final auto = scanBars(
        barsRunHorizontally: runHorizontal,
        spacingMm: spacing,
        coverMm: cover,
      );
      countOne = r.countMode == 'manual'
          ? math.max(0, n(r.manualCount)).toDouble()
          : auto.count.toDouble();
      if (r.lengthMode == 'manual') {
        totalLengthOne = countOne * math.max(0, d(r.manualLengthM)).toDouble();
      } else if (r.countMode == 'manual' && auto.count > 0) {
        totalLengthOne = countOne * (auto.totalLengthM / auto.count);
      } else {
        totalLengthOne = auto.totalLengthM;
      }
    } else if (supports.isNotEmpty) {
      final supportIndex = r.supportIndex.clamp(0, supports.length - 1).toInt();
      final support = supports[supportIndex];
      final supportQty = math.max(0, n(support.quantity)).toDouble();
      final supportLength = math.max(0, d(support.lengthM)).toDouble();
      final supportHeight = math.max(0, d(support.heightM)).toDouble();
      final coverM = cover / 1000.0;
      final clearAcross = math.max(
        0,
        (r.direction == 'vertical' ? supportLength : supportHeight) - 2 * coverM,
      );
      final autoCountPerSupport = spacing > 0
          ? (clearAcross * 1000.0 / spacing).ceil() + 1
          : 0;
      final autoBarLength = math.max(
        0,
        (r.direction == 'vertical' ? supportHeight : supportLength) - 2 * coverM,
      );
      countOne = r.countMode == 'manual'
          ? math.max(0, n(r.manualCount)).toDouble() * supportQty
          : (autoCountPerSupport * supportQty).toDouble();
      final barLength = r.lengthMode == 'manual'
          ? math.max(0, d(r.manualLengthM)).toDouble()
          : autoBarLength;
      totalLengthOne = countOne * barLength;
    }

    totalLengthOne += countOne * extraPerBar;
    countOne *= layerFactor;
    totalLengthOne *= layerFactor;

    final unitKgM = dia * dia / 162.0;
    final kgOneBeforeWaste = totalLengthOne * unitKgM;
    final kgOne = kgOneBeforeWaste * wasteFactor;

    return {
      'countOne': countOne,
      'lengthOne': totalLengthOne,
      'kgOne': kgOne,
      'countTotal': countOne * identicalQty,
      'lengthTotal': totalLengthOne * identicalQty,
      'kgTotal': kgOne * identicalQty,
      'unitKgM': unitKgM,
    };
  }

  String rebarSummary(_RebarInput r) {
    final m = calcRebarSet(r);
    final dia = d(r.diameterMm).toStringAsFixed(0);
    final spacing = d(r.spacingMm).toStringAsFixed(0);
    final layerOrFace = r.component == 'top'
        ? switch (r.layer) {
            'top' => 'Top layer',
            'both' => 'Top & bottom',
            _ => 'Bottom layer',
          }
        : (r.supportFace == 'both' ? 'Both faces' : 'Single face');
    final direction = r.direction == 'longitudinal'
        ? 'Longitudinal'
        : r.direction == 'transverse'
            ? 'Transverse'
            : r.direction == 'vertical'
                ? 'Vertical main bars'
                : 'Horizontal distribution';
    return '${r.name.text.trim().isEmpty ? 'Bar set' : r.name.text.trim()} • Y$dia @ $spacing • $layerOrFace • $direction → '
        '${m['countTotal']!.toStringAsFixed(0)} bars • ${m['lengthTotal']!.toStringAsFixed(2)} m • ${m['kgTotal']!.toStringAsFixed(2)} kg';
  }

  Map<String, double> calc() {
    final thickness = d(topThicknessCtrl);
    final qty = math.max(1, n(identicalQtyCtrl)).toDouble();
    var openingsArea = 0.0;
    var openingPerimeter = 0.0;
    for (final o in openings) {
      final q = math.max(0, n(o.quantity)).toDouble();
      final l = math.max(0, d(o.lengthM)).toDouble();
      final w = math.max(0, d(o.widthM)).toDouble();
      openingsArea += q * l * w;
      openingPerimeter += q * 2 * (l + w);
    }
    final netTopArea = math.max(0, grossTopAreaM2 - openingsArea).toDouble();

    var supportVolume = 0.0;
    var supportFormwork = 0.0;
    var supportFinish = 0.0;
    for (final s in supports) {
      final q = math.max(0, n(s.quantity)).toDouble();
      final l = math.max(0, d(s.lengthM)).toDouble();
      final t = math.max(0, d(s.thicknessM)).toDouble();
      final h = math.max(0, d(s.heightM)).toDouble();
      supportVolume += q * l * t * h;
      supportFormwork += q * 2 * (l + t) * h;
      supportFinish += q * 2 * l * h;
    }

    var rebarKgOne = 0.0;
    for (final r in rebars) {
      rebarKgOne += calcRebarSet(r)['kgOne']!;
    }

    final concreteOne = netTopArea * thickness + supportVolume;
    var formworkOne = 0.0;
    if (includeSoffitFormwork) formworkOne += netTopArea;
    if (includeTopEdgesFormwork) formworkOne += topPerimeterM * thickness;
    if (includeOpeningEdgesFormwork) formworkOne += openingPerimeter * thickness;
    if (includeSupportFormwork) formworkOne += supportFormwork;

    return {
      'qty': qty,
      'openingsArea': openingsArea,
      'openingPerimeter': openingPerimeter,
      'netTopArea': netTopArea,
      'supportVolume': supportVolume,
      'supportFormwork': supportFormwork,
      'supportFinish': supportFinish,
      'concrete': concreteOne * qty,
      'formwork': formworkOne * qty,
      'rebar': rebarKgOne * qty,
      'topFinish': netTopArea * qty,
      'supportFinishTotal': supportFinish * qty,
    };
  }

  Future<void> pickInto(BuildContext context, _BoqTarget target, StateSetter setState) async {
    final pick = await pickBoq(context);
    if (pick == null) return;
    setState(() {
      target.code.text = pick.code.trim();
      target.description.text = pick.description.trim();
      errorText = null;
    });
  }

  Widget numberField(TextEditingController c, String label, String suffix, VoidCallback changed) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => changed(),
      decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
    );
  }

  Widget boqRow({
    required String title,
    required String quantity,
    required bool included,
    required ValueChanged<bool> onIncluded,
    required _BoqTarget target,
    required BuildContext context,
    required StateSetter setState,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: AqsColors.border), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Checkbox(value: included, onChanged: (v) => onIncluded(v ?? false)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(quantity, style: const TextStyle(color: AqsColors.muted)),
          ])),
          OutlinedButton.icon(onPressed: included ? () => pickInto(context, target, setState) : null, icon: const Icon(Icons.search, size: 18), label: const Text('Pick BOQ')),
        ]),
        if (included && target.code.text.trim().isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('${target.code.text} — ${target.description.text}', style: const TextStyle(fontSize: 12))),
        ),
      ]),
    );
  }

  var dialogMinimized = false;
  var dialogMaximized = false;

  final accepted = await Get.dialog<bool>(
        StatefulBuilder(builder: (context, setState) {
          void changed() => setState(() => errorText = null);
          final q = calc();
          final screen = MediaQuery.sizeOf(context);
          final dialogWidth = dialogMinimized
              ? math.min(560.0, screen.width - 40)
              : dialogMaximized
                  ? screen.width * .94
                  : math.min(980.0, screen.width - 40);
          final dialogHeight = dialogMinimized
              ? 86.0
              : dialogMaximized
                  ? screen.height * .90
                  : math.min(820.0, screen.height - 40);
          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  child: Row(children: [
                    const Icon(Icons.countertops_outlined, color: AqsColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Concrete Bench & Worktop', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('One measured object → concrete, formwork, reinforcement and finishes.', style: TextStyle(color: AqsColors.muted)),
                    ])),
                    IconButton(
                      tooltip: dialogMinimized ? 'Restore form' : 'Minimize form',
                      onPressed: () => setState(() {
                        dialogMinimized = !dialogMinimized;
                        if (dialogMinimized) dialogMaximized = false;
                      }),
                      icon: Icon(dialogMinimized ? Icons.open_in_full_rounded : Icons.minimize_rounded),
                    ),
                    if (!dialogMinimized)
                      IconButton(
                        tooltip: dialogMaximized ? 'Restore size' : 'Maximize form',
                        onPressed: () => setState(() => dialogMaximized = !dialogMaximized),
                        icon: Icon(dialogMaximized ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded),
                      ),
                    IconButton(onPressed: () => Get.back(result: false), icon: const Icon(Icons.close)),
                  ]),
                ),
                if (!dialogMinimized) Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Description / reference', border: OutlineInputBorder())),
                    const SizedBox(height: 14),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(width: 220, child: numberField(topThicknessCtrl, 'Top thickness', 'm', changed)),
                      SizedBox(width: 220, child: numberField(identicalQtyCtrl, 'Identical units', 'nr', changed)),
                      SizedBox(width: 220, child: numberField(wasteCtrl, 'Rebar waste', '%', changed)),
                    ]),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _metric('Measured gross top', '${grossTopAreaM2.toStringAsFixed(3)} m²'),
                      _metric('Net top', '${q['netTopArea']!.toStringAsFixed(3)} m²'),
                      _metric('Perimeter', '${topPerimeterM.toStringAsFixed(3)} m'),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('Openings / sink cut-outs', onAdd: () => setState(() => openings.add(_OpeningInput(index: openings.length + 1)))),
                    if (openings.isEmpty) const Text('No openings. The measured polygon will be treated as the gross top area.', style: TextStyle(color: AqsColors.muted)),
                    for (var i = 0; i < openings.length; i++) _openingCard(openings[i], i, () => setState(() { openings[i].dispose(); openings.removeAt(i); }), changed),
                    const SizedBox(height: 20),
                    _sectionTitle('Supporting legs / walls', onAdd: () => setState(() => supports.add(_SupportInput(index: supports.length + 1)))),
                    for (var i = 0; i < supports.length; i++) _supportCard(supports[i], i, () => setState(() { supports[i].dispose(); supports.removeAt(i); }), changed),
                    const SizedBox(height: 20),
                    _sectionTitle('Reinforcement sets', onAdd: () => setState(() { rebars.add(_RebarInput(index: rebars.length + 1)); includeRebar = true; })),
                    if (rebars.isEmpty) const Text('Add one or more bar sets when reinforcement is required.', style: TextStyle(color: AqsColors.muted)),
                    for (var i = 0; i < rebars.length; i++)
                      _rebarCard(
                        rebars[i],
                        i,
                        supports,
                        rebarSummary(rebars[i]),
                        () => pickInto(context, rebars[i].boqTarget, setState),
                        () => setState(() {
                          rebars[i].dispose();
                          rebars.removeAt(i);
                          includeRebar = rebars.isNotEmpty;
                          errorText = null;
                        }),
                        () => setState(() => errorText = null),
                      ),
                    const SizedBox(height: 20),
                    const Text('Formwork surfaces', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Wrap(children: [
                      _check('Top soffit', includeSoffitFormwork, (v) => setState(() => includeSoffitFormwork = v)),
                      _check('Top edges', includeTopEdgesFormwork, (v) => setState(() => includeTopEdgesFormwork = v)),
                      _check('Opening edges', includeOpeningEdgesFormwork, (v) => setState(() => includeOpeningEdgesFormwork = v)),
                      _check('Support faces', includeSupportFormwork, (v) => setState(() => includeSupportFormwork = v)),
                    ]),
                    const SizedBox(height: 20),
                    const Text('BOQ output mapping', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    boqRow(title: 'Concrete', quantity: '${q['concrete']!.toStringAsFixed(3)} m³', included: includeConcrete, onIncluded: (v) => setState(() => includeConcrete = v), target: concreteBoq, context: context, setState: setState),
                    boqRow(title: 'Formwork', quantity: '${q['formwork']!.toStringAsFixed(3)} m²', included: includeFormwork, onIncluded: (v) => setState(() => includeFormwork = v), target: formworkBoq, context: context, setState: setState),
                    if (includeRebar)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AqsColors.primarySoft,
                          border: Border.all(color: AqsColors.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          const Icon(Icons.grid_on_outlined, color: AqsColors.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Reinforcement', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('${q['rebar']!.toStringAsFixed(3)} kg total', style: const TextStyle(color: AqsColors.muted)),
                            const Text('Each reinforcement set is linked to its own BOQ item above.', style: TextStyle(fontSize: 11, color: AqsColors.muted)),
                          ])),
                        ]),
                      ),
                    boqRow(title: 'Top finish', quantity: '${q['topFinish']!.toStringAsFixed(3)} m²', included: includeTopFinish, onIncluded: (v) => setState(() => includeTopFinish = v), target: topFinishBoq, context: context, setState: setState),
                    boqRow(title: 'Support finish', quantity: '${q['supportFinishTotal']!.toStringAsFixed(3)} m²', included: includeSupportFinish, onIncluded: (v) => setState(() => includeSupportFinish = v), target: supportFinishBoq, context: context, setState: setState),
                    if (errorText != null) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(10)), child: Text(errorText!, style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700))),
                  ]),
                )),
                if (!dialogMinimized) Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AqsColors.border))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
                    const SizedBox(width: 10),
                    FilledButton.icon(onPressed: () {
                      final thickness = d(topThicknessCtrl);
                      final qty = n(identicalQtyCtrl);
                      if (thickness <= 0 || qty <= 0) { setState(() => errorText = 'Enter a valid top thickness and number of identical units.'); return; }
                      if (q['netTopArea']! <= 0) { setState(() => errorText = 'Openings cannot be equal to or greater than the measured top area.'); return; }
                      final selected = <_BoqTarget>[
                        if (includeConcrete) concreteBoq,
                        if (includeFormwork) formworkBoq,
                        if (includeTopFinish) topFinishBoq,
                        if (includeSupportFinish) supportFinishBoq,
                      ];
                      final hasAnyOutput = selected.isNotEmpty || (includeRebar && rebars.isNotEmpty);
                      if (!hasAnyOutput) { setState(() => errorText = 'Include at least one output.'); return; }
                      final missing = selected.where((x) => x.code.text.trim().isEmpty).map((x) => x.title).toList();
                      if (missing.isNotEmpty) { setState(() => errorText = 'Pick a BOQ item for: ${missing.join(', ')}.'); return; }
                      if (includeRebar) {
                        final missingRebarBoq = <String>[];
                        for (var i = 0; i < rebars.length; i++) {
                          if (rebars[i].boqTarget.code.text.trim().isEmpty) {
                            missingRebarBoq.add(rebars[i].name.text.trim().isEmpty ? 'Set ${i + 1}' : rebars[i].name.text.trim());
                          }
                        }
                        if (missingRebarBoq.isNotEmpty) {
                          setState(() => errorText = 'Pick a BOQ item for reinforcement: ${missingRebarBoq.join(', ')}.');
                          return;
                        }
                      }
                      if (includeRebar && rebars.isEmpty) { setState(() => errorText = 'Add at least one reinforcement set or turn reinforcement off.'); return; }
                      if (includeRebar) {
                        for (var i = 0; i < rebars.length; i++) {
                          final r = rebars[i];
                          if (d(r.diameterMm) <= 0) {
                            setState(() => errorText = 'Reinforcement set ${i + 1}: enter a valid bar diameter.');
                            return;
                          }
                          if (r.countMode == 'auto' && d(r.spacingMm) <= 0) {
                            setState(() => errorText = 'Reinforcement set ${i + 1}: spacing must be greater than zero in Auto count mode.');
                            return;
                          }
                          if (r.countMode == 'manual' && n(r.manualCount) <= 0) {
                            setState(() => errorText = 'Reinforcement set ${i + 1}: enter a valid manual bar count.');
                            return;
                          }
                          if (r.lengthMode == 'manual' && d(r.manualLengthM) <= 0) {
                            setState(() => errorText = 'Reinforcement set ${i + 1}: enter a valid manual bar length.');
                            return;
                          }
                          if (r.component == 'support' && supports.isEmpty) {
                            setState(() => errorText = 'Reinforcement set ${i + 1}: add a support/leg first or change the element to Top / worktop.');
                            return;
                          }
                        }
                      }
                      Get.back(result: true);
                    }, icon: const Icon(Icons.save_outlined), label: const Text('Save Bench / Worktop')),
                  ]),
                ),
              ]),
            ),
          );
        }),
        barrierDismissible: false,
      ) ?? false;

  if (!accepted) {
    nameCtrl.dispose(); topThicknessCtrl.dispose(); identicalQtyCtrl.dispose(); wasteCtrl.dispose();
    for (final x in supports) x.dispose();
    for (final x in openings) x.dispose();
    for (final x in rebars) x.dispose();
    for (final x in allTargets) x.dispose();
    return false;
  }

  final q = calc();
  final groupId = measurementsRef.doc().id;
  final now = FieldValue.serverTimestamp();
  final common = <String, dynamic>{
    'projectId': projectId,
    'buildingId': buildingId,
    'drawingId': drawingId,
    'measureType': 'concreteBenchWorktop',
    'benchWorktopGroupId': groupId,
    'areaGroupId': groupId,
    'label': nameCtrl.text.trim(),
    'title': nameCtrl.text.trim(),
    'polygon': polygonData,
    'color': currentColor.value,
    'grossTopAreaM2': grossTopAreaM2,
    'netTopAreaM2': q['netTopArea'],
    'topPerimeterM': topPerimeterM,
    'topThicknessM': d(topThicknessCtrl),
    'identicalQty': n(identicalQtyCtrl),
    'openingsAreaM2': q['openingsArea'],
    'openingPerimeterM': q['openingPerimeter'],
    'supports': supports.map((s) => {
      'name': s.name.text.trim(), 'quantity': n(s.quantity), 'lengthM': d(s.lengthM), 'thicknessM': d(s.thicknessM), 'heightM': d(s.heightM),
    }).toList(),
    'openings': openings.map((o) => {
      'name': o.name.text.trim(), 'quantity': n(o.quantity), 'lengthM': d(o.lengthM), 'widthM': d(o.widthM),
    }).toList(),
    'reinforcementSets': rebars.map((r) => {
      'name': r.name.text.trim(),
      'component': r.component,
      'layer': r.layer,
      'supportFace': r.supportFace,
      'direction': r.direction,
      'supportIndex': r.supportIndex,
      'diameterMm': d(r.diameterMm),
      'spacingMm': d(r.spacingMm),
      'coverMm': d(r.coverMm),
      'countMode': r.countMode,
      'manualCount': n(r.manualCount),
      'lengthMode': r.lengthMode,
      'manualLengthM': d(r.manualLengthM),
      'extraLengthM': d(r.extraLengthM),
      'calculatedBarCount': calcRebarSet(r)['countTotal'],
      'calculatedLengthM': calcRebarSet(r)['lengthTotal'],
      'calculatedWeightKg': calcRebarSet(r)['kgTotal'],
      'boqCode': r.boqTarget.code.text.trim(),
      'boqDescription': r.boqTarget.description.text.trim(),
    }).toList(),
    'rebarWastePercent': d(wasteCtrl),
    'createdAt': now,
    'updatedAt': now,
  };

  final batch = FirebaseFirestore.instance.batch();
  var primary = true;
  void addOutput(String suffix, String type, double value, String unit, _BoqTarget target) {
    final id = primary ? groupId : '$groupId-$suffix';
    primary = false;
    batch.set(measurementsRef.doc(id), {
      ...common,
      'type': type,
      'itemType': type,
      'quantity': value,
      'value': value,
      'unit': unit,
      'boqUnit': unit,
      'boqCode': target.code.text.trim(),
      'boqDescription': target.description.text.trim(),
    });
  }

  if (includeConcrete) addOutput('concrete', 'benchConcrete', q['concrete']!, 'm3', concreteBoq);
  if (includeFormwork) addOutput('formwork', 'benchFormwork', q['formwork']!, 'm2', formworkBoq);
  if (includeRebar) {
    for (var i = 0; i < rebars.length; i++) {
      final r = rebars[i];
      final m = calcRebarSet(r);
      final suffix = 'rebar-${i + 1}';
      final id = primary ? groupId : '$groupId-$suffix';
      primary = false;
      batch.set(measurementsRef.doc(id), {
        ...common,
        'type': 'benchReinforcement',
        'itemType': 'benchReinforcement',
        'quantity': m['kgTotal'],
        'value': m['kgTotal'],
        'unit': 'kg',
        'boqUnit': 'kg',
        'boqCode': r.boqTarget.code.text.trim(),
        'boqDescription': r.boqTarget.description.text.trim(),
        'rebarSetIndex': i,
        'barMark': r.name.text.trim(),
        'rebarComponent': r.component,
        'rebarLayer': r.layer,
        'rebarSupportFace': r.supportFace,
        'rebarDirection': r.direction,
        'diameterMm': d(r.diameterMm),
        'spacingMm': d(r.spacingMm),
        'calculatedBarCount': m['countTotal'],
        'calculatedLengthM': m['lengthTotal'],
        'calculatedWeightKg': m['kgTotal'],
      });
    }
  }
  if (includeTopFinish) addOutput('top-finish', 'benchTopFinish', q['topFinish']!, 'm2', topFinishBoq);
  if (includeSupportFinish) addOutput('support-finish', 'benchSupportFinish', q['supportFinishTotal']!, 'm2', supportFinishBoq);

  await batch.commit();

  nameCtrl.dispose(); topThicknessCtrl.dispose(); identicalQtyCtrl.dispose(); wasteCtrl.dispose();
  for (final x in supports) x.dispose();
  for (final x in openings) x.dispose();
  for (final x in rebars) x.dispose();
  for (final x in allTargets) x.dispose();
  return true;
}

Widget _metric(String label, String value) => Container(
  width: 210,
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(color: AqsColors.primarySoft, borderRadius: BorderRadius.circular(12)),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, color: AqsColors.muted, fontWeight: FontWeight.w700)),
    const SizedBox(height: 3),
    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
  ]),
);

Widget _sectionTitle(String title, {required VoidCallback onAdd}) => Row(children: [
  Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
  OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
]);

Widget _check(String label, bool value, ValueChanged<bool> onChanged) => SizedBox(
  width: 210,
  child: CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(label), value: value, onChanged: (v) => onChanged(v ?? false), controlAffinity: ListTileControlAffinity.leading),
);

Widget _openingCard(_OpeningInput o, int index, VoidCallback remove, VoidCallback changed) => _inputCard(
  child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
    SizedBox(width: 180, child: TextField(controller: o.name, decoration: const InputDecoration(labelText: 'Opening', border: OutlineInputBorder()))),
    SizedBox(width: 110, child: _simpleNumber(o.quantity, 'Qty', 'nr', changed)),
    SizedBox(width: 140, child: _simpleNumber(o.lengthM, 'Length', 'm', changed)),
    SizedBox(width: 140, child: _simpleNumber(o.widthM, 'Width', 'm', changed)),
    IconButton(onPressed: remove, icon: const Icon(Icons.delete_outline)),
  ]),
);

Widget _supportCard(_SupportInput s, int index, VoidCallback remove, VoidCallback changed) => _inputCard(
  child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
    SizedBox(width: 170, child: TextField(controller: s.name, decoration: const InputDecoration(labelText: 'Support', border: OutlineInputBorder()))),
    SizedBox(width: 90, child: _simpleNumber(s.quantity, 'Qty', 'nr', changed)),
    SizedBox(width: 120, child: _simpleNumber(s.lengthM, 'Length', 'm', changed)),
    SizedBox(width: 130, child: _simpleNumber(s.thicknessM, 'Thickness', 'm', changed)),
    SizedBox(width: 120, child: _simpleNumber(s.heightM, 'Height', 'm', changed)),
    IconButton(onPressed: remove, icon: const Icon(Icons.delete_outline)),
  ]),
);

Widget _rebarCard(
  _RebarInput r,
  int index,
  List<_SupportInput> supports,
  String summary,
  VoidCallback pickBoq,
  VoidCallback remove,
  VoidCallback changed,
) => _inputCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Reinforcement set ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(onPressed: remove, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: r.name,
              onChanged: (_) => changed(),
              decoration: const InputDecoration(
                labelText: 'Bar mark',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: r.component,
              decoration: const InputDecoration(labelText: 'Rebar location', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'top', child: Text('Worktop slab')),
                DropdownMenuItem(value: 'support', child: Text('Support wall / leg')),
              ],
              onChanged: (v) {
                if (v == null) return;
                r.component = v;
                r.direction = v == 'top' ? 'longitudinal' : 'vertical';
                changed();
              },
            ),
          ),
          if (r.component == 'support' && supports.isNotEmpty)
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                value: r.supportIndex.clamp(0, supports.length - 1).toInt(),
                decoration: const InputDecoration(labelText: 'Support / leg', border: OutlineInputBorder()),
                items: [
                  for (var i = 0; i < supports.length; i++)
                    DropdownMenuItem(value: i, child: Text(supports[i].name.text.trim().isEmpty ? 'Support ${i + 1}' : supports[i].name.text.trim())),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  r.supportIndex = v;
                  changed();
                },
              ),
            ),
          if (r.component == 'top')
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: r.layer,
                decoration: const InputDecoration(labelText: 'Layer', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'top', child: Text('Top layer')),
                  DropdownMenuItem(value: 'bottom', child: Text('Bottom layer')),
                  DropdownMenuItem(value: 'both', child: Text('Top & bottom')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  r.layer = v;
                  changed();
                },
              ),
            )
          else
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: r.supportFace,
                decoration: const InputDecoration(labelText: 'Faces', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'single', child: Text('Single face')),
                  DropdownMenuItem(value: 'both', child: Text('Both faces')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  r.supportFace = v;
                  changed();
                },
              ),
            ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: r.direction,
              decoration: const InputDecoration(labelText: 'Direction', border: OutlineInputBorder()),
              items: r.component == 'top'
                  ? const [
                      DropdownMenuItem(value: 'longitudinal', child: Text('Longitudinal')),
                      DropdownMenuItem(value: 'transverse', child: Text('Transverse')),
                    ]
                  : const [
                      DropdownMenuItem(value: 'vertical', child: Text('Vertical main bars')),
                      DropdownMenuItem(value: 'distribution', child: Text('Horizontal distribution')),
                    ],
              onChanged: (v) {
                if (v == null) return;
                r.direction = v;
                changed();
              },
            ),
          ),
          SizedBox(width: 120, child: _simpleNumber(r.diameterMm, 'Diameter', 'mm', changed)),
          SizedBox(width: 120, child: _simpleNumber(r.spacingMm, 'Spacing', 'mm', changed)),
          SizedBox(width: 120, child: _simpleNumber(r.coverMm, 'Cover', 'mm', changed)),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 145,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: r.countMode,
              decoration: const InputDecoration(labelText: 'Bar count', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'manual', child: Text('Manual')),
              ],
              onChanged: (v) {
                if (v == null) return;
                r.countMode = v;
                changed();
              },
            ),
          ),
          if (r.countMode == 'manual')
            SizedBox(width: 135, child: _simpleNumber(r.manualCount, r.component == 'support' ? 'Bars / support' : 'No. bars', 'nr', changed)),
          SizedBox(
            width: 185,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: r.lengthMode,
              decoration: const InputDecoration(labelText: 'Bar length', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto from geometry')),
                DropdownMenuItem(value: 'manual', child: Text('Enter manually')),
              ],
              onChanged: (v) {
                if (v == null) return;
                r.lengthMode = v;
                changed();
              },
            ),
          ),
          if (r.lengthMode == 'manual')
            SizedBox(width: 140, child: _simpleNumber(r.manualLengthM, 'Bar length', 'm', changed)),
          SizedBox(width: 180, child: _simpleNumber(r.extraLengthM, 'Hook / anchorage extra', 'm/bar', changed)),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AqsColors.primarySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          summary,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AqsColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BOQ item for this bar set', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  r.boqTarget.code.text.trim().isEmpty
                      ? 'Not linked'
                      : '${r.boqTarget.code.text.trim()} — ${r.boqTarget.description.text.trim()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AqsColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: pickBoq,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Pick BOQ'),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text(
        r.component == 'top'
            ? 'Auto mode reads the measured polygon, so straight and L-shaped worktops are handled from the actual traced geometry. Openings are not automatically located in the mesh; add trimming bars as separate sets where required.'
            : 'Support auto mode uses the selected support dimensions and quantity. Add one set for vertical main bars and another for horizontal distribution bars. Select Single face or Both faces as detailed on the drawing.',
        style: const TextStyle(fontSize: 11, color: AqsColors.muted),
      ),
    ],
  ),
);

Widget _inputCard({required Widget child}) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: AqsColors.border), borderRadius: BorderRadius.circular(12)),
  child: child,
);

Widget _simpleNumber(TextEditingController c, String label, String suffix, VoidCallback changed) => TextField(
  controller: c,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  onChanged: (_) => changed(),
  decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
);
