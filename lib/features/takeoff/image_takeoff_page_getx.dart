import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/features/bindings/image_takeoff_binding.dart';
import 'package:aqs/features/boq/views/boq_tab_getx.dart';
import 'package:aqs/features/takeoff/active_summary_panel.dart';
import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';

import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
import 'package:aqs/features/takeoff/dialogs/roof_structure_measurement_sheet.dart';
import 'package:aqs/features/takeoff/measuring_tools_palette.dart';
import 'package:aqs/features/takeoff/models/count_marker.dart';
import 'package:aqs/features/takeoff/models/measured_segment.dart';
import 'package:aqs/features/takeoff/models/saved_area.dart';
import 'package:aqs/features/takeoff/overlays/count_marker_painter.dart';
import 'package:aqs/features/takeoff/overlays/segments_painter.dart';

import 'package:aqs/features/takeoff/overlays/point_painter.dart';
import 'package:aqs/features/takeoff/overlays/saved_area_painter.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

Stream<QuerySnapshot<Map<String, dynamic>>> _drawingsStream(
  String projectId,
  String buildingId,
) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('buildings')
      .doc(buildingId)
      .collection('drawings')
      .orderBy('createdAt', descending: true)
      .stateSnapshots();
}

String _scopedDrawingImageUrl({
  required String imageUrl,
  required String drawingId,
  required String imagePath,
  required int sourcePageNumber,
}) {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null || !uri.hasScheme) return imageUrl;

  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'aqsDrawingId': drawingId,
          if (imagePath.isNotEmpty) 'aqsImagePath': imagePath,
          'aqsPage': '$sourcePageNumber',
        },
      )
      .toString();
}

enum _LengthDraftMenuAction { addAnother, undo, cancel, finish }

class ImageTakeoffPageGetX extends StatefulWidget {
  final bool embedded;
  final ValueChanged<Map<String, String>>? onDrawingChanged;
  final VoidCallback? onBackToDrawings;

  const ImageTakeoffPageGetX({
    super.key,
    this.embedded = false,
    this.onDrawingChanged,
    this.onBackToDrawings,
  });

  @override
  State<ImageTakeoffPageGetX> createState() => _ImageTakeoffPageGetXState();
}

class _ImageTakeoffPageGetXState extends State<ImageTakeoffPageGetX> {
  // The desktop take-off chrome needs enough room for the permanent tool rail,
  // drawing selector, toolbar, and summary panel. Landscape phones and smaller
  // tablets are wider than a typical phone but still cannot fit that workspace.
  static const double _compactBreakpoint = 900;
  bool _switchingDrawing = false;
  bool _showingLengthDraftMenu = false;
  bool _openingBoq = false;
  late final bool _restoreNativeContextMenu;

  @override
  void initState() {
    super.initState();
    _restoreNativeContextMenu = kIsWeb && BrowserContextMenu.enabled;
    if (_restoreNativeContextMenu) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  void dispose() {
    if (_restoreNativeContextMenu) {
      BrowserContextMenu.enableContextMenu();
    }
    super.dispose();
  }

  void _switchToDrawing({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String drawingTitle,
    required String imageUrl,
  }) {
    if (_switchingDrawing) return;
    setState(() => _switchingDrawing = true);

    try {
      ImageTakeoffBinding.registerDrawing(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        imageUrl: imageUrl,
      );
    } finally {
      if (mounted) {
        setState(() => _switchingDrawing = false);
      }
    }
  }

  Future<void> _openBoqWorkspace(ImageTakeoffController controller) async {
    if (_openingBoq) return;
    setState(() => _openingBoq = true);

    try {
      var projectName = 'Project';
      var buildingName = 'Building';
      final projectRef = FirebaseFirestore.instance
          .collection('projects')
          .doc(controller.projectId);
      try {
        final snapshots = await Future.wait([
          projectRef.get(),
          projectRef.collection('buildings').doc(controller.buildingId).get(),
        ]);
        final projectData = snapshots[0].data() ?? const <String, dynamic>{};
        final buildingData = snapshots[1].data() ?? const <String, dynamic>{};
        projectName =
            (projectData['name'] ??
                    projectData['projectName'] ??
                    projectData['title'] ??
                    projectName)
                .toString();
        buildingName =
            (buildingData['name'] ??
                    buildingData['buildingName'] ??
                    buildingData['title'] ??
                    buildingName)
                .toString();
      } catch (_) {
        // Names are presentation-only; the BOQ can still open from its IDs.
      }

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) => _TakeoffBoqPage(
                projectId: controller.projectId,
                projectName: projectName,
                buildingId: controller.buildingId,
                buildingName: buildingName,
                drawingId: controller.drawingId,
                drawingTitle: controller.drawingTitle,
                imageUrl: controller.imageUrl,
              ),
        ),
      );
    } catch (error) {
      Get.snackbar(
        'Unable to open BOQ',
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _openingBoq = false);
    }
  }

  MouseCursor _cursorForMode(TakeoffMode mode) {
    switch (mode) {
      case TakeoffMode.view:
        return SystemMouseCursors.grab;
      case TakeoffMode.calibrate:
      case TakeoffMode.measureLength:
      case TakeoffMode.measureArea:
        return SystemMouseCursors.precise;
      case TakeoffMode.editSegment:
        return SystemMouseCursors.click;
    }
  }

  String _measurementOverlayGroupId(
    Map<String, dynamic> data,
    String documentId,
  ) {
    for (final key in const [
      'assemblyId',
      'plinthGroupId',
      'pavementGroupId',
      'finishGroupId',
      'segmentId',
      'areaSessionId',
      'areaGroupId',
      'beamId',
      'columnGroupId',
      'columnId',
      'footingGroupId',
      'slabId',
      'slabGroupId',
      'wallGroupId',
      'foundationWallId',
      'foundationGroupId',
      'retainingWallId',
      'stairId',
      'rampId',
      'civilWorkId',
      'ceilingGroupId',
      'tileGroupId',
      'roofGroupId',
      'countGroupId',
      'lengthGroupId',
      'roadProfileGroupId',
      'volumeGroupId',
      'doorGroupId',
      'windowGroupId',
      'groupId',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return documentId;
  }

  String _measurementOverlayTypeLabel(Map<String, dynamic> data) {
    final savedLabel = (data['label'] ?? '').toString().trim();
    if (savedLabel.isNotEmpty) return savedLabel;
    final raw =
        (data['measureType'] ?? data['typeGroup'] ?? data['type'] ?? '')
            .toString()
            .trim();
    if (raw.isEmpty) return 'Saved measurement';
    final words =
        raw
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match.group(1)} ${match.group(2)}',
            )
            .split(RegExp(r'[_\s-]+'))
            .where((word) => word.isNotEmpty)
            .toList();
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _showMeasurementVisibilitySheet(
    BuildContext context,
    MeasuringItemController mi,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => DraggableScrollableSheet(
                  expand: false,
                  minChildSize: 0.35,
                  initialChildSize: 0.72,
                  maxChildSize: 0.94,
                  builder:
                      (context, scrollController) => Material(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream:
                              mi.measurementsRef
                                  .where('drawingId', isEqualTo: mi.drawingId)
                                  .stateSnapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Could not load saved markings.\n${snapshot.error}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final groups =
                                <
                                  String,
                                  List<
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >
                                >{};
                            for (final doc in snapshot.data!.docs) {
                              final groupId = _measurementOverlayGroupId(
                                doc.data(),
                                doc.id,
                              );
                              groups.putIfAbsent(groupId, () => []).add(doc);
                            }
                            final entries =
                                groups.entries.toList()..sort(
                                  (a, b) => _measurementOverlayTypeLabel(
                                    a.value.first.data(),
                                  ).compareTo(
                                    _measurementOverlayTypeLabel(
                                      b.value.first.data(),
                                    ),
                                  ),
                                );
                            final hiddenCount =
                                entries
                                    .where(
                                      (entry) => mi.isMeasurementOverlayHidden(
                                        entry.key,
                                      ),
                                    )
                                    .length;

                            return Column(
                              children: [
                                const SizedBox(height: 10),
                                Container(
                                  width: 44,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF98A2B3),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    14,
                                    10,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.layers_outlined,
                                        color: Color(0xFF155EEF),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Drawing markings',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            Text(
                                              '${entries.length - hiddenCount} shown · $hiddenCount hidden',
                                              style: const TextStyle(
                                                color: Color(0xFF667085),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Close',
                                        onPressed:
                                            () => Navigator.pop(sheetContext),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed:
                                              entries.isEmpty
                                                  ? null
                                                  : () {
                                                    mi.setAllMeasurementOverlaysVisible(
                                                      entries.map(
                                                        (entry) => entry.key,
                                                      ),
                                                      false,
                                                    );
                                                    setSheetState(() {});
                                                  },
                                          icon: const Icon(
                                            Icons.visibility_off_outlined,
                                          ),
                                          label: const Text('Hide all'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed:
                                              entries.isEmpty
                                                  ? null
                                                  : () {
                                                    mi.setAllMeasurementOverlaysVisible(
                                                      entries.map(
                                                        (entry) => entry.key,
                                                      ),
                                                      true,
                                                    );
                                                    setSheetState(() {});
                                                  },
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                          ),
                                          label: const Text('Show all'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                Expanded(
                                  child:
                                      entries.isEmpty
                                          ? const Center(
                                            child: Text(
                                              'No saved markings on this drawing.',
                                            ),
                                          )
                                          : ListView.separated(
                                            controller: scrollController,
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              8,
                                              12,
                                              24,
                                            ),
                                            itemCount: entries.length,
                                            separatorBuilder:
                                                (_, __) =>
                                                    const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final entry = entries[index];
                                              final first =
                                                  entry.value.first.data();
                                              final visible =
                                                  !mi.isMeasurementOverlayHidden(
                                                    entry.key,
                                                  );
                                              final colorValue =
                                                  (first['color'] is num)
                                                      ? (first['color'] as num)
                                                          .toInt()
                                                      : Colors.blue.value;
                                              return ListTile(
                                                minTileHeight: 56,
                                                leading: Container(
                                                  width: 14,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    color: Color(colorValue),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.black12,
                                                    ),
                                                  ),
                                                ),
                                                title: Text(
                                                  _measurementOverlayTypeLabel(
                                                    first,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  '${_measurementOverlayTypeLabel({'measureType': first['measureType'] ?? first['typeGroup']})} · ${entry.value.length} saved item${entry.value.length == 1 ? '' : 's'}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                trailing: IconButton(
                                                  tooltip:
                                                      visible
                                                          ? 'Hide marking'
                                                          : 'Show marking',
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 48,
                                                        minHeight: 48,
                                                      ),
                                                  onPressed: () {
                                                    mi.setMeasurementOverlayVisible(
                                                      entry.key,
                                                      !visible,
                                                    );
                                                    setSheetState(() {});
                                                  },
                                                  icon: Icon(
                                                    visible
                                                        ? Icons
                                                            .visibility_outlined
                                                        : Icons
                                                            .visibility_off_outlined,
                                                    color:
                                                        visible
                                                            ? const Color(
                                                              0xFF155EEF,
                                                            )
                                                            : const Color(
                                                              0xFF98A2B3,
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
                ),
          ),
    );
  }

  Widget _drawingLoadFallback(MeasuringItemController c) {
    final bytes = c.imageBytes;
    final hasBytes = bytes != null && bytes.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasBytes)
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
          )
        else if (c.imageUrl.trim().isNotEmpty)
          Image.network(
            c.imageUrl,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder:
                (_, __, ___) => const Center(
                  child: Text('Drawing image could not be loaded'),
                ),
          ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.86),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              hasBytes
                  ? 'Preparing drawing canvas...'
                  : 'Loading drawing image...',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _drawingImageLayer(MeasuringItemController c) {
    final bytes = c.imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      );
    }

    if (c.uiImg != null) {
      return RawImage(
        image: c.uiImg,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _showMobileTools(
    BuildContext context,
    MeasuringItemController mi,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (sheetContext) => FractionallySizedBox(
            heightFactor: 0.86,
            child: MeasuringToolsPalette(
              compact: true,
              activeMeasureType: mi.activeMeasureType,
              activeLabel: mi.activeLabel,
              mode: mi.mode.value,
              currentColor: mi.currentColor,
              strokeWidth: mi.baseStroke,
              onSelected: (tool) async {
                Navigator.of(sheetContext).pop();
                await mi.selectMeasurementTool(
                  measureType: tool.measureType,
                  label: tool.label,
                  unit: tool.unit,
                );
              },
              onConfigure: () {
                Navigator.of(sheetContext).pop();
                mi.configureActiveMeasurementTool();
              },
              onPan: () => mi.setMode(TakeoffMode.view),
              onCalibrate: () => mi.setMode(TakeoffMode.calibrate),
              onEdit: () => mi.setMode(TakeoffMode.editSegment),
              onUndo: mi.undoLast,
              onRedo: mi.redoLast,
              onRefresh: mi.refreshWorkspace,
              onColor: mi.chooseMeasurementColor,
              onThickness: () => _showStrokeSliderDialog(mi),
              onZoomIn: mi.zoomIn,
              onZoomOut: mi.zoomOut,
            ),
          ),
    );
  }

  Future<void> _showMobileSummary(
    BuildContext context,
    MeasuringItemController mi,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => DraggableScrollableSheet(
            expand: false,
            minChildSize: 0.38,
            initialChildSize: 0.72,
            maxChildSize: 0.94,
            builder:
                (context, scrollController) => Material(
                  color: const Color(0xFFF6F8FC),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF98A2B3),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          child: ActiveItemSummaryPanel(
                            drawingId: mi.drawingId,
                            measurementsRef: mi.measurementsRef,
                            activeMeasureType: mi.activeMeasureType,
                            activeLabel: mi.activeLabel,
                            activeBoqCode: mi.activeBoqCode,
                            activeUnit: mi.activeUnit,
                            pendingTimberMemberCount:
                                mi.pendingTimberTrussMemberCount,
                            savingTimberTruss: mi.savingPendingTimberTruss,
                            onSaveTimberTruss:
                                () => mi.savePendingTimberTruss(),
                            onDiscardTimberTruss: mi.discardPendingTimberTruss,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _showMobileCanvasActions(
    BuildContext context,
    MeasuringItemController mi,
    ImageTakeoffController it,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (sheetContext) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Canvas actions',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.square_foot),
                  title: const Text('Calibrate'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.setMode(TakeoffMode.calibrate);
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.ads_click_rounded),
                  title: const Text('Select / edit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.setMode(TakeoffMode.editSegment);
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.redo_rounded),
                  title: const Text('Redo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.redoLast();
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Refresh and fit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.refreshWorkspace();
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Show or hide markings'),
                  subtitle: const Text(
                    'Choose which saved take-offs appear on the drawing',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showMeasurementVisibilitySheet(context, mi);
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Measurement color'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.chooseMeasurementColor();
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.line_weight_rounded),
                  title: const Text('Line thickness'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showStrokeSliderDialog(mi);
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configure active tool'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    mi.configureActiveMeasurementTool();
                  },
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(Icons.roofing_outlined),
                  title: const Text('Roof structure sheet'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showRoofStructureMeasurementSheet(
                      context: context,
                      projectId: it.projectId,
                      buildingId: it.buildingId,
                      drawingId: it.drawingId,
                      drawingTitle: it.drawingTitle,
                      measurementsRef: mi.measurementsRef,
                    );
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showLengthDraftMenu({
    required BuildContext context,
    required MeasuringItemController controller,
    required Map<String, dynamic> drawingData,
    required Offset globalPosition,
  }) async {
    if (_showingLengthDraftMenu || controller.draftLengthSegmentCount < 1) {
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;

    final localPosition = overlay.globalToLocal(globalPosition);
    final menuPosition = RelativeRect.fromRect(
      Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final segmentCount = controller.draftLengthSegmentCount;
    final totalLength = controller.draftLengthTotalMeters(drawingData);
    final finishLabel = controller.lengthDraftFinishLabel;

    _showingLengthDraftMenu = true;
    _LengthDraftMenuAction? action;
    try {
      action = await showMenu<_LengthDraftMenuAction>(
        context: context,
        position: menuPosition,
        elevation: 20,
        shadowColor: const Color(0x330F172A),
        surfaceTintColor: Colors.transparent,
        color: Colors.white,
        menuPadding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE4E7EC)),
        ),
        items: [
          PopupMenuItem<_LengthDraftMenuAction>(
            enabled: false,
            height: 76,
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1E0FF),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.straighten_rounded,
                      color: Color(0xFF155EEF),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$segmentCount segment${segmentCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xFF101828),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${totalLength.toStringAsFixed(3)} m total',
                          style: const TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(height: 12),
          PopupMenuItem<_LengthDraftMenuAction>(
            value: _LengthDraftMenuAction.addAnother,
            enabled: controller.canFinishLengthDraft,
            height: 64,
            padding: EdgeInsets.zero,
            child: _LengthMenuTile(
              icon: Icons.call_split_rounded,
              title: 'Add another segment',
              subtitle: 'New start, same measurement group',
              enabled: controller.canFinishLengthDraft,
            ),
          ),
          const PopupMenuItem<_LengthDraftMenuAction>(
            value: _LengthDraftMenuAction.undo,
            height: 54,
            padding: EdgeInsets.zero,
            child: _LengthMenuTile(
              icon: Icons.undo_rounded,
              title: 'Undo last point',
            ),
          ),
          const PopupMenuItem<_LengthDraftMenuAction>(
            value: _LengthDraftMenuAction.cancel,
            height: 54,
            padding: EdgeInsets.zero,
            child: _LengthMenuTile(
              icon: Icons.close_rounded,
              title: 'Cancel measurement',
              destructive: true,
            ),
          ),
          const PopupMenuDivider(height: 12),
          PopupMenuItem<_LengthDraftMenuAction>(
            value: _LengthDraftMenuAction.finish,
            enabled: controller.canFinishLengthDraft,
            height: 56,
            padding: EdgeInsets.zero,
            child: _LengthMenuTile(
              icon: Icons.arrow_forward_rounded,
              title: finishLabel,
              enabled: controller.canFinishLengthDraft,
              emphasized: true,
            ),
          ),
        ],
      );
    } finally {
      _showingLengthDraftMenu = false;
    }

    switch (action) {
      case _LengthDraftMenuAction.addAnother:
        if (controller.startAnotherLengthSegment(drawingData)) {
          Get.snackbar(
            'Add another segment',
            'Tap the new start point, then continue measuring.',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        break;
      case _LengthDraftMenuAction.undo:
        controller.undoDraftLengthPoint();
        break;
      case _LengthDraftMenuAction.cancel:
        controller.clearDraftLength();
        break;
      case _LengthDraftMenuAction.finish:
        await controller.finishContinuousLengthMeasurement(drawingData);
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = Get.find<MeasuringItemController>();
    final it = Get.find<ImageTakeoffController>();

    // print('drawingId frm img: ${it.drawingId}');
    // final beam = Get.find<CompositeBeamTakeoffController>();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: mi.drawingRef.stateSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(it.drawingTitle)),
            body: const Center(child: Text('Error loading drawing')),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: Text(it.drawingTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final drawingData = snapshot.data!.data()!;
        final calibrated = drawingData['calibrated'] == true;
        final scaleText = (drawingData['scaleText'] ?? '') as String;
        final isCompact = MediaQuery.sizeOf(context).width < _compactBreakpoint;
        final mobileBottomInset = MediaQuery.paddingOf(context).bottom + 12;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: widget.embedded ? 'Back to drawing register' : 'Back',
              onPressed: () {
                if (widget.embedded && widget.onBackToDrawings != null) {
                  widget.onBackToDrawings!();
                  return;
                }
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                  return;
                }
                Get.back<void>();
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            toolbarHeight: isCompact ? 60 : 72,
            titleSpacing: isCompact ? 4 : 18,
            title: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _drawingsStream(it.projectId, it.buildingId),
              builder: (ctx, ds) {
                // fallback title if drawings not loaded
                if (!ds.hasData) return Text(it.drawingTitle);

                final docs = ds.data!.docs;

                // build dropdown items (show all, but you can filter to ready-only if you want)
                final items =
                    docs.map((d) {
                      final data = d.data();
                      final title =
                          (data['title'] ?? 'Untitled drawing').toString();
                      final status =
                          (data['processingStatus'] ?? 'pending').toString();
                      final imageUrl =
                          (data['imageUrl'] ?? '').toString().trim();
                      final downloadUrl =
                          (data['downloadUrl'] ?? '').toString().trim();
                      final imagePath =
                          (data['imagePath'] ?? '').toString().trim();
                      final sourcePageNumber =
                          int.tryParse(
                            (data['sourcePageNumber'] ?? '').toString(),
                          ) ??
                          1;
                      final scopedImageUrl = _scopedDrawingImageUrl(
                        imageUrl: imageUrl,
                        drawingId: d.id,
                        imagePath: imagePath,
                        sourcePageNumber: sourcePageNumber,
                      );

                      return {
                        'id': d.id,
                        'title': title,
                        'status': status,
                        'imageUrl': scopedImageUrl,
                        'downloadUrl': downloadUrl,
                        'sourcePageNumber': '$sourcePageNumber',
                      };
                    }).toList();

                // ensure current value exists
                final currentId =
                    items.any((x) => x['id'] == it.drawingId)
                        ? it.drawingId
                        : (items.isNotEmpty
                            ? items.first['id'] as String
                            : it.drawingId);

                return Row(
                  children: [
                    if (!isCompact)
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DRAWING TAKEOFF',
                              style: TextStyle(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    it.drawingTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message:
                                      calibrated
                                          ? (scaleText.isNotEmpty
                                              ? scaleText
                                              : 'Drawing calibrated')
                                          : 'Drawing is not calibrated. Use Calibrate from the top controls.',
                                  child: Icon(
                                    calibrated
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 18,
                                    color:
                                        calibrated
                                            ? Colors.green
                                            : const Color(0xFFD92D20),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (!isCompact) const SizedBox(width: 10),

                    // dropdown
                    Flexible(
                      child: Container(
                        constraints:
                            isCompact
                                ? const BoxConstraints()
                                : const BoxConstraints(maxWidth: 360),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD0D5DD)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentId,
                            isDense: true,
                            isExpanded: isCompact,
                            dropdownColor:
                                Theme.of(context).colorScheme.surface,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            items:
                                items.map((x) {
                                  final id = x['id'] as String;
                                  final title = x['title'] as String;
                                  final status = x['status'] as String;

                                  final ready = status == 'ready';
                                  return DropdownMenuItem<String>(
                                    value: id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          ready
                                              ? Icons.image_outlined
                                              : Icons.hourglass_bottom_rounded,
                                          size: 16,
                                          color:
                                              ready
                                                  ? Colors.green
                                                  : Colors.orange,
                                        ),
                                        const SizedBox(width: 8),
                                        if (isCompact)
                                          Expanded(
                                            child: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )
                                        else
                                          SizedBox(
                                            width: 260,
                                            child: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            onChanged:
                                _switchingDrawing
                                    ? null
                                    : (newId) {
                                      if (newId == null ||
                                          newId == it.drawingId)
                                        return;

                                      final picked = items.firstWhere(
                                        (x) => x['id'] == newId,
                                      );
                                      final status = picked['status'] as String;
                                      final title = picked['title'] as String;
                                      final imageUrl =
                                          picked['imageUrl'] as String;
                                      final downloadUrl =
                                          picked['downloadUrl'] as String;

                                      if (status != 'ready' ||
                                          (imageUrl.isEmpty &&
                                              downloadUrl.isEmpty)) {
                                        Get.snackbar(
                                          'Not ready',
                                          'That drawing image is still processing.',
                                        );
                                        return;
                                      }

                                      if (widget.embedded &&
                                          widget.onDrawingChanged != null) {
                                        widget.onDrawingChanged!({
                                          'drawingId': newId,
                                          'drawingTitle': title,
                                          'imageUrl': imageUrl,
                                          'downloadUrl': downloadUrl,
                                          'sourcePageNumber':
                                              picked['sourcePageNumber']
                                                  as String,
                                        });
                                      } else {
                                        _switchToDrawing(
                                          projectId: it.projectId,
                                          buildingId: it.buildingId,
                                          drawingId: newId,
                                          drawingTitle: title,
                                          imageUrl: imageUrl,
                                        );
                                      }
                                    },
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              if (isCompact)
                IconButton(
                  tooltip: _openingBoq ? 'Opening BOQ' : 'View BOQ',
                  onPressed: _openingBoq ? null : () => _openBoqWorkspace(it),
                  icon:
                      _openingBoq
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.receipt_long_outlined),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: FilledButton.icon(
                    onPressed: _openingBoq ? null : () => _openBoqWorkspace(it),
                    icon:
                        _openingBoq
                            ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(_openingBoq ? 'Opening…' : 'View BOQ'),
                  ),
                ),
              const SizedBox(width: 12),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: const Color(0xFFD0D5DD)),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: GetBuilder<MeasuringItemController>(
                  key: ValueKey('measurement-overlays-${mi.drawingId}'),
                  id: 'overlayVisibility',
                  builder:
                      (
                        mi,
                      ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        key: ValueKey('measurement-stream-${mi.drawingId}'),
                        stream:
                            mi.measurementsRef
                                .where('drawingId', isEqualTo: mi.drawingId)
                                .orderBy('createdAt', descending: false)
                                .stateSnapshots(),
                        builder: (ctx, measSnap) {
                          if (measSnap.hasError) {
                            return Center(
                              child: Text(
                                'Error loading measurements:\n${measSnap.error}',
                              ),
                            );
                          }
                          if (measSnap.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: Card(
                                elevation: 8,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 18,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      Text(
                                        'Loading saved measurements…',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          final docs = measSnap.data?.docs ?? const [];
                          mi.cacheVisibleMeasurementDocuments(docs);

                          // ---------------- helpers ----------------
                          Map<String, dynamic> _asMap(dynamic v) {
                            if (v is Map<String, dynamic>) return v;
                            if (v is Map) return Map<String, dynamic>.from(v);
                            return <String, dynamic>{};
                          }

                          Offset _toOffset(Map<String, dynamic> m) {
                            return Offset(
                              (m['x'] as num? ?? 0).toDouble(),
                              (m['y'] as num? ?? 0).toDouble(),
                            );
                          }

                          ({Offset p1, Offset p2})? _readSegment(
                            Map<String, dynamic> m,
                          ) {
                            // preferred: segment.p1 / segment.p2
                            final seg = _asMap(m['segment']);
                            final p1m =
                                _asMap(seg['p1']).isNotEmpty
                                    ? _asMap(seg['p1'])
                                    : _asMap(m['p1']);
                            final p2m =
                                _asMap(seg['p2']).isNotEmpty
                                    ? _asMap(seg['p2'])
                                    : _asMap(m['p2']);

                            if (p1m.isEmpty || p2m.isEmpty) return null;
                            return (p1: _toOffset(p1m), p2: _toOffset(p2m));
                          }

                          List<
                            ({
                              Offset p1,
                              Offset p2,
                              double? lengthM,
                              double? heightM,
                            })
                          >
                          _readPolylineSegments(Map<String, dynamic> m) {
                            dynamic raw = m['polylineSegments'];
                            // Drainage V1-V7 stored drawable geometry nested under
                            // chains[].segments rather than at polylineSegments.
                            // Flatten it here so already-saved drains also repaint.
                            if (raw is! List || raw.isEmpty) {
                              final chains = m['chains'];
                              if (chains is List && chains.isNotEmpty) {
                                raw = <dynamic>[];
                                for (final chainItem in chains) {
                                  final chain = _asMap(chainItem);
                                  final chainSegments = chain['segments'];
                                  if (chainSegments is List) {
                                    raw.addAll(chainSegments);
                                  }
                                }
                              }
                            }
                            if (raw is! List || raw.isEmpty) return const [];
                            final out =
                                <
                                  ({
                                    Offset p1,
                                    Offset p2,
                                    double? lengthM,
                                    double? heightM,
                                  })
                                >[];
                            for (final item in raw) {
                              final segment = _asMap(item);
                              final p1m = _asMap(segment['p1']);
                              final p2m = _asMap(segment['p2']);
                              if (p1m.isEmpty || p2m.isEmpty) continue;
                              final length =
                                  (segment['lengthM'] is num)
                                      ? (segment['lengthM'] as num).toDouble()
                                      : double.tryParse(
                                        '${segment['lengthM']}',
                                      );
                              final height =
                                  (segment['heightM'] is num)
                                      ? (segment['heightM'] as num).toDouble()
                                      : double.tryParse(
                                        '${segment['heightM'] ?? m['heightM'] ?? ''}',
                                      );
                              out.add((
                                p1: _toOffset(p1m),
                                p2: _toOffset(p2m),
                                lengthM: length,
                                heightM: height,
                              ));
                            }
                            return out;
                          }

                          List<Offset> _readPolygon(Map<String, dynamic> m) {
                            final pts = <Offset>[];
                            final polyList = m['polygon'] ?? m['points'];
                            if (polyList is List) {
                              for (final p in polyList) {
                                final mp = _asMap(p);
                                if (mp.isEmpty) continue;
                                pts.add(_toOffset(mp));
                              }
                            }
                            if (pts.length >= 3) return pts;

                            final normalizedMeasureType = (m['measureType'] ??
                                    m['typeGroup'] ??
                                    '')
                                .toString()
                                .trim()
                                .toLowerCase()
                                .replaceAll(RegExp(r'[_\s-]+'), '');
                            if (normalizedMeasureType.startsWith('liftshaft')) {
                              final p1 = _asMap(m['p1']);
                              final p2 = _asMap(m['p2']);
                              if (p1.isNotEmpty && p2.isNotEmpty) {
                                final a = _toOffset(p1);
                                final c = _toOffset(p2);
                                if (a != c) {
                                  return [
                                    a,
                                    Offset(c.dx, a.dy),
                                    c,
                                    Offset(a.dx, c.dy),
                                  ];
                                }
                              }
                            }
                            return pts;
                          }

                          // ---------------- outputs ----------------
                          final segments = <MeasuredSegment>[];
                          final savedAreas = <SavedArea>[];
                          final drawnAreaIds = <String>{};
                          final countMarkers = <CountMarker>[];
                          final drawnCountGroups = <String>{};

                          final slabCompositeDocsBySlabId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final roofingCompositeDocsBySlabId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final footingCompositeDocsByGroupId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final columnCompositeDocsByColumnId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final beamCompositeDocsByBeamId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final retainingWallCompositeDocsByWallId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final foundationWallCompositeDocsByWallId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final wallCDocsByWallId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final stairCompositeDocsByWallId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final rampCompositeDocsByWallId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final civilWorkDocsId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final ceilingFinishId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          final roofSheetingAndTimberId =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};

                          // 1) parse documents
                          for (final d in docs) {
                            final m = d.data();
                            final visibilityGroupId =
                                _measurementOverlayGroupId(m, d.id);
                            if (mi.isMeasurementOverlayHidden(
                              visibilityGroupId,
                            )) {
                              continue;
                            }

                            final type =
                                (m['type'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final measureType =
                                (m['measureType'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final unitStr = (m['unit'] ?? '').toString().trim();
                            final valueNum = m['value'];
                            final value =
                                (valueNum is num) ? valueNum.toDouble() : 0.0;

                            final normalizedMeasureType =
                                measureType
                                    .replaceAll(RegExp(r'[_\s-]+'), '')
                                    .toLowerCase();
                            if (normalizedMeasureType == 'compositecolumn' ||
                                normalizedMeasureType == 'columncomposite') {
                              final columnId =
                                  (m['columnGroupId'] ??
                                          m['columnId'] ??
                                          m['segmentId'] ??
                                          d.id)
                                      .toString()
                                      .trim();
                              columnCompositeDocsByColumnId
                                  .putIfAbsent(columnId, () => [])
                                  .add(d);
                            }

                            final colorInt =
                                (m['color'] as num?)?.toInt() ??
                                Colors.blue.value;
                            final color = Color(colorInt);
                            final segmentStrokeWidth =
                                (m['strokeWidth'] as num?)?.toDouble();

                            debugPrint(
                              'DOC id=${d.id} type=${m['type']} measureType=${m['measureType']} '
                              'hasPolygon=${m['polygon'] is List} polygonLen=${(m['polygon'] is List) ? (m['polygon'] as List).length : 0}',
                            );

                            bool _isAreaLike(String measureType, String type) {
                              final mt = measureType.trim().toLowerCase();
                              final normalizedMt = mt.replaceAll(
                                RegExp(r'[_\s-]+'),
                                '',
                              );
                              final t = type.trim().toLowerCase();

                              // add your own names here
                              return t.contains('area') ||
                                  t.startsWith('liftshaft') ||
                                  t.contains('ceiling') ||
                                  t == 'floortiles' ||
                                  t == 'walltiles' ||
                                  t == 'floorterrazzo' ||
                                  t == 'floorsandscreed' ||
                                  t == 'floorgranolithicscreed' ||
                                  t == 'tilebackingbed' ||
                                  t.contains('slabConcrete') ||
                                  t.contains('slabconcrete') ||
                                  t.contains('Slab') ||
                                  mt.contains('area') ||
                                  normalizedMt == 'liftshaft' ||
                                  normalizedMt == 'liftshaftassembly' ||
                                  mt == 'plinth' ||
                                  mt == 'pavement' ||
                                  mt == 'groundpreparation' ||
                                  mt.contains('ceiling') ||
                                  mt == 'ceilingfinish' ||
                                  t.contains('roofing') ||
                                  t.contains('roof') ||
                                  mt.contains('roofing') ||
                                  mt.contains('roof') ||
                                  mt.contains('stair') ||
                                  mt.contains('ramp') ||
                                  mt.contains('Slab') ||
                                  mt.contains('slab') ||
                                  mt.contains('civil') ||
                                  mt.contains('footing') ||
                                  mt.contains('column') ||
                                  mt == 'ceilingfinish';
                            }

                            Offset _polygonCentroid(List<Offset> pts) {
                              // Simple centroid (good enough for labeling)
                              double x = 0, y = 0;
                              for (final p in pts) {
                                x += p.dx;
                                y += p.dy;
                              }
                              return Offset(x / pts.length, y / pts.length);
                            }

                            List<Offset> _readPoints(Map<String, dynamic> m) {
                              final raw = (m['points'] ?? []) as List<dynamic>;
                              final pts = <Offset>[];
                              for (final p in raw) {
                                final mp = _asMap(p);
                                if (mp.isNotEmpty) pts.add(_toOffset(mp));
                              }
                              return pts;
                            }

                            final bundleRaw = m['bundleCountPoints'];
                            if (bundleRaw is List && bundleRaw.isNotEmpty) {
                              final bundleMark =
                                  (m['barMark'] ?? m['rawMark'] ?? 'Rebar')
                                      .toString()
                                      .trim();
                              for (var i = 0; i < bundleRaw.length; i++) {
                                final pointMap = _asMap(bundleRaw[i]);
                                if (pointMap.isEmpty) continue;
                                countMarkers.add(
                                  CountMarker(
                                    id: '${d.id}-bundle-$i',
                                    groupId: '${d.id}-bundle-count',
                                    position: _toOffset(pointMap),
                                    color: color,
                                    mark: 'tick',
                                    label:
                                        '${bundleMark.isEmpty ? 'Rebar' : bundleMark} ×${i + 1}',
                                  ),
                                );
                              }
                            }

                            /// Optional: if you have a separate labels list

                            if (measureType == 'count' ||
                                measureType == 'door' ||
                                measureType == 'window' ||
                                measureType == 'compositewindow' ||
                                type == 'countmeasure') {
                              final groupId =
                                  (m['countGroupId'] ?? d.id).toString().trim();
                              if (drawnCountGroups.contains(groupId)) continue;
                              drawnCountGroups.add(groupId);

                              final points = _readPoints(m);
                              final mark =
                                  (m['mark'] ?? 'tick').toString().trim();
                              for (var i = 0; i < points.length; i++) {
                                countMarkers.add(
                                  CountMarker(
                                    id: '${d.id}-$i',
                                    groupId: groupId,
                                    position: points[i],
                                    color: color,
                                    mark: mark.isEmpty ? 'tick' : mark,
                                    label: '${i + 1}',
                                  ),
                                );
                              }
                              continue;
                            }

                            bool _isLengthLike(String mt, String t) {
                              final m = mt.toLowerCase().trim();
                              final tt = t.toLowerCase().trim();

                              if (m == 'length') return true;
                              if (tt == 'lengthmeasure') return true;
                              if (tt == 'beamconcrete') return true;
                              if (tt == 'compositeslab') return true;
                              if (tt == 'compositestair') return true;

                              // ✅ treat these as "line-based" measurements too
                              if (m == 'foundationwall') return true;
                              if (m == 'compositebeam') return true;
                              if (m == 'compositestair') return true;
                              // if (m == 'compositeSlab') return true;
                              if (m == 'compositestair') return true;

                              if (m == 'compositeramp') return true;
                              if (m == 'walling') return true;
                              if (m == 'civilwork') return true;
                              if (m == 'roadprofile' || tt == 'roadprofile') {
                                return true;
                              }
                              // Drainage sessions save one drawable polyline on the
                              // first BOQ-output document. Treat it as a line so the
                              // committed drain remains visible after save/reload.
                              if (m == 'drainage' || tt == 'drainage')
                                return true;
                              if (m == 'retainingwall') return true;
                              if (m == 'retainingcompositewall') return true;
                              if (m == 'roofstructuremember') return true;
                              // Timber roof member measurements are saved with
                              // measureType=compositeRoofing and type=timberRoofStructureMember.
                              // Treat them as line measurements so saved take-off marks remain
                              // visible after the dialog closes.
                              if (m == 'compositeroofing') return true;
                              if (tt == 'timberroofstructuremember')
                                return true;
                              if (m == 'slabrebarai' ||
                                  tt == 'rebarslabmanual' ||
                                  tt == 'rebarslabai') {
                                return true;
                              }

                              return false;
                            }

                            if (_isLengthLike(measureType, type)) {
                              final polylineSegments = _readPolylineSegments(m);
                              final seg = _readSegment(m);
                              if (seg == null && polylineSegments.isEmpty)
                                continue;
                              if (polylineSegments.isNotEmpty &&
                                  measureType.trim().toLowerCase() ==
                                      'walling' &&
                                  type.trim().toLowerCase() != 'wallingnet') {
                                continue;
                              }

                              // ✅ pick the best "length" number to label
                              final double len =
                                  (m['lengthM'] is num)
                                      ? (m['lengthM'] as num).toDouble()
                                      : (m['measuredLengthM'] is num)
                                      ? (m['measuredLengthM'] as num).toDouble()
                                      : (m['wallLengthM'] is num)
                                      ? (m['wallLengthM'] as num).toDouble()
                                      : (m['baseLengthM'] is num)
                                      ? (m['baseLengthM'] as num).toDouble()
                                      : value; // fallback

                              // ✅ groupId for wall/foundationwall should use wallGroupId
                              final groupId =
                                  (m['wallGroupId'] ??
                                          m['foundationWallId'] ??
                                          m['lengthGroupId'] ??
                                          m['beamId'] ??
                                          m['segmentId'] ??
                                          m['rampId'] ??
                                          m['ceilingGroupId'] ??
                                          m['stairId'] ??
                                          m['civilWorkId'] ??
                                          m['roadProfileGroupId'] ??
                                          m['drainageSessionId'] ??
                                          m['roofGroupId'] ??
                                          m['areaGroupId'] ??
                                          m['slabGroupId'] ??
                                          '')
                                      .toString()
                                      .trim();

                              // ✅ show line label as meters (even if doc unit is m2)
                              final label = '${len.toStringAsFixed(3)} m';

                              if (polylineSegments.isNotEmpty) {
                                for (
                                  var index = 0;
                                  index < polylineSegments.length;
                                  index++
                                ) {
                                  final chainSeg = polylineSegments[index];
                                  final chainLen = chainSeg.lengthM ?? len;
                                  final chainHeight = chainSeg.heightM;
                                  segments.add(
                                    MeasuredSegment(
                                      id: '${d.id}-$index',
                                      docId: d.id,
                                      p1: chainSeg.p1,
                                      p2: chainSeg.p2,
                                      color: color,
                                      strokeWidth: segmentStrokeWidth,
                                      label:
                                          chainHeight != null && chainHeight > 0
                                              ? '${chainLen.toStringAsFixed(3)} m · H ${chainHeight.toStringAsFixed(3)} m'
                                              : '${chainLen.toStringAsFixed(3)} m',
                                      measureType: measureType.trim(),
                                      groupId: groupId.isEmpty ? null : groupId,
                                    ),
                                  );
                                }
                                continue;
                              }

                              final straightSeg = seg!;
                              final straightHeight =
                                  (m['heightM'] is num)
                                      ? (m['heightM'] as num).toDouble()
                                      : double.tryParse(
                                        '${m['heightM'] ?? ''}',
                                      );
                              segments.add(
                                MeasuredSegment(
                                  id: d.id,
                                  docId: d.id,
                                  p1: straightSeg.p1,
                                  p2: straightSeg.p2,
                                  color: color,
                                  strokeWidth: segmentStrokeWidth,
                                  label:
                                      measureType.trim().toLowerCase() ==
                                                  'walling' &&
                                              straightHeight != null &&
                                              straightHeight > 0
                                          ? '$label · H ${straightHeight.toStringAsFixed(3)} m'
                                          : label,
                                  measureType:
                                      measureType
                                          .trim(), // "foundationWall" stays
                                  groupId: groupId.isEmpty ? null : groupId,
                                ),
                              );
                              continue;
                            }
                            if (_isAreaLike(measureType, type)) {
                              final points = _readPolygon(m);
                              if (points.length < 3) continue;
                              debugPrint(
                                'keys=${m.keys} type=${m['type']} measureType=${m['measureType']} poly=${m['polygon']}',
                              );

                              // ✅ pick best area number for label
                              final double areaM2 =
                                  (m['areaM2'] is num)
                                      ? (m['areaM2'] as num).toDouble()
                                      : (m['areaM2_total'] is num)
                                      ? (m['areaM2_total'] as num).toDouble()
                                      : (m['polygonNetAreaM2'] is num)
                                      ? (m['polygonNetAreaM2'] as num)
                                          .toDouble()
                                      : (m['polygonAreaM2'] is num)
                                      // ? (m['polygonAreaM2_one'] as num).toDouble()
                                      // : (m['polygonAreaM2_one'] is num)
                                      ? (m['polygonAreaM2'] as num).toDouble()
                                      : (m['value'] is num)
                                      ? (m['value'] as num).toDouble()
                                      : value; // fallback

                              // ✅ group id selection (same idea as your lengthGroupId logic)
                              final groupId =
                                  (m['assemblyId'] ??
                                          m['plinthGroupId'] ??
                                          m['pavementGroupId'] ??
                                          m['finishGroupId'] ??
                                          m['areaGroupId'] ??
                                          m['ceilingGroupId'] ??
                                          m['tileGroupId'] ??
                                          m['slabGroupId'] ??
                                          m['roofGroupId'] ??
                                          m['floorGroupId'] ??
                                          m['footingGroupId'] ??
                                          m['wallGroupId'] ??
                                          m['slabGroupId'] ??
                                          m['foundationGroupId'] ??
                                          m['columnGroupId'] ??
                                          m['columnId'] ??
                                          '')
                                      .toString()
                                      .trim();

                              // ✅ label
                              final normalizedAreaMeasureType =
                                  measureType
                                      .replaceAll(RegExp(r'[_\s-]+'), '')
                                      .toLowerCase();
                              final isLiftShaft =
                                  normalizedAreaMeasureType == 'liftshaft' ||
                                  normalizedAreaMeasureType ==
                                      'liftshaftassembly' ||
                                  type.startsWith('liftshaft');
                              final externalLengthM =
                                  (m['externalLengthM'] is num)
                                      ? (m['externalLengthM'] as num).toDouble()
                                      : double.tryParse(
                                            '${m['externalLengthM']}',
                                          ) ??
                                          0.0;
                              final externalWidthM =
                                  (m['externalWidthM'] is num)
                                      ? (m['externalWidthM'] as num).toDouble()
                                      : double.tryParse(
                                            '${m['externalWidthM']}',
                                          ) ??
                                          0.0;
                              final label =
                                  isLiftShaft
                                      ? externalLengthM > 0 &&
                                              externalWidthM > 0
                                          ? 'Lift shaft · ${externalLengthM.toStringAsFixed(2)} × ${externalWidthM.toStringAsFixed(2)} m'
                                          : 'Lift shaft'
                                      : '${areaM2.toStringAsFixed(3)} m²';

                              // ✅ add polygon to painter list
                              final polygonIndex =
                                  (m['polygonIndex'] is num)
                                      ? (m['polygonIndex'] as num).toInt()
                                      : 0;
                              final polygonCount =
                                  (m['polygonCount'] is num)
                                      ? (m['polygonCount'] as num).toInt()
                                      : 1;
                              final areaId =
                                  groupId.isNotEmpty
                                      ? polygonCount > 1
                                          ? '$groupId-polygon-$polygonIndex'
                                          : groupId
                                      : d.id;

                              if (drawnAreaIds.add(areaId)) {
                                savedAreas.add(
                                  SavedArea(
                                    id: areaId,
                                    docId: d.id,
                                    measureType: measureType,
                                    label:
                                        (m['label'] ?? m['title'] ?? type)
                                            .toString(),
                                    value: areaM2,
                                    unit: (m['unit'] ?? 'm2').toString(),
                                    points: points,
                                    color: color,
                                    // set your flags if needed
                                    // isSlabComposite: type.contains('Slab'),
                                    isCeilingFinish: type
                                        .toLowerCase()
                                        .contains('ceiling'),
                                    isSlabComposite: type
                                        .toLowerCase()
                                        .contains('slab'),
                                    isRoofingComposite: type
                                        .toLowerCase()
                                        .contains('roof'),
                                    isFootingComposite: type
                                        .toLowerCase()
                                        .contains('footing'),
                                    isColumnComposite: type
                                        .toLowerCase()
                                        .contains('column'),

                                    isRebarSlab: false,
                                    isRebarFooting: false,
                                    isRebarColumn: false,
                                  ),
                                );
                              }

                              continue;
                            }

                            final isCeilingFinish =
                                measureType == 'ceilingfinish' ||
                                measureType == 'ceilingfinishings' ||
                                measureType == 'ceiling';

                            if (isCeilingFinish) {
                              final cFId =
                                  (m['areaGroupId'] ?? d.id).toString().trim();
                              debugPrint(
                                'CEILING HIT id=$cFId type=$type measureType=$measureType',
                              );

                              final points = _readPolygon(m);
                              debugPrint(
                                'CEILING POLY points=${points.length}',
                              );

                              if (points.length >= 3) {
                                if (drawnAreaIds.add(cFId)) {
                                  savedAreas.add(
                                    SavedArea(
                                      id: cFId,
                                      docId: d.id,
                                      measureType: measureType,
                                      label:
                                          (m['label'] ?? m['title'] ?? type)
                                              .toString(),
                                      value:
                                          m['value'] is num
                                              ? (m['value'] as num).toDouble()
                                              : null,
                                      unit: (m['unit'] ?? 'm2').toString(),
                                      points: points,
                                      color: color,
                                      isSlabComposite: false,
                                      isCeilingFinish: true,
                                      isRebarSlab: false,
                                      isRebarFooting: false,
                                      isRebarColumn: false,
                                    ),
                                  );

                                  // ✅ force repaint/update
                                  // update(['viewer', 'overlay']);
                                }
                              }
                              continue;
                            }

                            // ---------------- BEAM composite grouping (docs only)
                            if (type.contains('beam')) {
                              final beamId = (m['beamId'] ?? d.id).toString();
                              (beamCompositeDocsByBeamId[beamId] ??= []).add(d);
                              continue;
                            }
                            if (type.contains('stair')) {
                              final stairId =
                                  (m['stairGroupId'] ?? d.id).toString();
                              (stairCompositeDocsByWallId[stairId] ??= []).add(
                                d,
                              );
                              continue;
                            }
                            if (type.contains('ramp')) {
                              final rampId =
                                  (m['rampGroupId'] ?? d.id).toString();
                              (rampCompositeDocsByWallId[rampId] ??= []).add(d);
                              continue;
                            }
                            if (type.contains('civil')) {
                              final cwId =
                                  (m['civilworkId'] ?? d.id).toString();
                              (civilWorkDocsId[cwId] ??= []).add(d);
                              continue;
                            }
                            if (type.contains('beam')) {
                              final beamId = (m['beamId'] ?? d.id).toString();
                              (beamCompositeDocsByBeamId[beamId] ??= []).add(d);
                              continue;
                            }
                            // if (type.contains('Slab')) {
                            //   final slabId = (m['slabGroupId'] ?? d.id).toString();
                            //   (slabCompositeDocsBySlabId[slabId] ??= []).add(d);
                            //   continue;
                            // }

                            // ---------------- retaining wall / foundation wall grouping (docs only)
                            if (type.contains('retainingWall') ||
                                (m['measureType'] ?? '') ==
                                    'compositeRetainingWall') {
                              final rwId =
                                  (m['wallGroupId'] ??
                                          m['retainingWallId'] ??
                                          d.id)
                                      .toString();
                              (retainingWallCompositeDocsByWallId[rwId] ??= [])
                                  .add(d);
                              continue;
                            }
                            if (type.contains('foundationWall') ||
                                (m['measureType'] ?? '') ==
                                    'compositeFoundationWall') {
                              final fwId =
                                  (m['wallGroupId'] ??
                                          m['foundationGroupId'] ??
                                          d.id)
                                      .toString();
                              (foundationWallCompositeDocsByWallId[fwId] ??= [])
                                  .add(d);
                              continue;
                            }
                            if (type.contains('compositeSlab') ||
                                (m['measureType'] ?? '') == 'compositeSlab') {
                              final slabId =
                                  (m['slabGroupId'] ?? d.id).toString();
                              (slabCompositeDocsBySlabId[slabId] ??= []).add(d);
                              continue;
                            }
                            if (type.contains('walling') ||
                                (m['measureType'] ?? '') == 'walling') {
                              final wId =
                                  (m['wallGroupId'] ??
                                          m['foundationWallId'] ??
                                          d.id)
                                      .toString();
                              (wallCDocsByWallId[wId] ??= []).add(d);
                              continue;
                            }
                          }

                          // 2) NOW compute rebarBeamDocsByBeamType (after beamCompositeDocsByBeamId is filled)
                          bool _isRebarType(String t) =>
                              t == 'rebarBeamMain' ||
                              t == 'rebarBeamMainSegment' ||
                              t == 'rebarBeamStirrups';

                          final rebarBeamDocsByBeamType =
                              <
                                String,
                                List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >
                              >{};
                          for (final entry
                              in beamCompositeDocsByBeamId.entries) {
                            for (final d in entry.value) {
                              final m = d.data();
                              final t = (m['type'] ?? '').toString().trim();
                              if (!_isRebarType(t)) continue;

                              final bt =
                                  (m['beamType'] ?? '').toString().trim();
                              if (bt.isEmpty) continue;

                              (rebarBeamDocsByBeamType[bt] ??= []).add(d);
                            }
                          }
                          mi.lastSegments = segments;

                          // ---------------- VIEWER: IMPORTANT coordinate fix ----------------
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              GetBuilder<MeasuringItemController>(
                                id: 'viewer',
                                builder: (c) {
                                  final isEdit =
                                      c.mode.value == TakeoffMode.editSegment;
                                  final isPanMode =
                                      c.mode.value == TakeoffMode.view;
                                  final canDragDraftLength =
                                      c.mode.value ==
                                          TakeoffMode.measureLength &&
                                      c.hasDraftLength;

                                  final storedW =
                                      c.usesInlineImage
                                          ? 0.0
                                          : (drawingData['imageW'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                  final storedH =
                                      c.usesInlineImage
                                          ? 0.0
                                          : (drawingData['imageH'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                  final loadedW =
                                      c.uiImg?.width.toDouble() ??
                                      c.baseW ??
                                      0.0;
                                  final loadedH =
                                      c.uiImg?.height.toDouble() ??
                                      c.baseH ??
                                      0.0;

                                  c.baseW = storedW > 0 ? storedW : loadedW;
                                  c.baseH = storedH > 0 ? storedH : loadedH;

                                  if (!c.usesInlineImage &&
                                      (storedW <= 0 || storedH <= 0) &&
                                      c.baseW! > 0 &&
                                      c.baseH! > 0) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          final drawingRef = FirebaseFirestore
                                              .instance
                                              .collection('projects')
                                              .doc(c.projectId)
                                              .collection('buildings')
                                              .doc(c.buildingId)
                                              .collection('drawings')
                                              .doc(c.drawingId);

                                          c.ensureImageSizeOnDrawingDoc(
                                            drawingRef: drawingRef,
                                            drawingData: drawingData,
                                            fallbackImageUrl: c.imageUrl,
                                          );
                                        });
                                  }

                                  if (!c.usesInlineImage &&
                                      (c.baseW! <= 0 || c.baseH! <= 0)) {
                                    // ✅ Kick off Fix B once (post-frame so it won't run during build)
                                    WidgetsBinding.instance.addPostFrameCallback((
                                      _,
                                    ) {
                                      // Build your drawingRef exactly like you do elsewhere:
                                      final drawingRef = FirebaseFirestore
                                          .instance
                                          .collection('projects')
                                          .doc(c.projectId)
                                          .collection('buildings')
                                          .doc(c.buildingId)
                                          .collection('drawings')
                                          .doc(c.drawingId);

                                      c.ensureImageSizeOnDrawingDoc(
                                        drawingRef: drawingRef,
                                        drawingData: drawingData,
                                        fallbackImageUrl:
                                            c.imageUrl, // if you already have it from args
                                      );
                                    });

                                    if (c.ensuringImageSize) {
                                      return const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                            SizedBox(height: 10),
                                            Text('Loading image size…'),
                                          ],
                                        ),
                                      );
                                    }
                                    return Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Missing imageW/imageH on drawingData',
                                          ),
                                          const SizedBox(height: 8),
                                          FilledButton(
                                            onPressed: () {
                                              final drawingRef =
                                                  FirebaseFirestore.instance
                                                      .collection('projects')
                                                      .doc(c.projectId)
                                                      .collection('buildings')
                                                      .doc(c.buildingId)
                                                      .collection('drawings')
                                                      .doc(c.drawingId);

                                              c.ensureImageSizeOnDrawingDoc(
                                                drawingRef: drawingRef,
                                                drawingData: drawingData,
                                                fallbackImageUrl: c.imageUrl,
                                              );
                                            },
                                            child: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  // Paint slab-rebar items that are still only in the
                                  // temporary session. This gives immediate visual feedback
                                  // after "Save temporary & measure another".
                                  for (final draft
                                      in it.pendingFastSlabRebarSegments) {
                                    Map<String, dynamic> asMap(dynamic value) {
                                      if (value is Map<String, dynamic>)
                                        return value;
                                      if (value is Map)
                                        return Map<String, dynamic>.from(value);
                                      return <String, dynamic>{};
                                    }

                                    Offset point(dynamic value) {
                                      final map = asMap(value);
                                      return Offset(
                                        (map['x'] as num? ?? 0).toDouble(),
                                        (map['y'] as num? ?? 0).toDouble(),
                                      );
                                    }

                                    final p1 = point(draft['p1']);
                                    final p2 = point(draft['p2']);
                                    final length =
                                        (draft['lengthM'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                    final mark =
                                        (draft['mark'] ?? '').toString();
                                    final dia =
                                        (draft['diameterMm'] as num?)
                                            ?.toInt() ??
                                        0;
                                    final layer =
                                        (draft['layer'] ?? '').toString();
                                    final direction =
                                        (draft['direction'] ?? '').toString();
                                    segments.add(
                                      MeasuredSegment(
                                        id:
                                            (draft['draftId'] ??
                                                    'slab-rebar-temp-${segments.length}')
                                                .toString(),
                                        docId:
                                            (draft['draftId'] ??
                                                    'slab-rebar-temp')
                                                .toString(),
                                        p1: p1,
                                        p2: p2,
                                        color: Color(
                                          (draft['color'] as num?)?.toInt() ??
                                              Colors.blue.value,
                                        ),
                                        strokeWidth: 4.0,
                                        label:
                                            mark.isEmpty
                                                ? '${length.toStringAsFixed(3)} m'
                                                : '$mark Y$dia $layer/$direction  ${length.toStringAsFixed(3)} m',
                                        measureType: 'slabRebarAiTemp',
                                        groupId: 'slab-rebar-temp-session',
                                      ),
                                    );
                                  }

                                  // Add the current unsaved timber-truss members to
                                  // the canvas. They look like normal saved lines but
                                  // remain purely in memory until Save truss is pressed.
                                  for (final draft
                                      in mi.pendingTimberTrussMembers) {
                                    Map<String, dynamic> asMap(dynamic value) {
                                      if (value is Map<String, dynamic>)
                                        return value;
                                      if (value is Map) {
                                        return Map<String, dynamic>.from(value);
                                      }
                                      return <String, dynamic>{};
                                    }

                                    Offset point(dynamic value) {
                                      final map = asMap(value);
                                      return Offset(
                                        (map['x'] as num? ?? 0).toDouble(),
                                        (map['y'] as num? ?? 0).toDouble(),
                                      );
                                    }

                                    final draftId =
                                        (draft['draftId'] ??
                                                'draft-${segments.length}')
                                            .toString();
                                    final draftColor = Color(
                                      (draft['color'] as num?)?.toInt() ??
                                          Colors.blue.value,
                                    );
                                    final groupId =
                                        (draft['trussId'] ??
                                                draft['roofGroupId'] ??
                                                '')
                                            .toString();
                                    final rawPolyline =
                                        draft['polylineSegments'];
                                    if (rawPolyline is List &&
                                        rawPolyline.isNotEmpty) {
                                      for (
                                        var i = 0;
                                        i < rawPolyline.length;
                                        i++
                                      ) {
                                        final item = asMap(rawPolyline[i]);
                                        final p1 = point(item['p1']);
                                        final p2 = point(item['p2']);
                                        final length =
                                            (item['lengthM'] as num?)
                                                ?.toDouble() ??
                                            (draft['measuredLengthM'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                        segments.add(
                                          MeasuredSegment(
                                            id: '$draftId-$i',
                                            docId: draftId,
                                            p1: p1,
                                            p2: p2,
                                            color: draftColor,
                                            label:
                                                '${length.toStringAsFixed(3)} m',
                                            measureType: 'compositeRoofing',
                                            groupId:
                                                groupId.isEmpty
                                                    ? null
                                                    : groupId,
                                          ),
                                        );
                                      }
                                    } else {
                                      final seg = asMap(draft['segment']);
                                      final p1 = point(
                                        seg.isNotEmpty
                                            ? seg['p1']
                                            : draft['p1'],
                                      );
                                      final p2 = point(
                                        seg.isNotEmpty
                                            ? seg['p2']
                                            : draft['p2'],
                                      );
                                      final length =
                                          (draft['measuredLengthM'] as num?)
                                              ?.toDouble() ??
                                          (draft['lengthM'] as num?)
                                              ?.toDouble() ??
                                          0.0;
                                      segments.add(
                                        MeasuredSegment(
                                          id: draftId,
                                          docId: draftId,
                                          p1: p1,
                                          p2: p2,
                                          color: draftColor,
                                          label:
                                              '${length.toStringAsFixed(3)} m',
                                          measureType: 'compositeRoofing',
                                          groupId:
                                              groupId.isEmpty ? null : groupId,
                                        ),
                                      );
                                    }
                                  }

                                  return GetBuilder<ImageTakeoffController>(
                                    id: 'viewr',
                                    builder: (context) {
                                      if (c.imageLoadError != null) {
                                        return Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.broken_image_outlined,
                                                color: Colors.red,
                                                size: 36,
                                              ),
                                              const SizedBox(height: 10),
                                              const Text(
                                                'Drawing image could not be loaded',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                c.imageLoadError.toString(),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Color(0xFF667085),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      final canUseInlineImage =
                                          c.usesInlineImage &&
                                          (c.baseW ?? 0) > 0 &&
                                          (c.baseH ?? 0) > 0;
                                      if (!canUseInlineImage &&
                                          (c.uiImg == null ||
                                              c.baseW == null ||
                                              c.baseH == null)) {
                                        return _drawingLoadFallback(c);
                                      }
                                      final polyCtrl = c.pctr;
                                      return LayoutBuilder(
                                        builder: (ctx, constraints) {
                                          final viewport = Size(
                                            constraints.maxWidth,
                                            constraints.maxHeight,
                                          );
                                          c.setViewportSize(viewport);
                                          WidgetsBinding.instance.addPostFrameCallback((
                                            _,
                                          ) {
                                            c.resetZoomForDrawing(
                                              drawingId: c.drawingId,
                                              baseW: c.baseW!,
                                              baseH: c.baseH!,
                                              viewport: viewport,
                                              centerInViewport: isCompact,
                                              viewportPadding:
                                                  isCompact
                                                      ? const EdgeInsets.fromLTRB(
                                                        12,
                                                        12,
                                                        12,
                                                        72,
                                                      )
                                                      : const EdgeInsets.fromLTRB(
                                                        146,
                                                        28,
                                                        28,
                                                        28,
                                                      ),
                                            );
                                          });

                                          return MouseRegion(
                                            cursor: _cursorForMode(
                                              c.mode.value,
                                            ),
                                            child: InteractiveViewer(
                                              transformationController:
                                                  c.transformController,
                                              minScale:
                                                  MeasuringItemController
                                                      .viewerMinScale,
                                              maxScale:
                                                  MeasuringItemController
                                                      .viewerMaxScale,
                                              scaleFactor: 900,
                                              constrained: false,
                                              boundaryMargin:
                                                  const EdgeInsets.all(100000),
                                              clipBehavior: Clip.none,
                                              panEnabled: !isEdit,
                                              scaleEnabled: true,
                                              alignment: Alignment.topLeft,
                                              child: AnimatedBuilder(
                                                animation:
                                                    c.transformController,
                                                builder: (_, __) {
                                                  final zoomScale =
                                                      c
                                                          .transformController
                                                          .value
                                                          .getMaxScaleOnAxis();
                                                  return SizedBox(
                                                    width:
                                                        c.baseW!, // ✅ image pixel width
                                                    height:
                                                        c.baseH!, // ✅ image pixel height
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        _drawingImageLayer(c),
                                                        Positioned.fill(
                                                          child: PolylineDrawOverlay(
                                                            c: polyCtrl,
                                                            toWorld:
                                                                (
                                                                  local,
                                                                ) => mi.toWorld(
                                                                  local: local,
                                                                  tCtrl:
                                                                      c.transformController,
                                                                ),
                                                            toScreen:
                                                                (
                                                                  world,
                                                                ) => mi.toScreen(
                                                                  world: world,
                                                                  tCtrl:
                                                                      c.transformController,
                                                                ), // world->screen
                                                            color:
                                                                it.currentColor,
                                                          ),
                                                        ),

                                                        // Tap handling layer (for calibrate / measure / delete)
                                                        GestureDetector(
                                                          behavior:
                                                              HitTestBehavior
                                                                  .translucent,
                                                          onTapUp:
                                                              isPanMode
                                                                  ? null
                                                                  : (
                                                                    details,
                                                                  ) async {
                                                                    final pos =
                                                                        details
                                                                            .localPosition;

                                                                    if (isEdit) {
                                                                      final selectedLine =
                                                                          c.selectSegmentAt(
                                                                            pos,
                                                                            segments,
                                                                          );
                                                                      if (selectedLine) {
                                                                        await c
                                                                            .showSelectedLineMeasurementDialog();
                                                                        return;
                                                                      }
                                                                      final selectedArea =
                                                                          c.selectAreaAt(
                                                                            pos,
                                                                            savedAreas,
                                                                          );
                                                                      if (selectedArea !=
                                                                          null) {
                                                                        await c.showSavedAreaDialog(
                                                                          selectedArea,
                                                                        );
                                                                        return;
                                                                      }
                                                                      final editedColumn = await it.handleColumnViewTap(
                                                                        pos,
                                                                        savedAreas,
                                                                        columnCompositeDocsByColumnId,
                                                                        c.measurementsRef,
                                                                        projectId:
                                                                            c.projectId,
                                                                        buildingId:
                                                                            c.buildingId,
                                                                        drawingId:
                                                                            c.drawingId,
                                                                        activeLabel:
                                                                            c.activeLabel,
                                                                      );
                                                                      if (editedColumn) {
                                                                        c.update([
                                                                          'viewer',
                                                                          'summary',
                                                                        ]);
                                                                        return;
                                                                      }
                                                                      return;
                                                                    }

                                                                    await c.onImageTap(
                                                                      ctx,
                                                                      pos, // ✅ now pos == image coords
                                                                      drawingData,
                                                                      segments,
                                                                      savedAreas,
                                                                      slabCompositeDocsBySlabId:
                                                                          slabCompositeDocsBySlabId,
                                                                      footingCompositeDocsByGroupId:
                                                                          footingCompositeDocsByGroupId,
                                                                      rebarSlabDocsBySlabId:
                                                                          const {},
                                                                      rebarFootingDocsByGroupId:
                                                                          const {},
                                                                      beamCompositeDocsByBeamId:
                                                                          beamCompositeDocsByBeamId,
                                                                      rebarDocsByBeamType:
                                                                          rebarBeamDocsByBeamType,
                                                                      rebarColumnDocsByGroupId:
                                                                          const {},
                                                                      columnDocsByColumnId:
                                                                          columnCompositeDocsByColumnId,
                                                                      retainingWallCompositeDocsByWallId:
                                                                          retainingWallCompositeDocsByWallId,
                                                                      foundationWallCompositeDocsByWallId:
                                                                          foundationWallCompositeDocsByWallId,
                                                                      wallCDocsByWallId:
                                                                          wallCDocsByWallId,
                                                                      roofingCompositeDocsBySlabId:
                                                                          roofingCompositeDocsBySlabId,
                                                                      ceilingFinishId:
                                                                          ceilingFinishId,
                                                                    );
                                                                  },
                                                          onSecondaryTapDown: (
                                                            details,
                                                          ) {
                                                            _showLengthDraftMenu(
                                                              context:
                                                                  this.context,
                                                              controller: c,
                                                              drawingData:
                                                                  drawingData,
                                                              globalPosition:
                                                                  details
                                                                      .globalPosition,
                                                            );
                                                          },
                                                          onLongPressStart: (
                                                            details,
                                                          ) {
                                                            _showLengthDraftMenu(
                                                              context:
                                                                  this.context,
                                                              controller: c,
                                                              drawingData:
                                                                  drawingData,
                                                              globalPosition:
                                                                  details
                                                                      .globalPosition,
                                                            );
                                                          },
                                                          onPanStart: null,
                                                          onPanUpdate:
                                                              canDragDraftLength
                                                                  ? (d) {
                                                                    final p = c
                                                                        .transformController
                                                                        .toScene(
                                                                          d.localPosition,
                                                                        );
                                                                    c.updateDraftLength(
                                                                      p,
                                                                    );
                                                                  }
                                                                  : null,
                                                          onPanEnd: null,
                                                          onPanCancel: null,
                                                        ),
                                                        // Calibration preview (red)
                                                        IgnorePointer(
                                                          ignoring: true,
                                                          child: CustomPaint(
                                                            painter: PointsPainter(
                                                              p1: it.calibP1,
                                                              p2: it.calibP2,
                                                              color:
                                                                  const Color(
                                                                    0xFFE11D48,
                                                                  ),
                                                              zoomScale:
                                                                  zoomScale,
                                                            ),
                                                          ),
                                                        ),

                                                        // Keep completed pavement
                                                        // zones visible while another
                                                        // disconnected zone is being
                                                        // traced. These disappear only
                                                        // when the session is saved or
                                                        // cancelled.
                                                        for (final polygon
                                                            in mi
                                                                .pendingPavementPolygons)
                                                          IgnorePointer(
                                                            child: CustomPaint(
                                                              painter: SavedAreasPainter(
                                                                areas: const [],
                                                                draftPoints:
                                                                    polygon,
                                                                zoomScale:
                                                                    zoomScale,
                                                                showDraftClosure:
                                                                    true,
                                                                showFirstPointOnly:
                                                                    false,
                                                                showAllVertexDots:
                                                                    false,
                                                                strokeWidth:
                                                                    2.5,
                                                                draftColor:
                                                                    mi.currentColor,
                                                                draftOpacityFill:
                                                                    0.18,
                                                                constantOnScreen:
                                                                    true,
                                                              ),
                                                            ),
                                                          ),
                                                        for (final polygon
                                                            in mi
                                                                .pendingPavementDeductionPolygons)
                                                          IgnorePointer(
                                                            child: CustomPaint(
                                                              painter: SavedAreasPainter(
                                                                areas: const [],
                                                                draftPoints:
                                                                    polygon,
                                                                zoomScale:
                                                                    zoomScale,
                                                                showDraftClosure:
                                                                    true,
                                                                showFirstPointOnly:
                                                                    false,
                                                                showAllVertexDots:
                                                                    false,
                                                                strokeWidth:
                                                                    2.5,
                                                                draftColor:
                                                                    const Color(
                                                                      0xFFE5484D,
                                                                    ),
                                                                draftOpacityFill:
                                                                    0.16,
                                                                constantOnScreen:
                                                                    true,
                                                              ),
                                                            ),
                                                          ),

                                                        // Saved segments + current temp line
                                                        IgnorePointer(
                                                          child: CustomPaint(
                                                            painter: SavedAreasPainter(
                                                              areas: savedAreas,
                                                              draftPoints:
                                                                  mi.areaPoints, // ✅ your current draft list
                                                              zoomScale:
                                                                  zoomScale, // ✅ from transformController
                                                              selectedAreaId:
                                                                  c.selectedAreaId,
                                                              showDraftClosure:
                                                                  true,
                                                              showFirstPointOnly:
                                                                  true,
                                                              showAllVertexDots:
                                                                  false,
                                                              constantOnScreen:
                                                                  true,
                                                            ),
                                                          ),
                                                        ),
                                                        // Keep the captured bar-mark
                                                        // region visible until its
                                                        // measured group is saved.
                                                        // This is intentionally a
                                                        // separate painter so normal
                                                        // area drafts are unaffected.
                                                        IgnorePointer(
                                                          child: CustomPaint(
                                                            painter: SavedAreasPainter(
                                                              areas: const [],
                                                              draftPoints:
                                                                  it.pendingSlabRebarMarkPolygon,
                                                              zoomScale:
                                                                  zoomScale,
                                                              showDraftClosure:
                                                                  true,
                                                              showFirstPointOnly:
                                                                  false,
                                                              showAllVertexDots:
                                                                  false,
                                                              strokeWidth: 3,
                                                              draftColor:
                                                                  const Color(
                                                                    0xFFFF8A00,
                                                                  ),
                                                              draftOpacityFill:
                                                                  0.16,
                                                              constantOnScreen:
                                                                  true,
                                                            ),
                                                          ),
                                                        ),
                                                        // IgnorePointer(
                                                        //   child: CustomPaint(
                                                        //     painter: SavedAreasPainter(
                                                        //       areas: savedAreas,
                                                        //       showFirstPointOnly: true,
                                                        //       firstPointRadius: 4,
                                                        //       strokeWidth: 2,
                                                        //     ),
                                                        //   ),
                                                        // ),
                                                        // Saved segments + current temp line
                                                        Positioned.fill(
                                                          child: IgnorePointer(
                                                            child: CustomPaint(
                                                              painter: SegmentsPainter(
                                                                segments:
                                                                    segments,
                                                                tempP1:
                                                                    c.draftLenP1,
                                                                tempP2:
                                                                    c.draftLenP2,
                                                                draftPoints:
                                                                    c.draftLengthPoints,
                                                                draftSegmentPairs: <
                                                                  List<Offset>
                                                                >[
                                                                  ...mi
                                                                      .pendingKerbSegmentPairs,
                                                                  ...mi
                                                                      .pendingDrainSegmentPairs,
                                                                  ...mi
                                                                      .draftIndependentSegmentPairs,
                                                                ],
                                                                tempColor:
                                                                    c.currentColor,
                                                                selectedSegmentId:
                                                                    c.selectedSegmentId,
                                                                editP1:
                                                                    c.editP1,
                                                                editP2:
                                                                    c.editP2,
                                                                zoomScale:
                                                                    zoomScale,
                                                                strokeMode:
                                                                    mi.strokeMode,
                                                                baseStroke:
                                                                    mi.baseStroke,
                                                                dotMode:
                                                                    DotMode.all,
                                                                dotRadius:
                                                                    mi.dotRadius,
                                                                dotColor:
                                                                    mi.dotColor,
                                                                dotScaleMode:
                                                                    mi.dotScaleMode,
                                                                dotsFollowSegmentColor:
                                                                    mi.dotsFollowSegmentColor,
                                                                // dotsFollowSegmentColor: true,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned.fill(
                                                          child: IgnorePointer(
                                                            child: CustomPaint(
                                                              painter: CountMarkerPainter(
                                                                markers: [
                                                                  ...countMarkers,
                                                                  ...it
                                                                      .pendingFastSlabRebarBundleMarkers,
                                                                ],
                                                                draftPoints:
                                                                    c.draftCountPoints,
                                                                zoomScale:
                                                                    zoomScale,
                                                                color:
                                                                    c.currentColor,
                                                                draftLabelPrefix:
                                                                    c.draftCountLabelPrefix,
                                                              ),
                                                            ),
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
                                    },
                                  );
                                },
                              ),

                              if (!isCompact)
                                GetBuilder<MeasuringItemController>(
                                  id: 'topbar',
                                  builder: (mi) {
                                    return Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: MeasuringToolsPalette(
                                        activeMeasureType: mi.activeMeasureType,
                                        activeLabel: mi.activeLabel,
                                        mode: mi.mode.value,
                                        currentColor: mi.currentColor,
                                        strokeWidth: mi.baseStroke,
                                        onSelected: (tool) async {
                                          await mi.selectMeasurementTool(
                                            measureType: tool.measureType,
                                            label: tool.label,
                                            unit: tool.unit,
                                          );
                                        },
                                        onConfigure: () {
                                          mi.configureActiveMeasurementTool();
                                        },
                                        onPan:
                                            () => mi.setMode(TakeoffMode.view),
                                        onCalibrate:
                                            () => mi.setMode(
                                              TakeoffMode.calibrate,
                                            ),
                                        onEdit:
                                            () => mi.setMode(
                                              TakeoffMode.editSegment,
                                            ),
                                        onUndo: () {
                                          mi.undoLast();
                                        },
                                        onRedo: () {
                                          mi.redoLast();
                                        },
                                        onRefresh: () {
                                          mi.refreshWorkspace();
                                        },
                                        onColor: () {
                                          mi.chooseMeasurementColor();
                                        },
                                        onThickness:
                                            () => _showStrokeSliderDialog(mi),
                                        onZoomIn: mi.zoomIn,
                                        onZoomOut: mi.zoomOut,
                                      ),
                                    );
                                  },
                                ),

                              GetBuilder<MeasuringItemController>(
                                id: 'topbar',
                                builder: (mi) {
                                  return Positioned(
                                    top: isCompact ? 8 : 14,
                                    left: isCompact ? 12 : 0,
                                    right: isCompact ? 12 : 0,
                                    child: Center(
                                      child: _TakeoffTopControls(
                                        compact: isCompact,
                                        mode: mi.mode.value,
                                        currentColor: mi.currentColor,
                                        strokeWidth: mi.baseStroke,
                                        activeLabel: mi.activeLabel,
                                        activeMeasureType: mi.activeMeasureType,
                                        onPan:
                                            () => mi.setMode(TakeoffMode.view),
                                        onCalibrate:
                                            () => mi.setMode(
                                              TakeoffMode.calibrate,
                                            ),
                                        onEdit:
                                            () => mi.setMode(
                                              TakeoffMode.editSegment,
                                            ),
                                        onUndo: mi.undoLast,
                                        onRedo: mi.redoLast,
                                        onRefresh: mi.refreshWorkspace,
                                        onColor: mi.chooseMeasurementColor,
                                        onThickness:
                                            () => _showStrokeSliderDialog(mi),
                                        onMarkings:
                                            () =>
                                                _showMeasurementVisibilitySheet(
                                                  context,
                                                  mi,
                                                ),
                                        onRoofSheet:
                                            () =>
                                                showRoofStructureMeasurementSheet(
                                                  context: context,
                                                  projectId: it.projectId,
                                                  buildingId: it.buildingId,
                                                  drawingId: it.drawingId,
                                                  drawingTitle: it.drawingTitle,
                                                  measurementsRef:
                                                      mi.measurementsRef,
                                                ),
                                        onMore:
                                            () => _showMobileCanvasActions(
                                              context,
                                              mi,
                                              it,
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              GetBuilder<MeasuringItemController>(
                                id: 'viewer',
                                builder: (mi) {
                                  return Positioned(
                                    right: isCompact ? 12 : 18,
                                    bottom: isCompact ? mobileBottomInset : 18,
                                    child: _CanvasZoomControls(
                                      compact: isCompact,
                                      onZoomOut: mi.zoomOut,
                                      onZoomIn: mi.zoomIn,
                                      onRefresh: mi.refreshWorkspace,
                                    ),
                                  );
                                },
                              ),

                              GetBuilder<MeasuringItemController>(
                                id: 'viewer',
                                builder: (mi) {
                                  if (!mi.hasCountDraft) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    left: isCompact ? 12 : 172,
                                    right: isCompact ? 76 : null,
                                    bottom:
                                        isCompact ? mobileBottomInset + 64 : 18,
                                    child: _CountDraftActions(
                                      compact: isCompact,
                                      count: mi.draftCountTotal,
                                      onUndoPoint: mi.undoDraftCountPoint,
                                      onCancel: mi.clearDraftCount,
                                      onFinish: mi.finishCountMeasurement,
                                    ),
                                  );
                                },
                              ),

                              if (isCompact)
                                GetBuilder<MeasuringItemController>(
                                  id: 'topbar',
                                  builder:
                                      (mi) => Positioned(
                                        left: 12,
                                        bottom: mobileBottomInset,
                                        child: Row(
                                          children: [
                                            _MobileCanvasButton(
                                              label: 'Tools',
                                              icon: Icons.architecture_rounded,
                                              onTap:
                                                  () => _showMobileTools(
                                                    context,
                                                    mi,
                                                  ),
                                            ),
                                            const SizedBox(width: 8),
                                            _MobileCanvasButton(
                                              label: 'Summary',
                                              icon: Icons.summarize_outlined,
                                              onTap:
                                                  () => _showMobileSummary(
                                                    context,
                                                    mi,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                )
                              else
                                GetBuilder<MeasuringItemController>(
                                  id: 'summary',
                                  builder: (mi) {
                                    return ActiveItemSummaryPanel(
                                      drawingId: mi.drawingId,
                                      measurementsRef: mi.measurementsRef,
                                      activeMeasureType: mi.activeMeasureType,
                                      activeLabel: mi.activeLabel,
                                      activeBoqCode: mi.activeBoqCode,
                                      activeUnit: mi.activeUnit,
                                      pendingTimberMemberCount:
                                          mi.pendingTimberTrussMemberCount,
                                      savingTimberTruss:
                                          mi.savingPendingTimberTruss,
                                      onSaveTimberTruss:
                                          () => mi.savePendingTimberTruss(),
                                      onDiscardTimberTruss:
                                          mi.discardPendingTimberTruss,
                                    );
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStrokeSliderDialog(MeasuringItemController mi) async {
    double temp = mi.baseStroke;
    StrokeMode tempMode = mi.strokeMode;

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Stroke thickness'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // mode
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<StrokeMode>(
                          dense: true,
                          title: const Text('Constant on screen'),
                          value: StrokeMode.constantOnScreen,
                          groupValue: tempMode,
                          onChanged: (v) => setState(() => tempMode = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<StrokeMode>(
                          dense: true,
                          title: const Text('Adaptive'),
                          value: StrokeMode.adaptive,
                          groupValue: tempMode,
                          onChanged: (v) => setState(() => tempMode = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Normal thickness: ${temp.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    min: 0.5,
                    max: 10.0,
                    divisions: 95, // step 0.1
                    value: temp.clamp(0.5, 10.0),
                    label: temp.toStringAsFixed(1),
                    onChanged: (v) => setState(() => temp = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  mi.setStrokeMode(tempMode);
                  mi.resetStrokeNormal(); // ✅ back to 2.0
                  Get.back();
                },
                child: const Text('Reset (Normal)'),
              ),
              FilledButton(
                onPressed: () {
                  mi.setStrokeMode(tempMode);
                  mi.setBaseStroke(temp);
                  Get.back();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );
  }

  Future<void> _showDotSettingsDialog(MeasuringItemController mi) async {
    double tempRadius = mi.dotRadius;
    DotMode tempMode = mi.dotMode;
    bool tempFollow = mi.dotsFollowSegmentColor;
    Color tempColor = mi.dotColor;
    DotScaleMode tempScale = mi.dotScaleMode;

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Dot settings'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // dot mode
                    DropdownButtonFormField<DotMode>(
                      value: tempMode,
                      decoration: const InputDecoration(
                        labelText: 'Dot mode',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DotMode.none,
                          child: Text('None (no dots)'),
                        ),
                        DropdownMenuItem(
                          value: DotMode.all,
                          child: Text('All endpoints'),
                        ),
                        DropdownMenuItem(
                          value: DotMode.chainEndpointsOnly,
                          child: Text('Chain endpoints only'),
                        ),
                      ],
                      onChanged:
                          (v) => setState(() => tempMode = v ?? tempMode),
                    ),
                    DropdownButtonFormField<DotScaleMode>(
                      value: tempScale,
                      decoration: const InputDecoration(
                        labelText: 'Dot scale',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DotScaleMode.constantOnScreen,
                          child: Text('Constant on screen'),
                        ),
                        DropdownMenuItem(
                          value: DotScaleMode.constantOnCanvas,
                          child: Text('Constant on canvas'),
                        ),
                      ],
                      onChanged:
                          (v) => setState(() => tempScale = v ?? tempScale),
                    ),

                    const SizedBox(height: 12),

                    // follow segment color
                    SwitchListTile(
                      title: const Text('Dots follow segment color'),
                      dense: true,
                      value: tempFollow,
                      onChanged: (v) => setState(() => tempFollow = v),
                    ),

                    const SizedBox(height: 8),

                    // color picker only if not following segment
                    if (!tempFollow)
                      _DotColorPicker(
                        selected: tempColor,
                        onPick: (c) => setState(() => tempColor = c),
                      ),

                    const SizedBox(height: 14),

                    Text(
                      'Dot size: ${tempRadius.toStringAsFixed(1)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      min: 0.5,
                      max: 10.0,
                      divisions: 95,
                      value: tempRadius.clamp(0.5, 10.0),
                      label: tempRadius.toStringAsFixed(1),
                      onChanged: (v) => setState(() => tempRadius = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  mi.resetDotsNormal();
                  Get.back();
                },
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () {
                  mi.setDotMode(tempMode);
                  mi.setDotsFollowSegment(tempFollow);
                  mi.setDotRadius(tempRadius);
                  mi.setDotScaleMode(tempScale);
                  mi.setDotRadius(tempRadius);
                  if (!tempFollow) {
                    mi.setDotColor(tempColor);
                  }
                  Get.back();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );
  }
}

class _ColorItem extends StatelessWidget {
  const _ColorItem({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 16),
        const SizedBox(width: 8),
        Text(name),
      ],
    );
  }
}

class _DotColorPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onPick;

  const _DotColorPicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    const options = <Color>[
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Dot color',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              options.map((c) {
                final isSel = c.value == selected.value;
                return InkWell(
                  onTap: () => onPick(c),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSel ? Colors.black : Colors.black26,
                        width: isSel ? 2.5 : 1,
                      ),
                    ),
                    child:
                        isSel
                            ? Icon(
                              Icons.check,
                              size: 18,
                              color:
                                  c == Colors.white
                                      ? Colors.black
                                      : Colors.white,
                            )
                            : null,
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _TakeoffTopControls extends StatelessWidget {
  const _TakeoffTopControls({
    this.compact = false,
    required this.mode,
    required this.currentColor,
    required this.strokeWidth,
    required this.activeLabel,
    required this.activeMeasureType,
    required this.onPan,
    required this.onCalibrate,
    required this.onEdit,
    required this.onUndo,
    required this.onRedo,
    required this.onRefresh,
    required this.onColor,
    required this.onThickness,
    required this.onMarkings,
    required this.onRoofSheet,
    this.onMore,
  });

  final bool compact;
  final TakeoffMode mode;
  final Color currentColor;
  final double strokeWidth;
  final String? activeLabel;
  final String? activeMeasureType;
  final VoidCallback onPan;
  final VoidCallback onCalibrate;
  final VoidCallback onEdit;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onRefresh;
  final VoidCallback onColor;
  final VoidCallback onThickness;
  final VoidCallback onMarkings;
  final VoidCallback onRoofSheet;
  final VoidCallback? onMore;

  String get _activeToolLabel {
    final label = (activeLabel ?? '').trim();
    if (label.isNotEmpty) return label;
    final type = (activeMeasureType ?? '').trim();
    return type.isEmpty ? 'No tool selected' : type;
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Material(
        elevation: 10,
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Pan',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                style: IconButton.styleFrom(
                  backgroundColor:
                      mode == TakeoffMode.view
                          ? const Color(0xFFEFF4FF)
                          : Colors.transparent,
                  foregroundColor:
                      mode == TakeoffMode.view
                          ? const Color(0xFF155EEF)
                          : const Color(0xFF344054),
                ),
                onPressed: onPan,
                icon: const Icon(Icons.pan_tool_outlined),
              ),
              IconButton(
                tooltip: 'Undo',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onUndo,
                icon: const Icon(Icons.undo_rounded),
              ),
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _activeToolLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'More canvas actions',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      elevation: 10,
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopDockButton(
                label: 'Pan',
                icon: Icons.pan_tool_outlined,
                selected: mode == TakeoffMode.view,
                onTap: onPan,
              ),
              _TopDockButton(
                label: 'Calibrate',
                icon: Icons.square_foot,
                selected: mode == TakeoffMode.calibrate,
                onTap: onCalibrate,
              ),
              _TopDockButton(
                label: 'Select',
                icon: Icons.ads_click_rounded,
                selected: mode == TakeoffMode.editSegment,
                onTap: onEdit,
              ),
              _DockDivider(),
              _TopDockButton(label: 'Undo', icon: Icons.undo, onTap: onUndo),
              _TopDockButton(label: 'Redo', icon: Icons.redo, onTap: onRedo),
              _TopDockButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: onRefresh,
              ),
              _TopDockButton(
                label: 'Markings',
                icon: Icons.layers_outlined,
                onTap: onMarkings,
              ),
              _DockDivider(),
              Tooltip(
                message: 'Color',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onColor,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: currentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
                ),
              ),
              _TopDockButton(
                label: 'Line ${strokeWidth.toStringAsFixed(1)}',
                icon: Icons.line_weight,
                onTap: onThickness,
              ),
              _DockDivider(),
              Container(
                constraints: const BoxConstraints(maxWidth: 190),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: currentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _activeToolLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasZoomControls extends StatelessWidget {
  const _CanvasZoomControls({
    this.compact = false,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
  });

  final bool compact;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom out',
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton(
              tooltip: 'Fit / refresh view',
              onPressed: onRefresh,
              icon: const Icon(Icons.center_focus_strong_rounded),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: onZoomIn,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountDraftActions extends StatelessWidget {
  const _CountDraftActions({
    this.compact = false,
    required this.count,
    required this.onUndoPoint,
    required this.onCancel,
    required this.onFinish,
  });

  final bool compact;
  final int count;
  final bool Function() onUndoPoint;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Material(
        elevation: 10,
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '$count marked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Undo last count',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => onUndoPoint(),
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton(
                tooltip: 'Cancel count',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              ),
              IconButton.filled(
                tooltip: 'Finish and save',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onFinish,
                icon: const Icon(Icons.check_rounded),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      elevation: 10,
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD0D5DD)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF101828).withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.fact_check_outlined,
                color: Color(0xFF155EEF),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Continuous count',
                  style: TextStyle(
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count objects marked',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            IconButton(
              tooltip: 'Undo last count',
              onPressed: () => onUndoPoint(),
              icon: const Icon(Icons.undo_rounded),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Finish & save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileCanvasButton extends StatelessWidget {
  const _MobileCanvasButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF155EEF)),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LengthMenuTile extends StatelessWidget {
  const _LengthMenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.destructive = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final bool destructive;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    late final Color foreground;
    late final Color iconBackground;
    if (!enabled) {
      foreground = const Color(0xFF98A2B3);
      iconBackground = const Color(0xFFF2F4F7);
    } else if (emphasized) {
      foreground = Colors.white;
      iconBackground = Colors.white.withOpacity(0.18);
    } else if (destructive) {
      foreground = const Color(0xFFD92D20);
      iconBackground = const Color(0xFFFEF3F2);
    } else {
      foreground = const Color(0xFF344054);
      iconBackground = const Color(0xFFF2F4F7);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            emphasized
                ? (enabled ? const Color(0xFF155EEF) : const Color(0xFFF2F4F7))
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: foreground),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          enabled
                              ? const Color(0xFF667085)
                              : const Color(0xFF98A2B3),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopDockButton extends StatelessWidget {
  const _TopDockButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF155EEF) : const Color(0xFF344054);
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEFF4FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.black.withOpacity(0.10),
    );
  }
}

// Preview card widget (same UI as yours, but reads/writes through controller)

class _TakeoffBoqPage extends StatelessWidget {
  const _TakeoffBoqPage({
    required this.projectId,
    required this.projectName,
    required this.buildingId,
    required this.buildingName,
    required this.drawingId,
    required this.drawingTitle,
    required this.imageUrl,
  });

  final String projectId;
  final String projectName;
  final String buildingId;
  final String buildingName;
  final String drawingId;
  final String drawingTitle;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BoqTabGetX(
          projectId: projectId,
          projectName: projectName,
          buildingId: buildingId,
          buildingName: buildingName,
          drawingId: drawingId,
          drawingTitle: drawingTitle,
          imageUrl: imageUrl,
          backLabel: 'Back to take-off',
          onBackToDrawings: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
