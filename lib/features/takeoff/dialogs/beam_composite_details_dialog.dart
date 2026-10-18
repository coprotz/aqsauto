import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/models/beam_type_total_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BeamCompositeDetailsDialog extends StatefulWidget {
  const BeamCompositeDetailsDialog({
    super.key,
    required this.beamId,
    required this.beamType,
    required this.sameTotals,
    required this.initialDocs,
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.currentColor,
  });

  final String beamId;
  final String beamType;
  final BeamTypeTotals? sameTotals;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String projectId;
  final String buildingId;
  final String drawingId;
  final Color currentColor;

  @override
  State<BeamCompositeDetailsDialog> createState() =>
      _BeamCompositeDetailsDialogState();
}

/* -------------------- DRAFT MODELS -------------------- */

class DraftMainBars {
  DraftMainBars({
    required this.rawMark,
    required this.barsCount,
    required this.diameterMm,
    required this.position,
    required this.boqCode,
    required this.barLengthM,
    required this.totalLengthM,
    required this.totalWeightKg,
    required this.unitWeightKgPerM,
    this.note,
    this.useDirectLength = false,
    this.embedEachEndM = 0.30,
    this.extraLengthM = 0.00,
  });

  String rawMark;
  int barsCount;
  int diameterMm;
  String position;
  String boqCode;

  bool useDirectLength;
  double embedEachEndM;
  double extraLengthM;

  double barLengthM;
  double totalLengthM;
  double totalWeightKg;
  double unitWeightKgPerM;

  String? note;

  Map<String, dynamic> toFirestoreMap({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String beamId,
    required String beamType,
    required int color,
  }) {
    return {
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,
      'beamId': beamId,
      'beamType': beamType,

      'type': 'rebarBeamMain',
      'measureType': 'compositebeam',
      'unit': 'kg',
      'value': totalWeightKg,

      'rawMark': rawMark,
      'diameterMm': diameterMm,
      'barsCount': barsCount,
      'position': position,

      'useDirectLength': useDirectLength,
      'embedEachEndM': embedEachEndM,
      'extraLengthM': extraLengthM,

      'barLengthM': barLengthM,
      'totalLengthAllBarsM': totalLengthM,
      'unitWeightKgPerM': unitWeightKgPerM,
      'totalWeightKg': totalWeightKg,

      'boqCode': boqCode,
      'segmentNote': (note ?? '').trim(),
      'color': color,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class DraftMainSegmentBars {
  DraftMainSegmentBars({
    required this.rawMark,
    required this.barsPerSegment,
    required this.diameterMm,
    required this.markCode,
    required this.clearLengthM,
    required this.embedEachEndM,
    required this.extraLengthM,
    required this.segmentCount,
    required this.totalBars,
    required this.barLengthM,
    required this.totalLengthM,
    required this.totalWeightKg,
    required this.unitWeightKgPerM,
    required this.boqCode,
    this.note,
  });

  String rawMark;
  int barsPerSegment;
  int diameterMm;
  String markCode;

  double clearLengthM;
  double embedEachEndM;
  double extraLengthM;

  int segmentCount;
  int totalBars;

  double barLengthM;
  double totalLengthM;
  double totalWeightKg;
  double unitWeightKgPerM;

  String boqCode;
  String? note;

  Map<String, dynamic> toFirestoreMap({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String beamId,
    required String beamType,
    required int color,
  }) {
    return {
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,
      'beamId': beamId,
      'beamType': beamType,

      'type': 'rebarBeamMainSegment',
      'measureType': 'compositebeam',
      'unit': 'kg',
      'value': totalWeightKg,

      'rawMark': rawMark,
      'markCode': markCode,
      'diameterMm': diameterMm,

      'barsPerSegment': barsPerSegment,
      'segmentCount': segmentCount,
      'totalBars': totalBars,

      'clearLengthM': clearLengthM,
      'embedEachEndM': embedEachEndM,
      'extraLengthM': extraLengthM,
      'barLengthM': barLengthM,

      'totalLengthAllBarsM': totalLengthM,
      'unitWeightKgPerM': unitWeightKgPerM,
      'totalWeightKg': totalWeightKg,

      'segmentNote': (note ?? '').trim(),
      'boqCode': boqCode,
      'color': color,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class DraftStirrups {
  DraftStirrups({
    required this.rawMark,
    required this.diameterMm,
    required this.spacingMm,
    required this.nStirrups,
    required this.coverM,
    required this.hookLengthM,
    required this.perimeterPerStirrupM,
    required this.totalLengthM,
    required this.totalWeightKg,
    required this.unitWeightKgPerM,
    required this.boqCode,
  });

  String rawMark;
  int diameterMm;
  int? spacingMm;
  int nStirrups;

  double coverM;
  double hookLengthM;

  double perimeterPerStirrupM;
  double totalLengthM;
  double totalWeightKg;
  double unitWeightKgPerM;

  String boqCode;

  Map<String, dynamic> toFirestoreMap({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String beamId,
    required String beamType,
    required int color,
  }) {
    return {
      'projectId': projectId,
      'buildingId': buildingId,
      'drawingId': drawingId,
      'beamId': beamId,
      'beamType': beamType,

      'type': 'rebarBeamStirrups',
      'measureType': 'compositebeam',
      'unit': 'kg',
      'value': totalWeightKg,

      'rawMark': rawMark,
      'diameterMm': diameterMm,
      'spacingMm': spacingMm,
      'nStirrups': nStirrups,
      'coverM': coverM,
      'hookLengthM': hookLengthM,

      'perimeterPerStirrupM': perimeterPerStirrupM,
      'totalLengthAllStirrupsM': totalLengthM,
      'unitWeightKgPerM': unitWeightKgPerM,
      'totalWeightKg': totalWeightKg,

      'boqCode': boqCode,
      'color': color,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

// class BoqPick {
//   final String code; // resolvedBoqCode
//   final String description;

//   BoqPick({required this.code, required this.description});
// }

/* -------------------- DIALOG -------------------- */

class _BeamCompositeDetailsDialogState
    extends State<BeamCompositeDetailsDialog> {
  late List<DocumentSnapshot<Map<String, dynamic>>> localDocs;

  // Movable dialog position (can persist in controller if you want)
  Offset dialogOffset = const Offset(24, 80);

  // Drafts (editable before saving)
  final List<DraftMainBars> draftMainBars = [];
  final List<DraftMainSegmentBars> draftMainSegments = [];
  final List<DraftStirrups> draftStirrups = [];

  String? mainBOQ;

  // Controllers for "Add" forms (draft creation)
  final mainMarkController = TextEditingController();
  // final mainBoqController = TextEditingController();
  final mainEmbedController = TextEditingController(text: '0.30');
  final mainExtraController = TextEditingController(text: '0.00');
  final mainBarLengthController = TextEditingController();
  final mainNoteController = TextEditingController();

  final mainSegMarkController = TextEditingController();
  final mainSegClearLenController = TextEditingController();
  final mainSegEmbedController = TextEditingController(text: '0.30');
  final mainSegExtraController = TextEditingController(text: '0.00');
  final mainSegSegmentCountController = TextEditingController(text: '1');

  String? segBOQ;
  // final mainSegBoqController = TextEditingController();
  final mainSegNoteController = TextEditingController();

  final stirrupMarkController = TextEditingController();

  String? strBOQ;
  // final stirrupBoqController = TextEditingController();
  final stirrupDiaController = TextEditingController(text: '10');
  final stirrupSpacingController = TextEditingController(text: '150');
  final stirrupCountController = TextEditingController();
  final stirrupCoverController = TextEditingController(text: '0.05');
  final stirrupHookController = TextEditingController(text: '0.10');

  // UI state
  String mainPosition = 'bottom';
  bool mainUseDirectLength = false;

  String? mainError;
  String? mainSegError;
  String? stirrupError;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    localDocs = List<DocumentSnapshot<Map<String, dynamic>>>.of(
      widget.initialDocs,
    );
  }

  @override
  void dispose() {
    mainMarkController.dispose();
    // mainBoqController.dispose();
    mainEmbedController.dispose();
    mainExtraController.dispose();
    mainBarLengthController.dispose();
    mainNoteController.dispose();

    mainSegMarkController.dispose();
    mainSegClearLenController.dispose();
    mainSegEmbedController.dispose();
    mainSegExtraController.dispose();
    mainSegSegmentCountController.dispose();
    // mainSegBoqController.dispose();
    mainSegNoteController.dispose();

    stirrupMarkController.dispose();
    // stirrupBoqController.dispose();
    stirrupDiaController.dispose();
    stirrupSpacingController.dispose();
    stirrupCountController.dispose();
    stirrupCoverController.dispose();
    stirrupHookController.dispose();
    super.dispose();
  }

  /* -------------------- HELPERS -------------------- */

  double _asDouble(dynamic v) =>
      (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
  int _asInt(dynamic v) => (v is num) ? v.toInt() : (int.tryParse('$v') ?? 0);

  double _unitWeightKgPerM(int diaMm) => 0.00617 * diaMm * diaMm;

  Map<String, dynamic>? _data(DocumentSnapshot<Map<String, dynamic>> d) =>
      d.data();

  Map<String, dynamic> _parseMainSegmentMark(String raw) {
    final m = RegExp(
      r'^\s*(\d+)\s*[Yy]\s*(\d+)(?:\s*-\s*([A-Za-z0-9]+))?\s*$',
    ).firstMatch(raw);

    if (m == null) {
      throw FormatException('Use mark like 3Y25-01');
    }

    return {
      'barsPerSegment': int.parse(m.group(1)!),
      'diameterMm': int.parse(m.group(2)!),
      'markCode': (m.group(3) ?? '').trim(),
    };
  }

  Map<String, dynamic> _parseMainBarsMark(String raw) {
    final m = RegExp(r'^\s*(\d+)\s*[Yy]\s*(\d+)').firstMatch(raw);
    if (m == null) throw FormatException('Use mark like 3Y20-T');
    return {
      'barsCount': int.parse(m.group(1)!),
      'diameterMm': int.parse(m.group(2)!),
    };
  }

  double _getBeamLengthMFromDocs() {
    for (final d in localDocs) {
      final m = _data(d);
      if (m == null) continue;
      final L = _asDouble(m['beamLengthM'] ?? m['lengthM']);
      if (L > 0) return L;
    }
    return 0;
  }

  Map<String, double> _getBeamGeometry() {
    double L = 0, B = 0, D = 0;
    bool isGroundBeam = false;

    for (final d in localDocs) {
      final m = _data(d);
      if (m == null) continue;
      L = (L <= 0) ? _asDouble(m['beamLengthM'] ?? m['lengthM']) : L;
      B = (B <= 0) ? _asDouble(m['beamWidthM'] ?? m['widthM']) : B;
      D = (D <= 0) ? _asDouble(m['beamDepthM'] ?? m['depthM']) : D;
      if (m['isGroundBeam'] == true) isGroundBeam = true;
      if (L > 0 && B > 0 && D > 0) break;
    }

    return {'L': L, 'B': B, 'D': D, 'isGroundBeam': isGroundBeam ? 1.0 : 0.0};
  }

  Future<BoqPick?> showBoqPickerDialog({
    required BuildContext context,
    required CollectionReference<Map<String, dynamic>> boqRef,
  }) async {
    return showDialog<BoqPick?>(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
            child: StatefulBuilder(
              builder: (ctx, setState) {
                String q = '';

                // Query BOQ once as stream
                final stream =
                    boqRef
                        // Optional: if you have headings, filter out using your rowType:
                        // .where('rowType', isEqualTo: 'item')
                        .orderBy(
                          'order',
                        ) // if you have 'order'. Otherwise use resolvedBoqCode
                        // .orderBy('resolvedBoqCode')
                        .stateSnapshots();

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select BOQ item',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search BOQ code / description',
                        ),
                        onChanged:
                            (v) => setState(() => q = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: stream,
                          builder: (ctx, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Text('Failed: ${snap.error}'),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final docs = snap.data!.docs;

                            // Build list using ONLY the two fields you asked
                            final items =
                                docs
                                    .map((d) {
                                      final data = d.data();
                                      final code =
                                          (data['resolvedBoqCode'] ?? '')
                                              .toString()
                                              .trim();
                                      final desc =
                                          (data['description'] ?? '')
                                              .toString()
                                              .trim();
                                      final unit =
                                          (data['unit'] ?? '')
                                              .toString()
                                              .trim();
                                      return BoqPick(
                                        code: code,
                                        description: desc,

                                        id: d.id,
                                      );
                                    })
                                    .where(
                                      (b) =>
                                          b.code.isNotEmpty &&
                                          b.description.isNotEmpty &&
                                          b.id.isNotEmpty,
                                    )
                                    .toList();

                            final filtered =
                                q.isEmpty
                                    ? items
                                    : items.where((b) {
                                      return b.code.toLowerCase().contains(q) ||
                                          b.description.toLowerCase().contains(
                                            q,
                                          );
                                    }).toList();

                            if (filtered.isEmpty) {
                              return const Center(
                                child: Text('No matching BOQ items'),
                              );
                            }

                            return ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final b = filtered[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(b.code),
                                  subtitle: Text(
                                    b.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(ctx, b),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  int get _draftCount =>
      draftMainBars.length + draftMainSegments.length + draftStirrups.length;

  /* -------------------- BUILD (MOVABLE) -------------------- */

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final dialogWidth = size.width < 720 ? size.width - 24 : 720.0;
    const minLeft = 10.0;
    const minTop = 24.0;

    final maxLeft = (size.width - dialogWidth - minLeft).clamp(
      0.0,
      double.infinity,
    );
    final left = dialogOffset.dx.clamp(minLeft, maxLeft);

    // rough Y clamp so it doesn't disappear
    final maxTop = (size.height - 240.0).clamp(minTop, double.infinity);
    final top = dialogOffset.dy.clamp(minTop, maxTop);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 18,
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: dialogWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height - 48),
                  child: Column(
                    children: [
                      _dragHeader(context),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _summaryBlock(),
                                const SizedBox(height: 14),

                                _addMainBarsBlock(),
                                const SizedBox(height: 14),

                                _addMainSegmentsBlock(),
                                const SizedBox(height: 14),

                                _addStirrupsBlock(),
                                const SizedBox(height: 14),

                                _draftsBlock(),
                                const SizedBox(height: 14),

                                _itemsListBlock(),
                              ],
                            ),
                          ),
                        ),
                      ),

                      _bottomActions(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dragHeader(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(() => dialogOffset += d.delta),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF102A56), Color(0xFF155EEF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              child: const Icon(
                Icons.account_tree_outlined,
                color: Color(0xFFD6E4FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Composite beam details',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${widget.beamType} • Beam ${widget.beamId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD6E4FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_draftCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.orange.withOpacity(0.26)),
                ),
                child: Text(
                  '$_draftCount draft${_draftCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFFFFE3B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Close',
              onPressed: saving ? null : () => Get.back(),
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: saving ? null : () => Get.back(),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Close'),
          ),
          const Spacer(),
          if (saving)
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: saving ? null : _saveDraftsToFirestore,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _draftCount == 0
                  ? 'Save additions'
                  : 'Save additions ($_draftCount)',
            ),
          ),
        ],
      ),
    );
  }

  /* -------------------- SUMMARY -------------------- */

  Widget _summaryBlock() {
    if (localDocs.isEmpty) {
      return const _BeamPanel(
        title: 'Beam summary',
        subtitle: 'No saved quantities found yet',
        icon: Icons.summarize_outlined,
        child: Text(
          'No items remain for this beam. Add reinforcement or save new additions to build the summary.',
          style: TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      );
    }

    double beamLengthM = 0, beamWidthM = 0, beamDepthM = 0;
    bool isGroundBeam = false;

    double concreteM3 = 0, sideFwM2 = 0, soffitFwM2 = 0;

    double mainWtKg = 0, mainLenM = 0;
    double mainSegWtKg = 0, mainSegLenM = 0;
    double stirWtKg = 0, stirLenM = 0;

    for (final d in localDocs) {
      final data = _data(d);
      if (data == null) continue;

      final type = (data['type'] ?? '').toString();

      if (beamLengthM <= 0) {
        beamLengthM = _asDouble(data['beamLengthM'] ?? data['lengthM']);
      }
      if (beamWidthM <= 0) {
        beamWidthM = _asDouble(data['beamWidthM'] ?? data['widthM']);
      }
      if (beamDepthM <= 0) {
        beamDepthM = _asDouble(data['beamDepthM'] ?? data['depthM']);
      }
      if (data['isGroundBeam'] == true) isGroundBeam = true;

      if (type == 'beamConcrete') concreteM3 += _asDouble(data['value']);
      if (type == 'beamFormworkSide') sideFwM2 += _asDouble(data['value']);
      if (type == 'beamFormworkSoffit') soffitFwM2 += _asDouble(data['value']);

      if (type == 'rebarBeamMain') {
        mainLenM += _asDouble(
          data['totalLengthAllBarsM'] ?? data['totalLengthM'],
        );
        mainWtKg += _asDouble(data['totalWeightKg'] ?? data['value']);
      }
      if (type == 'rebarBeamMainSegment') {
        mainSegLenM += _asDouble(data['totalLengthAllBarsM']);
        mainSegWtKg += _asDouble(data['totalWeightKg'] ?? data['value']);
      }
      if (type == 'rebarBeamStirrups') {
        stirLenM += _asDouble(
          data['totalLengthAllStirrupsM'] ?? data['totalLengthM'],
        );
        stirWtKg += _asDouble(data['totalWeightKg'] ?? data['value']);
      }
    }

    final totalLen = mainLenM + mainSegLenM + stirLenM;
    final totalWt = mainWtKg + mainSegWtKg + stirWtKg;

    final t = widget.sameTotals;

    return _BeamPanel(
      title: 'Beam summary',
      subtitle: isGroundBeam ? 'Ground beam • no soffit formwork' : 'Measured beam quantities',
      icon: Icons.summarize_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Beam ID', value: widget.beamId),
              _MetricChip(label: 'Type', value: widget.beamType),
              if (beamLengthM > 0)
                _MetricChip(
                  label: 'Length',
                  value: '${beamLengthM.toStringAsFixed(3)} m',
                ),
              if (beamWidthM > 0 && beamDepthM > 0)
                _MetricChip(
                  label: 'Section',
                  value:
                      '${beamWidthM.toStringAsFixed(3)} × ${beamDepthM.toStringAsFixed(3)} m',
                ),
              if (concreteM3 > 0)
                _MetricChip(
                  label: 'Concrete',
                  value: '${concreteM3.toStringAsFixed(3)} m³',
                ),
              if (sideFwM2 > 0)
                _MetricChip(
                  label: 'Side formwork',
                  value: '${sideFwM2.toStringAsFixed(3)} m²',
                ),
              if (!isGroundBeam && soffitFwM2 > 0)
                _MetricChip(
                  label: 'Soffit',
                  value: '${soffitFwM2.toStringAsFixed(3)} m²',
                ),
              if (totalWt > 0)
                _MetricChip(
                  label: 'Rebar',
                  value: '${totalWt.toStringAsFixed(2)} kg',
                ),
              if (totalLen > 0)
                _MetricChip(
                  label: 'Rebar length',
                  value: '${totalLen.toStringAsFixed(3)} m',
                ),
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD6E4FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Same-type totals: ${t.beamType}',
                    style: const TextStyle(
                      color: Color(0xFF17448A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricChip(
                        label: 'Beams',
                        value: '${t.beamsCount}',
                        tonal: true,
                      ),
                      _MetricChip(
                        label: 'Total length',
                        value: '${t.totalLengthM.toStringAsFixed(3)} m',
                        tonal: true,
                      ),
                      if (t.concreteM3 > 0)
                        _MetricChip(
                          label: 'Concrete',
                          value: '${t.concreteM3.toStringAsFixed(3)} m³',
                          tonal: true,
                        ),
                      if (t.sideFormworkM2 > 0)
                        _MetricChip(
                          label: 'Side formwork',
                          value: '${t.sideFormworkM2.toStringAsFixed(3)} m²',
                          tonal: true,
                        ),
                      if (t.soffitFormworkM2 > 0)
                        _MetricChip(
                          label: 'Soffit',
                          value: '${t.soffitFormworkM2.toStringAsFixed(3)} m²',
                          tonal: true,
                        ),
                      if (t.rebarTotalWeightKg > 0)
                        _MetricChip(
                          label: 'Rebar',
                          value: '${t.rebarTotalWeightKg.toStringAsFixed(2)} kg',
                          tonal: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: const Color(0xFF155EEF), size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /* -------------------- ADD BLOCKS (DRAFT CREATION) -------------------- */

  Widget _addMainBarsBlock() {
    return _BeamPanel(
      title: 'Main bar set',
      subtitle: 'Add top, bottom, centre, or extra beam reinforcement',
      icon: Icons.horizontal_rule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: mainMarkController,
            decoration: const InputDecoration(
              labelText: 'Main bar mark (e.g. 3Y20-T)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: mainPosition,
                  decoration: const InputDecoration(
                    labelText: 'Position',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'top', child: Text('Top')),
                    DropdownMenuItem(value: 'bottom', child: Text('Bottom')),
                    DropdownMenuItem(value: 'centre', child: Text('Centre')),
                    DropdownMenuItem(value: 'extra', child: Text('Extra')),
                  ],
                  onChanged:
                      saving
                          ? null
                          : (v) => setState(() => mainPosition = v ?? 'bottom'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('Add BOQ (Main)'),
                  onPressed: () async {
                    final boqRef = FirebaseFirestore.instance
                        .collection('projects')
                        .doc(widget.projectId)
                        .collection('buildings')
                        .doc(widget.buildingId)
                        .collection('boq');

                    final pick = await showBoqPickerDialog(
                      context: context,
                      boqRef: boqRef,
                    );

                    if (pick == null) return;
                    setState(() {
                      mainBOQ = pick.code;
                    });
                  },
                ),
              ),
              if (mainBOQ != null) Expanded(child: Text(mainBOQ.toString())),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              Switch(
                value: mainUseDirectLength,
                onChanged:
                    saving
                        ? null
                        : (v) => setState(() => mainUseDirectLength = v),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mainUseDirectLength
                      ? 'Use direct bar length'
                      : 'Compute bar length from span + embed + extra',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          if (!mainUseDirectLength) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: mainEmbedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Embed each end (m)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: mainExtraController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Extra length (m)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: mainBarLengthController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Bar length (m)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 6),
          TextField(
            controller: mainNoteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),

          if (mainError != null) ...[
            const SizedBox(height: 6),
            Text(
              mainError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving ? null : _addMainBarsDraft,
              icon: const Icon(Icons.add),
              label: const Text('Add draft'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMainBarsDraft() async {
    setState(() => mainError = null);

    final raw = mainMarkController.text.trim();
    final boq = mainBOQ;
    if (raw.isEmpty || boq == null) {
      setState(() => mainError = 'Enter mark and BOQ code.');
      return;
    }

    late final int qty;
    late final int dia;
    late final double beamLengthM;
    try {
      final parsed = _parseMainBarsMark(raw);
      qty = parsed['barsCount'] as int;
      dia = parsed['diameterMm'] as int;
    } catch (e) {
      setState(() => mainError = e.toString());
      return;
    }

    final t = widget.sameTotals;
    if (t != null) {
      beamLengthM = t.totalLengthM;
    }

    // final beamLengthM = _getBeamLengthMFromDocs();
    // final beamLengthM = t.totalLengthM;
    if (!mainUseDirectLength && beamLengthM <= 0) {
      setState(
        () =>
            mainError = 'Beam length not found. Re-open after measuring beam.',
      );
      return;
    }

    double barLenM;
    double embed = double.tryParse(mainEmbedController.text.trim()) ?? 0.30;
    double extra = double.tryParse(mainExtraController.text.trim()) ?? 0.00;

    if (mainUseDirectLength) {
      barLenM = double.tryParse(mainBarLengthController.text.trim()) ?? 0.0;
      if (barLenM <= 0) {
        setState(() => mainError = 'Enter bar length (m).');
        return;
      }
    } else {
      barLenM = beamLengthM + 2 * embed + extra;
      if (barLenM <= 0) {
        setState(() => mainError = 'Computed bar length is invalid.');
        return;
      }
    }

    final totalLen = qty * barLenM;
    final uw = _unitWeightKgPerM(dia);
    final totalWt = totalLen * uw;

    setState(() {
      draftMainBars.add(
        DraftMainBars(
          rawMark: raw,
          barsCount: qty,
          diameterMm: dia,
          position: mainPosition,
          boqCode: boq,
          useDirectLength: mainUseDirectLength,
          embedEachEndM: embed,
          extraLengthM: extra,
          barLengthM: barLenM,
          totalLengthM: totalLen,
          totalWeightKg: totalWt,
          unitWeightKgPerM: uw,
          note: mainNoteController.text.trim(),
        ),
      );

      mainMarkController.clear();
      // mainBoqController.clear();
      mainBarLengthController.clear();
      mainNoteController.clear();
    });
  }

  Widget _addMainSegmentsBlock() {
    return _BeamPanel(
      title: 'Main bar segment',
      subtitle: 'Record repeated segment lengths and reinforcement marks',
      icon: Icons.timeline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: mainSegMarkController,
                  decoration: const InputDecoration(
                    labelText: 'Mark (e.g. 3Y25-01)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: mainSegClearLenController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Clear length (m)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: mainSegEmbedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Embed each end (m)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: mainSegExtraController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Extra length (m)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: mainSegSegmentCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'No. of segments',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('Add BOQ (Seg)'),
                  onPressed: () async {
                    final boqRef = FirebaseFirestore.instance
                        .collection('projects')
                        .doc(widget.projectId)
                        .collection('buildings')
                        .doc(widget.buildingId)
                        .collection('boq');

                    final pick = await showBoqPickerDialog(
                      context: context,
                      boqRef: boqRef,
                    );

                    if (pick == null) return;
                    setState(() {
                      segBOQ = pick.code;
                    });
                  },
                ),
              ),
              if (segBOQ != null) Expanded(child: Text(segBOQ.toString())),
            ],
          ),

          const SizedBox(height: 6),
          TextField(
            controller: mainSegNoteController,
            decoration: const InputDecoration(
              labelText: 'Note (e.g. C1–C2 typical) (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),

          if (mainSegError != null) ...[
            const SizedBox(height: 6),
            Text(
              mainSegError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving ? null : _addMainSegmentDraft,
              icon: const Icon(Icons.add),
              label: const Text('Add draft'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMainSegmentDraft() async {
    setState(() => mainSegError = null);

    final raw = mainSegMarkController.text.trim();
    if (raw.isEmpty) {
      setState(() => mainSegError = 'Enter mark e.g. 3Y25-01');
      return;
    }

    final clearLenM =
        double.tryParse(mainSegClearLenController.text.trim()) ?? 0;
    if (clearLenM <= 0) {
      setState(() => mainSegError = 'Clear length must be > 0');
      return;
    }

    final embedM = double.tryParse(mainSegEmbedController.text.trim()) ?? 0.30;
    final extraM = double.tryParse(mainSegExtraController.text.trim()) ?? 0.00;

    final segCount =
        int.tryParse(mainSegSegmentCountController.text.trim()) ?? 0;
    if (segCount <= 0) {
      setState(() => mainSegError = 'No. of segments must be ≥ 1');
      return;
    }

    final boq = segBOQ;
    if (boq == null) {
      setState(() => mainSegError = 'Enter BOQ code');
      return;
    }

    Map<String, dynamic> parsed;
    try {
      parsed = _parseMainSegmentMark(raw);
    } catch (e) {
      setState(() => mainSegError = e.toString());
      return;
    }

    final barsPerSeg = parsed['barsPerSegment'] as int;
    final diaMm = parsed['diameterMm'] as int;
    final markCode = parsed['markCode'] as String;

    final barLenM = clearLenM + 2 * embedM + extraM;
    final totalBars = barsPerSeg * segCount;
    final totalLen = totalBars * barLenM;

    final uw = _unitWeightKgPerM(diaMm);
    final totalWt = totalLen * uw;

    setState(() {
      draftMainSegments.add(
        DraftMainSegmentBars(
          rawMark: raw,
          barsPerSegment: barsPerSeg,
          diameterMm: diaMm,
          markCode: markCode,
          clearLengthM: clearLenM,
          embedEachEndM: embedM,
          extraLengthM: extraM,
          segmentCount: segCount,
          totalBars: totalBars,
          barLengthM: barLenM,
          totalLengthM: totalLen,
          unitWeightKgPerM: uw,
          totalWeightKg: totalWt,
          boqCode: boq,
          note: mainSegNoteController.text.trim(),
        ),
      );

      mainSegMarkController.clear();
      mainSegClearLenController.clear();
      mainSegSegmentCountController.text = '1';
      // mainSegBoqController.clear();
      mainSegNoteController.clear();
    });
  }

  Widget _addStirrupsBlock() {
    return _BeamPanel(
      title: 'Stirrups',
      subtitle: 'Calculate links from beam section, cover, hooks, spacing, or count',
      icon: Icons.crop_square_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: stirrupMarkController,
            decoration: const InputDecoration(
              labelText: 'Stirrups mark/label (e.g. R10-150)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: stirrupDiaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ø (mm)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: stirrupSpacingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Spacing (mm)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: stirrupCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Count (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: stirrupCoverController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cover (m)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: stirrupHookController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Hook each (m)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('Add BOQ Code (stirrups)'),
                  onPressed: () async {
                    final boqRef = FirebaseFirestore.instance
                        .collection('projects')
                        .doc(widget.projectId)
                        .collection('buildings')
                        .doc(widget.buildingId)
                        .collection('boq');

                    final pick = await showBoqPickerDialog(
                      context: context,
                      boqRef: boqRef,
                    );

                    if (pick == null) return;
                    setState(() {
                      strBOQ = pick.code;
                    });
                  },
                ),
              ),
              if (strBOQ != null) Expanded(child: Text(strBOQ.toString())),
            ],
          ),

          if (stirrupError != null) ...[
            const SizedBox(height: 6),
            Text(
              stirrupError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving ? null : _addStirrupsDraft,
              icon: const Icon(Icons.add),
              label: const Text('Add draft'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addStirrupsDraft() async {
    setState(() => stirrupError = null);

    final raw = stirrupMarkController.text.trim();
    final boq = strBOQ;
    if (raw.isEmpty || boq == null) {
      setState(() => stirrupError = 'Enter stirrup mark and BOQ code.');
      return;
    }

    final geom = _getBeamGeometry();
    // final beamLengthM = geom['L'] ?? 0;

    late double beamLengthM;
    final t = widget.sameTotals;
    if (t != null) {
      beamLengthM = t.totalLengthM;
    }
    final beamWidthM = geom['B'] ?? 0;
    final beamDepthM = geom['D'] ?? 0;

    if (beamLengthM <= 0 || beamWidthM <= 0 || beamDepthM <= 0) {
      setState(
        () =>
            stirrupError =
                'Beam geometry missing. Re-open after measuring beam.',
      );
      return;
    }

    final dia = int.tryParse(stirrupDiaController.text.trim()) ?? 0;
    if (dia <= 0) {
      setState(() => stirrupError = 'Enter stirrup diameter.');
      return;
    }

    final spacingMm = int.tryParse(stirrupSpacingController.text.trim());
    int nStirrups = int.tryParse(stirrupCountController.text.trim()) ?? 0;

    if (nStirrups <= 0 && spacingMm != null && spacingMm > 0) {
      final spacingM = spacingMm / 1000.0;
      nStirrups = (beamLengthM / spacingM).ceil() + 1;
    }
    if (nStirrups <= 0) {
      setState(() => stirrupError = 'Provide spacing or count.');
      return;
    }

    final cover = double.tryParse(stirrupCoverController.text.trim()) ?? 0.05;
    final hook = double.tryParse(stirrupHookController.text.trim()) ?? 0.10;

    final bInner = (beamWidthM - 2 * cover).clamp(0.0, double.infinity);
    final hInner = (beamDepthM - 2 * cover).clamp(0.0, double.infinity);

    final perStirrup = 2 * (bInner + hInner) + 2 * hook;
    final totalLen = nStirrups * perStirrup;
    final uw = _unitWeightKgPerM(dia);
    final totalWt = totalLen * uw;

    setState(() {
      draftStirrups.add(
        DraftStirrups(
          rawMark: raw,
          diameterMm: dia,
          spacingMm: spacingMm,
          nStirrups: nStirrups,
          coverM: cover,
          hookLengthM: hook,
          perimeterPerStirrupM: perStirrup,
          totalLengthM: totalLen,
          unitWeightKgPerM: uw,
          totalWeightKg: totalWt,
          boqCode: boq,
        ),
      );

      stirrupMarkController.clear();
      // stirrupBoqController.clear();
      stirrupCountController.clear();
    });
  }

  /* -------------------- DRAFTS LIST + EDIT -------------------- */

  Widget _draftsBlock() {
    if (_draftCount == 0) {
      return const _BeamPanel(
        title: 'Draft additions',
        subtitle: 'Nothing pending for this beam',
        icon: Icons.pending_actions_outlined,
        child: Text(
          'No draft additions yet. Add main bars, segments, or stirrups above.',
          style: TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      );
    }

    return _BeamPanel(
      title: 'Draft additions',
      subtitle: 'Review, edit, or remove before saving',
      icon: Icons.pending_actions_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricChip(label: 'Pending items', value: '$_draftCount'),
          const SizedBox(height: 12),

          if (draftMainBars.isNotEmpty) ...[
            const Text(
              'Main bars',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...List.generate(draftMainBars.length, (i) {
              final it = draftMainBars[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${it.rawMark} (${it.position})'),
                subtitle: Text(
                  '${it.totalWeightKg.toStringAsFixed(2)} kg | '
                  'Len ${it.totalLengthM.toStringAsFixed(3)} m | '
                  'BOQ ${it.boqCode}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final edited = await _editDraftMainBarsDialog(it);
                        if (edited != null)
                          setState(() => draftMainBars[i] = edited);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed:
                          () => setState(() => draftMainBars.removeAt(i)),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 18),
          ],

          if (draftMainSegments.isNotEmpty) ...[
            const Text(
              'Main segments',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...List.generate(draftMainSegments.length, (i) {
              final it = draftMainSegments[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${it.rawMark} (x${it.segmentCount} seg)'),
                subtitle: Text(
                  '${it.totalWeightKg.toStringAsFixed(2)} kg | '
                  'Len ${it.totalLengthM.toStringAsFixed(3)} m | '
                  'BOQ ${it.boqCode}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final edited = await _editDraftMainSegmentDialog(it);
                        if (edited != null)
                          setState(() => draftMainSegments[i] = edited);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed:
                          () => setState(() => draftMainSegments.removeAt(i)),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 18),
          ],

          if (draftStirrups.isNotEmpty) ...[
            const Text(
              'Stirrups',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...List.generate(draftStirrups.length, (i) {
              final it = draftStirrups[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${it.rawMark} (Ø${it.diameterMm})'),
                subtitle: Text(
                  '${it.totalWeightKg.toStringAsFixed(2)} kg | '
                  'n=${it.nStirrups} | '
                  'BOQ ${it.boqCode}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final edited = await _editDraftStirrupsDialog(it);
                        if (edited != null)
                          setState(() => draftStirrups[i] = edited);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed:
                          () => setState(() => draftStirrups.removeAt(i)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<DraftMainBars?> _editDraftMainBarsDialog(
    DraftMainBars existing,
  ) async {
    final markCtrl = TextEditingController(text: existing.rawMark);
    final boqCtrl = TextEditingController(text: existing.boqCode);
    final noteCtrl = TextEditingController(text: existing.note ?? '');
    final embedCtrl = TextEditingController(
      text: existing.embedEachEndM.toStringAsFixed(2),
    );
    final extraCtrl = TextEditingController(
      text: existing.extraLengthM.toStringAsFixed(2),
    );
    final barLenCtrl = TextEditingController(
      text: existing.barLengthM.toStringAsFixed(3),
    );

    String pos = existing.position;
    bool useDirect = existing.useDirectLength;

    String? err;

    final ok = await Get.dialog<bool>(
      StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Edit draft (Main bars)'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: markCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mark (e.g. 3Y20-T)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: pos,
                      items: const [
                        DropdownMenuItem(value: 'top', child: Text('Top')),
                        DropdownMenuItem(
                          value: 'bottom',
                          child: Text('Bottom'),
                        ),
                        DropdownMenuItem(
                          value: 'centre',
                          child: Text('Centre'),
                        ),
                        DropdownMenuItem(value: 'extra', child: Text('Extra')),
                      ],
                      onChanged: (v) => setState(() => pos = v ?? 'bottom'),
                      decoration: const InputDecoration(labelText: 'Position'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: boqCtrl,
                      decoration: const InputDecoration(labelText: 'BOQ code'),
                    ),
                    const SizedBox(height: 8),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: useDirect,
                      onChanged: (v) => setState(() => useDirect = v),
                      title: Text(
                        useDirect
                            ? 'Use direct bar length'
                            : 'Compute from embed+extra',
                      ),
                    ),

                    if (!useDirect) ...[
                      TextField(
                        controller: embedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Embed each end (m)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: extraCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Extra length (m)',
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: barLenCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Bar length (m)',
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),

                    if (err != null) ...[
                      const SizedBox(height: 8),
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Get.back(result: true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );

    if (ok != true) {
      markCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      barLenCtrl.dispose();
      return null;
    }

    try {
      final parsed = _parseMainBarsMark(markCtrl.text.trim());
      final qty = parsed['barsCount'] as int;
      final dia = parsed['diameterMm'] as int;

      final beamLen = _getBeamLengthMFromDocs();
      double embed = double.tryParse(embedCtrl.text.trim()) ?? 0.30;
      double extra = double.tryParse(extraCtrl.text.trim()) ?? 0.00;

      double barLenM;
      if (useDirect) {
        barLenM = double.tryParse(barLenCtrl.text.trim()) ?? 0;
        if (barLenM <= 0) throw FormatException('Enter bar length.');
      } else {
        if (beamLen <= 0) throw FormatException('Beam length not found.');
        barLenM = beamLen + 2 * embed + extra;
      }

      final totalLen = qty * barLenM;
      final uw = _unitWeightKgPerM(dia);
      final totalWt = totalLen * uw;

      markCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      barLenCtrl.dispose();

      return DraftMainBars(
        rawMark: markCtrl.text.trim(),
        barsCount: qty,
        diameterMm: dia,
        position: pos,
        boqCode: boqCtrl.text.trim(),
        useDirectLength: useDirect,
        embedEachEndM: embed,
        extraLengthM: extra,
        barLengthM: barLenM,
        totalLengthM: totalLen,
        unitWeightKgPerM: uw,
        totalWeightKg: totalWt,
        note: noteCtrl.text.trim(),
      );
    } catch (e) {
      // quick fallback message
      Get.snackbar('Edit failed', e.toString());
      markCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      barLenCtrl.dispose();
      return null;
    }
  }

  Future<DraftMainSegmentBars?> _editDraftMainSegmentDialog(
    DraftMainSegmentBars existing,
  ) async {
    final markCtrl = TextEditingController(text: existing.rawMark);
    final clearCtrl = TextEditingController(
      text: existing.clearLengthM.toStringAsFixed(3),
    );
    final embedCtrl = TextEditingController(
      text: existing.embedEachEndM.toStringAsFixed(2),
    );
    final extraCtrl = TextEditingController(
      text: existing.extraLengthM.toStringAsFixed(2),
    );
    final segCtrl = TextEditingController(
      text: existing.segmentCount.toString(),
    );
    final boqCtrl = TextEditingController(text: existing.boqCode);
    final noteCtrl = TextEditingController(text: existing.note ?? '');

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Edit draft (Main segment bars)'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: markCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mark (e.g. 3Y25-01)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clearCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Clear length (m)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: embedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Embed each end (m)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: extraCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Extra length (m)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: segCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'No. of segments',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: boqCtrl,
                        decoration: const InputDecoration(
                          labelText: 'BOQ code',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note'),
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
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Apply'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (ok != true) {
      markCtrl.dispose();
      clearCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      segCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();
      return null;
    }

    try {
      final raw = markCtrl.text.trim();
      final clearLen = double.tryParse(clearCtrl.text.trim()) ?? 0;
      final embed = double.tryParse(embedCtrl.text.trim()) ?? 0.30;
      final extra = double.tryParse(extraCtrl.text.trim()) ?? 0.00;
      final segCount = int.tryParse(segCtrl.text.trim()) ?? 0;
      final boq = boqCtrl.text.trim();

      if (raw.isEmpty) throw FormatException('Mark required.');
      if (clearLen <= 0) throw FormatException('Clear length must be > 0.');
      if (segCount <= 0) throw FormatException('Segments must be ≥ 1.');
      if (boq.isEmpty) throw FormatException('BOQ code required.');

      final parsed = _parseMainSegmentMark(raw);
      final barsPerSeg = parsed['barsPerSegment'] as int;
      final dia = parsed['diameterMm'] as int;
      final markCode = parsed['markCode'] as String;

      final barLenM = clearLen + 2 * embed + extra;
      final totalBars = barsPerSeg * segCount;
      final totalLen = totalBars * barLenM;

      final uw = _unitWeightKgPerM(dia);
      final totalWt = totalLen * uw;

      markCtrl.dispose();
      clearCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      segCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();

      return DraftMainSegmentBars(
        rawMark: raw,
        barsPerSegment: barsPerSeg,
        diameterMm: dia,
        markCode: markCode,
        clearLengthM: clearLen,
        embedEachEndM: embed,
        extraLengthM: extra,
        segmentCount: segCount,
        totalBars: totalBars,
        barLengthM: barLenM,
        totalLengthM: totalLen,
        unitWeightKgPerM: uw,
        totalWeightKg: totalWt,
        boqCode: boq,
        note: noteCtrl.text.trim(),
      );
    } catch (e) {
      Get.snackbar('Edit failed', e.toString());
      markCtrl.dispose();
      clearCtrl.dispose();
      embedCtrl.dispose();
      extraCtrl.dispose();
      segCtrl.dispose();
      boqCtrl.dispose();
      noteCtrl.dispose();
      return null;
    }
  }

  Future<DraftStirrups?> _editDraftStirrupsDialog(
    DraftStirrups existing,
  ) async {
    final rawCtrl = TextEditingController(text: existing.rawMark);
    final diaCtrl = TextEditingController(text: existing.diameterMm.toString());
    final spacingCtrl = TextEditingController(
      text: (existing.spacingMm ?? '').toString(),
    );
    final countCtrl = TextEditingController(
      text: existing.nStirrups.toString(),
    );
    final coverCtrl = TextEditingController(
      text: existing.coverM.toStringAsFixed(2),
    );
    final hookCtrl = TextEditingController(
      text: existing.hookLengthM.toStringAsFixed(2),
    );
    final boqCtrl = TextEditingController(text: existing.boqCode);

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Edit draft (Stirrups)'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: rawCtrl,
                  decoration: const InputDecoration(labelText: 'Mark/label'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: diaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Ø (mm)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: spacingCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Spacing (mm) (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: countCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Count'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: coverCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cover (m)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: hookCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Hook each (m)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: boqCtrl,
                        decoration: const InputDecoration(
                          labelText: 'BOQ code',
                        ),
                      ),
                    ),
                  ],
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
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Apply'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (ok != true) {
      rawCtrl.dispose();
      diaCtrl.dispose();
      spacingCtrl.dispose();
      countCtrl.dispose();
      coverCtrl.dispose();
      hookCtrl.dispose();
      boqCtrl.dispose();
      return null;
    }

    try {
      final geom = _getBeamGeometry();
      final beamLengthM = geom['L'] ?? 0;
      final beamWidthM = geom['B'] ?? 0;
      final beamDepthM = geom['D'] ?? 0;

      if (beamLengthM <= 0 || beamWidthM <= 0 || beamDepthM <= 0) {
        throw FormatException('Beam geometry missing.');
      }

      final raw = rawCtrl.text.trim();
      final dia = int.tryParse(diaCtrl.text.trim()) ?? 0;
      final spacing = int.tryParse(spacingCtrl.text.trim());
      final n = int.tryParse(countCtrl.text.trim()) ?? 0;
      final cover = double.tryParse(coverCtrl.text.trim()) ?? 0.05;
      final hook = double.tryParse(hookCtrl.text.trim()) ?? 0.10;
      final boq = boqCtrl.text.trim();

      if (raw.isEmpty) throw FormatException('Mark is required.');
      if (dia <= 0) throw FormatException('Diameter must be > 0.');
      if (n <= 0) throw FormatException('Count must be ≥ 1.');
      if (boq.isEmpty) throw FormatException('BOQ code required.');

      final bInner = (beamWidthM - 2 * cover).clamp(0.0, double.infinity);
      final hInner = (beamDepthM - 2 * cover).clamp(0.0, double.infinity);

      final perStirrup = 2 * (bInner + hInner) + 2 * hook;
      final totalLen = n * perStirrup;
      final uw = _unitWeightKgPerM(dia);
      final totalWt = totalLen * uw;

      rawCtrl.dispose();
      diaCtrl.dispose();
      spacingCtrl.dispose();
      countCtrl.dispose();
      coverCtrl.dispose();
      hookCtrl.dispose();
      boqCtrl.dispose();

      return DraftStirrups(
        rawMark: raw,
        diameterMm: dia,
        spacingMm: spacing,
        nStirrups: n,
        coverM: cover,
        hookLengthM: hook,
        perimeterPerStirrupM: perStirrup,
        totalLengthM: totalLen,
        unitWeightKgPerM: uw,
        totalWeightKg: totalWt,
        boqCode: boq,
      );
    } catch (e) {
      Get.snackbar('Edit failed', e.toString());
      rawCtrl.dispose();
      diaCtrl.dispose();
      spacingCtrl.dispose();
      countCtrl.dispose();
      coverCtrl.dispose();
      hookCtrl.dispose();
      boqCtrl.dispose();
      return null;
    }
  }

  /* -------------------- SAVE DRAFTS (BATCH) -------------------- */

  Future<void> _saveDraftsToFirestore() async {
    if (_draftCount == 0) {
      Get.snackbar('Nothing to save', 'Add main bars/segments/stirrups first.');
      return;
    }

    setState(() => saving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final refs = <DocumentReference<Map<String, dynamic>>>[];

      void addDoc(Map<String, dynamic> data) {
        final ref = widget.measurementsRef.doc();
        refs.add(ref);
        batch.set(ref, data);
      }

      final color = widget.currentColor.value;

      for (final it in draftMainBars) {
        addDoc(
          it.toFirestoreMap(
            projectId: widget.projectId,
            buildingId: widget.buildingId,
            drawingId: widget.drawingId,
            beamId: widget.beamId,
            beamType: widget.beamType,
            color: color,
          ),
        );
      }

      for (final it in draftMainSegments) {
        addDoc(
          it.toFirestoreMap(
            projectId: widget.projectId,
            buildingId: widget.buildingId,
            drawingId: widget.drawingId,
            beamId: widget.beamId,
            beamType: widget.beamType,
            color: color,
          ),
        );
      }

      for (final it in draftStirrups) {
        addDoc(
          it.toFirestoreMap(
            projectId: widget.projectId,
            buildingId: widget.buildingId,
            drawingId: widget.drawingId,
            beamId: widget.beamId,
            beamType: widget.beamType,
            color: color,
          ),
        );
      }

      await batch.commit();

      // Pull the created docs back into localDocs so the list updates instantly
      for (final ref in refs) {
        final snap = await ref.get();
        localDocs.add(snap);
      }

      setState(() {
        draftMainBars.clear();
        draftMainSegments.clear();
        draftStirrups.clear();
      });

      Get.snackbar('Saved', 'Beam additions saved.');
    } catch (e) {
      Get.snackbar('Save failed', e.toString());
    } finally {
      setState(() => saving = false);
    }
  }

  /* -------------------- EXISTING ITEMS LIST (SAVED DOCS) -------------------- */

  Widget _itemsListBlock() {
    return _BeamPanel(
      title: 'Saved items',
      subtitle: 'Existing records already saved for this beam',
      icon: Icons.inventory_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (localDocs.isEmpty)
            const Text(
              'No saved items found for this beam.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: localDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final d = localDocs[i];
                final data = _data(d);
                if (data == null) return const SizedBox.shrink();

                final type = (data['type'] ?? '').toString();
                final boq = (data['boqCode'] ?? '').toString();
                final unit = (data['unit'] ?? '').toString();
                final value = _asDouble(data['value']);

                final deletable =
                    (type == 'rebarBeamMain' ||
                        type == 'rebarBeamMainSegment' ||
                        type == 'rebarBeamStirrups');

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      type,
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '${value.toStringAsFixed(3)} $unit${boq.isNotEmpty ? '  •  BOQ: $boq' : ''}',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                      ),
                    ),
                    trailing:
                        deletable
                            ? IconButton(
                              tooltip: 'Delete item',
                              icon: const Icon(Icons.delete_outline),
                              onPressed:
                                  saving ? null : () async => _deleteDoc(i),
                            )
                            : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _deleteDoc(int i) async {
    final d = localDocs[i];
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete this record from beam ${widget.beamId}?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => saving = true);
    try {
      await widget.measurementsRef.doc(d.id).delete();
      setState(() => localDocs.removeAt(i));
    } finally {
      setState(() => saving = false);
    }
  }
}

class _BeamPanel extends StatelessWidget {
  const _BeamPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF155EEF), Color(0xFF0B3B8F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22155EEF),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.tonal = false,
  });

  final String label;
  final String value;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final background =
        tonal ? Colors.white.withOpacity(0.72) : const Color(0xFFF8FAFC);
    final border = tonal ? const Color(0xFFD6E4FF) : const Color(0xFFE4E7EC);
    final valueColor = tonal ? const Color(0xFF17448A) : const Color(0xFF101828);

    return Container(
      constraints: const BoxConstraints(minWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
