import 'dart:typed_data';

import 'package:aqs/app_routes.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:aqs/features/drawings/controllers/drawings_tab_controller.dart';
import 'package:aqs/features/drawings/models/drawing_row.dart';
import 'package:aqs/features/drawings/services/drawing_download_service.dart';
import 'package:aqs/features/drawings/widgets/drawing_download_dialog.dart';
import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DrawingsTabGetX extends StatefulWidget {
  const DrawingsTabGetX({
    super.key,
    required this.projectId,
    required this.buildingId,
    this.projectName = '',
    this.buildingName = '',
    this.activeDrawingId,
    this.onDrawingSelected,
    this.onOpenBoq,
  });

  final String projectId;
  final String buildingId;
  final String projectName;
  final String buildingName;
  final String? activeDrawingId;

  final ValueChanged<String>? onDrawingSelected;
  final ValueChanged<String>? onOpenBoq;

  @override
  State<DrawingsTabGetX> createState() => _DrawingsTabGetXState();
}

class _DrawingsTabGetXState extends State<DrawingsTabGetX> {
  late final DrawingsTabController c;

  late final String controllerTag;
  int _previewRequest = 0;
  bool _isDownloadingDrawings = false;
  final DrawingDownloadService _drawingDownloadService =
      DrawingDownloadService();

  @override
  void initState() {
    super.initState();

    controllerTag = '${widget.projectId}|${widget.buildingId}';

    // --------------------------------------------------
    // GET / CREATE CONTROLLER ONCE
    // --------------------------------------------------

    if (Get.isRegistered<DrawingsTabController>(tag: controllerTag)) {
      c = Get.find<DrawingsTabController>(tag: controllerTag);
    } else {
      c = Get.put(
        DrawingsTabController(
          projectId: widget.projectId,
          buildingId: widget.buildingId,
        ),
        tag: controllerTag,
        permanent: true,
      );
    }

    // --------------------------------------------------
    // START LISTENER AFTER FIRST FRAME
    // --------------------------------------------------

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      c.startDrawingsListener();

      _applyInitialDrawing();
    });
  }

  @override
  void didUpdateWidget(covariant DrawingsTabGetX oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If parent changes activeDrawingId while this page
    // is already alive, apply it after the frame.
    if (oldWidget.activeDrawingId != widget.activeDrawingId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _applyInitialDrawing();
      });
    }
  }

  // =====================================================
  // INITIAL / EXTERNAL DRAWING SELECTION
  // =====================================================

  void _applyInitialDrawing() {
    final id = widget.activeDrawingId;

    if (id == null || id.isEmpty) {
      return;
    }

    final exists = c.drawings.any((drawing) => drawing.id == id);

    if (!exists) {
      return;
    }

    if (c.selectedDrawingId.value == id) {
      return;
    }

    c.selectedDrawingId.value = id;

    widget.onDrawingSelected?.call(id);
  }

  // =====================================================
  // OPEN MEASUREMENT
  // =====================================================

  void _openMeasurementForDrawing(DrawingRow drawing) {
    if (drawing.status != 'ready' ||
        (drawing.imageUrl.isEmpty && drawing.downloadUrl.isEmpty)) {
      return;
    }

    Get.delete<MeasuringItemController>(force: true);

    Get.delete<ImageTakeoffController>(force: true);

    Get.delete<WallingConfigController>(force: true);

    Get.delete<WallingTakeoffController>(force: true);

    Get.delete<CompositeBeamTakeoffController>(force: true);

    Get.toNamed(
      AppRoutes.drawingMeasurementPath(
        projectId: widget.projectId,
        buildingId: widget.buildingId,
        drawingId: drawing.id,
        drawingTitle: drawing.title,
        imageUrl: drawing.scopedImageUrl,
      ),
      arguments: {
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': drawing.id,
        'drawingTitle': drawing.title,
        'imageUrl': drawing.scopedImageUrl,
        'downloadUrl': drawing.downloadUrl,
        'sourcePageNumber': drawing.sourcePageNumber,
        'imagePath': drawing.imagePath,
      },
    );
  }

  // =====================================================
  // DELETE DRAWING
  // =====================================================

  Future<bool> _confirmDeleteDrawing(
    BuildContext context,
    DrawingRow drawing,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFFD92D20),
          ),
          title: const Text('Delete drawing?'),
          content: Text(
            '“${drawing.title.isEmpty ? 'Untitled drawing' : drawing.title}” '
            'will be removed from this building. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD92D20),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return false;
    }

    return c.deleteDrawing(drawingId: drawing.id, data: drawing.raw);
  }

  Future<void> _renameDrawing(BuildContext context, DrawingRow drawing) async {
    final titleController = TextEditingController(text: drawing.title);
    String? error;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF155EEF),
                  ),
                  title: const Text('Rename drawing'),
                  content: TextField(
                    controller: titleController,
                    autofocus: true,
                    enabled: !isSaving,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                    onSubmitted:
                        isSaving
                            ? null
                            : (_) async {
                              final cleanTitle = titleController.text.trim();
                              if (cleanTitle.isEmpty) {
                                setDialogState(
                                  () => error = 'Enter a drawing name.',
                                );
                                return;
                              }
                              setDialogState(() {
                                isSaving = true;
                                error = null;
                              });
                              try {
                                await c.renameDrawing(
                                  drawingId: drawing.id,
                                  title: cleanTitle,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    isSaving = false;
                                    error = 'Could not rename the drawing: $e';
                                  });
                                }
                              }
                            },
                    decoration: InputDecoration(
                      labelText: 'Drawing name',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isSaving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          isSaving
                              ? null
                              : () async {
                                final cleanTitle = titleController.text.trim();
                                if (cleanTitle.isEmpty) {
                                  setDialogState(
                                    () => error = 'Enter a drawing name.',
                                  );
                                  return;
                                }
                                if (cleanTitle == drawing.title.trim()) {
                                  Navigator.pop(dialogContext);
                                  return;
                                }
                                setDialogState(() {
                                  isSaving = true;
                                  error = null;
                                });
                                try {
                                  await c.renameDrawing(
                                    drawingId: drawing.id,
                                    title: cleanTitle,
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (e) {
                                  if (dialogContext.mounted) {
                                    setDialogState(() {
                                      isSaving = false;
                                      error =
                                          'Could not rename the drawing: $e';
                                    });
                                  }
                                }
                              },
                      icon:
                          isSaving
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.check_rounded),
                      label: Text(isSaving ? 'Saving…' : 'Rename'),
                    ),
                  ],
                ),
          ),
    );

    titleController.dispose();
  }

  Future<void> _duplicateDrawing(
    BuildContext context,
    DrawingRow drawing,
  ) async {
    final titleController = TextEditingController(
      text: c.suggestedDuplicateTitle(drawing.title),
    );
    String? error;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  icon: const Icon(
                    Icons.content_copy_rounded,
                    color: Color(0xFF155EEF),
                  ),
                  title: const Text('Duplicate drawing'),
                  content: SizedBox(
                    width: 430,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: titleController,
                          autofocus: true,
                          enabled: !isSaving,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            if (error != null) {
                              setDialogState(() => error = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'New drawing name',
                            border: const OutlineInputBorder(),
                            errorText: error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The drawing image and calibration will be copied. '
                          'Take-off measurements will remain separate.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isSaving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          isSaving
                              ? null
                              : () async {
                                final title = titleController.text.trim();
                                if (title.isEmpty) {
                                  setDialogState(
                                    () => error = 'Enter a drawing name.',
                                  );
                                  return;
                                }
                                setDialogState(() {
                                  isSaving = true;
                                  error = null;
                                });
                                try {
                                  final duplicateId = await c.duplicateDrawing(
                                    drawingId: drawing.id,
                                    data: drawing.raw,
                                    title: title,
                                  );
                                  c.selectedDrawingId.value = duplicateId;
                                  widget.onDrawingSelected?.call(duplicateId);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (e) {
                                  if (dialogContext.mounted) {
                                    setDialogState(() {
                                      isSaving = false;
                                      error =
                                          'Could not duplicate the drawing: $e';
                                    });
                                  }
                                }
                              },
                      icon:
                          isSaving
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.content_copy_rounded),
                      label: Text(isSaving ? 'Duplicating…' : 'Duplicate'),
                    ),
                  ],
                ),
          ),
    );

    titleController.dispose();
  }

  // =====================================================
  // SELECT DRAWING
  // =====================================================

  void _selectDrawing(String drawingId) {
    final changedDrawing = c.selectedDrawingId.value != drawingId;
    if (changedDrawing) {
      c.selectedDrawingId.value = drawingId;
      widget.onDrawingSelected?.call(drawingId);
    }

    // Reset zoom/pan when changing drawing.
    c.previewTransformController.value = Matrix4.identity();
    setState(() => _previewRequest++);
  }

  // =====================================================
  // STATUS
  // =====================================================

  Widget _buildStatusWidget(Map<String, dynamic> data) {
    final status = (data['processingStatus'] ?? 'pending').toString();

    final error = (data['processingError'] ?? '').toString();

    if (status == 'pending' ||
        status == 'processing' ||
        status == 'uploading') {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            'Converting drawing to image...',
            style: TextStyle(fontSize: 11),
          ),
        ],
      );
    }

    if (status == 'error') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              error.isNotEmpty
                  ? 'Error converting drawing:\n$error'
                  : 'Error converting drawing.',
              style: const TextStyle(fontSize: 11, color: Colors.red),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return const Row(
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 16),
        SizedBox(width: 6),
        Text(
          'Drawing image ready',
          style: TextStyle(fontSize: 11, color: Colors.green),
        ),
      ],
    );
  }

  // =====================================================
  // UPLOAD
  // =====================================================

  Future<void> _uploadDrawing() async {
    if (c.isUploading.value || c.isSelectingDrawingFiles.value) {
      return;
    }

    await c.uploadDrawingToR2(
      context: context,
      buildingId: widget.buildingId,
      drawingsRef: c.drawingsRef,
      projectId: widget.projectId,
    );
  }

  Future<void> _downloadDrawings(List<DrawingRow> drawings) async {
    if (_isDownloadingDrawings || drawings.isEmpty) return;

    final selected = await showDialog<List<DrawingRow>>(
      context: context,
      builder: (_) => DrawingDownloadDialog(drawings: drawings),
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    setState(() => _isDownloadingDrawings = true);
    final progress = ValueNotifier<DrawingDownloadProgress>(
      DrawingDownloadProgress(
        completed: 0,
        total: selected.length,
        currentDrawing: '',
      ),
    );
    var progressIsOpen = true;
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 390,
            child: ValueListenableBuilder<DrawingDownloadProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                final fraction = value.total == 0
                    ? null
                    : value.completed / value.total;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preparing drawings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: 12),
                    Text(
                      'Preparing drawings... ${value.completed} / ${value.total}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (value.currentDrawing.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        value.currentDrawing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    Future<void> closeProgress() async {
      if (!progressIsOpen || !mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressIsOpen = false;
      await progressDialog;
    }

    try {
      final result = await _drawingDownloadService.download(
        drawings: selected,
        projectName: widget.projectName.isEmpty
            ? widget.projectId
            : widget.projectName,
        buildingName: widget.buildingName.isEmpty
            ? widget.buildingId
            : widget.buildingName,
        onProgress: (value) => progress.value = value,
      );
      await closeProgress();
      if (!mounted) return;
      final message = result.failed == 0
          ? '${result.downloaded} ${result.downloaded == 1 ? 'drawing' : 'drawings'} downloaded successfully.'
          : '${result.downloaded} ${result.downloaded == 1 ? 'drawing' : 'drawings'} downloaded. '
                '${result.failed} ${result.failed == 1 ? 'drawing could' : 'drawings could'} not be downloaded.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      await closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Drawing download failed: $error')),
      );
    } finally {
      progress.dispose();
      if (mounted) setState(() => _isDownloadingDrawings = false);
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final tc = c.previewTransformController;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      body: Stack(
        children: [
          // =================================================
          // DRAWINGS CONTENT
          // =================================================
          Obx(() {
            final List<DrawingRow> list = c.drawings.toList()
              ..sort((a, b) {
                final aTitle = (a.title.isEmpty ? 'Untitled drawing' : a.title)
                    .trim()
                    .toLowerCase();
                final bTitle = (b.title.isEmpty ? 'Untitled drawing' : b.title)
                    .trim()
                    .toLowerCase();
                final byTitle = aTitle.compareTo(bTitle);
                if (byTitle != 0) return byTitle;
                return a.sheetNumber.trim().toLowerCase().compareTo(
                  b.sheetNumber.trim().toLowerCase(),
                );
              });

            final bool loading = c.isLoadingDrawings.value;

            final String error = c.drawingsError.value;

            final String? selectedId = c.selectedDrawingId.value;

            // -----------------------------------------------
            // INITIAL LOADING
            // -----------------------------------------------

            if (loading && list.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Loading building drawings',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            // -----------------------------------------------
            // ERROR
            // -----------------------------------------------

            if (error.isNotEmpty && list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 42,
                        color: Color(0xFFD92D20),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
              );
            }

            // -----------------------------------------------
            // EMPTY DRAWINGS
            // -----------------------------------------------

            if (list.isEmpty) {
              return _buildEmptyState();
            }

            // =================================================
            // IMPORTANT:
            //
            // DO NOT WRITE selectedDrawingId HERE.
            //
            // We only READ state during Obx build.
            // =================================================

            DrawingRow? selected;

            if (selectedId != null) {
              for (final drawing in list) {
                if (drawing.id == selectedId) {
                  selected = drawing;
                  break;
                }
              }
            }

            // Local display fallback ONLY.
            //
            // This does NOT modify Rx state.
            selected ??= list.first;

            final currentDrawing = selected;

            // -----------------------------------------------
            // WORKSPACE
            // -----------------------------------------------

            return LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 760;

                final viewer = _DrawingViewerCard(
                  key: ValueKey(
                    'drawing-viewer-'
                    '${currentDrawing.id}-'
                    '${currentDrawing.imageUrl}-'
                    '${currentDrawing.downloadUrl}-'
                    '${currentDrawing.sourcePageNumber}-'
                    '$_previewRequest',
                  ),

                  drawingId: currentDrawing.id,

                  title: currentDrawing.title,

                  statusWidget: _buildStatusWidget(currentDrawing.raw),

                  imageUrl: currentDrawing.imageUrl,

                  downloadUrl: currentDrawing.downloadUrl,

                  imagePath: currentDrawing.imagePath,

                  sourcePageNumber: currentDrawing.sourcePageNumber,

                  packageUpload: currentDrawing.packageUpload,

                  clientRenderedImage: currentDrawing.clientRenderedImage,

                  status: currentDrawing.status,

                  tc: tc,

                  renderPdfPreview: ({
                    required String pdfUrl,
                    required int pageNumber,
                    required double scale,
                  }) {
                    return c.renderPdfUrlPagePng(
                      pdfUrl: pdfUrl,
                      pageNumber: pageNumber,
                      scale: scale,
                    );
                  },

                  onOpenMeasure:
                      currentDrawing.status == 'ready' &&
                              (currentDrawing.imageUrl.isNotEmpty ||
                                  currentDrawing.downloadUrl.isNotEmpty)
                          ? () {
                            _openMeasurementForDrawing(currentDrawing);
                          }
                          : null,
                );

                final listPane = _DrawingsListPane(
                  drawings: list,

                  isDownloading: _isDownloadingDrawings,

                  onDownload: () => _downloadDrawings(list),

                  selectedId: currentDrawing.id,

                  // -----------------------------------------
                  // USER SELECTS DRAWING
                  // -----------------------------------------
                  onSelect: (drawingId) {
                    _selectDrawing(drawingId);
                  },

                  // -----------------------------------------
                  // DELETE
                  // -----------------------------------------
                  onDelete: (drawing) async {
                    await _confirmDeleteDrawing(context, drawing);

                    // Do NOT set:
                    //
                    // selectedDrawingId.value = null
                    //
                    // here.
                    //
                    // The Firestore listener will receive
                    // the updated list and decide whether
                    // another drawing needs selecting.
                  },

                  onRename: (drawing) => _renameDrawing(context, drawing),

                  onDuplicate: (drawing) => _duplicateDrawing(context, drawing),

                  // -----------------------------------------
                  // MEASURE
                  // -----------------------------------------
                  onOpenMeasure: _openMeasurementForDrawing,

                  // -----------------------------------------
                  // BOQ
                  // -----------------------------------------
                  onOpenBoq:
                      widget.onOpenBoq == null
                          ? null
                          : (drawing) async {
                            _selectDrawing(drawing.id);

                            final projectDataController =
                                Get.find<ProjectBuildingsController>();

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

                            widget.onOpenBoq!(drawing.id);
                          },

                  statusWidgetBuilder: _buildStatusWidget,
                );

                // -----------------------------------------
                // DESKTOP
                // -----------------------------------------

                if (sideBySide) {
                  final registerWidth =
                      (constraints.maxWidth * 0.36)
                          .clamp(300.0, 360.0)
                          .toDouble();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Row(
                      children: [
                        Expanded(flex: 8, child: viewer),
                        const SizedBox(width: 16),
                        SizedBox(width: registerWidth, child: listPane),
                      ],
                    ),
                  );
                }

                // -----------------------------------------
                // MOBILE / SMALL
                // -----------------------------------------

                final mobilePreviewWidth = constraints.maxWidth - 32;
                final widthBasedPreviewHeight =
                    (mobilePreviewWidth * 0.72).clamp(240.0, 420.0).toDouble();
                final heightBasedPreviewLimit =
                    (constraints.maxHeight * 0.55)
                        .clamp(180.0, 420.0)
                        .toDouble();
                final mobilePreviewHeight =
                    widthBasedPreviewHeight < heightBasedPreviewLimit
                        ? widthBasedPreviewHeight
                        : heightBasedPreviewLimit;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    children: [
                      SizedBox(height: mobilePreviewHeight, child: viewer),
                      const SizedBox(height: 12),
                      Expanded(child: listPane),
                    ],
                  ),
                );
              },
            );
          }),

          // =================================================
          // FILE PICKER OVERLAY
          // =================================================
          Obx(() {
            if (!c.isSelectingDrawingFiles.value) {
              return const SizedBox.shrink();
            }

            final message =
                c.uploadFileName.value ?? 'Opening drawing file picker...';

            return Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.18),
                alignment: Alignment.center,
                child: Material(
                  elevation: 18,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width:
                        (MediaQuery.sizeOf(context).width - 32)
                            .clamp(240.0, 360.0)
                            .toDouble(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Preparing drawing upload',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF667085),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // =================================================
          // UPLOAD PROGRESS
          // =================================================
          Obx(() {
            if (!c.isUploading.value) {
              return const SizedBox.shrink();
            }

            final p = c.uploadProgress.value;

            final name = c.uploadFileName.value ?? 'Uploading drawing...';

            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                elevation: 8,
                color: Colors.black.withOpacity(0.8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: p > 0 && p < 1 ? p : null,
                              minHeight: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),

      // ===================================================
      // ADD DRAWING
      // ===================================================
      floatingActionButton: Obx(() {
        final busy = c.isUploading.value || c.isSelectingDrawingFiles.value;
        if (c.drawings.isEmpty) return const SizedBox.shrink();

        return FloatingActionButton(
          tooltip: 'Upload drawing package',
          onPressed: busy ? null : _uploadDrawing,
          child:
              busy
                  ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.add),
        );
      }),
    );
  }

  // =====================================================
  // EMPTY STATE
  // =====================================================

  Widget _buildEmptyState() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 24 : 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 360 : 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 44,
                  color: Color(0xFF98A2B3),
                ),
                const SizedBox(height: 14),
                const Text(
                  'No drawings uploaded',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Upload one PDF or a drawing package, then choose the pages to use for take-off work.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF667085), height: 1.4),
                ),
                const SizedBox(height: 18),
                Obx(() {
                  final busy =
                      c.isUploading.value || c.isSelectingDrawingFiles.value;

                  return FilledButton.icon(
                    onPressed: busy ? null : _uploadDrawing,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    icon:
                        c.isSelectingDrawingFiles.value
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      c.isSelectingDrawingFiles.value
                          ? 'Opening...'
                          : 'Upload Package',
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// class DrawingsTabGetX extends StatelessWidget {
//   const DrawingsTabGetX({
//     super.key,
//     required this.projectId,
//     required this.buildingId,
//     this.activeDrawingId,
//     this.onDrawingSelected,
//     this.onOpenBoq,
//   });

//   final String projectId;
//   final String buildingId;
//   final String? activeDrawingId;
//   final ValueChanged<String>? onDrawingSelected;
//   final ValueChanged<String>? onOpenBoq;

//   DrawingsTabController _ensureController() {
//     final tag = '$projectId|$buildingId';

//     late final DrawingsTabController controller;

//     if (Get.isRegistered<DrawingsTabController>(tag: tag)) {
//       controller = Get.find<DrawingsTabController>(tag: tag);
//     } else {
//       controller = Get.put(
//         DrawingsTabController(projectId: projectId, buildingId: buildingId),
//         tag: tag,
//         permanent: true,
//       );
//     }

//     controller.startDrawingsListener();

//     return controller;
//   }

//   void _openMeasurementForDrawing(DrawingRow drawing) {
//     if (drawing.status != 'ready' ||
//         (drawing.imageUrl.isEmpty && drawing.downloadUrl.isEmpty)) {
//       return;
//     }

//     Get.delete<MeasuringItemController>(force: true);
//     Get.delete<ImageTakeoffController>(force: true);
//     Get.delete<WallingConfigController>(force: true);
//     Get.delete<WallingTakeoffController>(force: true);
//     Get.delete<CompositeBeamTakeoffController>(force: true);

//     Get.toNamed(
//       AppRoutes.drawingMeasurementPath(
//         projectId: projectId,
//         buildingId: buildingId,
//         drawingId: drawing.id,
//         drawingTitle: drawing.title,
//         imageUrl: drawing.scopedImageUrl,
//       ),
//       arguments: {
//         'projectId': projectId,
//         'buildingId': buildingId,
//         'drawingId': drawing.id,
//         'drawingTitle': drawing.title,
//         'imageUrl': drawing.scopedImageUrl,
//         'downloadUrl': drawing.downloadUrl,
//         'sourcePageNumber': drawing.sourcePageNumber,
//         'imagePath': drawing.imagePath,
//       },
//     );
//   }

//   Future<bool> _confirmDeleteDrawing(
//     BuildContext context,
//     DrawingsTabController controller,
//     DrawingRow drawing,
//   ) async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder:
//           (dialogContext) => AlertDialog(
//             icon: const Icon(
//               Icons.delete_outline_rounded,
//               color: Color(0xFFD92D20),
//             ),
//             title: const Text('Delete drawing?'),
//             content: Text(
//               '“${drawing.title.isEmpty ? 'Untitled drawing' : drawing.title}” '
//               'will be removed from this building. This action cannot be undone.',
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(dialogContext, false),
//                 child: const Text('Cancel'),
//               ),
//               FilledButton.icon(
//                 onPressed: () => Navigator.pop(dialogContext, true),
//                 style: FilledButton.styleFrom(
//                   backgroundColor: const Color(0xFFD92D20),
//                 ),
//                 icon: const Icon(Icons.delete_outline_rounded),
//                 label: const Text('Delete'),
//               ),
//             ],
//           ),
//     );

//     if (confirmed != true) return false;
//     return controller.deleteDrawing(drawingId: drawing.id, data: drawing.raw);
//   }

//   Widget _buildStatusWidget(Map<String, dynamic> data) {
//     final status = (data['processingStatus'] ?? 'pending') as String;
//     final error = (data['processingError'] ?? '') as String;

//     if (status == 'pending' ||
//         status == 'processing' ||
//         status == 'uploading') {
//       return Row(
//         children: const [
//           SizedBox(
//             width: 14,
//             height: 14,
//             child: CircularProgressIndicator(strokeWidth: 2),
//           ),
//           SizedBox(width: 6),
//           Text(
//             'Converting drawing to image...',
//             style: TextStyle(fontSize: 11),
//           ),
//         ],
//       );
//     }

//     if (status == 'error') {
//       return Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(Icons.error, color: Colors.red, size: 16),
//           const SizedBox(width: 4),
//           Expanded(
//             child: Text(
//               error.isNotEmpty
//                   ? 'Error converting drawing:\n$error'
//                   : 'Error converting drawing.',
//               style: const TextStyle(fontSize: 11, color: Colors.red),
//               maxLines: 4,
//               overflow: TextOverflow.ellipsis,
//             ),
//           ),
//         ],
//       );
//     }

//     return Row(
//       children: const [
//         Icon(Icons.check_circle, color: Colors.green, size: 16),
//         SizedBox(width: 6),
//         Text(
//           'Drawing image ready',
//           style: TextStyle(fontSize: 11, color: Colors.green),
//         ),
//       ],
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final c = _ensureController();
//     final tc = c.previewTransformController;
//     final selectedId = c.selectedDrawingId;

//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       body: Stack(
//         children: [
//           Obx(() {
//             final list = c.drawings.toList();

//             if (c.isLoadingDrawings.value && list.isEmpty) {
//               return const Center(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     SizedBox(
//                       width: 40,
//                       height: 40,
//                       child: CircularProgressIndicator(strokeWidth: 3),
//                     ),
//                     SizedBox(height: 14),
//                     Text(
//                       'Loading building drawings',
//                       style: TextStyle(
//                         color: Color(0xFF667085),
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ],
//                 ),
//               );
//             }

//             if (c.drawingsError.value.isNotEmpty && list.isEmpty) {
//               return Center(child: Text(c.drawingsError.value));
//             }

//             if (list.isEmpty) {
//               return Center(
//                 child: ConstrainedBox(
//                   constraints: const BoxConstraints(maxWidth: 420),
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       const Icon(
//                         Icons.layers_outlined,
//                         size: 44,
//                         color: Color(0xFF98A2B3),
//                       ),
//                       const SizedBox(height: 14),
//                       const Text(
//                         'No drawings uploaded',
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.w900,
//                           color: Color(0xFF344054),
//                         ),
//                       ),
//                       const SizedBox(height: 6),
//                       const Text(
//                         'Upload one PDF or a drawing package, then choose the pages to use for take-off work.',
//                         textAlign: TextAlign.center,
//                         style: TextStyle(color: Color(0xFF667085)),
//                       ),
//                       const SizedBox(height: 16),
//                       Obx(() {
//                         final busy =
//                             c.isUploading.value ||
//                             c.isSelectingDrawingFiles.value;

//                         return FilledButton.icon(
//                           onPressed:
//                               busy
//                                   ? null
//                                   : () => c.uploadDrawingToR2(
//                                     context: context,
//                                     buildingId: buildingId,
//                                     drawingsRef: c.drawingsRef,
//                                     projectId: projectId,
//                                   ),
//                           icon:
//                               c.isSelectingDrawingFiles.value
//                                   ? const SizedBox(
//                                     width: 18,
//                                     height: 18,
//                                     child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                       color: Colors.white,
//                                     ),
//                                   )
//                                   : const Icon(Icons.upload_file_outlined),
//                           label: Text(
//                             c.isSelectingDrawingFiles.value
//                                 ? 'Opening...'
//                                 : 'Upload Package',
//                           ),
//                         );
//                       }),
//                     ],
//                   ),
//                 ),
//               );
//             }

//             // --------------------------------------------------
//             // AUTO-SELECT DRAWING
//             // --------------------------------------------------

//             if (activeDrawingId != null &&
//                 list.any((drawing) => drawing.id == activeDrawingId) &&
//                 selectedId.value != activeDrawingId) {
//               WidgetsBinding.instance.addPostFrameCallback((_) {
//                 selectedId.value = activeDrawingId;
//               });
//             }

//             // if (selectedId.value == null) {
//             //   final ready = list.firstWhereOrNull(
//             //     (x) =>
//             //         x.status == 'ready' &&
//             //         (x.imageUrl.isNotEmpty || x.downloadUrl.isNotEmpty),
//             //   );

//             //   WidgetsBinding.instance.addPostFrameCallback((_) {
//             //     final id = (ready ?? list.first).id;

//             //     selectedId.value = id;

//             //     onDrawingSelected?.call(id);
//             //   });
//             // }

//             final sid = selectedId.value;

//             final selected =
//                 list.firstWhereOrNull((x) => x.id == sid) ?? list.first;

//             return Column(
//               children: [
//                 Expanded(
//                   child: LayoutBuilder(
//                     builder: (context, bc) {
//                       final wide = bc.maxWidth >= 1050;

//                       final viewer = _DrawingViewerCard(
//                         key: ValueKey(
//                           'drawing-viewer-${selected.id}-${selected.imageUrl}-${selected.downloadUrl}-${selected.sourcePageNumber}',
//                         ),
//                         drawingId: selected.id,
//                         title: selected.title,
//                         statusWidget: _buildStatusWidget(selected.raw),
//                         imageUrl: selected.imageUrl,
//                         downloadUrl: selected.downloadUrl,
//                         imagePath: selected.imagePath,
//                         sourcePageNumber: selected.sourcePageNumber,
//                         packageUpload: selected.packageUpload,
//                         clientRenderedImage: selected.clientRenderedImage,
//                         status: selected.status,
//                         tc: tc,
//                         renderPdfPreview:
//                             ({
//                               required String pdfUrl,
//                               required int pageNumber,
//                               required double scale,
//                             }) => c.renderPdfUrlPagePng(
//                               pdfUrl: pdfUrl,
//                               pageNumber: pageNumber,
//                               scale: scale,
//                             ),
//                         onOpenMeasure:
//                             selected.status == 'ready' &&
//                                     (selected.imageUrl.isNotEmpty ||
//                                         selected.downloadUrl.isNotEmpty)
//                                 ? () => _openMeasurementForDrawing(selected)
//                                 : null,
//                       );

//                       final listPane = _DrawingsListPane(
//                         drawings: list,
//                         selectedId: selected.id,
//                         onSelect: (id) {
//                           selectedId.value = id;

//                           tc.value = Matrix4.identity();

//                           onDrawingSelected?.call(id);
//                         },
//                         onDelete: (drawing) async {
//                           final deleted = await _confirmDeleteDrawing(
//                             context,
//                             c,
//                             drawing,
//                           );

//                           if (deleted && selectedId.value == drawing.id) {
//                             selectedId.value = null;
//                           }
//                         },
//                         onOpenMeasure: _openMeasurementForDrawing,
//                         onOpenBoq:
//                             onOpenBoq == null
//                                 ? null
//                                 : (drawing) {
//                                   selectedId.value = drawing.id;

//                                   onDrawingSelected?.call(drawing.id);

//                                   onOpenBoq!(drawing.id);
//                                 },
//                         statusWidgetBuilder: _buildStatusWidget,
//                       );

//                       if (wide) {
//                         return Padding(
//                           padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
//                           child: Row(
//                             children: [
//                               Expanded(flex: 8, child: viewer),
//                               const SizedBox(width: 16),
//                               SizedBox(width: 360, child: listPane),
//                             ],
//                           ),
//                         );
//                       }

//                       return Padding(
//                         padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
//                         child: Column(
//                           children: [
//                             Expanded(child: viewer),
//                             const SizedBox(height: 12),
//                             SizedBox(height: 260, child: listPane),
//                           ],
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ],
//             );
//           }),

//           Obx(() {
//             if (!c.isSelectingDrawingFiles.value) {
//               return const SizedBox.shrink();
//             }

//             final message =
//                 c.uploadFileName.value ?? 'Opening drawing file picker...';

//             return Positioned.fill(
//               child: Container(
//                 color: Colors.black.withValues(alpha: 0.18),
//                 alignment: Alignment.center,
//                 child: Material(
//                   elevation: 18,
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(18),
//                   child: Container(
//                     width: 360,
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 22,
//                       vertical: 20,
//                     ),
//                     child: Column(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         const SizedBox(
//                           width: 34,
//                           height: 34,
//                           child: CircularProgressIndicator(strokeWidth: 3),
//                         ),
//                         const SizedBox(height: 16),
//                         const Text(
//                           'Preparing drawing upload',
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.w800,
//                             color: Color(0xFF101828),
//                           ),
//                         ),
//                         const SizedBox(height: 8),
//                         Text(
//                           message,
//                           textAlign: TextAlign.center,
//                           style: const TextStyle(
//                             fontSize: 13,
//                             color: Color(0xFF667085),
//                             height: 1.35,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             );
//           }),

//           // ✅ Upload progress overlay (same as before)
//           Obx(() {
//             if (!c.isUploading.value) return const SizedBox.shrink();

//             final p = c.uploadProgress.value;
//             final name = c.uploadFileName.value ?? 'Uploading drawing...';

//             return Positioned(
//               left: 0,
//               right: 0,
//               bottom: 0,
//               child: Material(
//                 elevation: 8,
//                 color: Colors.black.withOpacity(0.8),
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 16,
//                     vertical: 8,
//                   ),
//                   child: Row(
//                     children: [
//                       const SizedBox(
//                         width: 18,
//                         height: 18,
//                         child: CircularProgressIndicator(strokeWidth: 2),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               name,
//                               style: const TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                             const SizedBox(height: 4),
//                             LinearProgressIndicator(
//                               value: (p > 0 && p < 1) ? p : null,
//                               minHeight: 4,
//                             ),
//                           ],
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       Text(
//                         p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : '',
//                         style: const TextStyle(
//                           color: Colors.white70,
//                           fontSize: 12,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           }),
//         ],
//       ),

//       floatingActionButton: Obx(() {
//         final busy = c.isUploading.value || c.isSelectingDrawingFiles.value;

//         return FloatingActionButton(
//           tooltip: 'Upload drawing package',
//           onPressed:
//               busy
//                   ? null
//                   : () => c.uploadDrawingToR2(
//                     context: context,
//                     buildingId: buildingId,
//                     drawingsRef: c.drawingsRef,
//                     projectId: projectId,
//                   ),
//           child:
//               busy
//                   ? const SizedBox(
//                     width: 24,
//                     height: 24,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2.5,
//                       color: Colors.white,
//                     ),
//                   )
//                   : const Icon(Icons.add),
//         );
//       }),
//     );
//   }
// }

/// -------------------- UI widgets --------------------

class _DrawingViewerCard extends StatelessWidget {
  final String drawingId;
  final String title;
  final Widget statusWidget;
  final String imageUrl;
  final String downloadUrl;
  final String imagePath;
  final int sourcePageNumber;
  final bool packageUpload;
  final bool clientRenderedImage;
  final String status;
  final TransformationController tc;
  final Future<Uint8List> Function({
    required String pdfUrl,
    required int pageNumber,
    required double scale,
  })
  renderPdfPreview;
  final VoidCallback? onOpenMeasure;

  const _DrawingViewerCard({
    super.key,
    required this.drawingId,
    required this.title,
    required this.statusWidget,
    required this.imageUrl,
    required this.downloadUrl,
    required this.imagePath,
    required this.sourcePageNumber,
    required this.packageUpload,
    required this.clientRenderedImage,
    required this.status,
    required this.tc,
    required this.renderPdfPreview,
    this.onOpenMeasure,
  });

  String _scopedImageUrl() {
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

  bool get _shouldRenderFromSourcePdf =>
      imageUrl.isEmpty && downloadUrl.isNotEmpty;

  Widget _previewLoading({double? progress}) {
    final percentage = progress == null ? null : (progress * 100).round();
    return ColoredBox(
      color: const Color(0xFFF5F7FB),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                value: progress,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Loading drawing preview...',
              style: TextStyle(
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (percentage != null) ...[
              const SizedBox(height: 5),
              Text(
                '$percentage%',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkDrawingImage(BuildContext context) {
    return SizedBox.expand(
      child: Image.network(
        _scopedImageUrl(),
        key: ValueKey('$drawingId|$imagePath|$sourcePageNumber|$imageUrl'),
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final expected = loadingProgress.expectedTotalBytes;
          final progress =
              expected == null || expected <= 0
                  ? null
                  : loadingProgress.cumulativeBytesLoaded / expected;
          return _previewLoading(progress: progress?.clamp(0.0, 1.0));
        },
        errorBuilder:
            (_, __, ___) => Center(
              child: Text(
                'Failed to load drawing image',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.60),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      ),
    );
  }

  Widget _sourcePdfDrawingImage(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: renderPdfPreview(
        pdfUrl: downloadUrl,
        pageNumber: sourcePageNumber,
        scale: 1.4,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            key: ValueKey('$drawingId|source-pdf|$sourcePageNumber'),
            fit: BoxFit.contain,
          );
        }
        if (snapshot.hasError) {
          return _networkDrawingImage(context);
        }
        return _previewLoading();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final canOpen = onOpenMeasure != null;

    return MouseRegion(
      cursor: canOpen ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenMeasure,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFFF5F7FB),
                    child:
                        (status == 'ready' &&
                                (imageUrl.isNotEmpty || downloadUrl.isNotEmpty))
                            ? InteractiveViewer(
                              transformationController: tc,
                              minScale: 0.5,
                              maxScale: 6,
                              child: Center(
                                child:
                                    _shouldRenderFromSourcePdf
                                        ? _sourcePdfDrawingImage(context)
                                        : _networkDrawingImage(context),
                              ),
                            )
                            : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 46,
                                      color: Colors.black.withOpacity(0.35),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      title.isEmpty
                                          ? 'Selected drawing is loading'
                                          : title,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black.withOpacity(0.75),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Preview will appear when processing finishes.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black.withOpacity(0.55),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    statusWidget,
                                  ],
                                ),
                              ),
                            ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.94),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      title.isEmpty ? 'Selected Drawing' : title,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingsListPane extends StatelessWidget {
  final List<DrawingRow> drawings;
  final bool isDownloading;
  final VoidCallback onDownload;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<DrawingRow> onDelete;
  final ValueChanged<DrawingRow> onRename;
  final ValueChanged<DrawingRow> onDuplicate;
  final ValueChanged<DrawingRow> onOpenMeasure;
  final ValueChanged<DrawingRow>? onOpenBoq;
  final Widget Function(Map<String, dynamic> data) statusWidgetBuilder;

  const _DrawingsListPane({
    required this.drawings,
    required this.isDownloading,
    required this.onDownload,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
    required this.onRename,
    required this.onDuplicate,
    required this.onOpenMeasure,
    this.onOpenBoq,
    required this.statusWidgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Drawing register',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF344054),
                    ),
                  ),
                ),
                Text(
                  '${drawings.length}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isDownloading ? null : onDownload,
                  icon: isDownloading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 17),
                  label: Text(isDownloading ? 'Preparing' : 'Download'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.black.withOpacity(0.06)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: drawings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = drawings[i];
                final selected = d.id == selectedId;

                final canMeasure =
                    d.status == 'ready' &&
                    (d.imageUrl.isNotEmpty || d.downloadUrl.isNotEmpty);

                return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.08)
                              : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            selected
                                ? Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.30)
                                : Colors.black.withOpacity(0.05),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          (d.status == 'ready' &&
                                  (d.imageUrl.isNotEmpty ||
                                      d.downloadUrl.isNotEmpty))
                              ? Icons.image_outlined
                              : Icons.picture_as_pdf_outlined,
                          size: 18,
                          color:
                              selected
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFF667085),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title.isEmpty ? 'Untitled drawing' : d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF344054),
                                ),
                              ),
                              if (d.sheetNumber.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'Sheet ${d.sheetNumber}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF667085),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              statusWidgetBuilder(d.raw),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed:
                                        canMeasure
                                            ? () => onOpenMeasure(d)
                                            : null,
                                    icon: const Icon(
                                      Icons.architecture_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Take-off'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                    ),
                                  ),
                                  if (onOpenBoq != null)
                                    OutlinedButton.icon(
                                      onPressed: () => onOpenBoq!(d),
                                      icon: const Icon(
                                        Icons.receipt_long_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('BOQ'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 9,
                                        ),
                                      ),
                                    ),
                                  TextButton.icon(
                                    onPressed: () => onSelect(d.id),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Preview'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename drawing',
                              onPressed: () => onRename(d),
                              icon: const Icon(Icons.edit_outlined),
                              color: const Color(0xFF155EEF),
                              splashRadius: 20,
                            ),
                            IconButton(
                              tooltip: 'Duplicate drawing',
                              onPressed: () => onDuplicate(d),
                              icon: const Icon(Icons.content_copy_rounded),
                              color: const Color(0xFF155EEF),
                              splashRadius: 20,
                            ),
                            IconButton(
                              tooltip: 'Delete drawing',
                              onPressed: () => onDelete(d),
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: const Color(0xFFD92D20),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
              },
            ),
          ),
        ],
      ),
    );
  }
}
