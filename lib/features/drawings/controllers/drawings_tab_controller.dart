// import 'dart:convert';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/drawings/models/drawing_row.dart';
import 'package:aqs/features/takeoff/models/reinforcement_callout.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdfx/pdfx.dart';

class DrawingsTabController extends GetxController {
  DrawingsTabController({required this.projectId, required this.buildingId});

  @override
  void onInit() {
    super.onInit();

    startDrawingsListener();
  }

  final String projectId;
  final String buildingId;

  final RxList<DrawingRow> drawings = <DrawingRow>[].obs;

  final RxBool isLoadingDrawings = false.obs;

  final RxString drawingsError = ''.obs;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _drawingsSubscription;

  bool get hasDrawingsListener => _drawingsSubscription != null;

  bool get drawingsLoaded => drawings.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get drawingsRef => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(projectId)
      .collection('buildings')
      .doc(buildingId)
      .collection('drawings');

  // Upload UI state
  final RxBool isSelectingDrawingFiles = false.obs;
  final RxBool isUploading = false.obs;
  final RxDouble uploadProgress = 0.0.obs; // 0..1
  final RxnString uploadFileName = RxnString();
  final RxnString selectedDrawingId = RxnString();
  final RxBool drawingsInitialized = false.obs;
  final TransformationController previewTransformController =
      TransformationController();
  final Map<String, Future<Uint8List>> _pdfPagePreviewCache = {};

  static const String kFilesGatewayBase = String.fromEnvironment(
    'AQS_FILES_GATEWAY_URL',
    defaultValue: 'https://aqssite-files-gateway.aqs-files.workers.dev',
  );
  static const String kUploadToken = String.fromEnvironment(
    'AQS_FILES_UPLOAD_TOKEN',
    defaultValue: 'NyamaChoma@2610',
  );

  @override
  void onClose() {
    _drawingsSubscription?.cancel();
    _drawingsSubscription = null;
    previewTransformController.dispose();
    super.onClose();
  }

  Future<void> startDrawingsListener({bool restart = false}) async {
    if (_drawingsSubscription != null) {
      if (!restart) return;

      await _drawingsSubscription!.cancel();
      _drawingsSubscription = null;
    }

    isLoadingDrawings.value = drawings.isEmpty;
    drawingsError.value = '';

    final bar = ReinforcementCallout.tryParse('36Y12-08-150T1');

    final lengthEachM = 4.8;

    final totalLength = bar!.totalLengthM(lengthEachM);
    final totalWeight = bar.totalWeightKg(lengthEachM);

    debugPrint(
      '📐 DRAWINGS LISTENER START\n'
      'projectId: $projectId\n'
      'buildingId: $buildingId\n'
      'path: projects/$projectId/buildings/$buildingId/drawings',
    );
    String formatLength(double value) => value.toStringAsFixed(3);
    String formatWeight(double value) => value.toStringAsFixed(2);
    String formatKgPerM(double value) => value.toStringAsFixed(3);

    final m = Text('${formatLength(totalLength)} m');
    final kg = Text('${formatKgPerM(bar.kgPerM)} kg/m');
    final weight = Text('${formatWeight(totalWeight)} kg');

    print(m);
    print(kg);
    print(weight);

    _drawingsSubscription = drawingsRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            debugPrint(
              '📐 DRAWINGS SNAPSHOT: '
              '${snapshot.docs.length} docs',
            );

            final rows =
                snapshot.docs.map<DrawingRow>((doc) {
                  final data = doc.data();

                  return DrawingRow(
                    id: doc.id,
                    title: (data['title'] ?? 'Untitled drawing').toString(),
                    sheetNumber: (data['sheetNumber'] ?? '').toString(),
                    calibrated: data['calibrated'] == true,
                    status: (data['processingStatus'] ?? 'pending').toString(),
                    error: (data['processingError'] ?? '').toString(),
                    imageUrl: (data['imageUrl'] ?? '').toString().trim(),
                    downloadUrl: (data['downloadUrl'] ?? '').toString().trim(),
                    imagePath: (data['imagePath'] ?? '').toString().trim(),
                    sourcePageNumber:
                        int.tryParse('${data['sourcePageNumber'] ?? ''}') ?? 1,
                    packageUpload: data['packageUpload'] == true,
                    clientRenderedImage: data['clientRenderedImage'] == true,
                    raw: data,
                  );
                }).toList();

            // First update list.
            drawings.assignAll(rows);

            // --------------------------------------------------
            // PRESERVE CURRENT DRAWING
            // --------------------------------------------------

            final currentId = selectedDrawingId.value;

            final currentStillExists =
                currentId != null &&
                rows.any((drawing) => drawing.id == currentId);

            if (rows.isEmpty) {
              if (selectedDrawingId.value != null) {
                selectedDrawingId.value = null;
              }
            } else if (!currentStillExists) {
              // ----------------------------------------------
              // Prefer a drawing that is ready.
              // ----------------------------------------------

              DrawingRow? preferred;

              for (final drawing in rows) {
                final ready = drawing.status == 'ready';

                final hasSource =
                    drawing.imageUrl.isNotEmpty ||
                    drawing.downloadUrl.isNotEmpty;

                if (ready && hasSource) {
                  preferred = drawing;
                  break;
                }
              }

              selectedDrawingId.value = (preferred ?? rows.first).id;
            }

            drawingsError.value = '';

            drawingsInitialized.value = true;

            isLoadingDrawings.value = false;
          },
          onError: (Object error) {
            debugPrint(
              '❌ DRAWINGS LISTENER ERROR: '
              '$error',
            );

            drawingsError.value = error.toString();

            drawingsInitialized.value = true;

            isLoadingDrawings.value = false;
          },
        );

    // _drawingsSubscription = drawingsRef
    //     .orderBy('createdAt', descending: true)
    //     .snapshots()
    //     .listen(
    //       (snapshot) {
    //         final rows =
    //             snapshot.docs.map<DrawingRow>((doc) {
    //               final data = doc.data();

    //               return DrawingRow(
    //                 id: doc.id,
    //                 title: (data['title'] ?? 'Untitled drawing').toString(),
    //                 sheetNumber: (data['sheetNumber'] ?? '').toString(),
    //                 calibrated: data['calibrated'] == true,
    //                 status: (data['processingStatus'] ?? 'pending').toString(),
    //                 error: (data['processingError'] ?? '').toString(),
    //                 imageUrl: (data['imageUrl'] ?? '').toString().trim(),
    //                 downloadUrl: (data['downloadUrl'] ?? '').toString().trim(),
    //                 imagePath: (data['imagePath'] ?? '').toString().trim(),
    //                 sourcePageNumber:
    //                     int.tryParse('${data['sourcePageNumber'] ?? ''}') ?? 1,
    //                 packageUpload: data['packageUpload'] == true,
    //                 clientRenderedImage: data['clientRenderedImage'] == true,
    //                 raw: data,
    //               );
    //             }).toList();

    //         drawings.assignAll(rows);

    //         // --------------------------------------------
    //         // Keep current selection if it still exists
    //         // --------------------------------------------

    //         final currentId = selectedDrawingId.value;

    //         final currentStillExists =
    //             currentId != null &&
    //             rows.any((drawing) => drawing.id == currentId);

    //         if (!currentStillExists && rows.isNotEmpty) {
    //           DrawingRow? preferred;

    //           for (final drawing in rows) {
    //             final ready =
    //                 drawing.status == 'ready' || drawing.status == 'completed';

    //             final hasImage =
    //                 drawing.imageUrl.isNotEmpty ||
    //                 drawing.downloadUrl.isNotEmpty;

    //             if (ready && hasImage) {
    //               preferred = drawing;
    //               break;
    //             }
    //           }

    //           selectedDrawingId.value = (preferred ?? rows.first).id;
    //         }

    //         if (rows.isEmpty) {
    //           selectedDrawingId.value = null;
    //         }

    //         drawingsError.value = '';
    //         drawingsInitialized.value = true;
    //         isLoadingDrawings.value = false;
    //       },
    //       onError: (Object error) {
    //         drawingsError.value = error.toString();
    //         drawingsInitialized.value = true;
    //         isLoadingDrawings.value = false;
    //       },
    //     );
  }

  // void startDrawingsListener() {
  //   if (_drawingsSubscription != null) {
  //     return;
  //   }

  //   isLoadingDrawings.value = drawings.isEmpty;
  //   drawingsError.value = '';

  //   _drawingsSubscription = drawingsRef
  //       .orderBy('createdAt', descending: true)
  //       .snapshots()
  //       .listen(
  //         (snapshot) {
  //           drawings.assignAll(
  //             snapshot.docs.map((doc) {
  //               final data = doc.data();

  //               return DrawingRow(
  //                 id: doc.id,
  //                 title: (data['title'] ?? 'Untitled drawing').toString(),
  //                 sheetNumber: (data['sheetNumber'] ?? '').toString(),
  //                 calibrated: data['calibrated'] == true,
  //                 status: (data['processingStatus'] ?? 'pending').toString(),
  //                 error: (data['processingError'] ?? '').toString(),
  //                 imageUrl: (data['imageUrl'] ?? '').toString().trim(),
  //                 downloadUrl: (data['downloadUrl'] ?? '').toString().trim(),
  //                 imagePath: (data['imagePath'] ?? '').toString().trim(),
  //                 sourcePageNumber:
  //                     int.tryParse(
  //                       (data['sourcePageNumber'] ?? '').toString(),
  //                     ) ??
  //                     1,
  //                 packageUpload: data['packageUpload'] == true,
  //                 clientRenderedImage: data['clientRenderedImage'] == true,
  //                 raw: data,
  //               );
  //             }),
  //           );

  //           isLoadingDrawings.value = false;
  //         },
  //         onError: (error) {
  //           drawingsError.value = error.toString();

  //           isLoadingDrawings.value = false;
  //         },
  //       );
  // }

  Future<void> uploadDrawing() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final originalFileName = picked.name;

    DocumentReference<Map<String, dynamic>>? docRef;

    try {
      // 1) Pre-create drawing doc so CF can find it immediately
      docRef = drawingsRef.doc();
      final drawingId = docRef.id;

      final storageRef = FirebaseStorage.instance.ref().child(
        'projects/$projectId/buildings/$buildingId/drawings/$drawingId.pdf',
      );

      await docRef.set({
        'title': originalFileName,
        'filePath': storageRef.fullPath,
        'downloadUrl': null,
        'imageUrl': null,
        'imagePath': null,
        'sheetNumber': null,
        'scaleText': '',
        'calibrated': false,
        'unit': 'm',
        'pixelsPerUnit': 0.0,
        'processingStatus': 'uploading',
        'processingError': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) Start upload
      isUploading.value = true;
      uploadProgress.value = 0.0;
      uploadFileName.value = originalFileName;

      UploadTask uploadTask;

      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null) throw Exception('No file bytes on web');
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
      } else {
        final path = picked.path;
        if (path == null) throw Exception('No file path on this platform');
        uploadTask = storageRef.putFile(
          File(path),
          SettableMetadata(contentType: 'application/pdf'),
        );
      }

      // 3) Track progress
      final sub = uploadTask.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        final transferred = snap.bytesTransferred;
        if (total > 0) {
          uploadProgress.value = transferred / total;
        }
      });

      final snapshot = await uploadTask;
      await sub.cancel();

      uploadProgress.value = 1.0;

      final downloadUrl = await snapshot.ref.getDownloadURL();

      // 4) Update doc → pending (CF will convert to PNG)
      await docRef.update({
        'downloadUrl': downloadUrl,
        'processingStatus': 'pending',
        'processingError': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      Get.snackbar('Uploaded', 'PDF uploaded. Converting to image...');
    } catch (e) {
      // mark doc as error if we created it
      try {
        if (docRef != null) {
          await docRef.update({
            'processingStatus': 'error',
            'processingError': e.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // fallback search by title (same as your original)
          final query =
              await drawingsRef
                  .where('title', isEqualTo: originalFileName)
                  .orderBy('createdAt', descending: true)
                  .limit(1)
                  .get();

          if (query.docs.isNotEmpty) {
            await query.docs.first.reference.update({
              'processingStatus': 'error',
              'processingError': e.toString(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {}

      Get.snackbar('Upload failed', e.toString());
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0.0;
      uploadFileName.value = null;
    }
  }

  String encodeR2KeyForUrl(String key) =>
      key.split('/').map(Uri.encodeComponent).join('/');

  Future<Uint8List> renderPdfFirstPagePng(
    Uint8List pdfBytes, {
    double scale = 3.5,
  }) async {
    return renderPdfPagePng(pdfBytes, pageNumber: 1, scale: scale);
  }

  Future<int> readPdfPageCount(Uint8List pdfBytes) async {
    if (kIsWeb) {
      final base64Pdf = base64Encode(pdfBytes);
      final raw = await promiseToFutureString(pdfPageCount(base64Pdf));
      final count = int.tryParse(raw.trim()) ?? 1;
      return count < 1 ? 1 : count;
    }

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(pdfBytes);
      return doc.pagesCount < 1 ? 1 : doc.pagesCount;
    } finally {
      try {
        doc?.close();
      } catch (_) {}
    }
  }

  Future<Uint8List> renderPdfPagePng(
    Uint8List pdfBytes, {
    required int pageNumber,
    double scale = 3.5,
  }) async {
    return renderPdfPagePngBytes(
      pdfBytes,
      pageNumber: pageNumber,
      scale: scale,
    );
  }

  static Future<Uint8List> renderPdfPagePngBytes(
    Uint8List pdfBytes, {
    required int pageNumber,
    double scale = 3.5,
  }) async {
    final safePage = pageNumber < 1 ? 1 : pageNumber;
    if (!kIsWeb) {
      PdfDocument? doc;
      PdfPage? page;
      try {
        doc = await PdfDocument.openData(pdfBytes);
        final pagesCount = doc.pagesCount < 1 ? 1 : doc.pagesCount;
        final boundedPage = safePage > pagesCount ? pagesCount : safePage;
        page = await doc.getPage(boundedPage);
        final targetW = page.width * scale;
        final targetH = page.height * scale;
        final img = await page.render(
          width: targetW,
          height: targetH,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (img == null) {
          throw Exception('PDF render returned no image.');
        }
        return img.bytes;
      } finally {
        try {
          page?.close();
        } catch (_) {}
        try {
          doc?.close();
        } catch (_) {}
      }
    }

    // Convert PDF bytes -> base64 for JS
    final base64Pdf = base64Encode(pdfBytes);

    final dataUrl = await promiseToFutureString(
      pdfPageToPngDataUrl(base64Pdf, safePage, scale),
    );

    // dataUrl: "data:image/png;base64,AAA..."
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;

    return base64Decode(b64);
  }

  static Future<Uint8List> renderPdfUrlPagePngBytes({
    required String pdfUrl,
    required int pageNumber,
    double scale = 1.4,
  }) async {
    final response = await dio.Dio(
      dio.BaseOptions(
        responseType: dio.ResponseType.bytes,
        validateStatus:
            (status) => status != null && status >= 200 && status < 300,
      ),
    ).get<List<int>>(pdfUrl);
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw Exception('Source PDF could not be read.');
    }
    return renderPdfPagePngBytes(
      Uint8List.fromList(data),
      pageNumber: pageNumber,
      scale: scale,
    );
  }

  Future<Uint8List> renderPdfUrlPagePng({
    required String pdfUrl,
    required int pageNumber,
    double scale = 1.4,
  }) {
    final key = '$pdfUrl|$pageNumber|$scale';
    return _pdfPagePreviewCache.putIfAbsent(
      key,
      () => renderPdfUrlPagePngBytes(
        pdfUrl: pdfUrl,
        pageNumber: pageNumber,
        scale: scale,
      ),
    );
  }

  Future<({int width, int height})?> _decodeImageSize(Uint8List bytes) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final image = await completer.future;
      final size = (width: image.width, height: image.height);
      image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  String _defaultDrawingName(String fileName, int pageNumber, int pageCount) {
    final trimmed = fileName.trim();
    final withoutExtension = trimmed.replaceFirst(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    final fallback = withoutExtension.isEmpty ? 'Drawing' : withoutExtension;
    return pageCount > 1 ? '$fallback - Page $pageNumber' : fallback;
  }

  Future<List<_DrawingUploadSelection>?> _reviewDrawingPackage({
    required List<_PickedDrawingFile> files,
    required AqsSubscription subscription,
  }) async {
    final maximumQualityRank = switch (subscription.plan) {
      AqsPlan.business => 3,
      AqsPlan.pro => 2,
      AqsPlan.basic => 1,
      AqsPlan.free => 0,
    };
    final maximumQuality = _drawingRenderQualities[maximumQualityRank];
    var selectedQuality = _drawingRenderQualities.first;
    final drafts = <_DrawingUploadDraft>[];
    for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
      final file = files[fileIndex];
      for (var page = 1; page <= file.pageCount; page++) {
        drafts.add(
          _DrawingUploadDraft(
            fileIndex: fileIndex,
            fileName: file.name,
            pageNumber: page,
            pageCount: file.pageCount,
            controller: TextEditingController(
              text: _defaultDrawingName(file.name, page, file.pageCount),
            ),
            selected: false,
            previewRequested: false,
          ),
        );
      }
    }

    if (drafts.isEmpty) return null;

    final previewFutures = <String, Future<Uint8List>>{};
    Future<Uint8List> previewFor(_DrawingUploadDraft draft) {
      final key = '${draft.fileIndex}:${draft.pageNumber}';
      return previewFutures.putIfAbsent(key, () {
        final file = files[draft.fileIndex];
        return renderPdfPagePng(
          file.bytes,
          pageNumber: draft.pageNumber,
          scale: 0.35,
        );
      });
    }

    try {
      final result = await Get.dialog<List<_DrawingUploadSelection>>(
        StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedCount =
                drafts.where((draft) => draft.selected).length;
            final allSelected = selectedCount == drafts.length;
            final compact = MediaQuery.sizeOf(context).width < 600;

            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 40,
                vertical: compact ? 16 : 24,
              ),
              titlePadding: EdgeInsets.fromLTRB(
                compact ? 20 : 24,
                compact ? 20 : 24,
                compact ? 20 : 24,
                10,
              ),
              contentPadding: EdgeInsets.fromLTRB(
                compact ? 20 : 24,
                0,
                compact ? 20 : 24,
                12,
              ),
              title: const Text('Review drawing package'),
              content: SizedBox(
                width: compact ? double.maxFinite : 760,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        compact
                            ? MediaQuery.sizeOf(context).height * 0.68
                            : 560,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select the drawings to upload and rename them before saving to this building.',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD1E0FF)),
                        ),
                        child: Text(
                          '${files.length} PDF ${files.length == 1 ? 'file' : 'files'} selected • '
                          '${drafts.length} ${drafts.length == 1 ? 'drawing/page' : 'drawings/pages'} found',
                          style: const TextStyle(
                            color: Color(0xFF155EEF),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEAECF0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: selectedQuality.id,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Drawing quality / resolution',
                                prefixIcon: Icon(Icons.high_quality_outlined),
                                isDense: true,
                              ),
                              items: [
                                for (final quality in _drawingRenderQualities)
                                  DropdownMenuItem<String>(
                                    value: quality.id,
                                    enabled:
                                        quality.minimumPlanRank <=
                                        maximumQualityRank,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${quality.paperSize} · ${quality.label}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          quality.minimumPlanName,
                                          style: TextStyle(
                                            color:
                                                quality.minimumPlanRank <=
                                                        maximumQualityRank
                                                    ? const Color(0xFF667085)
                                                    : const Color(0xFF98A2B3),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (quality.minimumPlanRank >
                                            maximumQualityRank) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.lock_outline,
                                            size: 16,
                                            color: Color(0xFF98A2B3),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (qualityId) {
                                if (qualityId == null) return;
                                setDialogState(() {
                                  selectedQuality = _drawingRenderQualities
                                      .firstWhere(
                                        (quality) => quality.id == qualityId,
                                      );
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${subscription.displayName} plan supports drawings up to '
                              '${maximumQuality.paperSize}. A3 is the standard default.',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed:
                                selectedCount == 0
                                    ? null
                                    : () {
                                      setDialogState(() {
                                        for (final draft in drafts) {
                                          draft.selected = false;
                                        }
                                      });
                                    },
                            icon: const Icon(Icons.check_box_outline_blank),
                            label: const Text('Unselect all'),
                          ),
                          TextButton.icon(
                            onPressed:
                                allSelected
                                    ? null
                                    : () {
                                      setDialogState(() {
                                        for (final draft in drafts) {
                                          draft.selected = true;
                                        }
                                      });
                                    },
                            icon: const Icon(Icons.select_all),
                            label: const Text('Select all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: drafts.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final draft = drafts[index];
                            final isMultiPage = draft.pageCount > 1;
                            final fileLabel =
                                isMultiPage
                                    ? '${draft.fileName} • page ${draft.pageNumber} of ${draft.pageCount}'
                                    : draft.fileName;
                            final preview = Container(
                              width: compact ? 76 : 86,
                              height: compact ? 96 : 112,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFEAECF0),
                                ),
                              ),
                              child:
                                  draft.previewRequested
                                      ? FutureBuilder<Uint8List>(
                                        future: previewFor(draft),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            return Image.memory(
                                              snapshot.data!,
                                              fit: BoxFit.contain,
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return const Icon(
                                              Icons.description_outlined,
                                              color: Color(0xFF98A2B3),
                                            );
                                          }
                                          return const Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                      : TextButton.icon(
                                        onPressed:
                                            () => setDialogState(() {
                                              draft.previewRequested = true;
                                            }),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          compact ? 'View' : 'Preview',
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                            );
                            final nameField = TextField(
                              controller: draft.controller,
                              enabled: draft.selected,
                              decoration: const InputDecoration(
                                labelText: 'Drawing name',
                                hintText: 'e.g. Foundation plan',
                                isDense: true,
                              ),
                            );
                            return Container(
                              padding: EdgeInsets.all(compact ? 10 : 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFEAECF0),
                                ),
                              ),
                              child:
                                  compact
                                      ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Checkbox(
                                                value: draft.selected,
                                                onChanged: (value) {
                                                  setDialogState(
                                                    () =>
                                                        draft.selected =
                                                            value ?? false,
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  fileLabel,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF344054),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              preview,
                                              const SizedBox(width: 10),
                                              Expanded(child: nameField),
                                            ],
                                          ),
                                        ],
                                      )
                                      : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            value: draft.selected,
                                            onChanged: (value) {
                                              setDialogState(
                                                () =>
                                                    draft.selected =
                                                        value ?? false,
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          preview,
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fileLabel,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF667085),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                nameField,
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back<List<_DrawingUploadSelection>?>(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      selectedCount == 0
                          ? null
                          : () {
                            if (selectedQuality.minimumPlanRank >
                                maximumQualityRank) {
                              Get.snackbar(
                                'Upgrade required',
                                '${selectedQuality.paperSize} drawing resolution requires the '
                                    '${selectedQuality.minimumPlanName} plan.',
                              );
                              return;
                            }
                            final selected = <_DrawingUploadSelection>[];
                            for (final draft in drafts.where(
                              (d) => d.selected,
                            )) {
                              final title = draft.controller.text.trim();
                              if (title.isEmpty) {
                                Get.snackbar(
                                  'Drawing name required',
                                  'Every selected drawing needs a name.',
                                );
                                return;
                              }
                              final file = files[draft.fileIndex];
                              selected.add(
                                _DrawingUploadSelection(
                                  bytes: file.bytes,
                                  title: title,
                                  sourceFileName: draft.fileName,
                                  pageNumber: draft.pageNumber,
                                  pageCount: draft.pageCount,
                                  quality: selectedQuality,
                                ),
                              );
                            }
                            Get.back(result: selected);
                          },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text('Upload $selectedCount'),
                ),
              ],
            );
          },
        ),
        barrierDismissible: false,
      );
      return result;
    } finally {
      for (final draft in drafts) {
        draft.controller.dispose();
      }
    }
  }

  // Future<void> uploadDrawingToR2() async {
  //   final result = await FilePicker.platform.pickFiles(
  //     type: FileType.custom,
  //     allowedExtensions: const ['pdf'],
  //     withData: true,
  //   );
  //   if (result == null || result.files.isEmpty) return;

  //   final picked = result.files.single;
  //   final originalFileName = picked.name;

  //   final docRef = drawingsRef.doc();
  //   final drawingId = docRef.id;

  //   final pdfKey =
  //       'projects/$projectId/buildings/$buildingId/drawings/$drawingId.pdf';
  //   final pngKey =
  //       'projects/$projectId/buildings/$buildingId/drawings/$drawingId.png';

  //   try {
  //     await docRef.set({
  //       'title': originalFileName,
  //       'filePath': pdfKey,
  //       'imagePath': pngKey,
  //       'downloadUrl': null,
  //       'imageUrl': null,
  //       'processingStatus': 'uploading',
  //       'createdAt': FieldValue.serverTimestamp(),
  //       'updatedAt': FieldValue.serverTimestamp(),
  //     });

  //     // Web bytes
  //     final Uint8List pdfBytes =
  //         picked.bytes ?? (throw Exception('No bytes (ensure withData:true)'));

  //     // ✅ HERE: render first page png
  //     final Uint8List pngBytes = await renderPdfFirstPagePng(
  //       pdfBytes,
  //       scale: 2.5,
  //     );

  //     final dio = dio.Dio(
  //       BaseOptions(
  //         headers: {'Authorization': 'Bearer $kUploadToken'},
  //         validateStatus: (s) => s != null && s >= 200 && s < 300,
  //       ),
  //     );

  //     final pdfRes = await dio.put(
  //       '$kFilesGatewayBase/upload/${Uri.encodeComponent(pdfKey)}',
  //       data: pdfBytes,
  //       options: Options(headers: {'Content-Type': 'application/pdf'}),
  //     );

  //     final pngRes = await dio.put(
  //       '$kFilesGatewayBase/upload/${Uri.encodeComponent(pngKey)}',
  //       data: pngBytes,
  //       options: Options(headers: {'Content-Type': 'image/png'}),
  //     );

  //     final pdfUrl =
  //         (pdfRes.data is Map) ? (pdfRes.data['url'] as String?) : null;
  //     final pngUrl =
  //         (pngRes.data is Map) ? (pngRes.data['url'] as String?) : null;
  //     if (pdfUrl == null || pngUrl == null) {
  //       throw Exception('Worker did not return urls.');
  //     }

  //     await docRef.update({
  //       'downloadUrl': pdfUrl,
  //       'imageUrl': pngUrl,
  //       'processingStatus': 'ready',
  //       'updatedAt': FieldValue.serverTimestamp(),
  //     });

  //     Get.snackbar('Uploaded', 'PDF + preview uploaded (R2).');
  //   } catch (e) {
  //     await docRef.update({
  //       'processingStatus': 'error',
  //       'processingError': e.toString(),
  //       'updatedAt': FieldValue.serverTimestamp(),
  //     });
  //     Get.snackbar('Upload failed', e.toString());
  //   }
  // }

  // Future<Uint8List> renderPdfFirstPagePng(
  //   Uint8List pdfBytes, {
  //   double scale = 2.0,
  // }) async {
  //   PdfDocument? doc;
  //   PdfPage? page;

  //   try {
  //     doc = await PdfDocument.openData(pdfBytes);
  //     page = await doc.getPage(1);

  //     final double targetW = page.width * scale;
  //     final double targetH = page.height * scale;

  //     final PdfPageImage? img = await page.render(
  //       width: targetW,
  //       height: targetH,
  //       // format: PdfPageImageFormat.png, // add only if your version supports it
  //     );

  //     if (img == null) {
  //       throw Exception('PDF render returned null (PdfPageImage).');
  //     }

  //     return img.bytes;
  //   } finally {
  //     try {
  //       page?.close();
  //     } catch (_) {}
  //     try {
  //       doc?.close();
  //     } catch (_) {}
  //   }
  // }

  Future<void> uploadDrawingToR2({
    required CollectionReference<Map<String, dynamic>> drawingsRef,
    required String projectId,
    required String buildingId,
    BuildContext? context,
    // required Future<Uint8List> Function(Uint8List pdfBytes)
    // renderPdfFirstPagePng,

    /// Optional progress callbacks
    void Function(double progress01)? onProgress,
  }) async {
    if (isSelectingDrawingFiles.value || isUploading.value) return;

    FilePickerResult? result;
    final files = <_PickedDrawingFile>[];
    final subscriptionFuture = SubscriptionService.instance
        .currentSubscription()
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => AqsSubscription.free,
        )
        .catchError((_) => AqsSubscription.free);
    AqsSubscription subscription = AqsSubscription.free;

    try {
      isSelectingDrawingFiles.value = true;
      uploadProgress.value = 0;
      uploadFileName.value = 'Opening drawing file picker...';

      // Give the UI a frame to show the loading state before the browser/native
      // file picker or cloud-drive handoff starts.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true, // IMPORTANT for web
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      uploadFileName.value = 'Preparing selected drawings...';

      final preparedFiles = await Future.wait(
        result.files.map((picked) async {
          final bytes = picked.bytes;
          if (bytes == null || bytes.isEmpty) {
            Get.snackbar('Skipped file', '${picked.name} could not be read.');
            return null;
          }
          var pageCount = 1;
          try {
            pageCount = await readPdfPageCount(
              bytes,
            ).timeout(const Duration(seconds: 15));
          } catch (_) {
            pageCount = 1;
          }
          return _PickedDrawingFile(
            name: picked.name,
            bytes: bytes,
            pageCount: pageCount < 1 ? 1 : pageCount,
          );
        }),
      );
      files.addAll(preparedFiles.whereType<_PickedDrawingFile>());
      subscription = await subscriptionFuture;
    } catch (error) {
      Get.snackbar('Could not prepare drawings', error.toString());
      return;
    } finally {
      isSelectingDrawingFiles.value = false;
      if (!isUploading.value) {
        uploadProgress.value = 0;
        uploadFileName.value = null;
      }
    }

    final dialogContext = Get.overlayContext ?? Get.context;
    if (dialogContext == null) {
      Get.snackbar('Upload failed', 'Could not open drawing review dialog.');
      return;
    }

    if (files.isEmpty) {
      Get.snackbar('Upload failed', 'No readable PDF files were selected.');
      return;
    }

    final selections = await _reviewDrawingPackage(
      files: files,
      subscription: subscription,
    );
    if (selections == null || selections.isEmpty) return;

    if (kUploadToken.isEmpty) {
      await _uploadPackageToFirebaseStorage(
        drawingsRef: drawingsRef,
        projectId: projectId,
        buildingId: buildingId,
        selections: selections,
        onProgress: onProgress,
      );
      return;
    }

    try {
      isUploading.value = true;
      uploadProgress.value = 0;
      final client = dio.Dio(
        dio.BaseOptions(
          headers: {'Authorization': 'Bearer $kUploadToken'},
          responseType: dio.ResponseType.plain, // ✅ decode ourselves
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

      Future<Map<String, dynamic>> putBytes({
        required String key,
        required Uint8List data,
        required String contentType,
        void Function(int sent, int total)? onSendProgress,
      }) async {
        final url = '$kFilesGatewayBase/upload/${Uri.encodeComponent(key)}';
        final resp = await client.put(
          url,
          data: data,
          options: dio.Options(headers: {'Content-Type': contentType}),
          onSendProgress: onSendProgress,
        );

        final raw = resp.data;
        final Map<String, dynamic> j =
            raw is String
                ? (jsonDecode(raw) as Map<String, dynamic>)
                : <String, dynamic>{};

        if (j['ok'] != true) {
          throw Exception('Upload failed: ${j['error'] ?? 'Unknown error'}');
        }
        return j;
      }

      void reportOverall(int index, double part) {
        final total = selections.length;
        final progress =
            ((index + part.clamp(0.0, 1.0)) / total).clamp(0.0, 1.0).toDouble();
        uploadProgress.value = progress;
        onProgress?.call(progress);
      }

      var uploaded = 0;
      var failed = 0;

      for (var i = 0; i < selections.length; i++) {
        final selection = selections[i];
        DocumentReference<Map<String, dynamic>>? docRef;
        uploadFileName.value = selection.title;
        reportOverall(i, 0.01);

        try {
          docRef = drawingsRef.doc();
          final drawingId = docRef.id;

          final pdfKey =
              'projects/$projectId/buildings/$buildingId/drawings/$drawingId.pdf';
          final pngKey =
              'projects/$projectId/buildings/$buildingId/drawings/$drawingId.png';

          await docRef.set({
            'title': selection.title,
            'projectId': projectId,
            'buildingId': buildingId,
            'sourceFileName': selection.sourceFileName,
            'sourcePageNumber': selection.pageNumber,
            'sourcePageCount': selection.pageCount,
            'packageUpload': selections.length > 1,
            'clientRenderedImage': true,
            'conversionMode': 'client-rendered-selected-page',
            'filePath': pdfKey,
            'imagePath': pngKey,
            'downloadUrl': null,
            'imageUrl': null,
            'renderPaperSize': selection.quality.paperSize,
            'renderScale': selection.quality.scale,
            'renderQuality': selection.quality.id,
            'processingStatus': 'uploading',
            'processingError': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final pngBytes = await renderPdfPagePng(
            selection.bytes,
            pageNumber: selection.pageNumber,
            scale: selection.quality.scale,
          );
          final imageSize = await _decodeImageSize(pngBytes);
          reportOverall(i, 0.10);

          final pdfJson = await putBytes(
            key: pdfKey,
            data: selection.bytes,
            contentType: 'application/pdf',
            onSendProgress: (sent, total) {
              if (total > 0) reportOverall(i, 0.15 + (sent / total) * 0.40);
            },
          );

          final pngJson = await putBytes(
            key: pngKey,
            data: pngBytes,
            contentType: 'image/png',
            onSendProgress: (sent, total) {
              if (total > 0) reportOverall(i, 0.60 + (sent / total) * 0.35);
            },
          );

          final pdfUrl = (pdfJson['url'] as String?)?.trim();
          final pngUrl = (pngJson['url'] as String?)?.trim();

          if (pdfUrl == null ||
              pdfUrl.isEmpty ||
              pngUrl == null ||
              pngUrl.isEmpty) {
            throw Exception(
              'Upload succeeded but Worker did not return url(s).',
            );
          }

          await docRef.update({
            'downloadUrl': pdfUrl,
            'imageUrl': pngUrl,
            if (imageSize != null) ...{
              'imageW': imageSize.width,
              'imageH': imageSize.height,
            },
            'renderPaperSize': selection.quality.paperSize,
            'renderScale': selection.quality.scale,
            'renderQuality': selection.quality.id,
            'processingStatus': 'ready',
            'processingError': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          uploaded++;
          reportOverall(i, 1.0);
        } catch (e) {
          failed++;
          if (docRef != null) {
            try {
              await docRef.update({
                'processingStatus': 'error',
                'processingError': e.toString(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } catch (_) {}
          }
        }
      }

      uploadProgress.value = 1.0;
      onProgress?.call(1.0);

      if (uploaded > 0 && failed == 0) {
        Get.snackbar(
          'Uploaded',
          '$uploaded ${uploaded == 1 ? 'drawing is' : 'drawings are'} ready.',
        );
      } else if (uploaded > 0) {
        Get.snackbar(
          'Upload partially complete',
          '$uploaded uploaded, $failed failed.',
        );
      } else {
        Get.snackbar('Upload failed', 'No drawings were uploaded.');
      }
    } catch (e) {
      Get.snackbar('Upload failed', e.toString());
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0;
      uploadFileName.value = null;
    }
  }

  Future<void> _uploadPackageToFirebaseStorage({
    required CollectionReference<Map<String, dynamic>> drawingsRef,
    required String projectId,
    required String buildingId,
    required List<_DrawingUploadSelection> selections,
    void Function(double progress01)? onProgress,
  }) async {
    isUploading.value = true;
    uploadProgress.value = 0;

    void reportOverall(int index, double part) {
      final total = selections.length;
      final progress =
          ((index + part.clamp(0.0, 1.0)) / total).clamp(0.0, 1.0).toDouble();
      uploadProgress.value = progress;
      onProgress?.call(progress);
    }

    var uploaded = 0;
    var failed = 0;

    try {
      for (var i = 0; i < selections.length; i++) {
        final selection = selections[i];
        DocumentReference<Map<String, dynamic>>? docRef;
        uploadFileName.value = selection.title;
        reportOverall(i, 0.01);

        try {
          docRef = drawingsRef.doc();
          final drawingId = docRef.id;
          final basePath =
              'projects/$projectId/buildings/$buildingId/drawings/$drawingId';
          final pdfPath = '$basePath-source.pdf';
          final pngPath = '$basePath.png';

          await docRef.set({
            'title': selection.title,
            'projectId': projectId,
            'buildingId': buildingId,
            'sourceFileName': selection.sourceFileName,
            'sourcePageNumber': selection.pageNumber,
            'sourcePageCount': selection.pageCount,
            'packageUpload': selections.length > 1,
            'clientRenderedImage': true,
            'conversionMode': 'client-rendered-selected-page',
            'filePath': pdfPath,
            'imagePath': pngPath,
            'downloadUrl': null,
            'imageUrl': null,
            'sheetNumber': null,
            'scaleText': '',
            'calibrated': false,
            'unit': 'm',
            'pixelsPerUnit': 0.0,
            'renderPaperSize': selection.quality.paperSize,
            'renderScale': selection.quality.scale,
            'renderQuality': selection.quality.id,
            'processingStatus': 'uploading',
            'processingError': null,
            'storageProvider': 'firebase',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final pngBytes = await renderPdfPagePng(
            selection.bytes,
            pageNumber: selection.pageNumber,
            scale: selection.quality.scale,
          );
          final imageSize = await _decodeImageSize(pngBytes);
          reportOverall(i, 0.20);

          final storage = FirebaseStorage.instance;
          final pdfRef = storage.ref(pdfPath);
          final pngRef = storage.ref(pngPath);

          await pdfRef.putData(
            selection.bytes,
            SettableMetadata(contentType: 'application/pdf'),
          );
          reportOverall(i, 0.60);

          await pngRef.putData(
            pngBytes,
            SettableMetadata(contentType: 'image/png'),
          );
          reportOverall(i, 0.90);

          final urls = await Future.wait([
            pdfRef.getDownloadURL(),
            pngRef.getDownloadURL(),
          ]);

          await docRef.update({
            'downloadUrl': urls[0],
            'imageUrl': urls[1],
            if (imageSize != null) ...{
              'imageW': imageSize.width,
              'imageH': imageSize.height,
            },
            'renderPaperSize': selection.quality.paperSize,
            'renderScale': selection.quality.scale,
            'renderQuality': selection.quality.id,
            'processingStatus': 'ready',
            'processingError': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          uploaded++;
          reportOverall(i, 1.0);
        } catch (e) {
          failed++;
          if (docRef != null) {
            try {
              await docRef.update({
                'processingStatus': 'error',
                'processingError': e.toString(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } catch (_) {}
          }
        }
      }

      uploadProgress.value = 1;
      onProgress?.call(1);

      if (uploaded > 0 && failed == 0) {
        Get.snackbar(
          'Uploaded',
          '$uploaded ${uploaded == 1 ? 'drawing is' : 'drawings are'} ready.',
        );
      } else if (uploaded > 0) {
        Get.snackbar(
          'Upload partially complete',
          '$uploaded uploaded, $failed failed.',
        );
      } else {
        Get.snackbar('Upload failed', 'No drawings were uploaded.');
      }
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0;
      uploadFileName.value = null;
    }
  }

  Future<void> _uploadDrawingToFirebaseStorage({
    required CollectionReference<Map<String, dynamic>> drawingsRef,
    required String projectId,
    required String buildingId,
    void Function(double progress01)? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final pdfBytes = picked.bytes;
    if (pdfBytes == null || pdfBytes.isEmpty) {
      Get.snackbar('Upload failed', 'The selected PDF could not be read.');
      return;
    }

    DocumentReference<Map<String, dynamic>>? docRef;
    isUploading.value = true;
    uploadProgress.value = 0;
    uploadFileName.value = picked.name;

    void reportProgress(double value) {
      final progress = value.clamp(0.0, 1.0).toDouble();
      uploadProgress.value = progress;
      onProgress?.call(progress);
    }

    try {
      docRef = drawingsRef.doc();
      final drawingId = docRef.id;
      final basePath =
          'projects/$projectId/buildings/$buildingId/drawings/$drawingId';
      final pdfPath = '$basePath.pdf';
      final pngPath = '$basePath.png';

      await docRef.set({
        'title': picked.name,
        'projectId': projectId,
        'buildingId': buildingId,
        'filePath': pdfPath,
        'imagePath': pngPath,
        'downloadUrl': null,
        'imageUrl': null,
        'sheetNumber': null,
        'scaleText': '',
        'calibrated': false,
        'unit': 'm',
        'pixelsPerUnit': 0.0,
        'processingStatus': 'uploading',
        'processingError': null,
        'storageProvider': 'firebase',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      reportProgress(0.05);
      final pngBytes = await renderPdfFirstPagePng(pdfBytes);
      final imageSize = await _decodeImageSize(pngBytes);
      reportProgress(0.20);

      final storage = FirebaseStorage.instance;
      final pdfRef = storage.ref(pdfPath);
      final pngRef = storage.ref(pngPath);

      await pdfRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      reportProgress(0.60);

      await pngRef.putData(
        pngBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      reportProgress(0.90);

      final urls = await Future.wait([
        pdfRef.getDownloadURL(),
        pngRef.getDownloadURL(),
      ]);

      await docRef.update({
        'downloadUrl': urls[0],
        'imageUrl': urls[1],
        if (imageSize != null) ...{
          'imageW': imageSize.width,
          'imageH': imageSize.height,
        },
        'renderScale': 3.5,
        'renderQuality': 'high',
        'processingStatus': 'ready',
        'processingError': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      reportProgress(1);
      Get.snackbar(
        'Uploaded',
        'High-resolution drawing uploaded and ready to measure.',
      );
    } catch (e) {
      if (docRef != null) {
        try {
          await docRef.update({
            'processingStatus': 'error',
            'processingError': e.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
      Get.snackbar('Upload failed', e.toString());
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0;
      uploadFileName.value = null;
    }
  }

  Future<bool> deleteDrawing({
    required String drawingId,
    required Map<String, dynamic> data,
  }) async {
    final filePath = (data['filePath'] ?? '').toString().trim();
    final imagePath = (data['imagePath'] ?? '').toString().trim();
    final provider = (data['storageProvider'] ?? '').toString().trim();
    final downloadUrl = (data['downloadUrl'] ?? '').toString();
    final imageUrl = (data['imageUrl'] ?? '').toString();
    final usesFirebase =
        provider == 'firebase' ||
        downloadUrl.contains('firebasestorage.googleapis.com') ||
        imageUrl.contains('firebasestorage.googleapis.com');

    final cleanupErrors = <String>[];

    Future<bool> hasOtherFileReference(String field, String value) async {
      if (value.isEmpty) return false;
      final snapshot =
          await drawingsRef.where(field, isEqualTo: value).limit(2).get();
      return snapshot.docs.any((document) => document.id != drawingId);
    }

    Future<void> deleteFirebaseObject(String path) async {
      if (path.isEmpty) return;
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          cleanupErrors.add(e.message ?? e.code);
        }
      } catch (e) {
        cleanupErrors.add(e.toString());
      }
    }

    Future<void> deleteGatewayObject(String key) async {
      if (key.isEmpty) return;
      if (kUploadToken.isEmpty) {
        cleanupErrors.add(
          'Gateway token missing; stored file was not removed.',
        );
        return;
      }
      try {
        final client = dio.Dio(
          dio.BaseOptions(
            headers: {'Authorization': 'Bearer $kUploadToken'},
            validateStatus:
                (status) => status != null && status >= 200 && status < 300,
          ),
        );
        await client.delete(
          '$kFilesGatewayBase/upload/${Uri.encodeComponent(key)}',
        );
      } catch (e) {
        cleanupErrors.add(e.toString());
      }
    }

    try {
      final references = await Future.wait([
        hasOtherFileReference('filePath', filePath),
        hasOtherFileReference('imagePath', imagePath),
      ]);
      final fileIsShared = references[0];
      final imageIsShared = references[1];

      if (usesFirebase) {
        await Future.wait([
          if (!fileIsShared) deleteFirebaseObject(filePath),
          if (!imageIsShared) deleteFirebaseObject(imagePath),
        ]);
      } else {
        await Future.wait([
          if (!fileIsShared) deleteGatewayObject(filePath),
          if (!imageIsShared) deleteGatewayObject(imagePath),
        ]);
      }

      await drawingsRef.doc(drawingId).delete();

      if (cleanupErrors.isEmpty) {
        Get.snackbar('Drawing deleted', 'The drawing has been removed.');
      } else {
        Get.snackbar(
          'Drawing deleted',
          'The drawing record was removed, but some stored files could not be cleaned up.',
        );
      }
      return true;
    } catch (e) {
      Get.snackbar('Delete failed', e.toString());
      return false;
    }
  }

  Future<void> renameDrawing({
    required String drawingId,
    required String title,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const FormatException('Enter a drawing name.');
    }

    await drawingsRef.doc(drawingId).update({
      'title': cleanTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String suggestedDuplicateTitle(String title) {
    final sourceTitle =
        title.trim().isEmpty ? 'Untitled drawing' : title.trim();
    final existingTitles =
        drawings.map((drawing) => drawing.title.trim().toLowerCase()).toSet();
    var candidate = '$sourceTitle (Copy)';
    var copyNumber = 2;
    while (existingTitles.contains(candidate.toLowerCase())) {
      candidate = '$sourceTitle (Copy $copyNumber)';
      copyNumber++;
    }
    return candidate;
  }

  Future<String> duplicateDrawing({
    required String drawingId,
    required Map<String, dynamic> data,
    required String title,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const FormatException('Enter a drawing name.');
    }

    final duplicateRef = drawingsRef.doc();
    final duplicate =
        Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('measurementCount')
          ..remove('takeoffCount')
          ..remove('lastMeasuredAt')
          ..remove('measurementSummary')
          ..addAll({
            'title': cleanTitle,
            'projectId': projectId,
            'buildingId': buildingId,
            'duplicatedFromDrawingId': drawingId,
            'sourceDrawingId':
                (data['sourceDrawingId'] ?? drawingId).toString().trim(),
            'sharesSourceFiles': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

    await duplicateRef.set(duplicate);
    Get.snackbar(
      'Drawing duplicated',
      'The drawing image and calibration were copied without take-off measurements.',
    );
    return duplicateRef.id;
  }
}

class _PickedDrawingFile {
  const _PickedDrawingFile({
    required this.name,
    required this.bytes,
    required this.pageCount,
  });

  final String name;
  final Uint8List bytes;
  final int pageCount;
}

class _DrawingUploadDraft {
  _DrawingUploadDraft({
    required this.fileIndex,
    required this.fileName,
    required this.pageNumber,
    required this.pageCount,
    required this.controller,
    required this.selected,
    required this.previewRequested,
  });

  final int fileIndex;
  final String fileName;
  final int pageNumber;
  final int pageCount;
  final TextEditingController controller;
  bool selected;
  bool previewRequested;
}

class _DrawingUploadSelection {
  const _DrawingUploadSelection({
    required this.bytes,
    required this.title,
    required this.sourceFileName,
    required this.pageNumber,
    required this.pageCount,
    required this.quality,
  });

  final Uint8List bytes;
  final String title;
  final String sourceFileName;
  final int pageNumber;
  final int pageCount;
  final _DrawingRenderQuality quality;
}

class _DrawingRenderQuality {
  const _DrawingRenderQuality({
    required this.id,
    required this.paperSize,
    required this.label,
    required this.scale,
    required this.minimumPlanRank,
    required this.minimumPlanName,
  });

  final String id;
  final String paperSize;
  final String label;
  final double scale;
  final int minimumPlanRank;
  final String minimumPlanName;
}

const _drawingRenderQualities = <_DrawingRenderQuality>[
  _DrawingRenderQuality(
    id: 'a3-standard',
    paperSize: 'A3',
    label: 'Standard',
    scale: 2.0,
    minimumPlanRank: 0,
    minimumPlanName: 'Free',
  ),
  _DrawingRenderQuality(
    id: 'a2-enhanced',
    paperSize: 'A2',
    label: 'Enhanced',
    scale: 2.8,
    minimumPlanRank: 1,
    minimumPlanName: 'Basic',
  ),
  _DrawingRenderQuality(
    id: 'a1-high',
    paperSize: 'A1',
    label: 'High resolution',
    scale: 4.0,
    minimumPlanRank: 2,
    minimumPlanName: 'Pro',
  ),
  _DrawingRenderQuality(
    id: 'a0-maximum',
    paperSize: 'A0',
    label: 'Maximum resolution',
    scale: 5.6,
    minimumPlanRank: 3,
    minimumPlanName: 'Business',
  ),
];
