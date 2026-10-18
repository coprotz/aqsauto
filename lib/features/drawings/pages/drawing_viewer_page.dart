// import 'dart:typed_data';

// import 'package:aqs/features/drawings/models/drawing_sheet.dart';
// import 'package:aqs/features/drawings/services/drawing_service.dart';
// import 'package:aqs/routes/app_routes.dart';

// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:http/http.dart' as http;
// import 'package:pdfx/pdfx.dart';

// class DrawingViewerPage extends StatefulWidget {
//   const DrawingViewerPage({
//     super.key,
//     required this.projectId,
//     required this.facilityId,
//     required this.drawingId,
//   });

//   final String projectId;
//   final String facilityId;
//   final String drawingId;

//   @override
//   State<DrawingViewerPage> createState() => _DrawingViewerPageState();
// }

// class _DrawingViewerPageState extends State<DrawingViewerPage> {
//   // PdfController? _pdfController;
//   PdfControllerPinch? _pdfController;

//   String? _loadedPdfUrl;
//   String? _requestedPdfUrl;

//   bool _loadingPdf = false;
//   String? _pdfError;

//   double _zoom = 1.0;

//   @override
//   void dispose() {
//     _pdfController?.dispose();
//     super.dispose();
//   }

//   Future<void> _loadPdf(DrawingSheet drawing) async {
//     final downloadUrl = drawing.downloadUrl.trim();

//     debugPrint('=====================================');
//     debugPrint('DRAWING VIEWER LOAD START');
//     debugPrint('Drawing ID: ${drawing.id}');
//     debugPrint('Download URL: $downloadUrl');

//     if (downloadUrl.isEmpty) {
//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _loadingPdf = false;
//         _pdfError = 'This drawing does not have a download URL.';
//       });

//       return;
//     }

//     //
//     // Already successfully loaded.
//     //
//     if (_loadedPdfUrl == downloadUrl && _pdfController != null) {
//       return;
//     }

//     if (_loadingPdf) {
//       debugPrint('PDF loading already in progress.');
//       return;
//     }

//     setState(() {
//       _loadingPdf = true;
//       _pdfError = null;
//     });

//     try {
//       //
//       // STEP 1
//       //
//       debugPrint('STEP 1: downloading PDF from Cloudflare R2...');

//       final response = await http
//           .get(Uri.parse(downloadUrl))
//           .timeout(const Duration(seconds: 60));

//       debugPrint('HTTP STATUS: ${response.statusCode}');

//       debugPrint(
//         'CONTENT TYPE: '
//         '${response.headers['content-type']}',
//       );

//       debugPrint(
//         'CONTENT LENGTH: '
//         '${response.bodyBytes.lengthInBytes}',
//       );

//       if (response.statusCode != 200) {
//         throw Exception(
//           'Could not download drawing. '
//           'HTTP ${response.statusCode}',
//         );
//       }

//       if (response.bodyBytes.isEmpty) {
//         throw Exception('Cloudflare R2 returned an empty file.');
//       }

//       debugPrint(
//         'STEP 1 COMPLETE: '
//         '${response.bodyBytes.lengthInBytes} bytes',
//       );

//       //
//       // Make an independent byte buffer for PDF.js.
//       //
//       final safeBytes = Uint8List.fromList(response.bodyBytes);

//       //
//       // STEP 2
//       //
//       debugPrint('STEP 2: opening PDF document...');

//       final newController = PdfControllerPinch(
//         document: PdfDocument.openData(safeBytes),
//       );

//       final document = await newController.document.timeout(
//         const Duration(seconds: 30),
//       );

//       debugPrint('STEP 2 COMPLETE');

//       debugPrint('PDF pages: ${document.pagesCount}');

//       if (!mounted) {
//         newController.dispose();
//         return;
//       }

//       final oldController = _pdfController;

//       setState(() {
//         _pdfController = newController;

//         //
//         // We can rename this variable later.
//         //
//         _loadedPdfUrl = downloadUrl;

//         _loadingPdf = false;

//         _pdfError = null;
//       });

//       oldController?.dispose();

//       debugPrint('DRAWING VIEWER LOAD COMPLETE');
//       debugPrint('=====================================');
//     } catch (error, stackTrace) {
//       debugPrint('=====================================');
//       debugPrint('DRAWING VIEWER LOAD FAILED');
//       debugPrint('$error');
//       debugPrint(stackTrace.toString());
//       debugPrint('=====================================');

//       if (!mounted) {
//         return;
//       }

//       setState(() {
//         _loadingPdf = false;
//         _pdfError = error.toString();
//       });
//     }
//   }

//   Future<Uint8List> _downloadPdfBytes(String downloadUrl) async {
//     //
//     // We already have a Storage path,
//     // so rather than depending on browser
//     // URL fetching/cors, get the bytes
//     // directly from Firebase Storage.
//     //
//     final path = _loadedPdfUrl;

//     if (path != null && path.isNotEmpty) {
//       final bytes = await FirebaseStorage.instance.ref(path).getData();

//       if (bytes != null) {
//         return bytes;
//       }
//     }

//     throw Exception('Could not download drawing PDF.');
//   }

//   void _openCalibration(DrawingSheet drawing) {
//     Get.toNamed(
//       AppRoutes.drawingCalibration,
//       parameters: {
//         'projectId': widget.projectId,

//         'facilityId': widget.facilityId,

//         'drawingId': drawing.id,
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       body: StreamBuilder<DrawingSheet?>(
//         stream: DrawingService.instance.watchDrawing(
//           projectId: widget.projectId,

//           facilityId: widget.facilityId,

//           drawingId: widget.drawingId,
//         ),

//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting &&
//               !snapshot.hasData) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           if (snapshot.hasError) {
//             print(snapshot.error);
//             return _ViewerError(message: snapshot.error.toString());
//           }

//           final drawing = snapshot.data;

//           if (drawing == null) {
//             return const _ViewerError(message: 'Drawing could not be found.');
//           }

//           //
//           // Load PDF after Firestore
//           // drawing arrives.
//           //
//           if (_requestedPdfUrl != drawing.pdfPath.trim()) {
//             _requestedPdfUrl = drawing.pdfPath.trim();

//             WidgetsBinding.instance.addPostFrameCallback((_) {
//               if (!mounted) {
//                 return;
//               }

//               _loadPdf(drawing);
//             });
//           }

//           return Column(
//             children: [
//               _DrawingViewerHeader(
//                 drawing: drawing,

//                 onBack: () {
//                   Get.back();
//                 },

//                 onCalibrate: () {
//                   _openCalibration(drawing);
//                 },
//               ),

//               Expanded(
//                 child: Row(
//                   children: [
//                     //
//                     // LEFT INFO PANEL
//                     //
//                     SizedBox(
//                       width: 290,

//                       child: _DrawingDetailsPanel(drawing: drawing),
//                     ),

//                     //
//                     // PDF VIEWER
//                     //
//                     Expanded(child: _buildViewer(drawing)),
//                   ],
//                 ),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildViewer(DrawingSheet drawing) {
//     if (_loadingPdf) {
//       return const Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             CircularProgressIndicator(),

//             SizedBox(height: 14),

//             Text('Loading drawing...'),
//           ],
//         ),
//       );
//     }

//     if (_pdfError != null) {
//       return _ViewerError(
//         message: _pdfError!,

//         onRetry: () {
//           final old = _pdfController;

//           old?.dispose();

//           setState(() {
//             _pdfController = null;

//             _loadedPdfUrl = null;

//             _pdfError = null;
//           });

//           _loadPdf(drawing);
//         },
//       );
//     }

//     final controller = _pdfController;

//     if (controller == null) {
//       return Center(
//         child: OutlinedButton.icon(
//           onPressed: () {
//             _loadPdf(drawing);
//           },

//           icon: const Icon(Icons.picture_as_pdf_outlined),

//           label: const Text('Open Drawing'),
//         ),
//       );
//     }

//     return Container(
//       color: const Color(0xFFE5E7EB),

//       child: PdfViewPinch(
//         controller: controller,

//         onDocumentLoaded: (document) {
//           debugPrint(
//             'PDF DISPLAYED: '
//             '${document.pagesCount} pages',
//           );
//         },

//         onDocumentError: (error) {
//           debugPrint('PDF VIEW ERROR: $error');
//         },
//       ),
//     );
//   }

//   void _zoomIn() {
//     //
//     // PdfView supports gestures natively.
//     // We keep these controls ready for
//     // custom transformation during takeoff.
//     //
//     setState(() {
//       _zoom = (_zoom + 0.25).clamp(1.0, 5.0);
//     });
//   }

//   void _zoomOut() {
//     setState(() {
//       _zoom = (_zoom - 0.25).clamp(1.0, 5.0);
//     });
//   }

//   void _resetZoom() {
//     setState(() {
//       _zoom = 1.0;
//     });
//   }
// }

// class _DrawingViewerHeader extends StatelessWidget {
//   const _DrawingViewerHeader({
//     required this.drawing,
//     required this.onBack,
//     required this.onCalibrate,
//   });

//   final DrawingSheet drawing;

//   final VoidCallback onBack;
//   final VoidCallback onCalibrate;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//       decoration: const BoxDecoration(
//         color: Colors.white,

//         border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
//       ),

//       child: Row(
//         children: [
//           IconButton(
//             onPressed: onBack,

//             icon: const Icon(Icons.arrow_back_rounded),
//           ),

//           const SizedBox(width: 10),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,

//               children: [
//                 Row(
//                   children: [
//                     Flexible(
//                       child: Text(
//                         drawing.drawingNumber.trim().isEmpty
//                             ? 'Untitled Drawing'
//                             : drawing.drawingNumber,

//                         overflow: TextOverflow.ellipsis,

//                         style: const TextStyle(
//                           fontSize: 20,

//                           fontWeight: FontWeight.w900,

//                           color: Color(0xFF101828),
//                         ),
//                       ),
//                     ),

//                     const SizedBox(width: 12),

//                     _StatusChip(drawing: drawing),
//                   ],
//                 ),

//                 if (drawing.title.trim().isNotEmpty)
//                   Padding(
//                     padding: const EdgeInsets.only(top: 3),

//                     child: Text(
//                       drawing.title,

//                       overflow: TextOverflow.ellipsis,

//                       style: const TextStyle(color: Color(0xFF667085)),
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           const SizedBox(width: 16),

//           OutlinedButton.icon(
//             onPressed: drawing.calibrated ? null : onCalibrate,

//             icon: Icon(
//               drawing.calibrated
//                   ? Icons.check_circle_outline_rounded
//                   : Icons.straighten_rounded,
//             ),

//             label: Text(
//               drawing.calibrated ? 'Calibrated' : 'Calibrate Drawing',
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _DrawingDetailsPanel extends StatelessWidget {
//   const _DrawingDetailsPanel({required this.drawing});

//   final DrawingSheet drawing;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: double.infinity,

//       padding: const EdgeInsets.all(22),

//       decoration: const BoxDecoration(
//         color: Colors.white,

//         border: Border(right: BorderSide(color: Color(0xFFE4E7EC))),
//       ),

//       child: SingleChildScrollView(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,

//           children: [
//             const Text(
//               'Drawing Information',

//               style: TextStyle(
//                 fontSize: 16,

//                 fontWeight: FontWeight.w900,

//                 color: Color(0xFF101828),
//               ),
//             ),

//             const SizedBox(height: 20),

//             _DetailItem(
//               label: 'Drawing No.',

//               value:
//                   drawing.drawingNumber.isEmpty ? '—' : drawing.drawingNumber,
//             ),

//             _DetailItem(
//               label: 'Title',

//               value: drawing.title.isEmpty ? '—' : drawing.title,
//             ),

//             _DetailItem(label: 'Discipline', value: drawing.discipline),

//             _DetailItem(
//               label: 'Revision',

//               value: drawing.revision.isEmpty ? '—' : drawing.revision,
//             ),

//             _DetailItem(
//               label: 'Source page',

//               value: '${drawing.sourcePageNumber}',
//             ),

//             _DetailItem(
//               label: 'Measurements',

//               value: '${drawing.measurementCount}',
//             ),

//             _DetailItem(
//               label: 'Calibration',

//               value: drawing.calibrated ? 'Calibrated' : 'Required',
//             ),

//             _DetailItem(label: 'Status', value: drawing.status),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _DetailItem extends StatelessWidget {
//   const _DetailItem({required this.label, required this.value});

//   final String label;
//   final String value;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 18),

//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,

//         children: [
//           Text(
//             label,

//             style: const TextStyle(
//               color: Color(0xFF98A2B3),

//               fontSize: 12,

//               fontWeight: FontWeight.w700,
//             ),
//           ),

//           const SizedBox(height: 4),

//           Text(
//             value,

//             style: const TextStyle(
//               color: Color(0xFF344054),

//               fontSize: 14,

//               fontWeight: FontWeight.w700,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _StatusChip extends StatelessWidget {
//   const _StatusChip({required this.drawing});

//   final DrawingSheet drawing;

//   @override
//   Widget build(BuildContext context) {
//     final label =
//         drawing.calibrated
//             ? 'READY'
//             : drawing.status.replaceAll('_', ' ').toUpperCase();

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

//       decoration: BoxDecoration(
//         color: const Color(0xFFF2F4F7),

//         borderRadius: BorderRadius.circular(999),
//       ),

//       child: Text(
//         label,

//         style: const TextStyle(
//           color: Color(0xFF475467),

//           fontSize: 11,

//           fontWeight: FontWeight.w900,
//         ),
//       ),
//     );
//   }
// }

// class _ViewerControls extends StatelessWidget {
//   const _ViewerControls({
//     required this.onZoomIn,
//     required this.onZoomOut,
//     required this.onReset,
//   });

//   final VoidCallback onZoomIn;
//   final VoidCallback onZoomOut;
//   final VoidCallback onReset;

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       elevation: 8,

//       borderRadius: BorderRadius.circular(14),

//       child: Container(
//         padding: const EdgeInsets.all(6),

//         decoration: BoxDecoration(
//           color: Colors.white,

//           borderRadius: BorderRadius.circular(14),
//         ),

//         child: Row(
//           mainAxisSize: MainAxisSize.min,

//           children: [
//             IconButton(
//               tooltip: 'Zoom out',

//               onPressed: onZoomOut,

//               icon: const Icon(Icons.remove_rounded),
//             ),

//             IconButton(
//               tooltip: 'Reset view',

//               onPressed: onReset,

//               icon: const Icon(Icons.fit_screen_rounded),
//             ),

//             IconButton(
//               tooltip: 'Zoom in',

//               onPressed: onZoomIn,

//               icon: const Icon(Icons.add_rounded),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _ViewerError extends StatelessWidget {
//   const _ViewerError({required this.message, this.onRetry});

//   final String message;
//   final VoidCallback? onRetry;

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(30),

//         child: Column(
//           mainAxisSize: MainAxisSize.min,

//           children: [
//             const Icon(
//               Icons.picture_as_pdf_outlined,

//               size: 44,

//               color: Color(0xFF98A2B3),
//             ),

//             const SizedBox(height: 14),

//             Text(
//               message,

//               textAlign: TextAlign.center,

//               style: const TextStyle(color: Color(0xFF667085)),
//             ),

//             if (onRetry != null) ...[
//               const SizedBox(height: 18),

//               OutlinedButton.icon(
//                 onPressed: onRetry,

//                 icon: const Icon(Icons.refresh_rounded),

//                 label: const Text('Retry'),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }
