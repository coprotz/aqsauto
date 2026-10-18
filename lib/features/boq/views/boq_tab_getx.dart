// import 'package:aqs/features/boq/controllers/linked_auto_sync_controller.dart';
import 'dart:math' as math;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/boq/models/qty_source_doc.dart';
import 'package:aqs/features/boq/views/boq_bills_summary_page.dart';
import 'package:aqs/features/commn%20widgets/linked_qty_section.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/links/link_repository.dart';
import 'package:aqs/features/links/linked_items_dialog.dart';
import 'package:aqs/features/links/linked_qty_controller.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/linked_qty_controller.dart';
import 'package:aqs/features/takeoff/controllers/takeoff_controller.dart';
import 'package:aqs/features/takeoff/models/linked_boq_target.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:aqs/features/boq/controllers/boq_controller.dart';

class BoqTabGetX extends StatefulWidget {
  final String projectId;
  final String buildingId;
  final String drawingId;
  final String imageUrl;
  final String drawingTitle;
  final String buildingName;
  final String projectName;
  final VoidCallback? onBackToDrawings;
  final String backLabel;

  const BoqTabGetX({
    super.key,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.imageUrl,
    required this.drawingTitle,
    required this.buildingName,
    required this.projectName,
    this.onBackToDrawings,
    this.backLabel = 'Drawing register',
  });

  @override
  State<BoqTabGetX> createState() => _BoqTabGetXState();
}

class _BoqTabGetXState extends State<BoqTabGetX> {
  final _vCtrl = ScrollController();
  final _hCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isRefreshing = false;
  bool _isOpeningAddBoq = false;

  late final ProjectBuildingsController projectDataController;

  static const double headerHeight = 44.0;
  LinkedQtyController linked = Get.put(LinkedQtyController());
  // ImageTakeoffController it = Get.put<ImageTakeoffController>();
  // final it = Get.find<TakeoffController>();

  late final String tag;
  // late final ImageTakeoffController it;

  late final LinkedAutoSyncController linkedCtrl;
  late final LinkRepository linkRepo;

  @override
  void initState() {
    super.initState();

    projectDataController =
        Get.isRegistered<ProjectBuildingsController>()
            ? Get.find<ProjectBuildingsController>()
            : Get.put(ProjectBuildingsController(), permanent: true);

    linkedCtrl = Get.put(
      LinkedAutoSyncController(),
      tag: 'links_${widget.drawingId}',
    );

    linkRepo = const LinkRepository();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        projectDataController.loadBoq(
          widget.projectId,
          widget.buildingId,
          forceRefresh: true,
        ),
        projectDataController.loadMeasurements(
          widget.projectId,
          widget.buildingId,
          forceRefresh: true,
        ),
      ]);
    });
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _refreshBoqData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        projectDataController.loadBoq(
          widget.projectId,
          widget.buildingId,
          forceRefresh: true,
        ),
        projectDataController.loadMeasurements(
          widget.projectId,
          widget.buildingId,
          forceRefresh: true,
        ),
      ]);
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _openAddBoq(BoqController controller) async {
    if (_isOpeningAddBoq) return;
    setState(() => _isOpeningAddBoq = true);
    try {
      await controller.showAddBoqMenu();
      await projectDataController.loadBoq(
        widget.projectId,
        widget.buildingId,
        forceRefresh: true,
      );
    } finally {
      if (mounted) setState(() => _isOpeningAddBoq = false);
    }
  }

  String _rowType(dynamic v) {
    final t = _s(v).toLowerCase();
    if (t == 'bill' || t == 'subheading' || t == 'minor' || t == 'item') {
      return t;
    }
    return 'item';
  }

  String _normKey(String code) {
    var c = (code).trim();
    c = c.replaceAll(RegExp(r'\s+'), '');
    return c;
  }

  void _addTotal(
    Map<String, double> totals,
    Map<String, int> counts,
    String key,
    double q,
  ) {
    final k = _normKey(key);
    if (k.isEmpty) return;
    totals[k] = (totals[k] ?? 0.0) + q;
    counts[k] = (counts[k] ?? 0) + 1;
  }

  String _takeoffToolLabel(Map<String, dynamic> measurement) {
    for (final key in const [
      'toolLabel',
      'toolName',
      'measurementTool',
      'sourceTool',
      'tool',
    ]) {
      final value = _s(measurement[key]);
      if (value.isNotEmpty) return value;
    }

    final type = _s(measurement['type']).toLowerCase();
    const known = <String, String>{
      'beam': 'Beam composite',
      'column': 'Column composite',
      'slab': 'Slab composite',
      'footing': 'Footing composite',
      'foundationwall': 'Foundation wall',
      'roofcover': 'Roof covering',
      'timberroof': 'Timber roof structure',
      'steelroof': 'Steel roof structure',
      'ceiling': 'Ceiling',
      'door': 'Door',
      'window': 'Window',
      'wall': 'Wall',
      'area': 'Area',
      'volume': 'Volume',
      'count': 'Count',
      'length': 'Length',
    };
    for (final entry in known.entries) {
      if (type.contains(entry.key)) return entry.value;
    }
    return type.isEmpty ? 'Take-off measurement' : type;
  }

  double _sourceNumber(dynamic value) {
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  String _canonicalSourceUnit(String unit) {
    final normalized = unit.trim().toLowerCase().replaceAll('.', '');
    if (const {
      'm2',
      'm²',
      'sqm',
      'square meter',
      'square meters',
      'square metre',
      'square metres',
    }.contains(normalized)) {
      return 'm2';
    }
    if (const {
      'm3',
      'm³',
      'cum',
      'cubic meter',
      'cubic meters',
      'cubic metre',
      'cubic metres',
    }.contains(normalized)) {
      return 'm3';
    }
    if (const {
      'm',
      'lm',
      'linear meter',
      'linear meters',
      'linear metre',
      'linear metres',
    }.contains(normalized)) {
      return 'm';
    }
    if (const {'nr', 'no', 'number', 'numbers'}.contains(normalized)) {
      return 'nr';
    }
    return normalized;
  }

  String _sourceUnitLabel(String unit) {
    switch (_canonicalSourceUnit(unit)) {
      case 'm2':
        return 'm²';
      case 'm3':
        return 'm³';
      case 'nr':
        return 'No.';
      default:
        return unit;
    }
  }

  double _sourceAreaM2(Map<String, dynamic> source) {
    final unit = _canonicalSourceUnit(_s(source['unit']));
    if (unit == 'm2') return _sourceNumber(source['value']);

    for (final key in const [
      'areaUsedM2Scaled',
      'areaM2_total',
      'planAreaM2Scaled',
      'sourceAreaM2Scaled',
      'concreteAreaM2Total',
    ]) {
      final value = _sourceNumber(source[key]);
      if (value > 0) return value;
    }

    final baseArea = _sourceNumber(
      source['areaUsedM2'] ??
          source['areaM2_one'] ??
          source['sourceAreaM2'] ??
          source['planAreaM2'],
    );
    final multiplier = _sourceNumber(
      source['multiplyingFactor'] ??
          source['multiplierTotal'] ??
          source['multiplier'] ??
          1,
    );
    if (baseArea > 0) return baseArea * (multiplier > 0 ? multiplier : 1);

    final type = _s(source['type']).toLowerCase();
    final measureType = _s(source['measureType']).toLowerCase();
    final isRampConcrete =
        measureType == 'compositeramp' &&
        type.startsWith('ramp_') &&
        type.endsWith('_concrete');
    if (isRampConcrete) {
      final length = _sourceNumber(source['lengthM'] ?? source['baseLengthM']);
      final width = _sourceNumber(source['widthM']);
      final savedTotal = _sourceNumber(source['qtyTotal']);
      final quantityEach = _sourceNumber(source['qtyEach']);
      final buildingFactor = _sourceNumber(source['buildingFactor']);
      final count =
          savedTotal > 0
              ? savedTotal
              : math.max(1, quantityEach) * math.max(1, buildingFactor);
      if (length > 0 && width > 0) return length * width * count;
    }

    final depth = _sourceNumber(
      source['depthM'] ??
          source['concreteBedThicknessM'] ??
          source['thicknessM'],
    );
    final value = _sourceNumber(source['value']);
    return unit == 'm3' && depth > 0 ? value / depth : 0;
  }

  String _convertedSourceType(String original, String unit) {
    final toVolume = unit == 'm3';
    if (toVolume) {
      if (original == 'area') return 'volume';
      if (original == 'areaMeasure') return 'volumeMeasure';
      if (original.endsWith('Area')) {
        return '${original.substring(0, original.length - 4)}Volume';
      }
    } else {
      if (original == 'volume') return 'area';
      if (original == 'volumeMeasure') return 'areaMeasure';
      if (original.endsWith('Volume')) {
        return '${original.substring(0, original.length - 6)}Area';
      }
    }
    return original;
  }

  String _convertedSourceLabel(String original, String unit) {
    final label = original.trim();
    if (unit == 'm3') {
      return label.replaceFirst(RegExp('area', caseSensitive: false), 'volume');
    }
    return label.replaceFirst(RegExp('volume', caseSensitive: false), 'area');
  }

  Future<bool> _deleteTakeoffSource({
    required Map<String, dynamic> source,
    required String drawingTitle,
  }) async {
    final measurementId = _s(source['id']);
    if (measurementId.isEmpty) {
      Get.snackbar(
        'Cannot delete source',
        'This legacy take-off record has no saved document ID.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }

    final label = _s(source['label']);
    final tool = _takeoffToolLabel(source);
    final quantity = _sourceNumber(source['value']);
    final sourceUnit = _sourceUnitLabel(
      _canonicalSourceUnit(_s(source['unit'])),
    );

    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (confirmContext) {
            var deleting = false;
            return StatefulBuilder(
              builder: (context, setConfirmState) {
                return AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.delete_outline, color: Color(0xFFD92D20)),
                      SizedBox(width: 10),
                      Expanded(child: Text('Delete measurement?')),
                    ],
                  ),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This will permanently delete this take-off measurement from the drawing and remove its contribution from the BOQ total.',
                        ),
                        const SizedBox(height: 14),
                        Text(
                          drawingTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          label.isEmpty
                              ? 'Tool: $tool'
                              : 'Tool: $tool • Measurement: $label',
                          style: const TextStyle(color: Color(0xFF667085)),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_fmtQty(quantity)} $sourceUnit',
                          style: const TextStyle(
                            color: Color(0xFF17366F),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Other take-off records created from the same drawing or measurement group will not be deleted.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          deleting
                              ? null
                              : () => Navigator.of(confirmContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD92D20),
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          deleting
                              ? null
                              : () async {
                                setConfirmState(() => deleting = true);
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('projects')
                                      .doc(widget.projectId)
                                      .collection('buildings')
                                      .doc(widget.buildingId)
                                      .collection('measurements')
                                      .doc(measurementId)
                                      .delete();
                                  if (confirmContext.mounted) {
                                    Navigator.of(confirmContext).pop(true);
                                  }
                                } catch (error) {
                                  setConfirmState(() => deleting = false);
                                  if (confirmContext.mounted) {
                                    ScaffoldMessenger.of(
                                      confirmContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not delete measurement: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                      icon:
                          deleting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.delete_outline),
                      label: Text(deleting ? 'Deleting…' : 'Delete'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (confirmed) {
      await _refreshBoqData();
      Get.snackbar(
        'Measurement deleted',
        'The take-off source was removed and the BOQ total was refreshed.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return confirmed;
  }

  Future<bool> _deleteAllTakeoffSources({
    required List<Map<String, dynamic>> sources,
    required String boqCode,
    required String description,
  }) async {
    if (sources.isEmpty) return false;

    final deletable =
        sources.where((source) => _s(source['id']).trim().isNotEmpty).toList();
    final legacyCount = sources.length - deletable.length;
    final drawingCount =
        sources
            .map((source) => _s(source['drawingId']).trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .length;

    if (deletable.isEmpty) {
      Get.snackbar(
        'Cannot delete measurements',
        'These take-off sources are legacy records without saved document IDs.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (confirmContext) {
            var deleting = false;
            return StatefulBuilder(
              builder: (context, setConfirmState) {
                return AlertDialog(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Color(0xFFD92D20),
                    size: 34,
                  ),
                  title: const Text('Delete all measurements?'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This will permanently delete ${deletable.length} take-off measurement${deletable.length == 1 ? '' : 's'} linked to BOQ $boqCode across $drawingCount drawing${drawingCount == 1 ? '' : 's'}.',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF344054),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (legacyCount > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '$legacyCount legacy source${legacyCount == 1 ? '' : 's'} without a document ID cannot be deleted automatically.',
                            style: const TextStyle(
                              color: Color(0xFFB54708),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Text(
                          'Their quantities will be removed from this BOQ total. This action cannot be undone.',
                          style: TextStyle(
                            color: Color(0xFFD92D20),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          deleting
                              ? null
                              : () => Navigator.of(confirmContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD92D20),
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          deleting
                              ? null
                              : () async {
                                setConfirmState(() => deleting = true);
                                try {
                                  const maxDeletesPerBatch = 450;
                                  final measurementsRef = FirebaseFirestore
                                      .instance
                                      .collection('projects')
                                      .doc(widget.projectId)
                                      .collection('buildings')
                                      .doc(widget.buildingId)
                                      .collection('measurements');
                                  for (
                                    var start = 0;
                                    start < deletable.length;
                                    start += maxDeletesPerBatch
                                  ) {
                                    final end =
                                        start + maxDeletesPerBatch <
                                                deletable.length
                                            ? start + maxDeletesPerBatch
                                            : deletable.length;
                                    final batch =
                                        FirebaseFirestore.instance.batch();
                                    for (final source in deletable.sublist(
                                      start,
                                      end,
                                    )) {
                                      batch.delete(
                                        measurementsRef.doc(_s(source['id'])),
                                      );
                                    }
                                    await batch.commit();
                                  }
                                  if (confirmContext.mounted) {
                                    Navigator.of(confirmContext).pop(true);
                                  }
                                } catch (error) {
                                  setConfirmState(() => deleting = false);
                                  if (confirmContext.mounted) {
                                    ScaffoldMessenger.of(
                                      confirmContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not delete all measurements: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                      icon:
                          deleting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.delete_forever_outlined),
                      label: Text(deleting ? 'Deleting…' : 'Delete all'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (confirmed) {
      await _refreshBoqData();
      Get.snackbar(
        'Measurements deleted',
        '${deletable.length} take-off measurement${deletable.length == 1 ? '' : 's'} were removed from BOQ $boqCode.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return confirmed;
  }

  Future<bool> _editTakeoffSource({
    required Map<String, dynamic> source,
    required String drawingTitle,
    required String boqUnit,
  }) async {
    final measurementId = _s(source['id']);
    if (measurementId.isEmpty) {
      Get.snackbar(
        'Cannot edit source',
        'This legacy take-off record has no saved document ID.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }

    final originalUnit = _canonicalSourceUnit(_s(source['unit']));
    final canonicalBoqUnit = _canonicalSourceUnit(boqUnit);
    final areaM2 = _sourceAreaM2(source);
    final canConvertAreaVolume =
        (originalUnit == 'm2' || originalUnit == 'm3') && areaM2 > 0;
    var selectedUnit = originalUnit;
    var unitCorrectionConfirmed = false;
    var saving = false;
    String? errorText;
    final labelController = TextEditingController(text: _s(source['label']));
    final quantityController = TextEditingController(
      text: _sourceNumber(source['value']).toStringAsFixed(3),
    );
    final savedDepth = _sourceNumber(
      source['depthM'] ??
          source['concreteBedThicknessM'] ??
          source['thicknessM'],
    );
    final thicknessController = TextEditingController(
      text: (savedDepth > 0 ? savedDepth : 0.15).toStringAsFixed(3),
    );

    void recalculateQuantity() {
      if (!canConvertAreaVolume) return;
      final thickness = double.tryParse(thicknessController.text.trim()) ?? 0;
      final value = selectedUnit == 'm3' ? areaM2 * thickness : areaM2;
      quantityController.text = value.toStringAsFixed(3);
    }

    final saved =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (editorContext) {
            return StatefulBuilder(
              builder: (context, setEditorState) {
                final quantity =
                    double.tryParse(quantityController.text.trim()) ?? 0;
                final thickness =
                    double.tryParse(thicknessController.text.trim()) ?? 0;
                final valid =
                    quantity.isFinite && quantity > 0 &&
                    (canConvertAreaVolume || selectedUnit == originalUnit || unitCorrectionConfirmed) &&
                    (selectedUnit != 'm3' ||
                        !canConvertAreaVolume ||
                        thickness > 0);

                return PopScope(
                  canPop: !saving,
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    title: const Text('View and edit take-off source'),
                    content: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Drawing: $drawingTitle',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tool: ${_takeoffToolLabel(source)}',
                              style: const TextStyle(color: Color(0xFF667085)),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: labelController,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Measurement name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (!canConvertAreaVolume) ...[
                              DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Saved measurement unit',
                                  border: OutlineInputBorder(),
                                ),
                                items: {originalUnit, canonicalBoqUnit, 'm', 'm2', 'm3'}
                                    .where((unit) => unit.isNotEmpty)
                                    .map((unit) => DropdownMenuItem(
                                      value: unit,
                                      child: Text(unit == 'm2' ? 'Area (m² / sqm)' : _sourceUnitLabel(unit)),
                                    )).toList(),
                                onChanged: saving ? null : (unit) {
                                  if (unit == null) return;
                                  setEditorState(() {
                                    selectedUnit = unit;
                                    unitCorrectionConfirmed = false;
                                    errorText = null;
                                  });
                                },
                              ),
                              if (selectedUnit != originalUnit)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: unitCorrectionConfirmed,
                                  title: const Text('I confirm the quantity is correct in the selected unit.'),
                                  subtitle: const Text('Changing the unit does not convert length to area or volume. Enter the correct measured quantity below.'),
                                  onChanged: saving ? null : (value) => setEditorState(() => unitCorrectionConfirmed = value ?? false),
                                ),
                              const SizedBox(height: 14),
                            ],
                            if (canConvertAreaVolume) ...[
                              DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Measure as',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'm2',
                                    child: Text('Area (m²)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'm3',
                                    child: Text('Volume (m³)'),
                                  ),
                                ],
                                onChanged:
                                    saving
                                        ? null
                                        : (value) {
                                          if (value == null) return;
                                          setEditorState(() {
                                            selectedUnit = value;
                                            errorText = null;
                                            recalculateQuantity();
                                          });
                                        },
                              ),
                              const SizedBox(height: 14),
                              if (selectedUnit == 'm3') ...[
                                TextField(
                                  controller: thicknessController,
                                  enabled: !saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Thickness / depth (m)',
                                    helperText:
                                        'Volume = measured area × thickness',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged:
                                      (_) => setEditorState(() {
                                        errorText = null;
                                        recalculateQuantity();
                                      }),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ],
                            TextField(
                              controller: quantityController,
                              enabled: !saving,
                              readOnly: canConvertAreaVolume,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    'Saved quantity (${_sourceUnitLabel(selectedUnit)})',
                                helperText:
                                    canConvertAreaVolume
                                        ? 'Measured area: ${_fmtQty(areaM2)} m². Drawing geometry is preserved.'
                                        : 'This changes the saved quantity; drawing geometry is preserved.',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged:
                                  (_) => setEditorState(() => errorText = null),
                            ),
                            if (selectedUnit != canonicalBoqUnit) ...[
                              const SizedBox(height: 12),
                              Text(
                                'BOQ unit is ${_sourceUnitLabel(canonicalBoqUnit)}; this source will use ${_sourceUnitLabel(selectedUnit)}.',
                                style: const TextStyle(
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (errorText != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                errorText!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (saving) ...[
                              const SizedBox(height: 18),
                              const Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Saving correction…'),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            saving
                                ? null
                                : () => Navigator.of(editorContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            saving || !valid
                                ? null
                                : () async {
                                  final value = double.tryParse(
                                    quantityController.text.trim(),
                                  );
                                  final depth = double.tryParse(
                                    thicknessController.text.trim(),
                                  );
                                  if (value == null || !value.isFinite || value <= 0) {
                                    setEditorState(
                                      () =>
                                          errorText =
                                              'Enter a valid positive quantity.',
                                    );
                                    return;
                                  }
                                  if (selectedUnit == 'm3' &&
                                      canConvertAreaVolume &&
                                      (depth == null || depth <= 0)) {
                                    setEditorState(
                                      () =>
                                          errorText =
                                              'Enter a valid thickness greater than zero.',
                                    );
                                    return;
                                  }

                                  setEditorState(() {
                                    saving = true;
                                    errorText = null;
                                  });
                                  try {
                                    final originalType = _s(source['type']);
                                    final originalMeasureType = _s(
                                      source['measureType'],
                                    );
                                    final newType =
                                        canConvertAreaVolume
                                            ? _convertedSourceType(
                                              originalType,
                                              selectedUnit,
                                            )
                                            : originalType;
                                    final newMeasureType =
                                        canConvertAreaVolume
                                            ? _convertedSourceType(
                                              originalMeasureType,
                                              selectedUnit,
                                            )
                                            : originalMeasureType;
                                    final enteredLabel =
                                        labelController.text.trim();
                                    final newLabel =
                                        enteredLabel.isEmpty
                                            ? _convertedSourceLabel(
                                              _s(source['label']),
                                              selectedUnit,
                                            )
                                            : canConvertAreaVolume &&
                                                selectedUnit != originalUnit &&
                                                enteredLabel ==
                                                    _s(source['label'])
                                            ? _convertedSourceLabel(
                                              enteredLabel,
                                              selectedUnit,
                                            )
                                            : enteredLabel;
                                    final update = <String, dynamic>{
                                      'label': newLabel,
                                      'value': value,
                                      'unit': selectedUnit,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    };
                                    if (source.containsKey('title')) {
                                      update['title'] = newLabel;
                                    }
                                    if (source.containsKey('quantity')) {
                                      update['quantity'] = value;
                                    }
                                    if (source.containsKey('boqUnit')) {
                                      update['boqUnit'] = selectedUnit;
                                    }
                                    if (canConvertAreaVolume) {
                                      final multiplier = _sourceNumber(
                                        source['multiplyingFactor'] ??
                                            source['multiplierTotal'] ??
                                            source['multiplier'] ??
                                            1,
                                      );
                                      final effectiveMultiplier =
                                          multiplier > 0 ? multiplier : 1;
                                      final baseAreaM2 =
                                          areaM2 / effectiveMultiplier;
                                      final baseValue =
                                          selectedUnit == 'm3'
                                              ? baseAreaM2 * depth!
                                              : baseAreaM2;
                                      update.addAll({
                                        'type': newType,
                                        'measureType': newMeasureType,
                                        'asVolume': selectedUnit == 'm3',
                                        'areaUsedM2Scaled': areaM2,
                                        'depthM':
                                            selectedUnit == 'm3'
                                                ? depth
                                                : FieldValue.delete(),
                                        'volumeM3Scaled':
                                            selectedUnit == 'm3'
                                                ? value
                                                : FieldValue.delete(),
                                      });
                                      if (source.containsKey('valueBase')) {
                                        update['valueBase'] = baseValue;
                                      }
                                      if (source.containsKey('areaUsedM2')) {
                                        update['areaUsedM2'] = baseAreaM2;
                                      }
                                      if (source.containsKey('volumeM3')) {
                                        update['volumeM3'] =
                                            selectedUnit == 'm3'
                                                ? baseValue
                                                : FieldValue.delete();
                                      }
                                      if (originalType.toLowerCase().contains(
                                        'concretebed',
                                      )) {
                                        update.addAll({
                                          'concreteBedUnit': selectedUnit,
                                          'concreteBedQuantityTotal': value,
                                          'concreteBedThicknessM': depth,
                                          'concreteBedThicknessMm':
                                              depth == null
                                                  ? null
                                                  : depth * 1000,
                                        });
                                      }
                                      final normalizedOriginalType =
                                          originalType.toLowerCase();
                                      final isRampConcrete =
                                          originalMeasureType.toLowerCase() ==
                                              'compositeramp' &&
                                          normalizedOriginalType.startsWith(
                                            'ramp_',
                                          ) &&
                                          normalizedOriginalType.endsWith(
                                            '_concrete',
                                          );
                                      if (isRampConcrete) {
                                        update.addAll({
                                          'concreteMeasureUnit': selectedUnit,
                                          'concreteAreaM2Total': areaM2,
                                          'concreteVolumeM3Total':
                                              areaM2 * (depth ?? 0),
                                          'thicknessM': depth,
                                        });
                                      }
                                    }

                                    await FirebaseFirestore.instance
                                        .collection('projects')
                                        .doc(widget.projectId)
                                        .collection('buildings')
                                        .doc(widget.buildingId)
                                        .collection('measurements')
                                        .doc(measurementId)
                                        .update(update);
                                    if (editorContext.mounted) {
                                      Navigator.of(editorContext).pop(true);
                                    }
                                  } catch (error) {
                                    setEditorState(() {
                                      saving = false;
                                      errorText = 'Could not save: $error';
                                    });
                                  }
                                },
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ) ??
        false;

    labelController.dispose();
    quantityController.dispose();
    thicknessController.dispose();
    if (saved) {
      await _refreshBoqData();
      Get.snackbar(
        'Take-off updated',
        'The saved source now uses ${_sourceUnitLabel(selectedUnit)}.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return saved;
  }

  Future<void> _showTakeoffSources({
    required String boqCode,
    required String boqItemId,
    required Iterable<String> boqAliases,
    required String description,
    required String unit,
    required List<Map<String, dynamic>> measurements,
  }) async {
    final normalizedCodes = {_normKey(boqCode), ...boqAliases.map(_normKey)}
      ..removeWhere((code) => code.isEmpty);
    final sources =
        measurements.where((measurement) {
          final measurementBoqItemId = _s(measurement['boqItemId']).trim();
          if (measurementBoqItemId.isNotEmpty) {
            return boqItemId.isNotEmpty && measurementBoqItemId == boqItemId;
          }
          final keys = [
            _s(measurement['boqCode']),
            _s(measurement['resolvedBoqCode']),
            _s(measurement['boqCodeNorm']),
          ];
          return keys.any((key) => normalizedCodes.contains(_normKey(key)));
        }).toList();

    Future<Map<String, Map<String, String>>> loadDrawingDetails() async {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('projects')
              .doc(widget.projectId)
              .collection('buildings')
              .doc(widget.buildingId)
              .collection('drawings')
              .get();
      return {
        for (final doc in snapshot.docs)
          doc.id: {
            'title': _s(
              doc.data()['title'] ??
                  doc.data()['drawingTitle'] ??
                  doc.data()['name'] ??
                  doc.data()['fileName'],
            ),
            'number': _s(
              doc.data()['drawingNumber'] ??
                  doc.data()['sheetNumber'] ??
                  doc.data()['drawingNo'] ??
                  doc.data()['sheetNo'],
            ),
          },
      };
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(26, 20, 16, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF17366F), Color(0xFF1769EA)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Take-off sources',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'BOQ $boqCode • $description',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFFD8E6FF)),
                            ),
                          ],
                        ),
                      ),
                      if (sources.isNotEmpty) ...[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFD92D20),
                          ),
                          onPressed: () async {
                            final deleted = await _deleteAllTakeoffSources(
                              sources: sources,
                              boqCode: boqCode,
                              description: description,
                            );
                            if (deleted && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Delete all'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<Map<String, Map<String, String>>>(
                    future: loadDrawingDetails(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Loading drawings and take-off sources…'),
                            ],
                          ),
                        );
                      }
                      final drawingDetails =
                          snapshot.data ??
                          const <String, Map<String, String>>{};
                      if (sources.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No drawing take-off records contribute to this BOQ item. Its quantity may be manual or not measured yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final canonicalBoqUnit = _canonicalSourceUnit(unit);
                      final matchingSources = sources.where((source) {
                        return _canonicalSourceUnit(_s(source['unit'])) ==
                            canonicalBoqUnit;
                      });
                      final total = matchingSources.fold<double>(0, (
                        totalSoFar,
                        source,
                      ) {
                        return totalSoFar + _sourceNumber(source['value']);
                      });
                      final drawingIds =
                          sources
                              .map((source) => _s(source['drawingId']))
                              .where((id) => id.isNotEmpty)
                              .toSet();
                      final tools =
                          sources.map(_takeoffToolLabel).toSet().toList()
                            ..sort();

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                _sourceMetric(
                                  '${sources.length}',
                                  'Measurements',
                                  Icons.straighten,
                                ),
                                const SizedBox(width: 12),
                                _sourceMetric(
                                  '${drawingIds.length}',
                                  'Drawings',
                                  Icons.image_outlined,
                                ),
                                const SizedBox(width: 12),
                                _sourceMetric(
                                  '${tools.length}',
                                  'Tools used',
                                  Icons.construction_outlined,
                                ),
                                const SizedBox(width: 12),
                                _sourceMetric(
                                  '${_fmtQty(total)} ${_sourceUnitLabel(canonicalBoqUnit)}',
                                  'BOQ-unit total',
                                  Icons.functions,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              itemCount: sources.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, index) {
                                final source = sources[index];
                                final drawingId = _s(source['drawingId']);
                                final registerDrawing =
                                    drawingDetails[drawingId] ?? const {};
                                final registerTitle = _s(
                                  registerDrawing['title'],
                                );
                                final drawingNumber = _s(
                                  registerDrawing['number'],
                                );
                                final storedTitle = _s(
                                  source['drawingTitle'] ??
                                      source['drawingName'],
                                );
                                final drawingTitle =
                                    registerTitle.isNotEmpty
                                        ? registerTitle
                                        : storedTitle.isNotEmpty
                                        ? storedTitle
                                        : (drawingId.isEmpty
                                            ? 'Drawing not recorded'
                                            : 'Drawing $drawingId');
                                final tool = _takeoffToolLabel(source);
                                final label = _s(source['label']);
                                final value = source['value'];
                                final quantity =
                                    value is num
                                        ? value.toDouble()
                                        : double.tryParse('$value') ?? 0;
                                final sourceUnit =
                                    _s(source['unit']).isEmpty
                                        ? canonicalBoqUnit
                                        : _canonicalSourceUnit(
                                          _s(source['unit']),
                                        );
                                final unitMismatch =
                                    sourceUnit != canonicalBoqUnit;
                                return Material(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color:
                                          unitMismatch
                                              ? const Color(0xFFFDB022)
                                              : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      final saved = await _editTakeoffSource(
                                        source: source,
                                        drawingTitle: drawingTitle,
                                        boqUnit: unit,
                                      );
                                      if (saved && dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF4FF),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.architecture_outlined,
                                              color: Color(0xFF1769EA),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Drawing: $drawingTitle',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                if (drawingNumber
                                                    .isNotEmpty) ...[
                                                  Text(
                                                    'Drawing no.: $drawingNumber',
                                                    style: const TextStyle(
                                                      color: Color(0xFF344054),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                ],
                                                Text(
                                                  label.isEmpty
                                                      ? 'Tool: $tool'
                                                      : 'Tool: $tool • Measurement: $label',
                                                  style: const TextStyle(
                                                    color: Color(0xFF667085),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${_fmtQty(quantity)} ${_sourceUnitLabel(sourceUnit)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF17366F),
                                                ),
                                              ),
                                              if (unitMismatch) ...[
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'Unit needs review',
                                                  style: TextStyle(
                                                    color: Color(0xFFB54708),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.edit_outlined,
                                            color: Color(0xFF1769EA),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            tooltip: 'Delete measurement',
                                            onPressed: () async {
                                              final deleted =
                                                  await _deleteTakeoffSource(
                                                    source: source,
                                                    drawingTitle: drawingTitle,
                                                  );
                                              if (deleted &&
                                                  dialogContext.mounted) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Color(0xFFD92D20),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sourceMetric(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1769EA), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _compareBoqDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Prefer explicit 'order' (int/num) if available
    final ao = a['order'];
    final bo = b['order'];

    final aNum = (ao is num) ? ao.toInt() : 0;
    final bNum = (bo is num) ? bo.toInt() : 0;

    final c = aNum.compareTo(bNum);
    if (c != 0) return c;

    // Fallback orderKey if present
    final ak = _s(a['orderKey']);
    final bk = _s(b['orderKey']);
    if (ak.isNotEmpty || bk.isNotEmpty) return ak.compareTo(bk);

    // Final fallback: createdAt
    final at = a['createdAt'];
    final bt = b['createdAt'];
    if (at is Timestamp && bt is Timestamp) {
      return at.compareTo(bt);
    }
    return 0;
  }

  // number formats with commas
  final _qtyFmt = NumberFormat.decimalPattern(); // 1,234
  final _moneyFmt =
      NumberFormat.decimalPattern(); // 1,234 (you can swap to currency)

  String _fmtQty(double v) => _qtyFmt.format(v);
  String _fmtMoney(double v) => _moneyFmt.format(v);

  @override
  Widget build(BuildContext context) {
    final tag =
        '${widget.projectId}|${widget.buildingId}|${widget.drawingId}|${widget.imageUrl}|${widget.drawingTitle}';
    final controller =
        Get.isRegistered<BoqController>(tag: tag)
            ? Get.find<BoqController>(tag: tag)
            : Get.put(
              BoqController(
                projectId: widget.projectId,
                buildingId: widget.buildingId,
                builldingName: widget.buildingName,
              ),
              tag: tag,
            );
    final it =
        Get.isRegistered<ImageTakeoffController>(tag: tag)
            ? Get.find<ImageTakeoffController>(tag: tag)
            : Get.put(
              ImageTakeoffController(
                projectId: widget.projectId,
                buildingId: widget.buildingId,
                drawingId: widget.drawingId,
                drawingTitle: widget.drawingTitle,
                imageUrl: widget.imageUrl,
              ),
              tag: tag,
            );

    return ColoredBox(
      color: AqsColors.canvas,
      child: LayoutBuilder(
        builder: (context, pageConstraints) {
          final isMobile = pageConstraints.maxWidth < 720;
          final viewportHeight =
              pageConstraints.hasBoundedHeight
                  ? pageConstraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
          final content = Obx(() {
            final key = projectDataController.buildingKey(
              widget.projectId,
              widget.buildingId,
            );

            final boqItems = projectDataController.boqFor(
              widget.projectId,
              widget.buildingId,
            );

            final measurements = projectDataController.measurementsFor(
              widget.projectId,
              widget.buildingId,
            );

            final boqLoaded = projectDataController.boqLoaded(
              widget.projectId,
              widget.buildingId,
            );

            final measurementsLoaded = projectDataController.measurementsLoaded(
              widget.projectId,
              widget.buildingId,
            );

            final loadingBoq = projectDataController.loadingBoq.contains(key);

            final loadingMeasurements = projectDataController
                .loadingMeasurements
                .contains(key);

            final boqError = projectDataController.boqErrors[key] ?? '';

            final measurementsError =
                projectDataController.measurementErrors[key] ?? '';

            // ---------------------------------------------------
            // INITIAL LOADING
            // ---------------------------------------------------

            if ((!boqLoaded || !measurementsLoaded) &&
                (loadingBoq || loadingMeasurements)) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Loading BOQ workspace...',
                      style: TextStyle(
                        color: AqsColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            // ---------------------------------------------------
            // ERRORS
            // ---------------------------------------------------

            if (!boqLoaded && boqError.isNotEmpty) {
              return Center(
                child: Text(
                  'Error loading BOQ items:\n$boqError',
                  textAlign: TextAlign.center,
                ),
              );
            }

            if (!measurementsLoaded && measurementsError.isNotEmpty) {
              return Center(
                child: Text(
                  'Error loading measurements:\n$measurementsError',
                  textAlign: TextAlign.center,
                ),
              );
            }

            // ---------------------------------------------------
            // EMPTY BOQ
            // ---------------------------------------------------

            if (boqItems.isEmpty) {
              return _emptyState(
                title: 'Build your first BOQ',
                subtitle:
                    'Create an item manually or import your existing schedule to start linking measurements.',
                actionLabel: _isOpeningAddBoq ? 'Opening…' : 'Add BOQ',
                onAction:
                    _isOpeningAddBoq ? null : () => _openAddBoq(controller),
              );
            }

            // ===================================================
            // MEASUREMENT TOTALS
            // ===================================================

            final totalsByBoq = <String, double>{};
            final totalsByBoqItemId = <String, double>{};

            final countByBoq = <String, int>{};

            double? asDouble(dynamic value) {
              if (value == null) {
                return null;
              }

              if (value is num) {
                return value.toDouble();
              }

              return double.tryParse(value.toString());
            }

            for (final measurement in measurements) {
              final q = asDouble(measurement['value']);

              if (q == null) {
                continue;
              }

              final boqItemId = _s(measurement['boqItemId']).trim();
              if (boqItemId.isNotEmpty) {
                totalsByBoqItemId.update(
                  boqItemId,
                  (value) => value + q,
                  ifAbsent: () => q,
                );
                // A stable BOQ document id is authoritative. Do not also add
                // this quantity under a repeated raw leaf such as "a" or
                // "b", which would make unrelated BOQ rows inherit it.
                continue;
              }

              // A measurement may store the same BOQ code in raw, resolved,
              // and normalized fields. Add the quantity once per distinct
              // normalized alias; otherwise one saved Door/Window record can
              // be counted two or three times in the BOQ table.
              final keys = {
                _normKey(_s(measurement['boqCode'])),
                _normKey(_s(measurement['resolvedBoqCode'])),
                _normKey(_s(measurement['boqCodeNorm'])),
              }..removeWhere((key) => key.isEmpty);

              for (final key in keys) {
                _addTotal(totalsByBoq, countByBoq, key, q);
              }
            }

            // ===================================================
            // BUILD DISPLAY ROWS
            // ===================================================

            final display = <Map<String, dynamic>>[];

            for (final source in boqItems) {
              final d = Map<String, dynamic>.from(source);

              final type = _rowType(d['rowType']);

              final billLabel = _s(d['billLabel']);

              final subheading = _s(d['subheading']);

              final minorLabel = _s(d['minorLabel']);

              final rawBoqCode = _s(d['boqCode']);

              final displayCode = _s(d['displayCode']);

              final resolved = _s(d['resolvedBoqCode']);

              final desc = _s(d['description']);

              final unit = _s(d['unit']);

              final isCivil =
                  _s(d['boqWorkType']).toLowerCase() == 'civil' ||
                  _s(d['sectionType']).toLowerCase() == 'series';

              if (rawBoqCode.isEmpty && desc.isEmpty && displayCode.isEmpty) {
                continue;
              }

              if (type == 'bill') {
                final billCode = _s(d['billCode']);
                var text = billLabel.isNotEmpty ? billLabel : desc;
                if (isCivil && billCode.isNotEmpty) {
                  text =
                      text
                          .replaceFirst(
                            RegExp(
                              '^series\\s*${RegExp.escape(billCode)}\\s*[-:]?\\s*',
                              caseSensitive: false,
                            ),
                            '',
                          )
                          .trim();
                }

                display.add({
                  'type': 'bill',
                  'left':
                      isCivil && billCode.isNotEmpty ? 'SERIES\n$billCode' : '',
                  'text': text,
                  'data': d,
                });

                continue;
              }

              if (type == 'subheading') {
                final storedLeft =
                    _s(d['subHeadingNo']).isNotEmpty
                        ? _s(d['subHeadingNo'])
                        : displayCode.isNotEmpty
                        ? displayCode
                        : rawBoqCode;
                final left =
                    isCivil
                        ? 'Section\n${storedLeft.replaceFirst(RegExp(r'^section\s*', caseSensitive: false), '').replaceFirst(RegExp(r':\s*$'), '')}:'
                        : storedLeft;

                final text = subheading.isNotEmpty ? subheading : desc;

                display.add({
                  'type': 'subheading',
                  'left': left,
                  'text': text,
                  'data': d,
                });

                continue;
              }

              if (type == 'minor') {
                final left =
                    _s(d['minorNo']).isNotEmpty
                        ? _s(d['minorNo'])
                        : displayCode.isNotEmpty
                        ? displayCode
                        : rawBoqCode;

                final text = minorLabel.isNotEmpty ? minorLabel : desc;

                display.add({
                  'type': 'minor',
                  'left': left,
                  'text': text,
                  'data': d,
                });

                continue;
              }

              display.add({
                'type': 'item',

                'viewCode': hierarchicalBoqCodeFromRows(d, boqItems),

                'resolved': resolved.isNotEmpty ? resolved : rawBoqCode,

                'desc': desc,
                'unit': unit,

                // Source contains id because our cache
                // adds {'id': doc.id, ...doc.data()}
                'data': d,
              });
            }

            if (display.isEmpty) {
              return const Center(child: Text('No rows to display.'));
            }

            Future<void> editDisplayRow(Map<String, dynamic> data) async {
              final saved = await controller.showBoqItemDialog(
                existingId: _s(data['id']),
                existingData: data,
                measurementsRef: controller.measRef,
              );
              if (!saved) return;

              await Future.wait([
                projectDataController.loadBoq(
                  widget.projectId,
                  widget.buildingId,
                  forceRefresh: true,
                ),
                projectDataController.loadMeasurements(
                  widget.projectId,
                  widget.buildingId,
                  forceRefresh: true,
                ),
              ]);
            }

            // ===================================================
            // SEARCH
            // ===================================================

            final query = _searchQuery.toLowerCase().trim();

            final visibleDisplay =
                query.isEmpty
                    ? display
                    : display.where((row) {
                      final haystack =
                          '${row['left'] ?? ''} '
                                  '${row['text'] ?? ''} '
                                  '${row['viewCode'] ?? ''} '
                                  '${row['resolved'] ?? ''} '
                                  '${row['desc'] ?? ''} '
                                  '${row['unit'] ?? ''}'
                              .toLowerCase();

                      return haystack.contains(query);
                    }).toList();

            // ===================================================
            // STATISTICS
            // ===================================================

            final itemCount =
                display.where((row) => row['type'] == 'item').length;

            final measuredCount = measurements.length;

            final linkedItemCount =
                display.where((row) {
                  if (row['type'] != 'item') {
                    return false;
                  }

                  final data = row['data'] as Map<String, dynamic>;
                  final id = _s(data['id']).trim();
                  if ((totalsByBoqItemId[id] ?? 0).abs() > 0) {
                    return true;
                  }

                  final keys = [
                    _s(row['resolved']),
                    _s(row['viewCode']),
                    _s(data['boqCode']),
                  ];

                  return keys.any(
                    (key) => (totalsByBoq[_normKey(key)] ?? 0).abs() > 0,
                  );
                }).length;

            // ===================================================
            // NO SEARCH RESULTS
            // ===================================================

            if (visibleDisplay.isEmpty) {
              final empty = _emptyState(
                title: 'No matching BOQ items',
                subtitle:
                    'Try a different code, description, unit, or clear the search.',
                actionLabel: 'Clear search',
                onAction: () {
                  _searchCtrl.clear();

                  setState(() => _searchQuery = '');
                },
              );

              final stats = _statsStrip(
                itemCount: itemCount,
                measuredCount: measuredCount,
                linkedItemCount: linkedItemCount,
              );

              if (isMobile) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [stats, empty],
                );
              }

              return Column(children: [stats, Expanded(child: empty)]);
            }

            // ===================================================
            // TABLE
            // ===================================================

            final table = Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableW = constraints.maxWidth;

                    const tableW = _BoqCols.total + 20;

                    final minW = tableW < availableW ? availableW : tableW;

                    return Scrollbar(
                      controller: _hCtrl,
                      thumbVisibility: true,
                      notificationPredicate:
                          (n) => n.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _hCtrl,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: minW,
                          height: constraints.maxHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: tableW,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: headerHeight,
                                    child: _boqHeaderRow(),
                                  ),

                                  Expanded(
                                    child: Scrollbar(
                                      controller: _vCtrl,
                                      thumbVisibility: true,
                                      notificationPredicate:
                                          (n) =>
                                              n.metrics.axis == Axis.vertical,
                                      child: ListView.builder(
                                        controller: _vCtrl,
                                        itemCount: visibleDisplay.length,
                                        itemBuilder: (context, index) {
                                          final row = visibleDisplay[index];

                                          final type = row['type'] as String;

                                          if (type == 'bill') {
                                            final data =
                                                row['data']
                                                    as Map<String, dynamic>;
                                            return _boqBillRow(
                                              _s(row['left']),
                                              _s(row['text']),
                                              onEdit:
                                                  () => editDisplayRow(data),
                                            );
                                          }

                                          if (type == 'subheading') {
                                            final data =
                                                row['data']
                                                    as Map<String, dynamic>;
                                            return _boqSubheadingRow(
                                              _s(row['left']),
                                              _s(row['text']),
                                              onEdit:
                                                  () => editDisplayRow(data),
                                            );
                                          }

                                          if (type == 'minor') {
                                            final data =
                                                row['data']
                                                    as Map<String, dynamic>;
                                            return _boqMinorRow(
                                              _s(row['left']),
                                              _s(row['text']),
                                              onEdit:
                                                  () => editDisplayRow(data),
                                            );
                                          }

                                          final d =
                                              row['data']
                                                  as Map<String, dynamic>;

                                          final id = _s(d['id']);

                                          final viewCode = _s(row['viewCode']);

                                          final resolved = _s(row['resolved']);

                                          final desc = _s(row['desc']);

                                          final unit = _s(row['unit']);

                                          final rateNum = d['rate'];

                                          final double? rate =
                                              rateNum is num
                                                  ? rateNum.toDouble()
                                                  : double.tryParse('$rateNum');

                                          final rawBoq = _s(d['boqCode']);

                                          double pickTotal(List<String> keys) {
                                            for (final key in keys) {
                                              final value =
                                                  totalsByBoq[_normKey(key)];

                                              if (value != null && value != 0) {
                                                return value;
                                              }
                                            }

                                            return 0.0;
                                          }

                                          final qtyByStableId =
                                              totalsByBoqItemId[id];
                                          final qtyComputed =
                                              qtyByStableId ??
                                              pickTotal([
                                                resolved,
                                                viewCode,
                                                rawBoq,
                                              ]);

                                          final qtyOverrideNum =
                                              d['qtyOverride'];

                                          final double? qtyOverride =
                                              qtyOverrideNum is num
                                                  ? qtyOverrideNum.toDouble()
                                                  : double.tryParse(
                                                    '$qtyOverrideNum',
                                                  );

                                          final qty =
                                              qtyOverride ?? qtyComputed;

                                          final amount =
                                              rate == null ? null : qty * rate;

                                          return _boqItemRow(
                                            onMoveUp: query.isEmpty && display.indexOf(row) > 0 ? () => _moveBoqItem(controller, id, -1) : null,
                                            onMoveDown: query.isEmpty && display.indexOf(row) < display.length - 1 ? () => _moveBoqItem(controller, id, 1) : null,
                                            code: viewCode,
                                            desc: desc,
                                            unit: unit,
                                            qty: qty,
                                            rate: rate,
                                            amount: amount,

                                            onViewSources: () {
                                              _showTakeoffSources(
                                                boqCode: viewCode,
                                                boqItemId: id,
                                                boqAliases: [
                                                  resolved,
                                                  rawBoq,
                                                  _s(d['displayCode']),
                                                ],
                                                description: desc,
                                                unit: unit,
                                                measurements: measurements,
                                              );
                                            },

                                            onEdit: () async {
                                              await editDisplayRow(d);
                                            },

                                            onDelete: () async {
                                              await controller.deleteItem(id);

                                              await projectDataController
                                                  .loadBoq(
                                                    widget.projectId,
                                                    widget.buildingId,
                                                    forceRefresh: true,
                                                  );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );

            final stats = _statsStrip(
              itemCount: itemCount,
              measuredCount: measuredCount,
              linkedItemCount: linkedItemCount,
            );

            if (isMobile) {
              final tableHeight =
                  viewportHeight < 580 ? 420.0 : viewportHeight * 0.72;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [stats, SizedBox(height: tableHeight, child: table)],
              );
            }

            return Column(children: [stats, Expanded(child: table)]);
          });
          // final content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          //   stream: controller.boqStream(),
          //   builder: (ctx, boqSnap) {
          //     if (boqSnap.hasError) {
          //       return Center(
          //         child: Text('Error loading BOQ items:\n${boqSnap.error}'),
          //       );
          //     }
          //     if (!boqSnap.hasData) {
          //       return const Center(child: CircularProgressIndicator());
          //     }

          //     final boqDocs = boqSnap.data!.docs;
          //     if (boqDocs.isEmpty) {
          //       return _emptyState(
          //         title: 'Build your first BOQ',
          //         subtitle:
          //             'Create an item manually or import your existing schedule to start linking measurements.',
          //         actionLabel: 'Add BOQ item',
          //         onAction: () => controller.showAddBoqMenu(),
          //       );
          //     }

          //     return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          //       stream: controller.measStream(),
          //       builder: (ctx, measSnap) {
          //         // -------- totals by measurement boqCode ----------
          //         final totalsByBoq = <String, double>{};
          //         final countByBoq = <String, int>{};

          //         double? asDouble(dynamic v) =>
          //             v == null ? null : (v as num).toDouble();

          //         if (measSnap.hasData) {
          //           for (final d in measSnap.data!.docs) {
          //             final m = d.data();

          //             final q = asDouble(m['value']);
          //             if (q == null) continue;

          //             final raw = _s(m['boqCode']).trim();
          //             final resolved =
          //                 _s(m['resolvedBoqCode']).trim(); // if you store it
          //             final norm =
          //                 _s(m['boqCodeNorm']).trim(); // if you store it

          //             // Always index by raw
          //             if (raw.isNotEmpty) {
          //               _addTotal(totalsByBoq, countByBoq, raw, q);
          //             }

          //             // Also index by resolved (if present)
          //             if (resolved.isNotEmpty) {
          //               _addTotal(totalsByBoq, countByBoq, resolved, q);
          //             }

          //             // Also index by norm (if present)
          //             if (norm.isNotEmpty) {
          //               _addTotal(totalsByBoq, countByBoq, norm, q);
          //             }
          //           }
          //         }

          //         // -------- sort docs ----------
          //         // boqDocs.sort((a, b) => _compareBoqDocs(a.data(), b.data()));

          //         // -------- build display rows (NO returns inside loop!) ----------
          //         final display = <Map<String, dynamic>>[];

          //         for (final doc in boqDocs) {
          //           final d = Map<String, dynamic>.from(doc.data());
          //           d['__id'] = doc.id;

          //           final type = _rowType(d['rowType']);

          //           // prefer firestore fields if present
          //           final billLabel = _s(d['billLabel']);
          //           final subheading = _s(d['subheading']);
          //           final minorLabel = _s(d['minorLabel']);

          //           final rawBoqCode = _s(d['boqCode']);
          //           final displayCode = _s(d['displayCode']);
          //           final resolved = _s(d['resolvedBoqCode']);

          //           final desc = _s(d['description']);
          //           final unit = _s(d['unit']);

          //           // skip truly empty
          //           if (rawBoqCode.isEmpty &&
          //               desc.isEmpty &&
          //               displayCode.isEmpty) {
          //             continue;
          //           }

          //           if (type == 'bill') {
          //             final t = billLabel.isNotEmpty ? billLabel : desc;
          //             display.add({'type': 'bill', 'text': t});
          //             continue;
          //           }

          //           if (type == 'subheading') {
          //             // show code at left (prefer subHeadingNo / boqCode)
          //             final left =
          //                 _s(d['subHeadingNo']).isNotEmpty
          //                     ? _s(d['subHeadingNo'])
          //                     : (displayCode.isNotEmpty
          //                         ? displayCode
          //                         : rawBoqCode);

          //             final t = subheading.isNotEmpty ? subheading : desc;
          //             display.add({
          //               'type': 'subheading',
          //               'left': left,
          //               'text': t,
          //             });
          //             continue;
          //           }

          //           if (type == 'minor') {
          //             // show minorNo at left if exists
          //             final left =
          //                 _s(d['minorNo']).isNotEmpty
          //                     ? _s(d['minorNo'])
          //                     : (displayCode.isNotEmpty
          //                         ? displayCode
          //                         : rawBoqCode);

          //             final t = minorLabel.isNotEmpty ? minorLabel : desc;
          //             display.add({'type': 'minor', 'left': left, 'text': t});
          //             continue;
          //           }

          //           // item row
          //           display.add({
          //             'type': 'item',
          //             'viewCode':
          //                 displayCode.isNotEmpty ? displayCode : rawBoqCode,
          //             'resolved': resolved.isNotEmpty ? resolved : rawBoqCode,
          //             'desc': desc,
          //             'unit': unit,
          //             'data': d,
          //           });
          //         }

          //         if (display.isEmpty) {
          //           return const Center(child: Text('No rows to display.'));
          //         }

          //         final query = _searchQuery.toLowerCase().trim();
          //         final visibleDisplay =
          //             query.isEmpty
          //                 ? display
          //                 : display.where((row) {
          //                   final haystack =
          //                       '${row['left'] ?? ''} ${row['text'] ?? ''} '
          //                               '${row['viewCode'] ?? ''} ${row['resolved'] ?? ''} '
          //                               '${row['desc'] ?? ''} ${row['unit'] ?? ''}'
          //                           .toLowerCase();
          //                   return haystack.contains(query);
          //                 }).toList();

          //         final itemCount =
          //             display.where((row) => row['type'] == 'item').length;
          //         final measuredCount = measSnap.data?.docs.length ?? 0;
          //         final linkedItemCount =
          //             display.where((row) {
          //               if (row['type'] != 'item') return false;
          //               final data = row['data'] as Map<String, dynamic>;
          //               final keys = [
          //                 _s(row['resolved']),
          //                 _s(row['viewCode']),
          //                 _s(data['boqCode']),
          //               ];
          //               return keys.any(
          //                 (key) => (totalsByBoq[_normKey(key)] ?? 0).abs() > 0,
          //               );
          //             }).length;

          //         if (visibleDisplay.isEmpty) {
          //           final empty = _emptyState(
          //             title: 'No matching BOQ items',
          //             subtitle:
          //                 'Try a different code, description, unit, or clear the search.',
          //             actionLabel: 'Clear search',
          //             onAction: () {
          //               _searchCtrl.clear();
          //               setState(() => _searchQuery = '');
          //             },
          //           );
          //           final stats = _statsStrip(
          //             itemCount: itemCount,
          //             measuredCount: measuredCount,
          //             linkedItemCount: linkedItemCount,
          //           );

          //           if (isMobile) {
          //             return Column(
          //               mainAxisSize: MainAxisSize.min,
          //               children: [stats, empty],
          //             );
          //           }

          //           return Column(children: [stats, Expanded(child: empty)]);
          //         }

          //         final table = Padding(
          //           padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          //           child: Card(
          //             clipBehavior: Clip.antiAlias,
          //             child: LayoutBuilder(
          //               builder: (context, constraints) {
          //                 final availableW = constraints.maxWidth;
          //                 const tableW = _BoqCols.total + 20;

          //                 // If screen is wider than table, center it.
          //                 final minW =
          //                     tableW < availableW ? availableW : tableW;

          //                 return Scrollbar(
          //                   controller: _hCtrl,
          //                   thumbVisibility: true,
          //                   notificationPredicate:
          //                       (n) => n.metrics.axis == Axis.horizontal,
          //                   child: SingleChildScrollView(
          //                     controller: _hCtrl,
          //                     scrollDirection: Axis.horizontal,
          //                     child: SizedBox(
          //                       width: minW,
          //                       height:
          //                           constraints
          //                               .maxHeight, // ✅ allow Expanded inside
          //                       child: Align(
          //                         alignment: Alignment.topCenter,
          //                         child: SizedBox(
          //                           width: tableW,
          //                           child: Column(
          //                             children: [
          //                               SizedBox(
          //                                 height: headerHeight,
          //                                 child: _boqHeaderRow(),
          //                               ),
          //                               Expanded(
          //                                 child: Scrollbar(
          //                                   controller: _vCtrl,
          //                                   thumbVisibility: true,
          //                                   notificationPredicate:
          //                                       (n) =>
          //                                           n.metrics.axis ==
          //                                           Axis.vertical,
          //                                   child: ListView.builder(
          //                                     controller: _vCtrl,
          //                                     itemCount: visibleDisplay.length,
          //                                     itemBuilder: (ctx, i) {
          //                                       final row = visibleDisplay[i];
          //                                       final type =
          //                                           row['type'] as String;

          //                                       if (type == 'bill') {
          //                                         return _boqBillRow(
          //                                           _s(row['text']),
          //                                         );
          //                                       }
          //                                       if (type == 'subheading') {
          //                                         return _boqSubheadingRow(
          //                                           _s(row['left']),
          //                                           _s(row['text']),
          //                                         );
          //                                       }
          //                                       if (type == 'minor') {
          //                                         return _boqMinorRow(
          //                                           _s(row['left']),
          //                                           _s(row['text']),
          //                                         );
          //                                       }

          //                                       // item
          //                                       final d =
          //                                           row['data']
          //                                               as Map<String, dynamic>;
          //                                       final id = _s(d['__id']);

          //                                       final viewCode = _s(
          //                                         row['viewCode'],
          //                                       );
          //                                       final resolved = _s(
          //                                         row['resolved'],
          //                                       );
          //                                       final desc = _s(row['desc']);
          //                                       final unit = _s(row['unit']);

          //                                       final rateNum = d['rate'];
          //                                       final rate =
          //                                           (rateNum is num)
          //                                               ? rateNum.toDouble()
          //                                               : null;

          //                                       // qty: try resolved first (recommended), then viewCode, then raw
          //                                       // qtyComputed: from measurements totals
          //                                       // final qtyComputed =
          //                                       //     totalsByBoq[resolved] ??
          //                                       //     totalsByBoq[viewCode] ??
          //                                       //     totalsByBoq[_s(d['boqCode'])] ??
          //                                       //     0.0;
          //                                       final rawBoq = _s(d['boqCode']);
          //                                       // final viewCode = _s(row['viewCode']);
          //                                       // final resolved = _s(row['resolved']);

          //                                       double _pickTotal(
          //                                         List<String> keys,
          //                                       ) {
          //                                         for (final k in keys) {
          //                                           final v =
          //                                               totalsByBoq[_normKey(
          //                                                 k,
          //                                               )];
          //                                           if (v != null && v != 0)
          //                                             return v;
          //                                         }
          //                                         return 0.0;
          //                                       }

          //                                       final qtyComputed = _pickTotal([
          //                                         resolved,
          //                                         viewCode,
          //                                         rawBoq,
          //                                       ]);

          //                                       // qtyOverride: from BOQ item doc (manual override)
          //                                       final qtyOverrideNum =
          //                                           d['qtyOverride'];
          //                                       final double? qtyOverride =
          //                                           (qtyOverrideNum is num)
          //                                               ? qtyOverrideNum
          //                                                   .toDouble()
          //                                               : double.tryParse(
          //                                                 '$qtyOverrideNum',
          //                                               );

          //                                       // final qty to display
          //                                       final qty =
          //                                           qtyOverride ?? qtyComputed;

          //                                       final amount =
          //                                           (rate == null)
          //                                               ? null
          //                                               : (qty * rate);

          //                                       return _boqItemRow(
          //                                         code: viewCode,
          //                                         desc: desc,
          //                                         unit: unit,
          //                                         qty: qty,
          //                                         rate: rate,
          //                                         amount: amount,
          //                                         onEdit:
          //                                             () => controller
          //                                                 .showBoqItemDialog(
          //                                                   // projectId:
          //                                                   //     widget.projectId,
          //                                                   // buildingId:
          //                                                   // widget.buildingId,
          //                                                   existingId: id,
          //                                                   existingData: d,
          //                                                   measurementsRef:
          //                                                       controller
          //                                                           .measRef,
          //                                                 ),
          //                                         onDelete:
          //                                             () => controller
          //                                                 .deleteItem(id),
          //                                       );
          //                                     },
          //                                   ),
          //                                 ),
          //                               ),
          //                             ],
          //                           ),
          //                         ),
          //                       ),
          //                     ),
          //                   ),
          //                 );
          //               },
          //             ),
          //           ),
          //         );

          //         final stats = _statsStrip(
          //           itemCount: itemCount,
          //           measuredCount: measuredCount,
          //           linkedItemCount: linkedItemCount,
          //         );

          //         if (isMobile) {
          //           final tableHeight =
          //               viewportHeight < 580 ? 420.0 : viewportHeight * 0.72;
          //           return Column(
          //             mainAxisSize: MainAxisSize.min,
          //             children: [
          //               stats,
          //               SizedBox(height: tableHeight, child: table),
          //             ],
          //           );
          //         }

          //         return Column(children: [stats, Expanded(child: table)]);
          //       },
          //     );
          //   },
          // );

          if (isMobile) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewportHeight),
                child: Column(
                  children: [
                    _workspaceHeader(context, controller, it),
                    content,
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              _workspaceHeader(context, controller, it),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _workspaceHeader(
    BuildContext context,
    BoqController controller,
    ImageTakeoffController it,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final title = Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AqsColors.primaryDark, AqsColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bill of Quantities',
                      style: TextStyle(
                        color: AqsColors.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.onBackToDrawings != null)
                OutlinedButton.icon(
                  onPressed: widget.onBackToDrawings,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(widget.backLabel),
                ),
              OutlinedButton.icon(
                onPressed: _isRefreshing ? null : _refreshBoqData,
                icon:
                    _isRefreshing
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_isRefreshing ? 'Refreshing' : 'Refresh'),
              ),
              // =====================================================
              // BILLS SUMMARY
              // =====================================================
              OutlinedButton.icon(
                onPressed: () {
                  Get.to(
                    () => BoqBillsSummaryPage(
                      projectId: widget.projectId,
                      buildingId: widget.buildingId,
                      projectName: widget.projectName,
                      buildingName: widget.buildingName,
                      workspaceController: controller,
                    ),
                  );
                },
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('Bills summary'),
              ),

              // =====================================================
              // LINKED ITEMS
              // =====================================================
              OutlinedButton.icon(
                onPressed: () async {
                  await showLinkedItemsDialog(
                    context: context,
                    ctxp: it,
                    linkedCtrl: linkedCtrl,
                    repo: linkRepo,
                    pickTargetBoq: (c) {
                      return it.showBoqPickerDialog(context: context);
                    },
                  );

                  if (mounted) {
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Obx(() {
                  final count = linkedCtrl.targets.length;

                  return Text(count == 0 ? 'Linked items' : 'Linked ($count)');
                }),
              ),

              // =====================================================
              // DELETE ALL BOQ
              // =====================================================
              OutlinedButton.icon(
                onPressed: () async {
                  await controller.deleteAllBoqItems();

                  // Refresh shared BOQ state after deletion.
                  await projectDataController.loadBoq(
                    widget.projectId,
                    widget.buildingId,
                    forceRefresh: true,
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD92D20),
                  side: const BorderSide(color: Color(0xFFFDA29B)),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Delete BOQ'),
              ),

              // =====================================================
              // ADD BOQ ITEM
              // =====================================================
              FilledButton.icon(
                onPressed:
                    _isOpeningAddBoq ? null : () => _openAddBoq(controller),
                icon:
                    _isOpeningAddBoq
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.add_rounded, size: 19),
                label: Text(_isOpeningAddBoq ? 'Opening…' : 'Add BOQ'),
              ),
            ],
          );

          // final actions = Wrap(
          //   spacing: 8,
          //   runSpacing: 8,
          //   crossAxisAlignment: WrapCrossAlignment.center,
          //   children: [
          //     OutlinedButton.icon(
          //       onPressed: () {
          //         Get.to(
          //           () => BoqBillsSummaryPage(
          //             projectId: widget.projectId,
          //             buildingId: widget.buildingId,
          //             projectName: widget.projectName,
          //             buildingName: widget.buildingName,
          //             workspaceController: controller,
          //           ),
          //         );
          //       },
          //       icon: const Icon(Icons.analytics_outlined, size: 18),
          //       label: const Text('Bills summary'),
          //     ),
          //     OutlinedButton.icon(
          //       onPressed: () async {
          //         await showLinkedItemsDialog(
          //           context: context,
          //           ctxp: it,
          //           linkedCtrl: linkedCtrl,
          //           repo: linkRepo,
          //           pickTargetBoq:
          //               (c) => it.showBoqPickerDialog(context: context),
          //         );
          //         if (mounted) setState(() {});
          //       },
          //       icon: const Icon(Icons.link_rounded, size: 18),
          //       label: Obx(() {
          //         final count = linkedCtrl.targets.length;
          //         return Text(count == 0 ? 'Linked items' : 'Linked ($count)');
          //       }),
          //     ),
          //     OutlinedButton.icon(
          //       onPressed: () => controller.deleteAllBoqItems(),
          //       style: OutlinedButton.styleFrom(
          //         foregroundColor: const Color(0xFFD92D20),
          //         side: const BorderSide(color: Color(0xFFFDA29B)),
          //       ),
          //       icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          //       label: const Text('Delete BOQ'),
          //     ),
          //     FilledButton.icon(
          //       onPressed: () => controller.showAddBoqMenu(),
          //       icon: const Icon(Icons.add_rounded, size: 19),
          //       label: const Text('Add item'),
          //     ),
          //   ],
          // );

          return Column(
            children: [
              if (compact) ...[
                title,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: actions),
              ] else
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    actions,
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search BOQ code, description, heading or unit…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon:
                      _searchQuery.isEmpty
                          ? null
                          : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statsStrip({
    required int itemCount,
    required int measuredCount,
    required int linkedItemCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final cards = [
            _statCard(
              icon: Icons.list_alt_rounded,
              label: 'BOQ items',
              value: '$itemCount',
              color: AqsColors.primary,
              background: AqsColors.primarySoft,
            ),
            _statCard(
              icon: Icons.straighten_rounded,
              label: 'Measurements',
              value: '$measuredCount',
              color: const Color(0xFF027A48),
              background: AqsColors.successSoft,
            ),
            _statCard(
              icon: Icons.link_rounded,
              label: 'Linked codes',
              value: '$linkedItemCount',
              color: const Color(0xFFB54708),
              background: const Color(0xFFFFFAEB),
            ),
          ];

          if (compact) {
            return Column(
              children: [
                cards[0],
                const SizedBox(height: 8),
                cards[1],
                const SizedBox(height: 8),
                cards[2],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
              const SizedBox(width: 10),
              Expanded(child: cards[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback? onAction,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AqsColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AqsLogoMark(size: 52),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AqsColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AqsColors.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon:
                  actionLabel.contains('Opening')
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Icon(
                        actionLabel.toLowerCase().contains('clear')
                            ? Icons.close_rounded
                            : Icons.add_rounded,
                      ),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI rows ----------
  Widget _boqHeaderRow() {
    return Container(
      decoration: const BoxDecoration(
        color: AqsColors.primaryDark,
        border: Border(bottom: BorderSide(color: AqsColors.primaryDark)),
      ),
      child: Row(
        children: [
          _cell(
            'BOQ CODE',
            width: _BoqCols.wCode,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            'DESCRIPTION',
            width: _BoqCols.wDesc,
            fw: FontWeight.w800,
            textColor: Colors.white,
          ),
          _cell(
            'UNIT',
            width: _BoqCols.wUnit,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            'QTY',
            width: _BoqCols.wQty,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            'RATE',
            width: _BoqCols.wRate,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            'AMOUNT',
            width: _BoqCols.wAmt,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            'ACTIONS',
            width: _BoqCols.wAct,
            fw: FontWeight.w800,
            center: true,
            textColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _boqBillRow(
    String leftCode,
    String text, {
    required VoidCallback onEdit,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF315A96))),
      ),
      width: _BoqCols.total,
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _BoqCols.wCode,
            fw: FontWeight.w900,
            center: true,
            textColor: Colors.white,
          ),
          _cell(
            text.toUpperCase(),
            width: _BoqCols.spanRest - _BoqCols.wAct,
            fw: FontWeight.w900,
            center: true,
            wrap: true,
            textColor: Colors.white,
          ),
          _headingEditCell(onEdit: onEdit, iconColor: Colors.white),
        ],
      ),
    );
  }

  Widget _boqSubheadingRow(
    String leftCode,
    String text, {
    required VoidCallback onEdit,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: AqsColors.primarySoft,
        border: Border(bottom: BorderSide(color: Color(0xFFBFD2FA))),
      ),
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _BoqCols.wCode,
            fw: FontWeight.w900,
            center: true,
            textColor: AqsColors.primaryDark,
          ),
          _cell(
            text.toUpperCase(),
            width: _BoqCols.spanRest - _BoqCols.wAct,
            fw: FontWeight.w900,
            wrap: true,
            textColor: AqsColors.primaryDark,
          ),
          _headingEditCell(onEdit: onEdit),
        ],
      ),
    );
  }

  Widget _boqMinorRow(
    String leftCode,
    String text, {
    required VoidCallback onEdit,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _BoqCols.wCode,
            fw: FontWeight.w800,
            center: true,
            textColor: AqsColors.text,
          ),
          _cell(
            text.toUpperCase(),
            width: _BoqCols.spanRest - _BoqCols.wAct,
            fw: FontWeight.w800,
            wrap: true,
            textColor: AqsColors.text,
          ),
          _headingEditCell(onEdit: onEdit),
        ],
      ),
    );
  }

  Widget _headingEditCell({
    required VoidCallback onEdit,
    Color iconColor = AqsColors.primary,
  }) {
    return SizedBox(
      width: _BoqCols.wAct,
      child: Center(
        child: IconButton(
          tooltip: 'Edit',
          icon: Icon(Icons.edit_outlined, size: 18, color: iconColor),
          onPressed: onEdit,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  bool _movingBoq = false;

  Future<void> _moveBoqItem(BoqController controller, String id, int direction) async {
    if (_movingBoq) return;
    setState(() => _movingBoq = true);
    try {
      final snapshot = await controller.boqRef.orderBy('order').get();
      final docs = snapshot.docs.toList();
      final index = docs.indexWhere((d) => d.id == id);
      final target = index + direction;
      if (index < 0 || target < 0 || target >= docs.length) return;
      if (docs.length > 450) throw StateError('This BOQ is too large for an atomic reorder. No rows were changed.');
      final reordered = docs.toList();
      final moved = reordered.removeAt(index);
      reordered.insert(target, moved);
      await controller.boqRef.firestore.runTransaction((tx) async {
        for (final doc in docs) {
          final current = await tx.get(doc.reference);
          if (!current.exists || current.data()?['order'] != doc.data()['order']) {
            throw StateError('BOQ order changed. Refresh and try again.');
          }
        }
        for (var i = 0; i < reordered.length; i++) {
          tx.update(reordered[i].reference, {'order': i + 1});
        }
      });
      await projectDataController.loadBoq(widget.projectId, widget.buildingId, forceRefresh: true);
    } catch (e) {
      Get.snackbar('Could not move item', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _movingBoq = false);
    }
  }

  Widget _boqItemRow({
    required String code,
    required String desc,
    required String unit,
    required double qty,
    required double? rate,
    required double? amount,
    required VoidCallback onViewSources,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final qtyText = _fmtQty(qty);
    final rateText = rate == null ? '' : fmtMoney(rate);
    final amtText = amount == null ? '' : fmtMoney(amount);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cell(
            code,
            width: _BoqCols.wCode,
            center: true,
            fw: FontWeight.w800,
            textColor: AqsColors.primary,
          ),
          _cell(desc, width: _BoqCols.wDesc, wrap: true),
          _cell(
            unit,
            width: _BoqCols.wUnit,
            center: true,
            fw: FontWeight.w700,
            textColor: AqsColors.muted,
          ),
          _cell(
            qtyText,
            width: _BoqCols.wQty,
            center: true,
            fw: FontWeight.w800,
          ),
          _cell(rateText, width: _BoqCols.wRate, center: true),
          _cell(
            amtText,
            width: _BoqCols.wAmt,
            center: true,
            fw: FontWeight.w800,
            textColor: AqsColors.ink,
          ),
          _actionsCell(
            onViewSources: onViewSources,
            onEdit: onEdit,
            onDelete: onDelete,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
          ),
        ],
      ),
    );
  }

  Widget _actionsCell({
    required VoidCallback onViewSources,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    return Container(
      width: _BoqCols.wAct,
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Move item',
            icon: const Icon(Icons.swap_vert, size: 18),
            enabled: !_movingBoq && (onMoveUp != null || onMoveDown != null),
            onSelected: (value) => value == 'up' ? onMoveUp?.call() : onMoveDown?.call(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'up', enabled: onMoveUp != null, child: const Text('Move up')),
              PopupMenuItem(value: 'down', enabled: onMoveDown != null, child: const Text('Move down')),
            ],
          ),
          IconButton(
            tooltip: 'Take-off sources',
            icon: const Icon(
              Icons.account_tree_outlined,
              size: 18,
              color: Color(0xFF0E9384),
            ),
            onPressed: onViewSources,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AqsColors.primary,
            ),
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFFD92D20),
            ),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required double width,
    FontWeight fw = FontWeight.w400,
    bool center = false,
    bool wrap = false,
    Color? bg,
    Color? textColor,
    double fontSize = 13,
    EdgeInsets pad = const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: pad,
        color: bg,
        child: Text(
          text,
          textAlign: center ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: textColor ?? AqsColors.text,
            fontWeight: fw,
            fontSize: fontSize,
          ),
          softWrap: true,
          // ✅ IMPORTANT: never use visible here
          overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
          maxLines: wrap ? null : 2,
        ),
      ),
    );
  }
}

class _BoqCols {
  static const double wCode = 90;
  static const double wDesc = 560;
  static const double wUnit = 110;
  static const double wQty = 110;
  static const double wRate = 100;
  static const double wAmt = 120;
  static const double wAct = 120;

  static const double total =
      wCode + wDesc + wUnit + wQty + wRate + wAmt + wAct;

  static const double spanRest = wDesc + wUnit + wQty + wRate + wAmt + wAct;
}
