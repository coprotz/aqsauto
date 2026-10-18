// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';

// import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/drawings/models/drawing_sheet.dart';
// import 'package:aqs/features/drawings/models/drawing_storage_estimate.dart';
// import 'package:aqs/features/drawings/models/pending_drawing_page.dart';
// import 'package:aqs/features/drawings/services/drawing_page_extraction_service.dart';
// import 'package:aqs/features/drawings/services/drawing_service.dart';
// import 'package:aqs/features/drawings/services/pdf_drawing_service.dart';
// import 'package:aqs/features/drawings/widgets/drawing_page_thumbnail.dart';
// import 'package:aqs/routes/app_routes.dart';

// import 'package:dio/dio.dart' as dio;
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';

// class UploadDrawingBundlePage extends StatefulWidget {
//   const UploadDrawingBundlePage({
//     super.key,
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//     this.bundleId,
//     this.appendMode = false,
//   });

//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   final String? bundleId;

//   final bool appendMode;

//   bool get isAppending {
//     return appendMode && bundleId != null && bundleId!.trim().isNotEmpty;
//   }

//   @override
//   State<UploadDrawingBundlePage> createState() =>
//       _UploadDrawingBundlePageState();
// }

// class _UploadDrawingBundlePageState extends State<UploadDrawingBundlePage> {
//   final _formKey = GlobalKey<FormState>();

//   final _bundleNameController = TextEditingController();

//   final _revisionController = TextEditingController();

//   final _descriptionController = TextEditingController();

//   final _drawingSearchController = TextEditingController();

//   String _discipline = 'architectural';

//   String _issueType = 'construction';

//   PlatformFile? _selectedFile;

//   Uint8List? _pdfBytes;

//   List<PendingDrawingPage> _pages = [];

//   bool _selectingFile = false;

//   bool _inspectingPdf = false;

//   bool _uploading = false;

//   double _uploadProgress = 0;

//   String _drawingSearch = '';
//   bool _pauseThumbnails = false;
//   DrawingStorageEstimate? _storageEstimate;
//   bool _loadingExistingBundle = false;

//   bool _preparingDrawings = false;

//   @override
//   void initState() {
//     super.initState();

//     if (widget.isAppending) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _loadExistingBundle();
//       });
//     }
//   }

//   Future<void> _loadExistingBundle() async {
//     final bundleId = widget.bundleId?.trim();

//     if (bundleId == null || bundleId.isEmpty) {
//       return;
//     }

//     setState(() {
//       _loadingExistingBundle = true;
//     });

//     try {
//       final bundle = await DrawingService.instance.getBundle(
//         projectId: widget.projectId,

//         facilityId: widget.facilityId,

//         bundleId: bundleId,
//       );

//       if (bundle == null) {
//         throw Exception('Drawing bundle was not found.');
//       }

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         //
//         // Existing bundle name.
//         //
//         _bundleNameController.text = bundle.name;

//         //
//         // Existing classification.
//         //
//         _discipline = bundle.discipline;

//         _issueType = bundle.issueType;

//         //
//         // I suggest NOT inheriting revision.
//         //
//         // The added drawings may belong to
//         // a different issue/revision.
//         //
//         _revisionController.clear();

//         //
//         // Keep description blank so this can
//         // describe this particular upload.
//         //
//         _descriptionController.clear();

//         _loadingExistingBundle = false;
//       });
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _loadingExistingBundle = false;
//       });

//       _showMessage('Could not load bundle: $error');
//     }
//   }

//   static const Map<String, String> _disciplines = {
//     'architectural': 'Architectural',
//     'structural': 'Structural',
//     'civil': 'Civil',
//     'mechanical': 'Mechanical',
//     'electrical': 'Electrical',
//     'plumbing': 'Plumbing',
//     'landscaping': 'Landscaping',
//     'general': 'General',
//     'other': 'Other',
//   };

//   static const Map<String, String> _issueTypes = {
//     'preliminary': 'Preliminary',
//     'tender': 'Tender',
//     'construction': 'Construction',
//     'revised': 'Revised',
//     'as_built': 'As Built',
//     'other': 'Other',
//   };

//   static const String _filesGatewayBase = String.fromEnvironment(
//     'AQS_FILES_GATEWAY_URL',
//     defaultValue: 'https://aqssite-files-gateway.aqs-files.workers.dev',
//   );

//   static const String _uploadToken = String.fromEnvironment(
//     'AQS_FILES_UPLOAD_TOKEN',
//     defaultValue: 'NyamaChoma@2610',
//   );

//   int get _selectedCount {
//     return _pages.where((page) => page.selected).length;
//   }

//   int get _selectedPdfSizeBytes {
//     final selectedPages = _pages.where((page) => page.selected).toList();

//     if (selectedPages.isEmpty) {
//       return 0;
//     }

//     final selectedSize = selectedPages.fold<int>(
//       0,
//       (total, page) => total + page.displayPdfSizeBytes,
//     );

//     if (selectedSize > 0) {
//       return selectedSize;
//     }

//     return selectedPages.fold<int>(
//       0,
//       (total, page) => total + _estimatedSizeForPage(page),
//     );
//   }

//   int get _sourcePdfSizeBytes {
//     final pdfBytesSize = _pdfBytes?.lengthInBytes ?? 0;

//     if (pdfBytesSize > 0) {
//       return pdfBytesSize;
//     }

//     final selectedFileBytesSize = _selectedFile?.bytes?.lengthInBytes ?? 0;

//     if (selectedFileBytesSize > 0) {
//       return selectedFileBytesSize;
//     }

//     final selectedFileSize = _selectedFile?.size ?? 0;

//     return selectedFileSize > 0 ? selectedFileSize : 0;
//   }

//   int _estimatedSizeForPage(PendingDrawingPage page) {
//     if (page.displayPdfSizeBytes > 0) {
//       return page.displayPdfSizeBytes;
//     }

//     if (_pages.isEmpty) {
//       return 0;
//     }

//     final sourceBytes = _sourcePdfSizeBytes;

//     if (sourceBytes <= 0) {
//       return 0;
//     }

//     final basePageSize = sourceBytes ~/ _pages.length;
//     final remainder = sourceBytes % _pages.length;

//     return basePageSize + (page.pageIndex < remainder ? 1 : 0);
//   }

//   void _allocatePdfSizeToPages(
//     List<PendingDrawingPage> pages,
//     int sourceBytes,
//   ) {
//     if (pages.isEmpty || sourceBytes <= 0) {
//       return;
//     }

//     final hasUsableSizes = pages.any((page) => page.displayPdfSizeBytes > 0);

//     if (hasUsableSizes) {
//       return;
//     }

//     final basePageSize = sourceBytes ~/ pages.length;
//     var remainder = sourceBytes % pages.length;

//     for (final page in pages) {
//       page.estimatedPdfSizeBytes = basePageSize + (remainder > 0 ? 1 : 0);
//       page.pdfSizeBytes = null;

//       if (remainder > 0) {
//         remainder -= 1;
//       }
//     }
//   }

//   void _ensurePageSizeEstimates() {
//     _allocatePdfSizeToPages(_pages, _sourcePdfSizeBytes);
//   }

//   bool get _hasPdf {
//     return _selectedFile != null && _pdfBytes != null;
//   }

//   bool get _allSelected {
//     return _pages.isNotEmpty && _selectedCount == _pages.length;
//   }

//   @override
//   void dispose() {
//     _bundleNameController.dispose();
//     _revisionController.dispose();
//     _descriptionController.dispose();
//     _drawingSearchController.dispose();

//     super.dispose();
//   }

//   List<PendingDrawingPage> get _visiblePages {
//     final query = _drawingSearch.trim().toLowerCase();

//     if (query.isEmpty) {
//       return _pages;
//     }

//     return _pages.where((page) {
//       return page.sourcePageNumber.toString().contains(query) ||
//           page.drawingNumber.toLowerCase().contains(query) ||
//           page.title.toLowerCase().contains(query);
//     }).toList();
//   }

//   String get _fileSizeLabel {
//     final file = _selectedFile;

//     if (file == null) {
//       return '';
//     }

//     final bytes = _sourcePdfSizeBytes;

//     if (bytes < 1024) {
//       return '$bytes B';
//     }

//     if (bytes < 1024 * 1024) {
//       return '${(bytes / 1024).toStringAsFixed(1)} KB';
//     }

//     return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
//   }

//   void _reorderPages(int oldIndex, int newIndex) {
//     setState(() {
//       if (newIndex > oldIndex) {
//         newIndex -= 1;
//       }

//       final item = _pages.removeAt(oldIndex);

//       _pages.insert(newIndex, item);

//       for (var i = 0; i < _pages.length; i++) {
//         _pages[i].sortOrder = i + 1;
//       }
//       _storageEstimate = null;
//     });
//   }

//   Future<void> _prepareSelectedDrawings() async {
//     final bytes = _pdfBytes;

//     if (bytes == null) {
//       _showMessage('Select a PDF first.');

//       return;
//     }

//     final selectedCount = _pages.where((page) => page.selected).length;

//     if (selectedCount == 0) {
//       _showMessage('Select at least one drawing.');

//       return;
//     }

//     setState(() {
//       _preparingDrawings = true;
//       _storageEstimate = null;
//       _pauseThumbnails = true;
//     });

//     await Future<void>.delayed(const Duration(milliseconds: 50));

//     try {
//       final estimate = await DrawingPageExtractionService.instance
//           .prepareSelectedPages(sourcePdfBytes: bytes, pages: _pages);

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _storageEstimate = estimate;
//         final exactByPage = {
//           for (final drawing in estimate.drawings)
//             drawing.pageIndex: drawing.pdfSizeBytes,
//         };
//         for (final page in _pages) {
//           page.pdfSizeBytes = exactByPage[page.pageIndex];
//         }
//       });
//     } catch (error, stackTrace) {
//       debugPrint('Drawing preparation failed: $error');

//       debugPrint(stackTrace.toString());

//       if (!mounted) {
//         return;
//       }

//       _showMessage('Could not prepare selected drawings: $error');
//     } finally {
//       if (mounted) {
//         setState(() {
//           _preparingDrawings = false;
//           _pauseThumbnails = false;
//         });
//       }
//     }
//   }

//   String _formatBytes(int bytes) {
//     if (bytes <= 0) {
//       return '0 B';
//     }

//     const kb = 1024;
//     const mb = kb * 1024;
//     const gb = mb * 1024;

//     if (bytes >= gb) {
//       return '${(bytes / gb).toStringAsFixed(2)} GB';
//     }

//     if (bytes >= mb) {
//       return '${(bytes / mb).toStringAsFixed(2)} MB';
//     }

//     if (bytes >= kb) {
//       return '${(bytes / kb).toStringAsFixed(1)} KB';
//     }

//     return '$bytes B';
//   }

//   Future<void> _pickPdf() async {
//     if (_selectingFile || _inspectingPdf || _uploading) {
//       return;
//     }

//     setState(() {
//       _selectingFile = true;
//     });

//     try {
//       final result = await FilePicker.platform.pickFiles(
//         allowMultiple: false,
//         withData: true,
//         type: FileType.custom,
//         allowedExtensions: const ['pdf'],
//       );

//       if (result == null || result.files.isEmpty) {
//         return;
//       }

//       final file = result.files.single;

//       if (!file.name.toLowerCase().endsWith('.pdf')) {
//         throw Exception('Please select a PDF file.');
//       }

//       final bytes = file.bytes;

//       if (bytes == null) {
//         throw Exception('Could not read the selected PDF.');
//       }
//       setState(() {
//         _selectedFile = file;

//         _pdfBytes = bytes;

//         _pages.clear();

//         _storageEstimate = null;

//         _drawingSearch = '';

//         _uploadProgress = 0;
//       });

//       DrawingPageThumbnail.clearCache();

//       debugPrint('PDF SELECTED: ${file.name}');

//       debugPrint('PDF SIZE: ${bytes.lengthInBytes}');

//       await _inspectPdf();
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Could not open PDF: $error')));
//     } finally {
//       if (mounted) {
//         setState(() {
//           _selectingFile = false;
//         });
//       }
//     }
//   }

//   Future<void> _inspectPdf() async {
//     final bytes = _pdfBytes;

//     if (bytes == null || bytes.isEmpty) {
//       debugPrint('INSPECT PDF STOPPED: no bytes');
//       return;
//     }

//     debugPrint('INSPECT PDF STARTED: ${bytes.lengthInBytes} bytes');

//     setState(() {
//       _inspectingPdf = true;

//       //
//       // Do NOT clear _pages here if
//       // an existing PDF is already loaded.
//       //
//       _storageEstimate = null;
//     });

//     try {
//       List<PendingDrawingPage> pages;

//       try {
//         pages = await PdfDrawingService.instance
//             .inspectPdf(bytes)
//             .timeout(const Duration(seconds: 20));
//       } on TimeoutException {
//         debugPrint('Primary PDF inspection timed out. Trying fallback reader.');

//         pages = await PdfDrawingService.instance
//             .inspectPdfWithFallbackReader(bytes)
//             .timeout(const Duration(seconds: 20));
//       }

//       _allocatePdfSizeToPages(pages, bytes.lengthInBytes);

//       debugPrint('INSPECT PDF RESULT: ${pages.length} pages');

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _pages
//           ..clear()
//           ..addAll(pages);

//         _inspectingPdf = false;

//         _drawingSearch = '';
//       });

//       debugPrint('PAGES SAVED: ${_pages.length}');
//     } catch (error, stackTrace) {
//       debugPrint('INSPECT PDF ERROR: $error');

//       debugPrint(stackTrace.toString());

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _inspectingPdf = false;
//       });

//       _showMessage('Could not read drawing PDF: $error');
//     } finally {
//       if (mounted) {
//         setState(() {
//           _inspectingPdf = false;
//         });
//       }
//     }
//   }

//   void _selectAll() {
//     setState(() {
//       _ensurePageSizeEstimates();
//       for (final page in _pages) {
//         page.selected = true;
//       }
//       _storageEstimate = null;
//     });
//   }

//   void _unselectAll() {
//     setState(() {
//       _ensurePageSizeEstimates();
//       for (final page in _pages) {
//         page.selected = false;
//       }
//       _storageEstimate = null;
//     });
//   }

//   void _togglePage(PendingDrawingPage page, bool value) {
//     setState(() {
//       _ensurePageSizeEstimates();
//       page.selected = value;
//       _storageEstimate = null;
//     });
//   }

//   String _safeFileName(String name) {
//     return name
//         .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
//         .replaceAll(RegExp(r'_+'), '_');
//   }

//   Future<Map<String, dynamic>> _uploadBytesToR2({
//     required dio.Dio client,
//     required String key,
//     required Uint8List data,
//     required String contentType,
//     void Function(int sentBytes)? onProgress,
//   }) async {
//     final response = await client.put<String>(
//       '$_filesGatewayBase/upload/${Uri.encodeComponent(key)}',
//       data: data,
//       options: dio.Options(headers: {'Content-Type': contentType}),
//       onSendProgress: (sent, _) {
//         onProgress?.call(sent);
//       },
//     );

//     final raw = response.data ?? '';
//     final decoded =
//         raw.trim().isEmpty
//             ? <String, dynamic>{}
//             : jsonDecode(raw) as Map<String, dynamic>;

//     if (decoded['ok'] != true) {
//       throw Exception(
//         'R2 upload failed: ${decoded['error'] ?? response.statusMessage ?? 'Unknown error'}',
//       );
//     }

//     return decoded;
//   }

//   Future<void> _uploadBundle() async {
//     debugPrint('====================================');
//     debugPrint('UPLOAD BUTTON CLICKED');
//     debugPrint(
//       widget.isAppending
//           ? 'MODE: APPEND TO EXISTING BUNDLE'
//           : 'MODE: CREATE NEW BUNDLE',
//     );
//     debugPrint('====================================');

//     if (_uploading) {
//       debugPrint('STOP: upload already in progress');
//       return;
//     }

//     //
//     // ---------------------------------------------------------
//     // A. Validate bundle information
//     // ---------------------------------------------------------
//     //

//     final bundleName = _bundleNameController.text.trim();

//     if (!widget.isAppending && bundleName.isEmpty) {
//       debugPrint('STOP: bundle name is empty');

//       _showMessage('Enter the drawing bundle name.');

//       return;
//     }

//     //
//     // Existing bundle required in append mode.
//     //
//     if (widget.isAppending &&
//         (widget.bundleId == null || widget.bundleId!.trim().isEmpty)) {
//       debugPrint('STOP: append mode has no bundleId');

//       _showMessage('Existing drawing bundle could not be identified.');

//       return;
//     }

//     //
//     // ---------------------------------------------------------
//     // B. Validate PDF
//     // ---------------------------------------------------------
//     //

//     final file = _selectedFile;

//     final bytes = _pdfBytes;

//     if (file == null || bytes == null || bytes.isEmpty) {
//       debugPrint('STOP: PDF unavailable');

//       _showMessage('Select a drawing PDF first.');

//       return;
//     }

//     //
//     // ---------------------------------------------------------
//     // C. Validate pages
//     // ---------------------------------------------------------
//     //

//     if (_pages.isEmpty) {
//       debugPrint('STOP: no detected pages');

//       _showMessage('No drawing pages were detected.');

//       return;
//     }

//     _ensurePageSizeEstimates();

//     final selectedPages =
//         _pages.where((page) => page.selected).toList()
//           ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//     if (selectedPages.isEmpty) {
//       debugPrint('STOP: no selected pages');

//       _showMessage('Select at least one drawing page.');

//       return;
//     }

//     //
//     // ---------------------------------------------------------
//     // D. Validate R2 upload token
//     // ---------------------------------------------------------
//     //

//     if (_uploadToken.isEmpty) {
//       _showMessage(
//         'AQS_FILES_UPLOAD_TOKEN is missing. '
//         'R2 upload cannot start.',
//       );

//       return;
//     }

//     //
//     // ---------------------------------------------------------
//     // E. Enter uploading state
//     // ---------------------------------------------------------
//     //

//     setState(() {
//       _uploading = true;
//       _pauseThumbnails = true;
//       _uploadProgress = 0;
//     });

//     await Future<void>.delayed(const Duration(milliseconds: 100));

//     //
//     // Important:
//     //
//     // createdNewBundle tells catch() whether
//     // it is safe to mark the bundle failed.
//     //
//     bool createdNewBundle = false;

//     String? activeBundleId;

//     try {
//       //
//       // =========================================================
//       // STEP 1
//       // Prepare only selected pages
//       // =========================================================
//       //

//       debugPrint('STEP 1: preparing selected drawing PDFs...');

//       final preparedEstimate = await DrawingPageExtractionService.instance
//           .prepareSelectedPages(sourcePdfBytes: bytes, pages: _pages)
//           .timeout(
//             const Duration(minutes: 2),
//             onTimeout: () {
//               throw Exception('Timed out while preparing selected drawings.');
//             },
//           );

//       if (preparedEstimate.drawings.isEmpty) {
//         throw Exception('No selected drawing PDFs were prepared.');
//       }

//       final selectedUploadBytes = preparedEstimate.drawingPdfBytes;

//       if (mounted) {
//         setState(() {
//           _storageEstimate = preparedEstimate;

//           final exactByPage = {
//             for (final drawing in preparedEstimate.drawings)
//               drawing.pageIndex: drawing.pdfSizeBytes,
//           };

//           for (final page in _pages) {
//             page.pdfSizeBytes = exactByPage[page.pageIndex];
//           }

//           _uploadProgress = 0.02;
//         });
//       }

//       debugPrint(
//         'STEP 1 COMPLETE: '
//         '${preparedEstimate.drawingCount} drawings, '
//         '$selectedUploadBytes bytes',
//       );

//       //
//       // =========================================================
//       // STEP 2
//       // Resolve the bundle
//       // =========================================================
//       //

//       if (widget.isAppending) {
//         //
//         // Existing bundle.
//         //
//         activeBundleId = widget.bundleId!.trim();

//         debugPrint('STEP 2: using existing bundle');

//         debugPrint('Bundle ID: $activeBundleId');
//       } else {
//         //
//         // New bundle.
//         //
//         debugPrint('STEP 2: creating new drawing bundle...');

//         activeBundleId = await DrawingService.instance
//             .createDrawingBundle(
//               projectId: widget.projectId,

//               facilityId: widget.facilityId,

//               name: bundleName,

//               discipline: _discipline,

//               issueType: _issueType,

//               revision: _revisionController.text.trim(),

//               description: _descriptionController.text.trim(),

//               fileName: file.name,

//               storagePath: '',

//               //
//               // For a new bundle these represent
//               // the first uploaded source.
//               //
//               pageCount: selectedPages.length,

//               originalSizeBytes: bytes.lengthInBytes,

//               selectedSizeBytes: selectedUploadBytes,

//               status: 'uploading',
//             )
//             .timeout(
//               const Duration(seconds: 30),
//               onTimeout: () {
//                 throw Exception('Timed out while creating the drawing bundle.');
//               },
//             );

//         createdNewBundle = true;

//         debugPrint(
//           'STEP 2 COMPLETE: '
//           '$activeBundleId',
//         );
//       }

//       if (activeBundleId == null || activeBundleId!.isEmpty) {
//         throw Exception('Drawing bundle could not be resolved.');
//       }

//       final bundleId = activeBundleId!;

//       //
//       // =========================================================
//       // STEP 3
//       // Upload selected drawings to Cloudflare R2
//       // =========================================================
//       //

//       final cleanSourceFileName = _safeFileName(file.name);

//       final r2Folder =
//           'projects/'
//           '${widget.projectId}/'
//           'facilities/'
//           '${widget.facilityId}/'
//           'drawingBundles/'
//           '$bundleId';

//       debugPrint('STEP 3: uploading selected drawings to R2');

//       debugPrint('R2 folder: $r2Folder');

//       debugPrint(
//         'Selected upload size: '
//         '${(selectedUploadBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
//       );

//       final client = dio.Dio(
//         dio.BaseOptions(
//           headers: {'Authorization': 'Bearer $_uploadToken'},

//           responseType: dio.ResponseType.plain,

//           validateStatus: (status) {
//             return status != null && status >= 200 && status < 300;
//           },
//         ),
//       );

//       final pdfPathByPageIndex = <int, String>{};

//       final downloadUrlByPageIndex = <int, String>{};

//       var uploadedBytesBeforeCurrentFile = 0;

//       void reportSelectedByteProgress(int currentFileSentBytes) {
//         if (!mounted || selectedUploadBytes <= 0) {
//           return;
//         }

//         final transferred =
//             uploadedBytesBeforeCurrentFile + currentFileSentBytes;

//         //
//         // Reserve approximately first 5%
//         // for preparation / Firestore.
//         //
//         final byteProgress = (transferred / selectedUploadBytes).clamp(
//           0.0,
//           1.0,
//         );

//         final overallProgress = 0.05 + (byteProgress * 0.85);

//         setState(() {
//           _uploadProgress = overallProgress.clamp(0.0, 0.90);
//         });
//       }

//       for (var index = 0; index < preparedEstimate.drawings.length; index++) {
//         final drawing = preparedEstimate.drawings[index];

//         final pageNumber = drawing.sourcePageNumber.toString().padLeft(3, '0');

//         //
//         // Prefer drawing number in filename.
//         //
//         final identity =
//             drawing.drawingNumber.trim().isNotEmpty
//                 ? drawing.drawingNumber.trim()
//                 : drawing.title.trim().isNotEmpty
//                 ? drawing.title.trim()
//                 : 'page_$pageNumber';

//         final cleanIdentity = _safeFileName(identity);

//         //
//         // Include timestamp so adding another
//         // drawing/revision cannot accidentally
//         // overwrite an existing R2 object.
//         //
//         final uploadStamp = DateTime.now().microsecondsSinceEpoch;

//         final key =
//             '$r2Folder/'
//             'drawings/'
//             '${uploadStamp}_'
//             'page_$pageNumber-'
//             '$cleanIdentity.pdf';

//         debugPrint(
//           'Uploading '
//           '${index + 1}/'
//           '${preparedEstimate.drawings.length}: '
//           '$key',
//         );

//         final uploadResult = await _uploadBytesToR2(
//           client: client,

//           key: key,

//           data: drawing.pdfBytes,

//           contentType: 'application/pdf',

//           onProgress: reportSelectedByteProgress,
//         ).timeout(
//           const Duration(minutes: 3),
//           onTimeout: () {
//             throw Exception(
//               'Timed out while uploading '
//               'drawing page '
//               '${drawing.sourcePageNumber}.',
//             );
//           },
//         );

//         final url = (uploadResult['url'] as String?)?.trim();

//         if (url == null || url.isEmpty) {
//           throw Exception(
//             'R2 upload succeeded but no '
//             'download URL was returned for '
//             'page ${drawing.sourcePageNumber}.',
//           );
//         }

//         pdfPathByPageIndex[drawing.pageIndex] = key;

//         downloadUrlByPageIndex[drawing.pageIndex] = url;

//         uploadedBytesBeforeCurrentFile += drawing.pdfSizeBytes;

//         reportSelectedByteProgress(0);
//       }

//       debugPrint('STEP 3 COMPLETE');

//       //
//       // =========================================================
//       // STEP 4
//       // Update NEW bundle to processing.
//       //
//       // Existing bundle should remain usable while additional
//       // drawings are being committed.
//       // =========================================================
//       //

//       if (!widget.isAppending) {
//         debugPrint('STEP 4: updating new bundle...');

//         await DrawingService.instance.updateBundle(
//           projectId: widget.projectId,

//           facilityId: widget.facilityId,

//           bundleId: bundleId,

//           storagePath: r2Folder,

//           pageCount: selectedPages.length,

//           originalSizeBytes: bytes.lengthInBytes,

//           selectedSizeBytes: selectedUploadBytes,

//           status: 'processing',
//         );

//         debugPrint('STEP 4 COMPLETE');
//       } else {
//         debugPrint(
//           'STEP 4: existing bundle - '
//           'no status change required',
//         );
//       }

//       if (mounted) {
//         setState(() {
//           _uploadProgress = 0.92;
//         });
//       }

//       //
//       // =========================================================
//       // STEP 5
//       // Create DrawingSheet documents
//       // =========================================================
//       //

//       debugPrint(
//         'STEP 5: creating '
//         '${selectedPages.length} drawing records...',
//       );

//       final createdDrawingIds = await DrawingService.instance
//           .createDrawingSheetsBatch(
//             projectId: widget.projectId,

//             facilityId: widget.facilityId,

//             bundleId: bundleId,

//             discipline: _discipline,

//             revision: _revisionController.text.trim(),

//             sourceFileName: file.name,

//             pdfPath: r2Folder,

//             pdfPathByPageIndex: pdfPathByPageIndex,

//             downloadUrlByPageIndex: downloadUrlByPageIndex,

//             storageProvider: 'r2',

//             pages: _pages,
//           )
//           .timeout(
//             const Duration(seconds: 60),
//             onTimeout: () {
//               throw Exception('Timed out while creating drawing records.');
//             },
//           );

//       debugPrint(
//         'STEP 5 COMPLETE: '
//         '${createdDrawingIds.length} records created',
//       );

//       if (mounted) {
//         setState(() {
//           _uploadProgress = 0.97;
//         });
//       }

//       //
//       // =========================================================
//       // STEP 6
//       // Finalise / increment bundle
//       // =========================================================
//       //

//       if (widget.isAppending) {
//         debugPrint('STEP 6: incrementing existing bundle totals...');

//         await DrawingService.instance.incrementBundleDrawings(
//           projectId: widget.projectId,

//           facilityId: widget.facilityId,

//           bundleId: bundleId,

//           addedDrawings: createdDrawingIds.length,

//           addedOriginalBytes: bytes.lengthInBytes,

//           addedSelectedBytes: selectedUploadBytes,

//           addedStorageBytes: selectedUploadBytes,
//         );

//         debugPrint(
//           'STEP 6 COMPLETE: '
//           'existing bundle updated',
//         );
//       } else {
//         debugPrint('STEP 6: finalising new bundle...');

//         await DrawingService.instance.updateBundle(
//           projectId: widget.projectId,

//           facilityId: widget.facilityId,

//           bundleId: bundleId,

//           storagePath: r2Folder,

//           pageCount: createdDrawingIds.length,

//           selectedPageCount: createdDrawingIds.length,

//           originalSizeBytes: bytes.lengthInBytes,

//           selectedSizeBytes: selectedUploadBytes,

//           storageBytes: selectedUploadBytes,

//           status: 'ready',
//         );

//         debugPrint(
//           'STEP 6 COMPLETE: '
//           'new bundle ready',
//         );
//       }

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _uploadProgress = 1.0;
//       });

//       debugPrint('====================================');

//       debugPrint(
//         widget.isAppending
//             ? 'DRAWINGS ADDED SUCCESSFULLY'
//             : 'BUNDLE UPLOAD COMPLETE',
//       );

//       debugPrint('Bundle: $bundleId');

//       debugPrint('New drawings: ${createdDrawingIds.length}');

//       debugPrint('====================================');

//       //
//       // =========================================================
//       // STEP 7
//       // Open this bundle's Drawing Register
//       // =========================================================
//       //

//       Get.offNamed(
//         AppRoutes.drawingRegister,
//         parameters: {
//           'projectId': widget.projectId,

//           'facilityId': widget.facilityId,

//           'facilityName': widget.facilityName,

//           'bundleId': bundleId,
//         },
//       );
//     } catch (error, stackTrace) {
//       debugPrint('====================================');

//       debugPrint('DRAWING UPLOAD ERROR');

//       debugPrint('$error');

//       debugPrint(stackTrace.toString());

//       debugPrint('====================================');

//       //
//       // CRITICAL:
//       //
//       // Only mark a bundle failed if THIS upload
//       // created that bundle.
//       //
//       // Never mark an existing bundle failed merely
//       // because adding additional drawings failed.
//       //
//       if (createdNewBundle && activeBundleId != null) {
//         try {
//           debugPrint('Marking newly-created bundle failed...');

//           await DrawingService.instance.markBundleFailed(
//             projectId: widget.projectId,

//             facilityId: widget.facilityId,

//             bundleId: activeBundleId!,
//           );

//           debugPrint('New bundle marked failed.');
//         } catch (markError) {
//           debugPrint(
//             'Could not mark bundle failed: '
//             '$markError',
//           );
//         }
//       } else if (widget.isAppending) {
//         debugPrint(
//           'Append failed, but existing bundle '
//           'was left unchanged.',
//         );
//       }

//       if (!mounted) {
//         return;
//       }

//       _showMessage(
//         widget.isAppending
//             ? 'Could not add drawings: $error'
//             : 'Drawing upload failed: $error',
//       );
//     } finally {
//       debugPrint('UPLOAD FINALLY');

//       if (mounted) {
//         setState(() {
//           _uploading = false;

//           _pauseThumbnails = false;
//         });
//       }
//     }
//   }

//   // Future<void> _uploadBundle() async {
//   //   debugPrint('====================================');
//   //   debugPrint('UPLOAD BUTTON CLICKED');
//   //   debugPrint('====================================');

//   //   if (_uploading) {
//   //     debugPrint('STOP: upload already in progress');
//   //     return;
//   //   }

//   //   debugPrint('STEP A: validating bundle information...');

//   //   final bundleName = _bundleNameController.text.trim();

//   //   if (bundleName.isEmpty) {
//   //     debugPrint('STOP: bundle name is empty');

//   //     _showMessage('Enter the drawing bundle name.');

//   //     return;
//   //   }

//   //   debugPrint('STEP A COMPLETE: bundle information valid');

//   //   //
//   //   // 2. Validate PDF
//   //   //
//   //   debugPrint('STEP B: checking selected PDF...');

//   //   final file = _selectedFile;

//   //   final bytes = _pdfBytes;

//   //   debugPrint('Selected file: ${file?.name}');

//   //   debugPrint('PDF bytes available: ${bytes != null}');

//   //   debugPrint('PDF bytes length: ${bytes?.length ?? 0}');

//   //   if (file == null || bytes == null) {
//   //     debugPrint('STOP: PDF unavailable');

//   //     _showMessage('Select a drawing PDF first.');

//   //     return;
//   //   }

//   //   //
//   //   // 3. Validate detected pages
//   //   //
//   //   debugPrint('STEP C: checking drawing pages...');

//   //   debugPrint('Detected pages: ${_pages.length}');

//   //   if (_pages.isEmpty) {
//   //     debugPrint('STOP: no detected pages');

//   //     _showMessage('No drawing pages were detected.');

//   //     return;
//   //   }

//   //   _ensurePageSizeEstimates();

//   //   final selectedPages =
//   //       _pages.where((page) => page.selected).toList()
//   //         ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//   //   debugPrint('Selected pages: ${selectedPages.length}');

//   //   if (selectedPages.isEmpty) {
//   //     debugPrint('STOP: no selected pages');

//   //     _showMessage('Select at least one drawing page.');

//   //     return;
//   //   }

//   //   //
//   //   // 4. Enter uploading state
//   //   //
//   //   debugPrint('STEP D: entering upload state...');

//   //   setState(() {
//   //     _uploading = true;

//   //     _pauseThumbnails = true;

//   //     _uploadProgress = 0;
//   //   });

//   //   //
//   //   // Give browser time to repaint.
//   //   //
//   //   await Future<void>.delayed(const Duration(milliseconds: 100));

//   //   debugPrint('STEP D COMPLETE');

//   //   String? bundleId;

//   //   try {
//   //     //
//   //     // 5. Prepare only selected drawing pages.
//   //     //
//   //     if (_uploadToken.isEmpty) {
//   //       throw Exception(
//   //         'AQS_FILES_UPLOAD_TOKEN is missing. ToR2 upload cannot start.',
//   //       );
//   //     }

//   //     debugPrint('STEP 1: preparing selected drawing PDFs...');

//   //     final preparedEstimate = await DrawingPageExtractionService.instance
//   //         .prepareSelectedPages(sourcePdfBytes: bytes, pages: _pages)
//   //         .timeout(
//   //           const Duration(minutes: 2),
//   //           onTimeout: () {
//   //             throw Exception('Timed out while preparing selected drawings.');
//   //           },
//   //         );

//   //     if (preparedEstimate.drawings.isEmpty) {
//   //       throw Exception('No selected drawing PDFs were prepared.');
//   //     }

//   //     setState(() {
//   //       _storageEstimate = preparedEstimate;

//   //       final exactByPage = {
//   //         for (final drawing in preparedEstimate.drawings)
//   //           drawing.pageIndex: drawing.pdfSizeBytes,
//   //       };

//   //       for (final page in _pages) {
//   //         page.pdfSizeBytes = exactByPage[page.pageIndex];
//   //       }

//   //       _uploadProgress = 0.02;
//   //     });

//   //     final selectedUploadBytes = preparedEstimate.drawingPdfBytes;

//   //     debugPrint(
//   //       'STEP 1 COMPLETE: prepared '
//   //       '${preparedEstimate.drawingCount} drawings, '
//   //       '$selectedUploadBytes bytes',
//   //     );

//   //     //
//   //     // 6. Create Firestore bundle
//   //     //
//   //     debugPrint('STEP 2: creating drawing bundle...');

//   //     bundleId = await DrawingService.instance
//   //         .createDrawingBundle(
//   //           projectId: widget.projectId,

//   //           facilityId: widget.facilityId,

//   //           name: _bundleNameController.text.trim(),

//   //           discipline: _discipline,

//   //           issueType: _issueType,

//   //           revision: _revisionController.text.trim(),

//   //           description: _descriptionController.text.trim(),

//   //           fileName: file.name,

//   //           storagePath: '',

//   //           pageCount: selectedPages.length,

//   //           originalSizeBytes: bytes.lengthInBytes,

//   //           selectedSizeBytes: selectedUploadBytes,

//   //           status: 'uploading',
//   //         )
//   //         .timeout(
//   //           const Duration(seconds: 30),
//   //           onTimeout: () {
//   //             throw Exception('Timed out while creating the drawing bundle.');
//   //           },
//   //         );

//   //     debugPrint('STEP 2 COMPLETE');

//   //     debugPrint('Bundle ID: $bundleId');

//   //     //
//   //     // 7. Upload selected page PDFs to ToR2.
//   //     //
//   //     final cleanFileName = _safeFileName(file.name);

//   //     final r2Folder =
//   //         'projects/'
//   //         '${widget.projectId}/'
//   //         'facilities/'
//   //         '${widget.facilityId}/'
//   //         'drawingBundles/'
//   //         '$bundleId';

//   //     debugPrint('STEP 3: starting ToR2 selected drawing upload');

//   //     debugPrint('R2 folder: $r2Folder');

//   //     debugPrint(
//   //       'Selected upload size: '
//   //       '${(selectedUploadBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
//   //     );

//   //     final client = dio.Dio(
//   //       dio.BaseOptions(
//   //         headers: {'Authorization': 'Bearer $_uploadToken'},
//   //         responseType: dio.ResponseType.plain,
//   //         validateStatus: (status) {
//   //           return status != null && status >= 200 && status < 300;
//   //         },
//   //       ),
//   //     );

//   //     final pdfPathByPageIndex = <int, String>{};
//   //     final downloadUrlByPageIndex = <int, String>{};
//   //     var uploadedBytesBeforeCurrentFile = 0;

//   //     void reportSelectedByteProgress(int currentFileSentBytes) {
//   //       if (!mounted || selectedUploadBytes <= 0) {
//   //         return;
//   //       }

//   //       final transferred =
//   //           uploadedBytesBeforeCurrentFile + currentFileSentBytes;
//   //       final progress = (transferred / selectedUploadBytes).clamp(0.0, 1.0);

//   //       setState(() {
//   //         _uploadProgress = progress.toDouble();
//   //       });
//   //     }

//   //     for (final drawing in preparedEstimate.drawings) {
//   //       final pageNumber = drawing.sourcePageNumber.toString().padLeft(3, '0');
//   //       final key =
//   //           '$r2Folder/drawings/page_$pageNumber-${_safeFileName(drawing.title.isEmpty ? cleanFileName : drawing.title)}.pdf';

//   //       final uploadResult = await _uploadBytesToR2(
//   //         client: client,
//   //         key: key,
//   //         data: drawing.pdfBytes,
//   //         contentType: 'application/pdf',
//   //         onProgress: reportSelectedByteProgress,
//   //       ).timeout(
//   //         const Duration(minutes: 3),
//   //         onTimeout: () {
//   //           throw Exception(
//   //             'Timed out while uploading drawing page ${drawing.sourcePageNumber}.',
//   //           );
//   //         },
//   //       );

//   //       final url = (uploadResult['url'] as String?)?.trim();

//   //       if (url == null || url.isEmpty) {
//   //         throw Exception(
//   //           'ToR2 upload succeeded but no URL was returned for page ${drawing.sourcePageNumber}.',
//   //         );
//   //       }

//   //       pdfPathByPageIndex[drawing.pageIndex] = key;
//   //       downloadUrlByPageIndex[drawing.pageIndex] = url;
//   //       uploadedBytesBeforeCurrentFile += drawing.pdfSizeBytes;
//   //       reportSelectedByteProgress(0);
//   //     }

//   //     debugPrint('STEP 3 COMPLETE: selected drawing PDFs uploaded');

//   //     //
//   //     // 8. Update bundle with ToR2 folder
//   //     //
//   //     debugPrint('STEP 4: updating bundle...');

//   //     await DrawingService.instance.updateBundle(
//   //       projectId: widget.projectId,

//   //       facilityId: widget.facilityId,

//   //       bundleId: bundleId,

//   //       storagePath: r2Folder,

//   //       pageCount: selectedPages.length,

//   //       originalSizeBytes: bytes.lengthInBytes,

//   //       selectedSizeBytes: selectedUploadBytes,

//   //       status: 'processing',
//   //     );

//   //     debugPrint('STEP 4 COMPLETE');

//   //     //
//   //     // 9. Create selected DrawingSheet documents
//   //     //
//   //     debugPrint(
//   //       'STEP 5: creating '
//   //       '${selectedPages.length} drawing sheets...',
//   //     );

//   //     final createdDrawingIds = await DrawingService.instance
//   //         .createDrawingSheetsBatch(
//   //           projectId: widget.projectId,

//   //           facilityId: widget.facilityId,

//   //           bundleId: bundleId,

//   //           discipline: _discipline,

//   //           revision: _revisionController.text.trim(),

//   //           sourceFileName: file.name,

//   //           pdfPath: r2Folder,

//   //           pdfPathByPageIndex: pdfPathByPageIndex,

//   //           downloadUrlByPageIndex: downloadUrlByPageIndex,

//   //           storageProvider: 'r2',

//   //           pages: _pages,
//   //         )
//   //         .timeout(
//   //           const Duration(seconds: 60),
//   //           onTimeout: () {
//   //             throw Exception('Timed out while creating drawing records.');
//   //           },
//   //         );

//   //     debugPrint(
//   //       'STEP 5 COMPLETE: '
//   //       '${createdDrawingIds.length} records created',
//   //     );

//   //     //
//   //     // 10. Finalise bundle
//   //     //
//   //     debugPrint('STEP 6: finalising bundle...');

//   //     await DrawingService.instance.updateBundle(
//   //       projectId: widget.projectId,

//   //       facilityId: widget.facilityId,

//   //       bundleId: bundleId,

//   //       pageCount: selectedPages.length,

//   //       selectedPageCount: selectedPages.length,

//   //       originalSizeBytes: bytes.lengthInBytes,

//   //       selectedSizeBytes: selectedUploadBytes,

//   //       storageBytes: selectedUploadBytes,

//   //       status: 'ready',
//   //     );

//   //     debugPrint('STEP 6 COMPLETE');

//   //     //
//   //     // markBundleReady() is actually redundant
//   //     // because updateBundle above already sets ready.
//   //     //
//   //     // So we do NOT call it again.
//   //     //

//   //     if (!mounted) {
//   //       debugPrint('STOP: widget no longer mounted');

//   //       return;
//   //     }

//   //     debugPrint('UPLOAD COMPLETE');

//   //     debugPrint('Opening Drawing Register...');

//   //     Get.offNamed(
//   //       AppRoutes.drawingRegister,
//   //       parameters: {
//   //         'projectId': widget.projectId,

//   //         'facilityId': widget.facilityId,

//   //         'facilityName': widget.facilityName,

//   //         'bundleId': bundleId,
//   //       },
//   //     );
//   //   } catch (error, stackTrace) {
//   //     debugPrint('====================================');

//   //     debugPrint('DRAWING UPLOAD ERROR');

//   //     debugPrint('$error');

//   //     debugPrint(stackTrace.toString());

//   //     debugPrint('====================================');

//   //     if (bundleId != null) {
//   //       try {
//   //         debugPrint('Marking bundle failed...');

//   //         await DrawingService.instance.markBundleFailed(
//   //           projectId: widget.projectId,

//   //           facilityId: widget.facilityId,

//   //           bundleId: bundleId,
//   //         );

//   //         debugPrint('Bundle marked failed.');
//   //       } catch (markError) {
//   //         debugPrint(
//   //           'Could not mark bundle failed: '
//   //           '$markError',
//   //         );
//   //       }
//   //     }

//   //     if (!mounted) {
//   //       return;
//   //     }

//   //     _showMessage('Drawing upload failed: $error');
//   //   } finally {
//   //     debugPrint('UPLOAD FINALLY');

//   //     if (mounted) {
//   //       setState(() {
//   //         _uploading = false;

//   //         _pauseThumbnails = false;
//   //       });
//   //     }
//   //   }
//   // }
//   // Future<void> _uploadBundle() async {
//   //   if (_uploading) {
//   //     return;
//   //   }
//   //   debugPrint('UPLOAD BUTTON CLICKED');

//   //   if (!(_formKey.currentState?.validate() ?? false)) {
//   //     return;
//   //   }

//   //   final file = _selectedFile;

//   //   final bytes = _pdfBytes;

//   //   if (file == null || bytes == null) {
//   //     _showMessage('Select a drawing PDF first.');

//   //     return;
//   //   }

//   //   if (_pages.isEmpty) {
//   //     _showMessage('No drawing pages were detected.');

//   //     return;
//   //   }

//   //   final selectedPages =
//   //       _pages.where((page) => page.selected).toList()
//   //         ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//   //   if (selectedPages.isEmpty) {
//   //     _showMessage('Select at least one drawing page.');

//   //     return;
//   //   }

//   //   setState(() {
//   //     _uploading = true;
//   //     _pauseThumbnails = true;
//   //     _uploadProgress = 0;
//   //   });

//   //   await Future<void>.delayed(const Duration(milliseconds: 50));

//   //   String? bundleId;

//   //   try {
//   //     //
//   //     // 1. Create drawing bundle
//   //     //
//   //     bundleId = await DrawingService.instance.createDrawingBundle(
//   //       projectId: widget.projectId,
//   //       facilityId: widget.facilityId,
//   //       name: _bundleNameController.text.trim(),
//   //       discipline: _discipline,
//   //       issueType: _issueType,
//   //       revision: _revisionController.text.trim(),
//   //       description: _descriptionController.text.trim(),
//   //       fileName: file.name,
//   //       storagePath: '',
//   //       pageCount: _pages.length,
//   //       status: 'uploading',
//   //     );

//   //     //
//   //     // 2. Upload original PDF
//   //     //
//   //     final cleanFileName = _safeFileName(file.name);

//   //     final storagePath =
//   //         'projects/'
//   //         '${widget.projectId}/'
//   //         'facilities/'
//   //         '${widget.facilityId}/'
//   //         'drawingBundles/'
//   //         '$bundleId/'
//   //         '$cleanFileName';

//   //     final storageRef = FirebaseStorage.instance.ref(storagePath);

//   //     final uploadTask = storageRef.putData(
//   //       bytes,
//   //       SettableMetadata(
//   //         contentType: 'application/pdf',
//   //         customMetadata: {
//   //           'projectId': widget.projectId,
//   //           'facilityId': widget.facilityId,
//   //           'bundleId': bundleId,
//   //           'discipline': _discipline,
//   //         },
//   //       ),
//   //     );

//   //     uploadTask.snapshotEvents.listen((snapshot) {
//   //       if (!mounted) {
//   //         return;
//   //       }

//   //       if (snapshot.totalBytes <= 0) {
//   //         return;
//   //       }

//   //       setState(() {
//   //         _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
//   //       });
//   //     });

//   //     await uploadTask;

//   //     //
//   //     // 3. Update bundle
//   //     //
//   //     await DrawingService.instance.updateBundle(
//   //       projectId: widget.projectId,
//   //       facilityId: widget.facilityId,
//   //       bundleId: bundleId,
//   //       storagePath: storagePath,
//   //       pageCount: _pages.length,
//   //       status: 'processing',
//   //     );

//   //     //
//   //     // 4. Create DrawingSheet records
//   //     //

//   //     await DrawingService.instance.createDrawingSheetsBatch(
//   //       projectId: widget.projectId,

//   //       facilityId: widget.facilityId,

//   //       bundleId: bundleId,

//   //       discipline: _discipline,

//   //       revision: _revisionController.text.trim(),

//   //       sourceFileName: file.name,

//   //       pdfPath: storagePath,

//   //       pages: _pages,
//   //     );

//   //     await DrawingService.instance.updateBundle(
//   //       projectId: widget.projectId,

//   //       facilityId: widget.facilityId,

//   //       bundleId: bundleId,

//   //       pageCount: _pages.length,

//   //       selectedPageCount: selectedPages.length,

//   //       status: 'ready',
//   //     );

//   //     //
//   //     // 5. Bundle ready
//   //     //
//   //     await DrawingService.instance.markBundleReady(
//   //       projectId: widget.projectId,
//   //       facilityId: widget.facilityId,
//   //       bundleId: bundleId,
//   //       pageCount: _pages.length,
//   //     );

//   //     if (!mounted) {
//   //       return;
//   //     }
//   //     Get.offNamed(
//   //       AppRoutes.drawingRegister,
//   //       parameters: {
//   //         'projectId': widget.projectId,
//   //         'facilityId': widget.facilityId,
//   //         'facilityName': widget.facilityName,
//   //         'bundleId': bundleId,
//   //       },
//   //     );

//   //     // await _showSuccessDialog(
//   //     //   uploadedCount: selectedPages.length,
//   //     //   totalPages: _pages.length,
//   //     //   bundleId: bundleId,
//   //     // );
//   //   } catch (error) {
//   //     if (bundleId != null) {
//   //       try {
//   //         await DrawingService.instance.markBundleFailed(
//   //           projectId: widget.projectId,
//   //           facilityId: widget.facilityId,
//   //           bundleId: bundleId,
//   //         );
//   //       } catch (_) {}
//   //     }

//   //     if (!mounted) {
//   //       return;
//   //     }

//   //     _showMessage('Drawing upload failed: $error');
//   //   } finally {
//   //     if (mounted) {
//   //       setState(() {
//   //         _uploading = false;
//   //         _pauseThumbnails = false;
//   //       });
//   //     }
//   //   }
//   // }

//   Future<void> _showBulkNumberingDialog() async {
//     final prefixController = TextEditingController(
//       text:
//           _discipline == 'architectural'
//               ? 'A-'
//               : _discipline == 'structural'
//               ? 'S-'
//               : _discipline == 'civil'
//               ? 'C-'
//               : '',
//     );

//     final startController = TextEditingController(text: '001');

//     final result = await showDialog<_BulkNumberingResult>(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: const Text('Bulk Drawing Numbering'),
//           content: SizedBox(
//             width: 450,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Text(
//                   'Automatically number all selected drawings in their current register order.',
//                   style: TextStyle(color: AqsColors.muted, height: 1.4),
//                 ),

//                 const SizedBox(height: 18),

//                 Row(
//                   children: [
//                     Expanded(
//                       child: TextField(
//                         controller: prefixController,
//                         decoration: const InputDecoration(
//                           labelText: 'Prefix',
//                           hintText: 'A-',
//                           border: OutlineInputBorder(),
//                         ),
//                       ),
//                     ),

//                     const SizedBox(width: 12),

//                     Expanded(
//                       child: TextField(
//                         controller: startController,
//                         keyboardType: TextInputType.number,
//                         decoration: const InputDecoration(
//                           labelText: 'Start Number',
//                           hintText: '001',
//                           border: OutlineInputBorder(),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),

//                 const SizedBox(height: 14),

//                 Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.all(14),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFFF9FAFB),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: const Text(
//                     'Example: A-001, A-002, A-003...',
//                     style: TextStyle(color: AqsColors.muted, fontSize: 12),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.of(context).pop();
//               },
//               child: const Text('Cancel'),
//             ),

//             FilledButton(
//               onPressed: () {
//                 final startText = startController.text.trim();

//                 final start = int.tryParse(startText);

//                 if (start == null || start < 0) {
//                   return;
//                 }

//                 Navigator.of(context).pop(
//                   _BulkNumberingResult(
//                     prefix: prefixController.text,
//                     start: start,
//                     digits: startText.length,
//                   ),
//                 );
//               },
//               child: const Text('Apply'),
//             ),
//           ],
//         );
//       },
//     );

//     prefixController.dispose();
//     startController.dispose();

//     if (result == null) {
//       return;
//     }

//     _applyBulkNumbering(result);
//   }

//   void _applyBulkNumbering(_BulkNumberingResult settings) {
//     final selected =
//         _pages.where((page) => page.selected).toList()
//           ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//     var number = settings.start;

//     setState(() {
//       for (final page in selected) {
//         final padded = number.toString().padLeft(settings.digits, '0');

//         page.drawingNumber = '${settings.prefix}$padded';

//         number++;
//       }
//     });
//   }

//   void _showMessage(String message) {
//     ScaffoldMessenger.of(
//       context,
//     ).showSnackBar(SnackBar(content: Text(message)));
//   }

//   Future<void> _showSuccessDialog({
//     required int uploadedCount,
//     required int totalPages,
//     required String bundleId,
//   }) async {
//     await showDialog<void>(
//       context: context,
//       barrierDismissible: false,
//       builder: (dialogContext) {
//         return AlertDialog(
//           title: const Row(
//             children: [
//               Icon(Icons.check_circle_rounded, color: Color(0xFF039855)),

//               SizedBox(width: 10),

//               Text('Drawing bundle ready'),
//             ],
//           ),
//           content: Text(
//             '$uploadedCount drawing '
//             '${uploadedCount == 1 ? 'sheet' : 'sheets'} '
//             'were selected from $totalPages PDF pages '
//             'and added to the facility drawing register.',
//           ),
//           actions: [
//             FilledButton(
//               onPressed: () {
//                 Navigator.of(dialogContext).pop();

//                 Get.offNamed(
//                   AppRoutes.drawingRegister,
//                   parameters: {
//                     'projectId': widget.projectId,

//                     'facilityId': widget.facilityId,

//                     'facilityName': widget.facilityName,

//                     'bundleId': bundleId,
//                   },
//                 );
//               },
//               child: const Text('Done'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   void _updateDrawingNumber(PendingDrawingPage page, String value) {
//     page.drawingNumber = value.trim();
//   }

//   void _updateDrawingTitle(PendingDrawingPage page, String value) {
//     page.title = value.trim();
//   }

//   @override
//   Widget build(BuildContext context) {
//     debugPrint(
//       'BUILD => '
//       'pdf=${_pdfBytes != null}, '
//       'inspecting=$_inspectingPdf, '
//       'pages=${_pages.length}, '
//       'visible=${_visiblePages.length}, '
//       'storage=${_storageEstimate != null}',
//     );
//     return Scaffold(
//       backgroundColor: AqsColors.canvas,
//       appBar: AppBar(title: const Text('Upload Drawing Bundle')),
//       body: Center(
//         child: ConstrainedBox(
//           constraints: const BoxConstraints(maxWidth: 1200),
//           child: ListView(
//             padding: const EdgeInsets.fromLTRB(24, 28, 24, 60),
//             children: [
//               _PageHeader(facilityName: widget.facilityName),

//               const SizedBox(height: 24),

//               _ExistingDrawingsCard(
//                 projectId: widget.projectId,
//                 facilityId: widget.facilityId,
//                 facilityName: widget.facilityName,
//               ),

//               const SizedBox(height: 22),

//               _PdfPickerCard(
//                 file: _selectedFile,
//                 fileSize: _fileSizeLabel,
//                 selecting: _selectingFile,
//                 inspecting: _inspectingPdf,
//                 uploading: _uploading,
//                 uploadProgress: _uploadProgress,
//                 onPick: _pickPdf,
//               ),

//               const SizedBox(height: 22),

//               Form(
//                 key: _formKey,
//                 child:
//                     _loadingExistingBundle
//                         ? const Padding(
//                           padding: EdgeInsets.symmetric(vertical: 24),
//                           child: Center(child: CircularProgressIndicator()),
//                         )
//                         : _BundleInformationCard(
//                           bundleNameController: _bundleNameController,

//                           revisionController: _revisionController,

//                           descriptionController: _descriptionController,

//                           discipline: _discipline,

//                           issueType: _issueType,

//                           disciplines: _disciplines,

//                           issueTypes: _issueTypes,

//                           enabled: !_uploading,

//                           isAppending: widget.isAppending,

//                           onDisciplineChanged: (value) {
//                             if (value == null) {
//                               return;
//                             }

//                             setState(() {
//                               _discipline = value;
//                             });
//                           },

//                           onIssueTypeChanged: (value) {
//                             if (value == null) {
//                               return;
//                             }

//                             setState(() {
//                               _issueType = value;
//                             });
//                           },
//                         ),
//               ),

//               if (_inspectingPdf) ...[
//                 const SizedBox(height: 24),

//                 const _InspectingCard(),
//               ],

//               if (!_inspectingPdf && _pages.isNotEmpty) ...[
//                 const SizedBox(height: 26),

//                 _DrawingSelectionHeader(
//                   totalCount: _pages.length,
//                   selectedCount: _selectedCount,
//                   selectedSizeLabel: _formatBytes(_selectedPdfSizeBytes),
//                   allSelected: _allSelected,
//                   enabled: !_uploading,
//                   onBulkNumbering: _showBulkNumberingDialog,
//                   onSelectAll: _selectAll,
//                   onUnselectAll: _unselectAll,
//                 ),

//                 const SizedBox(height: 14),
//                 TextField(
//                   controller: _drawingSearchController,
//                   decoration: InputDecoration(
//                     hintText: 'Search page, drawing number or title',
//                     prefixIcon: const Icon(Icons.search_rounded),
//                     suffixIcon:
//                         _drawingSearch.isEmpty
//                             ? null
//                             : IconButton(
//                               tooltip: 'Clear search',
//                               onPressed: () {
//                                 _drawingSearchController.clear();

//                                 setState(() {
//                                   _drawingSearch = '';
//                                 });
//                               },
//                               icon: const Icon(Icons.close_rounded),
//                             ),
//                     border: const OutlineInputBorder(),
//                   ),
//                   onChanged: (value) {
//                     setState(() {
//                       _drawingSearch = value;
//                     });
//                   },
//                 ),
//                 const SizedBox(height: 24),

//                 _DrawingPageList(
//                   pages: _visiblePages,
//                   pdfBytes: _pdfBytes!,

//                   enabled: !_uploading && _drawingSearch.trim().isEmpty,

//                   pauseThumbnails: _pauseThumbnails,

//                   onSelectedChanged: _togglePage,

//                   onDrawingNumberChanged: (page, value) {
//                     _updateDrawingNumber(page, value);
//                   },

//                   onTitleChanged: (page, value) {
//                     _updateDrawingTitle(page, value);
//                   },

//                   onReorder: _reorderPages,
//                   formatBytes: _formatBytes,
//                   sizeForPage: _estimatedSizeForPage,
//                 ),
//                 const SizedBox(height: 24),

//                 // FOOTER ALWAYS APPEARS.
//                 //
//                 _UploadFooter(
//                   selectedCount: _selectedCount,

//                   selectedSizeLabel: _formatBytes(_selectedPdfSizeBytes),

//                   totalCount: _pages.length,

//                   uploading: _uploading,

//                   progress: _uploadProgress,

//                   isAppending: widget.isAppending,

//                   storagePrepared: _storageEstimate != null,

//                   preparingStorage: _preparingDrawings,

//                   onCalculateStorage: _prepareSelectedDrawings,

//                   onUpload: _uploadBundle,
//                 ),
//                 // _UploadFooter(
//                 //   selectedCount: _selectedCount,
//                 //   selectedSizeLabel: _formatBytes(_selectedPdfSizeBytes),

//                 //   totalCount: _pages.length,

//                 //   uploading: _uploading,

//                 //   progress: _uploadProgress,

//                 //   onUpload: _uploadBundle,
//                 // ),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _BulkNumberingResult {
//   const _BulkNumberingResult({
//     required this.prefix,
//     required this.start,
//     required this.digits,
//   });

//   final String prefix;
//   final int start;
//   final int digits;
// }

// class _ExistingDrawingsCard extends StatelessWidget {
//   const _ExistingDrawingsCard({
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//   });

//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<List<DrawingSheet>>(
//       stream: DrawingService.instance.watchDrawings(
//         projectId: projectId,
//         facilityId: facilityId,
//       ),
//       builder: (context, snapshot) {
//         final loading = snapshot.connectionState == ConnectionState.waiting;
//         final drawings = snapshot.data ?? const <DrawingSheet>[];
//         final latest = drawings.take(5).toList();

//         return Container(
//           padding: const EdgeInsets.all(18),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(22),
//             border: Border.all(color: const Color(0xFFE4E7EC)),
//             boxShadow: const [
//               BoxShadow(
//                 color: Color(0x0A101828),
//                 blurRadius: 18,
//                 offset: Offset(0, 8),
//               ),
//             ],
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Container(
//                     width: 46,
//                     height: 46,
//                     decoration: BoxDecoration(
//                       color: const Color(0xFFEFF4FF),
//                       borderRadius: BorderRadius.circular(14),
//                     ),
//                     child: const Icon(
//                       Icons.folder_copy_outlined,
//                       color: Color(0xFF155EEF),
//                     ),
//                   ),
//                   const SizedBox(width: 14),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           loading
//                               ? 'Loading uploaded drawings'
//                               : '${drawings.length} uploaded ${drawings.length == 1 ? 'drawing' : 'drawings'}',
//                           style: const TextStyle(
//                             fontSize: 17,
//                             fontWeight: FontWeight.w900,
//                             color: Color(0xFF101828),
//                           ),
//                         ),
//                         const SizedBox(height: 3),
//                         const Text(
//                           'Existing drawings for this facility. Use the form below only when uploading a new PDF bundle.',
//                           style: TextStyle(
//                             color: Color(0xFF667085),
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   OutlinedButton.icon(
//                     onPressed: () {
//                       Get.toNamed(
//                         AppRoutes.drawingRegister,
//                         parameters: {
//                           'projectId': projectId,
//                           'facilityId': facilityId,
//                           'facilityName': facilityName,
//                         },
//                       );
//                     },
//                     icon: const Icon(Icons.list_alt_rounded, size: 18),
//                     label: const Text('View register'),
//                   ),
//                 ],
//               ),
//               if (snapshot.hasError) ...[
//                 const SizedBox(height: 14),
//                 Text(
//                   'Could not load uploaded drawings: ${snapshot.error}',
//                   style: const TextStyle(color: Color(0xFFB42318)),
//                 ),
//               ] else if (loading) ...[
//                 const SizedBox(height: 14),
//                 const LinearProgressIndicator(),
//               ] else if (drawings.isEmpty) ...[
//                 const SizedBox(height: 14),
//                 Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.all(14),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFFF8FAFC),
//                     borderRadius: BorderRadius.circular(14),
//                     border: Border.all(color: const Color(0xFFE4E7EC)),
//                   ),
//                   child: const Text(
//                     'No drawings have been uploaded to this facility yet.',
//                     style: TextStyle(
//                       color: Color(0xFF667085),
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                 ),
//               ] else ...[
//                 const SizedBox(height: 14),
//                 ...latest.map(
//                   (drawing) => Padding(
//                     padding: const EdgeInsets.only(bottom: 8),
//                     child: _ExistingDrawingRow(drawing: drawing),
//                   ),
//                 ),
//                 if (drawings.length > latest.length)
//                   Text(
//                     '+ ${drawings.length - latest.length} more in the drawing register',
//                     style: const TextStyle(
//                       color: Color(0xFF667085),
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//               ],
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

// class _ExistingDrawingRow extends StatelessWidget {
//   const _ExistingDrawingRow({required this.drawing});

//   final DrawingSheet drawing;

//   @override
//   Widget build(BuildContext context) {
//     final drawingNo =
//         drawing.drawingNumber.trim().isEmpty
//             ? 'No drawing no.'
//             : drawing.drawingNumber;
//     final title =
//         drawing.title.trim().isEmpty ? 'Untitled drawing' : drawing.title;
//     final revision =
//         drawing.revision.trim().isEmpty ? 'Rev —' : 'Rev ${drawing.revision}';

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(14),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Row(
//         children: [
//           const Icon(Icons.description_outlined, color: Color(0xFF155EEF)),
//           const SizedBox(width: 10),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   drawingNo,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(
//                     color: Color(0xFF101828),
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   title,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(
//                     color: Color(0xFF667085),
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(width: 10),
//           Text(
//             revision,
//             style: const TextStyle(
//               color: Color(0xFF667085),
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(width: 12),
//           Chip(
//             visualDensity: VisualDensity.compact,
//             label: Text(
//               drawing.calibrated ? 'Calibrated' : 'Needs calibration',
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _PageHeader extends StatelessWidget {
//   const _PageHeader({required this.facilityName});

//   final String facilityName;

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           facilityName,
//           style: const TextStyle(
//             color: AqsColors.muted,
//             fontSize: 12,
//             fontWeight: FontWeight.w700,
//           ),
//         ),

//         const SizedBox(height: 4),

//         const Text(
//           'Upload Drawing Bundle',
//           style: TextStyle(
//             color: AqsColors.ink,
//             fontSize: 28,
//             fontWeight: FontWeight.w900,
//             letterSpacing: -0.6,
//           ),
//         ),

//         const SizedBox(height: 6),

//         const Text(
//           'Choose a drawing PDF, review the detected pages and select only the sheets required for take-off.',
//           style: TextStyle(color: AqsColors.muted, height: 1.45),
//         ),
//       ],
//     );
//   }
// }

// class _PdfPickerCard extends StatelessWidget {
//   const _PdfPickerCard({
//     required this.file,
//     required this.fileSize,
//     required this.selecting,
//     required this.inspecting,
//     required this.uploading,
//     required this.uploadProgress,
//     required this.onPick,
//   });

//   final PlatformFile? file;

//   final String fileSize;

//   final bool selecting;
//   final bool inspecting;
//   final bool uploading;

//   final double uploadProgress;

//   final VoidCallback onPick;

//   @override
//   Widget build(BuildContext context) {
//     final busy = selecting || inspecting || uploading;

//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 62,
//             height: 62,
//             decoration: BoxDecoration(
//               color: AqsColors.primary.withOpacity(0.08),
//               borderRadius: BorderRadius.circular(18),
//             ),
//             child: const Icon(
//               Icons.picture_as_pdf_outlined,
//               color: AqsColors.primary,
//               size: 30,
//             ),
//           ),

//           const SizedBox(width: 16),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   file?.name ?? 'No PDF selected',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: const TextStyle(
//                     color: AqsColors.ink,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),

//                 const SizedBox(height: 5),

//                 Text(
//                   file == null ? 'Choose a multi-page drawing PDF.' : fileSize,
//                   style: const TextStyle(color: AqsColors.muted, fontSize: 12),
//                 ),

//                 if (uploading) ...[
//                   const SizedBox(height: 10),

//                   LinearProgressIndicator(value: uploadProgress, minHeight: 6),
//                 ],
//               ],
//             ),
//           ),

//           const SizedBox(width: 16),

//           OutlinedButton.icon(
//             onPressed: busy ? null : onPick,
//             icon:
//                 selecting || inspecting
//                     ? const SizedBox(
//                       width: 17,
//                       height: 17,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                     : const Icon(Icons.folder_open_outlined),
//             label: Text(file == null ? 'Browse PDF' : 'Change PDF'),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _BundleInformationCard extends StatelessWidget {
//   const _BundleInformationCard({
//     required this.bundleNameController,
//     required this.revisionController,
//     required this.descriptionController,
//     required this.discipline,
//     required this.issueType,
//     required this.disciplines,
//     required this.issueTypes,
//     required this.enabled,
//     required this.isAppending,
//     required this.onDisciplineChanged,
//     required this.onIssueTypeChanged,
//   });

//   final TextEditingController bundleNameController;
//   final TextEditingController revisionController;
//   final TextEditingController descriptionController;

//   final String discipline;
//   final String issueType;

//   final Map<String, String> disciplines;
//   final Map<String, String> issueTypes;

//   final bool enabled;
//   final bool isAppending;

//   final ValueChanged<String?> onDisciplineChanged;
//   final ValueChanged<String?> onIssueTypeChanged;

//   @override
//   Widget build(BuildContext context) {
//     final metadataEditable = enabled && !isAppending;

//     return Container(
//       padding: const EdgeInsets.all(22),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               const Expanded(
//                 child: Text(
//                   'Bundle information',
//                   style: TextStyle(
//                     color: AqsColors.ink,
//                     fontSize: 18,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),
//               ),

//               if (isAppending)
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 10,
//                     vertical: 6,
//                   ),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFFEFF8FF),
//                     borderRadius: BorderRadius.circular(999),
//                   ),
//                   child: const Text(
//                     'EXISTING BUNDLE',
//                     style: TextStyle(
//                       color: Color(0xFF175CD3),
//                       fontSize: 11,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ),
//             ],
//           ),

//           if (isAppending) ...[
//             const SizedBox(height: 8),

//             const Text(
//               'New drawings will be added to this existing bundle.',
//               style: TextStyle(color: AqsColors.muted, fontSize: 13),
//             ),
//           ],

//           const SizedBox(height: 18),

//           //
//           // Bundle name
//           //
//           TextFormField(
//             controller: bundleNameController,

//             //
//             // Existing bundle:
//             // show the name but do not allow editing.
//             //
//             enabled: metadataEditable,

//             decoration: InputDecoration(
//               labelText: 'Bundle name *',
//               border: const OutlineInputBorder(),

//               prefixIcon: Icon(
//                 isAppending
//                     ? Icons.folder_outlined
//                     : Icons.drive_file_rename_outline,
//               ),

//               suffixIcon:
//                   isAppending
//                       ? const Tooltip(
//                         message:
//                             'Bundle name is inherited from the existing bundle.',
//                         child: Icon(Icons.lock_outline_rounded, size: 18),
//                       )
//                       : null,

//               filled: isAppending,
//               fillColor: isAppending ? const Color(0xFFF9FAFB) : null,
//             ),

//             validator: (value) {
//               if ((value ?? '').trim().isEmpty) {
//                 return 'Enter bundle name';
//               }

//               return null;
//             },
//           ),

//           const SizedBox(height: 14),

//           LayoutBuilder(
//             builder: (context, constraints) {
//               final wide = constraints.maxWidth >= 650;

//               final disciplineWidget = DropdownButtonFormField<String>(
//                 value: discipline,
//                 isExpanded: true,

//                 decoration: InputDecoration(
//                   labelText: 'Discipline',
//                   border: const OutlineInputBorder(),

//                   suffixIcon:
//                       isAppending
//                           ? const Icon(Icons.lock_outline_rounded, size: 18)
//                           : null,

//                   filled: isAppending,
//                   fillColor: isAppending ? const Color(0xFFF9FAFB) : null,
//                 ),

//                 items:
//                     disciplines.entries.map((entry) {
//                       return DropdownMenuItem(
//                         value: entry.key,
//                         child: Text(entry.value),
//                       );
//                     }).toList(),

//                 //
//                 // Existing bundle discipline
//                 // must remain unchanged.
//                 //
//                 onChanged: metadataEditable ? onDisciplineChanged : null,
//               );

//               final issueWidget = DropdownButtonFormField<String>(
//                 value: issueType,
//                 isExpanded: true,

//                 decoration: InputDecoration(
//                   labelText: 'Issue type',
//                   border: const OutlineInputBorder(),

//                   suffixIcon:
//                       isAppending
//                           ? const Icon(Icons.lock_outline_rounded, size: 18)
//                           : null,

//                   filled: isAppending,
//                   fillColor: isAppending ? const Color(0xFFF9FAFB) : null,
//                 ),

//                 items:
//                     issueTypes.entries.map((entry) {
//                       return DropdownMenuItem(
//                         value: entry.key,
//                         child: Text(entry.value),
//                       );
//                     }).toList(),

//                 onChanged: metadataEditable ? onIssueTypeChanged : null,
//               );

//               if (!wide) {
//                 return Column(
//                   children: [
//                     disciplineWidget,

//                     const SizedBox(height: 14),

//                     issueWidget,
//                   ],
//                 );
//               }

//               return Row(
//                 children: [
//                   Expanded(child: disciplineWidget),

//                   const SizedBox(width: 14),

//                   Expanded(child: issueWidget),
//                 ],
//               );
//             },
//           ),

//           const SizedBox(height: 14),

//           //
//           // Revision remains editable.
//           //
//           TextFormField(
//             controller: revisionController,

//             enabled: enabled,

//             decoration: const InputDecoration(
//               labelText: 'Revision',

//               hintText: 'Rev 02',

//               border: OutlineInputBorder(),
//             ),
//           ),

//           const SizedBox(height: 14),

//           //
//           // Description can also remain editable.
//           //
//           TextFormField(
//             controller: descriptionController,

//             enabled: enabled,

//             minLines: 2,

//             maxLines: 4,

//             decoration: InputDecoration(
//               labelText:
//                   isAppending ? 'Upload notes / Description' : 'Description',

//               border: const OutlineInputBorder(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // class _BundleInformationCard extends StatelessWidget {
// //   const _BundleInformationCard({
// //     required this.bundleNameController,
// //     required this.revisionController,
// //     required this.descriptionController,
// //     required this.discipline,
// //     required this.issueType,
// //     required this.disciplines,
// //     required this.issueTypes,
// //     required this.enabled,
// //     required this.onDisciplineChanged,
// //     required this.onIssueTypeChanged,
// //   });

// //   final TextEditingController bundleNameController;

// //   final TextEditingController revisionController;

// //   final TextEditingController descriptionController;

// //   final String discipline;

// //   final String issueType;

// //   final Map<String, String> disciplines;

// //   final Map<String, String> issueTypes;

// //   final bool enabled;

// //   final ValueChanged<String?> onDisciplineChanged;

// //   final ValueChanged<String?> onIssueTypeChanged;

// //   @override
// //   Widget build(BuildContext context) {
// //     return Container(
// //       padding: const EdgeInsets.all(22),
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(22),
// //         border: Border.all(color: const Color(0xFFE4E7EC)),
// //       ),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.start,
// //         children: [
// //           const Text(
// //             'Bundle information',
// //             style: TextStyle(
// //               color: AqsColors.ink,
// //               fontSize: 18,
// //               fontWeight: FontWeight.w900,
// //             ),
// //           ),

// //           const SizedBox(height: 18),

// //           TextFormField(
// //             controller: bundleNameController,
// //             enabled: enabled,
// //             decoration: const InputDecoration(
// //               labelText: 'Bundle name *',
// //               border: OutlineInputBorder(),
// //             ),
// //             validator: (value) {
// //               if ((value ?? '').trim().isEmpty) {
// //                 return 'Enter bundle name';
// //               }

// //               return null;
// //             },
// //           ),

// //           const SizedBox(height: 14),

// //           LayoutBuilder(
// //             builder: (context, constraints) {
// //               final wide = constraints.maxWidth >= 650;

// //               final disciplineWidget = DropdownButtonFormField<String>(
// //                 value: discipline,
// //                 isExpanded: true,
// //                 decoration: const InputDecoration(
// //                   labelText: 'Discipline',
// //                   border: OutlineInputBorder(),
// //                 ),
// //                 items:
// //                     disciplines.entries.map((entry) {
// //                       return DropdownMenuItem(
// //                         value: entry.key,
// //                         child: Text(entry.value),
// //                       );
// //                     }).toList(),
// //                 onChanged: enabled ? onDisciplineChanged : null,
// //               );

// //               final issueWidget = DropdownButtonFormField<String>(
// //                 value: issueType,
// //                 isExpanded: true,
// //                 decoration: const InputDecoration(
// //                   labelText: 'Issue type',
// //                   border: OutlineInputBorder(),
// //                 ),
// //                 items:
// //                     issueTypes.entries.map((entry) {
// //                       return DropdownMenuItem(
// //                         value: entry.key,
// //                         child: Text(entry.value),
// //                       );
// //                     }).toList(),
// //                 onChanged: enabled ? onIssueTypeChanged : null,
// //               );

// //               if (!wide) {
// //                 return Column(
// //                   children: [
// //                     disciplineWidget,
// //                     const SizedBox(height: 14),
// //                     issueWidget,
// //                   ],
// //                 );
// //               }

// //               return Row(
// //                 children: [
// //                   Expanded(child: disciplineWidget),

// //                   const SizedBox(width: 14),

// //                   Expanded(child: issueWidget),
// //                 ],
// //               );
// //             },
// //           ),

// //           const SizedBox(height: 14),

// //           TextFormField(
// //             controller: revisionController,
// //             enabled: enabled,
// //             decoration: const InputDecoration(
// //               labelText: 'Revision',
// //               hintText: 'Rev 02',
// //               border: OutlineInputBorder(),
// //             ),
// //           ),

// //           const SizedBox(height: 14),

// //           TextFormField(
// //             controller: descriptionController,
// //             enabled: enabled,
// //             minLines: 2,
// //             maxLines: 4,
// //             decoration: const InputDecoration(
// //               labelText: 'Description',
// //               border: OutlineInputBorder(),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

// class _InspectingCard extends StatelessWidget {
//   const _InspectingCard();

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(28),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//       ),
//       child: const Column(
//         children: [
//           CircularProgressIndicator(),

//           SizedBox(height: 14),

//           Text(
//             'Reading drawing pages...',
//             style: TextStyle(color: AqsColors.ink, fontWeight: FontWeight.w800),
//           ),

//           SizedBox(height: 4),

//           Text(
//             'AQS is checking the PDF page structure.',
//             style: TextStyle(color: AqsColors.muted, fontSize: 12),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _DrawingSelectionHeader extends StatelessWidget {
//   const _DrawingSelectionHeader({
//     required this.totalCount,
//     required this.selectedCount,
//     required this.selectedSizeLabel,
//     required this.allSelected,
//     required this.enabled,
//     required this.onSelectAll,
//     required this.onUnselectAll,
//     required this.onBulkNumbering,
//   });

//   final int totalCount;
//   final int selectedCount;
//   final String selectedSizeLabel;

//   final bool allSelected;
//   final bool enabled;

//   final VoidCallback onSelectAll;
//   final VoidCallback onUnselectAll;
//   final VoidCallback onBulkNumbering;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Wrap(
//         spacing: 12,
//         runSpacing: 10,
//         crossAxisAlignment: WrapCrossAlignment.center,
//         children: [
//           Text(
//             '$totalCount PDF '
//             '${totalCount == 1 ? 'page' : 'pages'} detected',
//             style: const TextStyle(
//               color: AqsColors.ink,
//               fontWeight: FontWeight.w900,
//             ),
//           ),

//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//             decoration: BoxDecoration(
//               color: const Color(0xFFECFDF3),
//               borderRadius: BorderRadius.circular(30),
//             ),
//             child: Text(
//               '$selectedCount selected',
//               style: const TextStyle(
//                 color: Color(0xFF027A48),
//                 fontSize: 11,
//                 fontWeight: FontWeight.w900,
//               ),
//             ),
//           ),

//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//             decoration: BoxDecoration(
//               color: const Color(0xFFEFF4FF),
//               borderRadius: BorderRadius.circular(30),
//             ),
//             child: Text(
//               'Selected size: $selectedSizeLabel',
//               style: const TextStyle(
//                 color: Color(0xFF155EEF),
//                 fontSize: 11,
//                 fontWeight: FontWeight.w900,
//               ),
//             ),
//           ),

//           const SizedBox(width: 6),

//           TextButton.icon(
//             onPressed: !enabled || allSelected ? null : onSelectAll,
//             icon: const Icon(Icons.select_all_rounded),
//             label: const Text('Select All'),
//           ),

//           TextButton(
//             onPressed: !enabled || selectedCount == 0 ? null : onUnselectAll,
//             child: const Text('Unselect All'),
//           ),
//           OutlinedButton.icon(
//             onPressed: !enabled || selectedCount == 0 ? null : onBulkNumbering,
//             icon: const Icon(Icons.format_list_numbered_rounded),
//             label: const Text('Auto Number'),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _DrawingPageList extends StatelessWidget {
//   const _DrawingPageList({
//     required this.pages,
//     required this.pdfBytes,
//     required this.enabled,
//     required this.pauseThumbnails,
//     required this.onSelectedChanged,
//     required this.onDrawingNumberChanged,
//     required this.onTitleChanged,
//     required this.onReorder,
//     required this.formatBytes,
//     required this.sizeForPage,
//   });

//   final List<PendingDrawingPage> pages;
//   final Uint8List pdfBytes;

//   final bool enabled;
//   final bool pauseThumbnails;

//   final void Function(PendingDrawingPage page, bool selected) onSelectedChanged;

//   final void Function(PendingDrawingPage page, String value)
//   onDrawingNumberChanged;

//   final void Function(PendingDrawingPage page, String value) onTitleChanged;

//   final void Function(int oldIndex, int newIndex) onReorder;
//   final String Function(int bytes) formatBytes;
//   final int Function(PendingDrawingPage page) sizeForPage;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 720,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: ReorderableListView.builder(
//         padding: const EdgeInsets.all(14),
//         buildDefaultDragHandles: false,
//         itemCount: pages.length,
//         onReorder: enabled ? onReorder : (_, __) {},
//         itemBuilder: (context, index) {
//           final page = pages[index];

//           return Padding(
//             key: ValueKey('drawing-page-${page.pageIndex}'),
//             padding: const EdgeInsets.only(bottom: 14),
//             child: _DrawingPageCard(
//               page: page,
//               pdfBytes: pdfBytes,
//               enabled: enabled,
//               pauseThumbnails: pauseThumbnails,
//               reorderIndex: index,

//               onSelectedChanged: (value) {
//                 onSelectedChanged(page, value);
//               },

//               onDrawingNumberChanged: (value) {
//                 onDrawingNumberChanged(page, value);
//               },

//               onTitleChanged: (value) {
//                 onTitleChanged(page, value);
//               },
//               formatBytes: formatBytes,
//               pdfSizeBytes: sizeForPage(page),
//             ),
//           );
//         },
//       ),
//     );
//   }
// }

// class _DrawingPageCard extends StatelessWidget {
//   const _DrawingPageCard({
//     super.key,
//     required this.page,
//     required this.enabled,
//     required this.reorderIndex,
//     required this.onSelectedChanged,
//     required this.onDrawingNumberChanged,
//     required this.onTitleChanged,
//     required this.pauseThumbnails,
//     required this.pdfBytes,
//     required this.formatBytes,
//     required this.pdfSizeBytes,
//   });

//   final PendingDrawingPage page;
//   final bool pauseThumbnails;

//   final Uint8List pdfBytes;

//   final bool enabled;
//   final int reorderIndex;

//   final ValueChanged<bool> onSelectedChanged;

//   final ValueChanged<String> onDrawingNumberChanged;

//   final ValueChanged<String> onTitleChanged;
//   final String Function(int bytes) formatBytes;
//   final int pdfSizeBytes;

//   @override
//   Widget build(BuildContext context) {
//     return AnimatedOpacity(
//       duration: const Duration(milliseconds: 180),
//       opacity: page.selected ? 1 : 0.58,
//       child: Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(20),
//           border: Border.all(
//             color:
//                 page.selected
//                     ? const Color(0xFFD0D5DD)
//                     : const Color(0xFFE4E7EC),
//           ),
//         ),
//         child: LayoutBuilder(
//           builder: (context, constraints) {
//             final compact = constraints.maxWidth < 720;

//             final thumbnail = Stack(
//               children: [
//                 DrawingPageThumbnail(
//                   pdfBytes: pdfBytes,

//                   pageIndex: page.pageIndex,

//                   width: compact ? 120 : 150,
//                 ),

//                 Positioned(
//                   top: 7,
//                   left: 7,
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 8,
//                       vertical: 4,
//                     ),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF101828).withOpacity(0.88),
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: Text(
//                       'Page ${page.sourcePageNumber}',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 9,
//                         fontWeight: FontWeight.w800,
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             );

//             final editor = Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Checkbox(
//                       value: page.selected,
//                       onChanged:
//                           !enabled
//                               ? null
//                               : (value) {
//                                 onSelectedChanged(value ?? false);
//                               },
//                     ),

//                     const SizedBox(width: 4),

//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             'PDF Page ${page.sourcePageNumber}',
//                             style: const TextStyle(
//                               color: AqsColors.ink,
//                               fontSize: 15,
//                               fontWeight: FontWeight.w900,
//                             ),
//                           ),

//                           const SizedBox(height: 2),

//                           Text(
//                             page.selected
//                                 ? 'Included • PDF ${formatBytes(pdfSizeBytes)}'
//                                 : 'Excluded from drawing register',
//                             style: TextStyle(
//                               color:
//                                   page.selected
//                                       ? const Color(0xFF027A48)
//                                       : AqsColors.muted,
//                               fontSize: 11,
//                               fontWeight: FontWeight.w700,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),

//                     _SelectionChip(selected: page.selected),
//                   ],
//                 ),

//                 const SizedBox(height: 14),

//                 LayoutBuilder(
//                   builder: (context, constraints) {
//                     final sideBySide = constraints.maxWidth >= 600;

//                     final drawingNumber = TextFormField(
//                       initialValue: page.drawingNumber,
//                       enabled: enabled && page.selected,
//                       decoration: const InputDecoration(
//                         labelText: 'Drawing No.',
//                         hintText: 'A-001',
//                         border: OutlineInputBorder(),
//                         prefixIcon: Icon(Icons.tag_rounded),
//                       ),
//                       onChanged: onDrawingNumberChanged,
//                     );

//                     final drawingTitle = TextFormField(
//                       initialValue: page.title,
//                       enabled: enabled && page.selected,
//                       decoration: const InputDecoration(
//                         labelText: 'Drawing Title',
//                         hintText: 'Ground Floor Plan',
//                         border: OutlineInputBorder(),
//                         prefixIcon: Icon(Icons.drive_file_rename_outline),
//                       ),
//                       onChanged: onTitleChanged,
//                     );

//                     if (!sideBySide) {
//                       return Column(
//                         children: [
//                           drawingNumber,

//                           const SizedBox(height: 12),

//                           drawingTitle,
//                         ],
//                       );
//                     }

//                     return Row(
//                       children: [
//                         SizedBox(width: 220, child: drawingNumber),

//                         const SizedBox(width: 12),

//                         Expanded(child: drawingTitle),
//                       ],
//                     );
//                   },
//                 ),

//                 const SizedBox(height: 12),

//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 11,
//                     vertical: 8,
//                   ),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFFF9FAFB),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(
//                         Icons.picture_as_pdf_outlined,
//                         size: 16,
//                         color: AqsColors.muted,
//                       ),

//                       const SizedBox(width: 7),

//                       Expanded(
//                         child: Text(
//                           'Original source page ${page.sourcePageNumber}',
//                           style: const TextStyle(
//                             color: AqsColors.muted,
//                             fontSize: 10,
//                           ),
//                         ),
//                       ),

//                       Text(
//                         'Order ${page.sortOrder}',
//                         style: const TextStyle(
//                           color: AqsColors.muted,
//                           fontSize: 10,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             );

//             if (compact) {
//               return Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Center(child: thumbnail),

//                   const SizedBox(height: 16),

//                   editor,
//                 ],
//               );
//             }

//             return Row(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 thumbnail,

//                 const SizedBox(width: 20),

//                 Expanded(child: editor),
//               ],
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// class _SelectionChip extends StatelessWidget {
//   const _SelectionChip({required this.selected});

//   final bool selected;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
//       decoration: BoxDecoration(
//         color: selected ? const Color(0xFFECFDF3) : const Color(0xFFF2F4F7),
//         borderRadius: BorderRadius.circular(30),
//       ),
//       child: Text(
//         selected ? 'SELECTED' : 'EXCLUDED',
//         style: TextStyle(
//           color: selected ? const Color(0xFF027A48) : const Color(0xFF667085),
//           fontSize: 9,
//           fontWeight: FontWeight.w900,
//         ),
//       ),
//     );
//   }
// }

// class _UploadFooter extends StatelessWidget {
//   const _UploadFooter({
//     required this.selectedCount,
//     required this.selectedSizeLabel,
//     required this.totalCount,
//     required this.uploading,
//     required this.progress,
//     required this.isAppending,
//     required this.storagePrepared,
//     required this.preparingStorage,
//     required this.onCalculateStorage,
//     required this.onUpload,
//   });

//   final int selectedCount;
//   final String selectedSizeLabel;
//   final int totalCount;

//   final bool uploading;
//   final double progress;

//   final bool isAppending;
//   final bool storagePrepared;
//   final bool preparingStorage;

//   final VoidCallback onCalculateStorage;
//   final VoidCallback onUpload;

//   @override
//   Widget build(BuildContext context) {
//     final canCalculate = !uploading && !preparingStorage && selectedCount > 0;

//     final canUpload =
//         !uploading && !preparingStorage && selectedCount > 0 && storagePrepared;

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF101828),
//         borderRadius: BorderRadius.circular(22),
//       ),
//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final summary = Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 '$selectedCount of $totalCount drawings selected',
//                 style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 16,
//                   fontWeight: FontWeight.w900,
//                 ),
//               ),

//               const SizedBox(height: 4),

//               Text(
//                 isAppending
//                     ? 'Selected drawings will be added to the existing bundle. '
//                         'Selected drawings size: $selectedSizeLabel.'
//                     : 'Only selected pages will be added. '
//                         'Selected drawings size: $selectedSizeLabel.',
//                 style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
//               ),

//               if (!storagePrepared && selectedCount > 0 && !uploading) ...[
//                 const SizedBox(height: 6),

//                 const Text(
//                   'Calculate storage before uploading.',
//                   style: TextStyle(
//                     color: Color(0xFFFDB022),
//                     fontSize: 12,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ],

//               if (storagePrepared && !uploading) ...[
//                 const SizedBox(height: 6),

//                 const Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(
//                       Icons.check_circle_outline_rounded,
//                       color: Color(0xFF32D583),
//                       size: 16,
//                     ),

//                     SizedBox(width: 6),

//                     Text(
//                       'Selected drawings are ready for upload.',
//                       style: TextStyle(
//                         color: Color(0xFF32D583),
//                         fontSize: 12,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],

//               if (uploading) ...[
//                 const SizedBox(height: 12),

//                 LinearProgressIndicator(value: progress, minHeight: 6),

//                 const SizedBox(height: 6),

//                 Text(
//                   '${(progress * 100).toStringAsFixed(0)}%',
//                   style: const TextStyle(
//                     color: Color(0xFF98A2B3),
//                     fontSize: 11,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ],
//             ],
//           );

//           final calculateButton = OutlinedButton.icon(
//             onPressed: canCalculate ? onCalculateStorage : null,

//             style: OutlinedButton.styleFrom(
//               foregroundColor: Colors.white,
//               side: const BorderSide(color: Color(0xFF475467)),
//             ),

//             icon:
//                 preparingStorage
//                     ? const SizedBox.square(
//                       dimension: 17,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                     : const Icon(Icons.calculate_outlined),

//             label: Text(
//               preparingStorage
//                   ? 'Calculating...'
//                   : storagePrepared
//                   ? 'Recalculate'
//                   : 'Calculate Storage',
//             ),
//           );

//           final uploadButton = FilledButton.icon(
//             onPressed: canUpload ? onUpload : null,

//             icon:
//                 uploading
//                     ? const SizedBox.square(
//                       dimension: 18,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         color: Colors.white,
//                       ),
//                     )
//                     : Icon(
//                       isAppending
//                           ? Icons.add_to_photos_outlined
//                           : Icons.cloud_upload_outlined,
//                     ),

//             label: Text(
//               uploading
//                   ? isAppending
//                       ? 'Adding Drawings...'
//                       : 'Uploading...'
//                   : isAppending
//                   ? 'Add $selectedCount Drawings'
//                   : 'Upload $selectedCount Drawings',
//             ),
//           );

//           if (constraints.maxWidth < 700) {
//             return Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 summary,

//                 const SizedBox(height: 18),

//                 calculateButton,

//                 const SizedBox(height: 10),

//                 uploadButton,
//               ],
//             );
//           }

//           return Row(
//             children: [
//               Expanded(child: summary),

//               const SizedBox(width: 20),

//               calculateButton,

//               const SizedBox(width: 10),

//               uploadButton,
//             ],
//           );
//         },
//       ),
//     );
//   }
// }

// // class _UploadFooter extends StatelessWidget {
// //   const _UploadFooter({
// //     required this.selectedCount,
// //     required this.selectedSizeLabel,
// //     required this.totalCount,
// //     required this.uploading,
// //     required this.progress,
// //     required this.onUpload,
// //   });

// //   final int selectedCount;
// //   final String selectedSizeLabel;
// //   final int totalCount;

// //   final bool uploading;
// //   final double progress;

// //   final VoidCallback onUpload;

// //   @override
// //   Widget build(BuildContext context) {
// //     return Container(
// //       padding: const EdgeInsets.all(20),
// //       decoration: BoxDecoration(
// //         color: const Color(0xFF101828),
// //         borderRadius: BorderRadius.circular(22),
// //       ),
// //       child: LayoutBuilder(
// //         builder: (context, constraints) {
// //           final summary = Column(
// //             crossAxisAlignment: CrossAxisAlignment.start,
// //             children: [
// //               Text(
// //                 '$selectedCount of $totalCount drawings selected',
// //                 style: const TextStyle(
// //                   color: Colors.white,
// //                   fontSize: 16,
// //                   fontWeight: FontWeight.w900,
// //                 ),
// //               ),

// //               const SizedBox(height: 4),

// //               Text(
// //                 'Only selected pages will be added. Selected drawings size: $selectedSizeLabel.',
// //                 style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
// //               ),

// //               if (uploading) ...[
// //                 const SizedBox(height: 12),

// //                 LinearProgressIndicator(value: progress, minHeight: 6),
// //               ],
// //             ],
// //           );

// //           if (constraints.maxWidth < 600) {
// //             return Column(
// //               crossAxisAlignment: CrossAxisAlignment.stretch,
// //               children: [
// //                 summary,

// //                 const SizedBox(height: 18),

// //                 FilledButton.icon(
// //                   onPressed: uploading || selectedCount == 0 ? null : onUpload,

// //                   icon:
// //                       uploading
// //                           ? const SizedBox.square(
// //                             dimension: 18,
// //                             child: CircularProgressIndicator(
// //                               strokeWidth: 2,
// //                               color: Colors.white,
// //                             ),
// //                           )
// //                           : const Icon(Icons.cloud_upload_outlined),

// //                   label: Text(
// //                     uploading
// //                         ? 'Preparing upload...'
// //                         : 'Upload $selectedCount Drawings',
// //                   ),
// //                 ),
// //               ],
// //             );
// //           }

// //           return Row(
// //             children: [
// //               Expanded(child: summary),

// //               const SizedBox(width: 20),

// //               FilledButton.icon(
// //                 onPressed: uploading || selectedCount == 0 ? null : onUpload,

// //                 icon:
// //                     uploading
// //                         ? const SizedBox.square(
// //                           dimension: 17,
// //                           child: CircularProgressIndicator(strokeWidth: 2),
// //                         )
// //                         : const Icon(Icons.cloud_upload_outlined),

// //                 label: Text(
// //                   uploading ? 'Uploading...' : 'Upload $selectedCount Drawings',
// //                 ),
// //               ),
// //             ],
// //           );
// //         },
// //       ),
// //     );
// //   }
// // }
