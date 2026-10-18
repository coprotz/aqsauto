// import 'dart:io';

// import 'package:aqs/features/takeoff/drawing_take_off_page.dart';
// import 'package:aqs/features/takeoff/image_takeoff_page.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';

// class DrawingsTab extends StatefulWidget {
//   final String projectId;
//   final String buildingId; // 👈 NEW

//   const DrawingsTab({
//     super.key,
//     required this.projectId,
//     required this.buildingId,
//   });

//   @override
//   State<DrawingsTab> createState() => _DrawingsTabState();
// }

// class _DrawingsTabState extends State<DrawingsTab> {
//   CollectionReference<Map<String, dynamic>> get _drawingsRef =>
//       FirebaseFirestore.instance
//           .collection('projects')
//           .doc(widget.projectId)
//           .collection('buildings') // 👈 NEW LEVEL
//           .doc(widget.buildingId) // 👈 NEW LEVEL
//           .collection('drawings');

//   bool _isUploading = false;
//   double _uploadProgress = 0.0; // 0.0 → 1.0
//   String? _uploadFileName;

//   Future<void> _uploadDrawing() async {
//     final result = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['pdf'],
//       withData: true,
//     );

//     if (result == null || result.files.isEmpty) return;

//     final picked = result.files.single;
//     final originalFileName = picked.name;

//     try {
//       // 1) Pre-create drawing doc so CF can find it immediately
//       final docRef = _drawingsRef.doc();
//       final drawingId = docRef.id;

//       // Storage path now includes buildingId
//       final storageRef = FirebaseStorage.instance.ref().child(
//         'projects/${widget.projectId}/buildings/${widget.buildingId}/drawings/$drawingId.pdf',
//       );

//       await docRef.set({
//         'title': originalFileName,
//         'filePath': storageRef.fullPath,
//         'downloadUrl': null,
//         'imageUrl': null,
//         'imagePath': null,
//         'sheetNumber': null,
//         'scaleText': '',
//         'calibrated': false,
//         'unit': 'm',
//         'pixelsPerUnit': 0.0,
//         'processingStatus': 'uploading',
//         'processingError': null,
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       // 2) Start upload
//       setState(() {
//         _isUploading = true;
//         _uploadProgress = 0.0;
//         _uploadFileName = originalFileName;
//       });

//       UploadTask uploadTask;

//       if (kIsWeb) {
//         final bytes = picked.bytes;
//         if (bytes == null) {
//           throw Exception('No file bytes on web');
//         }
//         uploadTask = storageRef.putData(
//           bytes,
//           SettableMetadata(contentType: 'application/pdf'),
//         );
//       } else {
//         final path = picked.path;
//         if (path == null) {
//           throw Exception('No file path on this platform');
//         }
//         uploadTask = storageRef.putFile(
//           File(path),
//           SettableMetadata(contentType: 'application/pdf'),
//         );
//       }

//       // 3) Track progress
//       final sub = uploadTask.snapshotEvents.listen((snap) {
//         if (!mounted) return;
//         final total = snap.totalBytes;
//         final transferred = snap.bytesTransferred;
//         if (total > 0) {
//           setState(() {
//             _uploadProgress = transferred / total;
//           });
//         }
//       });

//       final snapshot = await uploadTask;
//       await sub.cancel();

//       if (mounted) {
//         setState(() {
//           _uploadProgress = 1.0;
//         });
//       }

//       final downloadUrl = await snapshot.ref.getDownloadURL();

//       // 4) Update doc with downloadUrl, set to pending so CF converts to PNG
//       await docRef.update({
//         'downloadUrl': downloadUrl,
//         'processingStatus': 'pending',
//         'processingError': null,
//         'updatedAt': FieldValue.serverTimestamp(),
//       });

//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('PDF uploaded. Converting to image...')),
//       );
//     } catch (e) {
//       // mark doc as error if we already created it
//       try {
//         final query =
//             await _drawingsRef
//                 .where('title', isEqualTo: originalFileName)
//                 .orderBy('createdAt', descending: true)
//                 .limit(1)
//                 .get();
//         if (query.docs.isNotEmpty) {
//           await query.docs.first.reference.update({
//             'processingStatus': 'error',
//             'processingError': e.toString(),
//             'updatedAt': FieldValue.serverTimestamp(),
//           });
//         }
//       } catch (_) {}

//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isUploading = false;
//           _uploadProgress = 0.0;
//           _uploadFileName = null;
//         });
//       }
//     }
//   }

//   Widget _buildStatusWidget(Map<String, dynamic> data) {
//     final status = (data['processingStatus'] ?? 'pending') as String;
//     final error = (data['processingError'] ?? '') as String;

//     if (status == 'pending' || status == 'processing') {
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

//     // status == 'ready' or other
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
//     return Scaffold(
//       body: Stack(
//         children: [
//           // 🔹 Main drawings list
//           StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//             stream:
//                 _drawingsRef.orderBy('createdAt', descending: true).snapshots(),
//             builder: (context, snapshot) {
//               if (snapshot.hasError) {
//                 return const Center(child: Text('Error loading drawings'));
//               }
//               if (!snapshot.hasData) {
//                 return const Center(child: CircularProgressIndicator());
//               }

//               final docs = snapshot.data!.docs;
//               if (docs.isEmpty) {
//                 return const Center(
//                   child: Text('No drawings yet. Tap + to upload a PDF.'),
//                 );
//               }

//               return ListView.builder(
//                 itemCount: docs.length,
//                 itemBuilder: (ctx, i) {
//                   final doc = docs[i];
//                   final data = doc.data();
//                   final title = (data['title'] ?? 'Untitled drawing') as String;
//                   final sheetNumber = (data['sheetNumber'] ?? '') as String;
//                   final calibrated = data['calibrated'] == true;
//                   final status =
//                       (data['processingStatus'] ?? 'pending') as String;
//                   final error = (data['processingError'] ?? '') as String;
//                   final imagePath = data['imagePath'] as String?;

//                   return ListTile(
//                     leading: const Icon(Icons.picture_as_pdf),
//                     title: Text(title),
//                     subtitle: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           sheetNumber.isNotEmpty
//                               ? 'Sheet: $sheetNumber'
//                               : 'Unlabeled sheet',
//                         ),
//                         const SizedBox(height: 4),
//                         _buildStatusWidget(data),
//                       ],
//                     ),
//                     trailing: Icon(
//                       calibrated
//                           ? Icons.check_circle
//                           : Icons.radio_button_unchecked,
//                       color: calibrated ? Colors.green : null,
//                     ),
//                     onTap: () async {
//                       // If image is ready, resolve URL & go to ImageTakeoff
//                       if (status == 'ready' &&
//                           imagePath != null &&
//                           imagePath.isNotEmpty) {
//                         try {
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             const SnackBar(
//                               content: Text('Opening image drawing...'),
//                               duration: Duration(seconds: 1),
//                             ),
//                           );

//                           final ref = FirebaseStorage.instance.ref().child(
//                             imagePath,
//                           );
//                           final imageUrl = await ref.getDownloadURL();

//                           if (!mounted) return;
//                           Navigator.of(context).push(
//                             MaterialPageRoute(
//                               builder:
//                                   (_) => ImageTakeoffPage(
//                                     projectId: widget.projectId,
//                                     buildingId: widget.buildingId, // 👈 NEW
//                                     drawingId: doc.id,
//                                     drawingTitle: title,
//                                     imageUrl: imageUrl,
//                                   ),
//                             ),
//                           );
//                           return;
//                         } catch (e) {
//                           if (!mounted) return;
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             SnackBar(
//                               content: Text(
//                                 'Failed to open image drawing: $e\nOpening PDF instead.',
//                               ),
//                             ),
//                           );
//                         }
//                       } else if (status == 'error') {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           SnackBar(
//                             content: Text(
//                               error.isNotEmpty
//                                   ? 'Drawing image conversion failed:\n$error'
//                                   : 'Drawing image conversion failed.',
//                             ),
//                             duration: const Duration(seconds: 6),
//                           ),
//                         );
//                       } else if (status == 'pending' ||
//                           status == 'processing') {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text(
//                               'Image still processing, opening PDF viewer...',
//                             ),
//                           ),
//                         );
//                       }

//                       // Always allow PDF fallback
//                       if (!mounted) return;
//                       Navigator.of(context).push(
//                         MaterialPageRoute(
//                           builder:
//                               (_) => DrawingTakeoffPage(
//                                 projectId: widget.projectId,
//                                 buildingId: widget.buildingId, // 👈 NEW
//                                 drawingId: doc.id,
//                                 drawingTitle: title,
//                               ),
//                         ),
//                       );
//                     },
//                   );
//                 },
//               );
//             },
//           ),

//           // 🔹 Upload progress overlay
//           if (_isUploading)
//             Positioned(
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
//                               _uploadFileName ?? 'Uploading drawing...',
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
//                               value:
//                                   _uploadProgress > 0 && _uploadProgress < 1
//                                       ? _uploadProgress
//                                       : null,
//                               minHeight: 4,
//                             ),
//                           ],
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       Text(
//                         _uploadProgress > 0
//                             ? '${(_uploadProgress * 100).toStringAsFixed(0)}%'
//                             : '',
//                         style: const TextStyle(
//                           color: Colors.white70,
//                           fontSize: 12,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _isUploading ? null : _uploadDrawing,
//         child:
//             _isUploading
//                 ? const Icon(Icons.cloud_upload_outlined)
//                 : const Icon(Icons.add),
//       ),
//     );
//   }
// }
