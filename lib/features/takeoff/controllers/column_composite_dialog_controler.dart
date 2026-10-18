import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

double _asD(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? def;
}

int _asI(dynamic v, [int def = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? def;
}

// clamp returns num => force double
double _clampD(num v, double lo, double hi) => v.clamp(lo, hi).toDouble();

double _kgPerM(double diaMm) {
  // kg/m = d^2 / 162 (common QS approx)
  return (diaMm * diaMm) / 162.0;
}

class ColumnCompositeDialogController extends GetxController {
  ColumnCompositeDialogController({
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.areaM2,
    required this.perimeterM,
    required double widthM,
    required double depthM,
    required this.polyData,
    required this.currentColor,
    required this.pickBoq,
    this.initialLabel,
    this.lastDefaults,
    this.lastConcBoq,
    this.lastFwBoq,
    this.lastMainBoq,
    this.lastStirBoq,
  }) : _widthInit = widthM.toDouble(),
       _depthInit = depthM.toDouble();

  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String projectId;
  final String buildingId;
  final String drawingId;

  // original from polygon (keep for display)
  final double areaM2;
  final double perimeterM;

  final double _widthInit;
  final double _depthInit;

  final List<Map<String, dynamic>> polyData;
  final Color currentColor;
  final Future<BoqPick?> Function(BuildContext ctx) pickBoq;
  final String? initialLabel;

  final Map<String, dynamic>? lastDefaults;
  final BoqPick? lastConcBoq;
  final BoqPick? lastFwBoq;
  final BoqPick? lastMainBoq;
  final BoqPick? lastStirBoq;

  // --- reactive state ---
  final saving = false.obs;
  final err = RxnString();
  final dialogOffset = Offset.zero.obs;

  // IMPORTANT: a "recalc tick" to rebuild result texts
  final calcTick = 0.obs;

  // BOQ picks
  final boqConcrete = Rxn<BoqPick>();
  final boqFormwork = Rxn<BoqPick>();
  final boqMain = Rxn<BoqPick>();
  final boqStir = Rxn<BoqPick>();

  final includeConcrete = true.obs;
  final includeFormwork = true.obs;
  final includeMainRebar = false.obs;
  final includeStirrups = false.obs;

  final manualMainKg = false.obs;
  final manualStirKg = false.obs;

  // Rx for edited geometry + key inputs
  final widthRx = 0.0.obs;
  final depthRx = 0.0.obs;
  final heightRx = 0.0.obs;
  final qtyRx = 1.obs;

  // controllers
  late final TextEditingController widthCtrl;
  late final TextEditingController depthCtrl;
  late final TextEditingController colTypeCtrl;
  late final TextEditingController heightCtrl;
  late final TextEditingController qtyCtrl;

  // rebar controllers
  late final TextEditingController mainCountCtrl;
  late final TextEditingController mainDiaCtrl;
  late final TextEditingController mainMarkCtrl;
  late final TextEditingController mainDevCtrl;
  late final TextEditingController mainManualKgCtrl;

  late final TextEditingController stirDiaCtrl;
  late final TextEditingController stirSpacingCtrl;
  late final TextEditingController coverCtrl;
  late final TextEditingController hookCtrl;
  late final TextEditingController stirMarkCtrl;
  late final TextEditingController stirManualKgCtrl;

  double _d(TextEditingController c, double def) =>
      double.tryParse(c.text.trim()) ?? def;
  int _i(TextEditingController c, int def) =>
      int.tryParse(c.text.trim()) ?? def;

  void bumpCalc() => calcTick.value++;

  void clearError() => err.value = null;
  void setErr(String msg) => err.value = msg;

  @override
  void onInit() {
    super.onInit();

    // restore defaults
    final h0 =
        (lastDefaults?['heightM'] is num)
            ? (lastDefaults!['heightM'] as num).toDouble()
            : 3.0;
    final q0 =
        (lastDefaults?['qty'] is num)
            ? (lastDefaults!['qty'] as num).toInt()
            : 1;

    widthRx.value = _widthInit;
    depthRx.value = _depthInit;
    heightRx.value = h0;
    qtyRx.value = q0;

    widthCtrl = TextEditingController(text: widthRx.value.toStringAsFixed(3));
    depthCtrl = TextEditingController(text: depthRx.value.toStringAsFixed(3));
    colTypeCtrl = TextEditingController(text: (initialLabel ?? 'C1').trim());
    heightCtrl = TextEditingController(text: heightRx.value.toStringAsFixed(2));
    qtyCtrl = TextEditingController(text: qtyRx.value.toString());

    // rebar defaults
    mainCountCtrl = TextEditingController(
      text: '${lastDefaults?['mainCount'] ?? 4}',
    );
    mainDiaCtrl = TextEditingController(
      text: '${lastDefaults?['mainDia'] ?? 16}',
    );
    mainMarkCtrl = TextEditingController(
      text: '${lastDefaults?['mainMark'] ?? '01'}',
    );
    mainDevCtrl = TextEditingController(
      text: '${lastDefaults?['mainDevExtraM'] ?? 0.60}',
    );
    mainManualKgCtrl = TextEditingController(text: '');

    stirDiaCtrl = TextEditingController(
      text: '${lastDefaults?['stirDia'] ?? 10}',
    );
    stirSpacingCtrl = TextEditingController(
      text: '${lastDefaults?['stirSpacingMm'] ?? 200}',
    );
    coverCtrl = TextEditingController(
      text: '${lastDefaults?['coverMm'] ?? 25}',
    );
    hookCtrl = TextEditingController(text: '${lastDefaults?['hookM'] ?? 0.10}');
    stirMarkCtrl = TextEditingController(
      text: '${lastDefaults?['stirMark'] ?? '05'}',
    );
    stirManualKgCtrl = TextEditingController(text: '');

    // restore last BOQs
    boqConcrete.value = lastConcBoq;
    boqFormwork.value = lastFwBoq;
    boqMain.value = lastMainBoq;
    boqStir.value = lastStirBoq;

    // listeners => update Rx and bump calc
    widthCtrl.addListener(() {
      widthRx.value = _d(widthCtrl, widthRx.value);
      bumpCalc();
    });
    depthCtrl.addListener(() {
      depthRx.value = _d(depthCtrl, depthRx.value);
      bumpCalc();
    });
    heightCtrl.addListener(() {
      heightRx.value = _d(heightCtrl, heightRx.value);
      bumpCalc();
    });
    qtyCtrl.addListener(() {
      qtyRx.value = _i(qtyCtrl, qtyRx.value);
      bumpCalc();
    });

    // any rebar inputs affect calc too
    void listen(TextEditingController c) => c.addListener(bumpCalc);
    listen(mainCountCtrl);
    listen(mainDiaCtrl);
    listen(mainMarkCtrl);
    listen(mainDevCtrl);
    listen(mainManualKgCtrl);

    listen(stirDiaCtrl);
    listen(stirSpacingCtrl);
    listen(coverCtrl);
    listen(hookCtrl);
    listen(stirMarkCtrl);
    listen(stirManualKgCtrl);
  }

  @override
  void onClose() {
    widthCtrl.dispose();
    depthCtrl.dispose();
    colTypeCtrl.dispose();
    heightCtrl.dispose();
    qtyCtrl.dispose();

    mainCountCtrl.dispose();
    mainDiaCtrl.dispose();
    mainMarkCtrl.dispose();
    mainDevCtrl.dispose();
    mainManualKgCtrl.dispose();

    stirDiaCtrl.dispose();
    stirSpacingCtrl.dispose();
    coverCtrl.dispose();
    hookCtrl.dispose();
    stirMarkCtrl.dispose();
    stirManualKgCtrl.dispose();

    super.onClose();
  }

  // ✅ edited geometry
  double widthMEdited() => widthRx.value;
  double depthMEdited() => depthRx.value;

  double effectiveAreaM2() =>
      (widthRx.value * depthRx.value).clamp(0.0, double.infinity);
  double effectivePerimeterM() =>
      (2.0 * (widthRx.value + depthRx.value)).clamp(0.0, double.infinity);

  double heightM() => heightRx.value;
  int qty() => qtyRx.value;

  // ✅ these now use edited size
  double concM3() => effectiveAreaM2() * heightM() * qty();
  double formworkM2() => effectivePerimeterM() * heightM() * qty();

  // --- rebar helpers ---
  String mainSpec() {
    final n = _i(mainCountCtrl, 4);
    final dia = _i(mainDiaCtrl, 16);
    final mark =
        (mainMarkCtrl.text.trim().isEmpty) ? '01' : mainMarkCtrl.text.trim();
    return '${n}Y$dia-$mark';
  }

  double mainRebarKg() {
    if (manualMainKg.value) return _d(mainManualKgCtrl, 0);
    // simple: vertical bars length = height + dev extra; weight kg/m by dia
    final n = _i(mainCountCtrl, 4);
    final dia = _i(mainDiaCtrl, 16);
    final dev = _d(mainDevCtrl, 0.60);
    final lenPerBar = (heightM() + dev).clamp(0.0, double.infinity);
    final totalLen = lenPerBar * n * qty();
    final kgPerM = (dia * dia) / 162.0; // approx
    return totalLen * kgPerM;
  }

  String stirSpec() {
    final dia = _i(stirDiaCtrl, 10);
    final mark =
        (stirMarkCtrl.text.trim().isEmpty) ? '05' : stirMarkCtrl.text.trim();
    final sp = _i(stirSpacingCtrl, 200);
    return 'R$dia-$mark-${sp}c/c';
  }

  double stirrupsKg() {
    if (manualStirKg.value) return _d(stirManualKgCtrl, 0);

    final dia = _i(stirDiaCtrl, 10);
    final spacingMm = _d(stirSpacingCtrl, 200);
    final coverMm = _d(coverCtrl, 25);
    final hookM = _d(hookCtrl, 0.10);

    final w = widthMEdited();
    final d = depthMEdited();
    final h = heightM();
    final q = qty();

    if (w <= 0 || d <= 0 || h <= 0 || spacingMm <= 0) return 0;

    final coverM = coverMm / 1000.0;
    final coreW = (w - 2 * coverM).clamp(0.0, double.infinity);
    final coreD = (d - 2 * coverM).clamp(0.0, double.infinity);

    final stirLen = (2 * (coreW + coreD) + 2 * hookM).clamp(
      0.0,
      double.infinity,
    );
    final nStirrups = ((h * 1000.0) / spacingMm).ceil() + 1;

    final totalLen = stirLen * nStirrups * q;
    final kgPerM = (dia * dia) / 162.0;
    return totalLen * kgPerM;
  }

  Future<void> pickFor(Rxn<BoqPick> slot, BuildContext ctx) async {
    clearError();
    final p = await pickBoq(ctx);
    if (p != null) slot.value = p;
  }

  Future<void> save(BuildContext dialogCtx) async {
    clearError();
    saving.value = true;

    final h = heightM();
    final q = qty();
    if (h <= 0) return _fail('Height must be > 0');
    if (q <= 0) return _fail('Qty must be >= 1');

    final wE = widthMEdited();
    final dE = depthMEdited();

    if (wE <= 0 || dE <= 0) return _fail('Width & Depth must be > 0');

    if (includeConcrete.value && boqConcrete.value == null) {
      return _fail('Pick BOQ item for Concrete.');
    }
    if (includeFormwork.value && boqFormwork.value == null) {
      return _fail('Pick BOQ item for Formwork.');
    }
    if (includeMainRebar.value && boqMain.value == null) {
      return _fail('Pick BOQ item for Main rebar.');
    }
    if (includeStirrups.value && boqStir.value == null) {
      return _fail('Pick BOQ item for Stirrups.');
    }

    if (includeMainRebar.value &&
        manualMainKg.value &&
        _asD(mainManualKgCtrl.text, 0) <= 0) {
      return _fail('Enter manual kg for Main rebar.');
    }
    if (includeStirrups.value &&
        manualStirKg.value &&
        _asD(stirManualKgCtrl.text, 0) <= 0) {
      return _fail('Enter manual kg for Stirrups.');
    }

    try {
      final colType =
          (colTypeCtrl.text.trim().isEmpty) ? 'C1' : colTypeCtrl.text.trim();
      final columnId = measurementsRef.doc().id;
      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();

      // geometry doc
      batch.set(measurementsRef.doc(columnId), {
        'projectId': projectId,
        'buildingId': buildingId,
        'drawingId': drawingId,

        'columnId': columnId,
        'columnType': colType,

        'type': 'columnGeom',
        'measureType': 'compositecolumn',

        'unit': 'm2',
        'value': areaM2,
        'areaM2': areaM2,
        'perimeterM': perimeterM,

        'widthM': widthMEdited(),
        'depthM': depthMEdited(),
        'heightM': h,
        'qty': q,

        'label': 'Column $colType',
        'color': currentColor.value,
        'polygon': polyData,

        'createdAt': now,
        'updatedAt': now,
      });

      if (includeConcrete.value) {
        final b = boqConcrete.value!;
        batch.set(measurementsRef.doc(), {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'columnId': columnId,
          'columnType': colType,

          'type': 'columnConcrete',
          'measureType': 'compositecolumn',
          'unit': 'm3',
          'value': concM3(),

          'heightM': h,
          'qty': q,

          'boqItemId': b.id,
          'boqCode': b.code,
          'boqDescription': b.description,

          'color': currentColor.value,
          'polygon': polyData,

          'createdAt': now,
          'updatedAt': now,
        });
      }

      if (includeFormwork.value) {
        final b = boqFormwork.value!;
        batch.set(measurementsRef.doc(), {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'columnId': columnId,
          'columnType': colType,

          'type': 'columnFormworkSides',
          'measureType': 'compositecolumn',
          'unit': 'm2',
          'value': formworkM2(),

          'perimeterM': perimeterM,
          'heightM': h,
          'qty': q,

          'boqItemId': b.id,
          'boqCode': b.code,
          'boqDescription': b.description,

          'color': currentColor.value,
          'polygon': polyData,

          'createdAt': now,
          'updatedAt': now,
        });
      }

      if (includeMainRebar.value) {
        final b = boqMain.value!;
        final kg = mainRebarKg();

        batch.set(measurementsRef.doc(), {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'columnId': columnId,
          'columnType': colType,

          'type': 'columnMainRebar',
          'measureType': 'compositecolumn',
          'unit': 'kg',
          'value': kg,

          'rebarSpec': mainSpec(),
          'manualKg': manualMainKg.value,

          'heightM': h,
          'qty': q,

          'mainCount': _asI(mainCountCtrl.text, 4),
          'mainDiaMm': _asD(mainDiaCtrl.text, 16),
          'mainMark': mainMarkCtrl.text.trim(),
          'devExtraM': _asD(mainDevCtrl.text, 0.60),

          'boqItemId': b.id,
          'boqCode': b.code,
          'boqDescription': b.description,

          'color': currentColor.value,
          'polygon': polyData,

          'createdAt': now,
          'updatedAt': now,
        });
      }

      if (includeStirrups.value) {
        final b = boqStir.value!;
        final kg = stirrupsKg();

        batch.set(measurementsRef.doc(), {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'columnId': columnId,
          'columnType': colType,

          'type': 'columnStirrups',
          'measureType': 'compositecolumn',
          'unit': 'kg',
          'value': kg,

          'rebarSpec': stirSpec(),
          'manualKg': manualStirKg.value,

          'widthM': widthMEdited(),
          'depthM': depthMEdited(),
          'heightM': h,
          'qty': q,

          'stirDiaMm': _asD(stirDiaCtrl.text, 10),
          'stirMark': stirMarkCtrl.text.trim(),
          'spacingMm': _asD(stirSpacingCtrl.text, 200),
          'coverMm': _asD(coverCtrl.text, 25),
          'hookM': _asD(hookCtrl.text, 0.10),

          'boqItemId': b.id,
          'boqCode': b.code,
          'boqDescription': b.description,

          'color': currentColor.value,
          'polygon': polyData,

          'createdAt': now,
          'updatedAt': now,
        });
      }

      await batch.commit();

      saving.value = false;
      Get.back(result: true);
      // optional snackbar
      ScaffoldMessenger.of(
        dialogCtx,
      ).showSnackBar(const SnackBar(content: Text('Composite column saved.')));
    } catch (e) {
      return _fail('Save failed: $e');
    }
  }

  Future<void> _fail(String m) async {
    saving.value = false;
    err(m);
  }
}
