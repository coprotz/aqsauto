// import 'dart:async';

// import 'package:aqs/features/drawings/models/pending_drawing_page.dart';
// import 'package:aqs/features/takeoff/models/drawing_calibration.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:dio/dio.dart' as dio;
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_storage/firebase_storage.dart';

// import '../models/drawing_bundle.dart';
// import '../models/drawing_sheet.dart';

// class DrawingService {
//   DrawingService._();

//   static final DrawingService instance = DrawingService._();

//   final FirebaseFirestore _db = FirebaseFirestore.instance;

//   final FirebaseAuth _auth = FirebaseAuth.instance;

//   static const String _filesGatewayBase = String.fromEnvironment(
//     'AQS_FILES_GATEWAY_URL',
//     defaultValue: 'https://aqssite-files-gateway.aqs-files.workers.dev',
//   );

//   static const String _uploadToken = String.fromEnvironment(
//     'AQS_FILES_UPLOAD_TOKEN',
//   );

//   User _requireUser() {
//     final user = _auth.currentUser;

//     if (user == null) {
//       throw Exception('You must sign in first.');
//     }

//     return user;
//   }

//   DocumentReference<Map<String, dynamic>> _projectRef(String projectId) {
//     return _db.collection('projects').doc(projectId);
//   }

//   DocumentReference<Map<String, dynamic>> _facilityRef({
//     required String projectId,
//     required String facilityId,
//   }) {
//     return _projectRef(projectId).collection('facilities').doc(facilityId);
//   }

//   DocumentReference<Map<String, dynamic>> _buildingRef({
//     required String projectId,
//     required String facilityId,
//   }) {
//     return _projectRef(projectId).collection('facilities').doc(facilityId);
//   }

//   Future<DrawingBundle?> getBundle({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) async {
//     final snapshot =
//         await _bundlesRef(
//           projectId: projectId,
//           facilityId: facilityId,
//         ).doc(bundleId).get();

//     if (!snapshot.exists) {
//       return null;
//     }

//     return DrawingBundle.fromFirestore(snapshot);
//   }

//   Future<DocumentReference<Map<String, dynamic>>> _workspaceRef({
//     required String projectId,
//     required String facilityId,
//   }) async {
//     final facilityRef = _facilityRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );
//     final facilitySnapshot = await facilityRef.get();
//     if (facilitySnapshot.exists) {
//       return facilityRef;
//     }

//     final buildingRef = _buildingRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );
//     final buildingSnapshot = await buildingRef.get();
//     if (buildingSnapshot.exists) {
//       return buildingRef;
//     }

//     return facilityRef;
//   }

//   CollectionReference<Map<String, dynamic>> _bundlesRef({
//     required String projectId,
//     required String facilityId,
//   }) {
//     return _facilityRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).collection('drawingBundles');
//   }

//   CollectionReference<Map<String, dynamic>> _buildingBundlesRef({
//     required String projectId,
//     required String facilityId,
//   }) {
//     return _buildingRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).collection('drawingBundles');
//   }

//   // CollectionReference<Map<String, dynamic>> _drawingsRef({
//   //   required String projectId,
//   //   required String facilityId,
//   // }) {
//   //   return _facilityRef(
//   //     projectId: projectId,
//   //     facilityId: facilityId,
//   //   ).collection('drawings');
//   // }
//   CollectionReference<Map<String, dynamic>> _drawingsRef(
//     String projectId,
//     String facilityId,
//   ) {
//     return _db
//         .collection('projects')
//         .doc(projectId)
//         .collection('facilities')
//         .doc(facilityId)
//         .collection('drawings');
//   }

//   CollectionReference<Map<String, dynamic>> _buildingDrawingsRef({
//     required String projectId,
//     required String facilityId,
//   }) {
//     return _buildingRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).collection('drawings');
//   }

//   DocumentReference<Map<String, dynamic>> _drawingRef(
//     String projectId,
//     String facilityId,
//     String drawingId,
//   ) {
//     return _db
//         .collection('projects')
//         .doc(projectId)
//         .collection('facilities')
//         .doc(facilityId)
//         .collection('drawings')
//         .doc(drawingId);
//   }

//   Future<void> incrementBundleDrawings({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//     required int addedDrawings,
//     required int addedOriginalBytes,
//     required int addedSelectedBytes,
//     required int addedStorageBytes,
//   }) async {
//     if (addedDrawings <= 0) {
//       return;
//     }

//     final bundleRef = _bundlesRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).doc(bundleId);

//     await bundleRef.update({
//       //
//       // Number of drawings currently
//       // belonging to this bundle.
//       //
//       'pageCount': FieldValue.increment(addedDrawings),

//       'selectedPageCount': FieldValue.increment(addedDrawings),

//       //
//       // Original incoming PDF bytes.
//       // This is useful for analytics even though
//       // original source PDFs are not stored.
//       //
//       'originalSizeBytes': FieldValue.increment(addedOriginalBytes),

//       //
//       // Actual extracted PDF bytes.
//       //
//       'selectedSizeBytes': FieldValue.increment(addedSelectedBytes),

//       //
//       // Actual R2 usage.
//       //
//       'storageBytes': FieldValue.increment(addedStorageBytes),

//       'status': 'ready',

//       'updatedAt': FieldValue.serverTimestamp(),
//     });
//   }

//   Future<void> saveDrawingCalibration({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//     required DrawingCalibration calibration,
//   }) async {
//     await _drawingsRef(projectId, facilityId).doc(drawingId).update({
//       'calibrated': true,

//       'calibration': calibration.toMap(),

//       'status': 'ready',

//       'updatedAt': FieldValue.serverTimestamp(),
//     });
//   }

//   Future<void> _verifyFacilityAccess({
//     required String projectId,
//     required String facilityId,
//   }) async {
//     final user = _requireUser();

//     final projectSnapshot = await _projectRef(projectId).get();

//     if (!projectSnapshot.exists) {
//       throw Exception('Project not found.');
//     }

//     final projectData = projectSnapshot.data() ?? <String, dynamic>{};

//     final ownerId = (projectData['ownerId'] ?? '').toString();

//     final members =
//         (projectData['members'] as List? ?? const [])
//             .map((value) => value.toString())
//             .toList();

//     if (ownerId != user.uid && !members.contains(user.uid)) {
//       throw Exception('You do not have access to this project.');
//     }

//     final facilitySnapshot =
//         await _facilityRef(projectId: projectId, facilityId: facilityId).get();

//     if (facilitySnapshot.exists) {
//       return;
//     }

//     final buildingSnapshot =
//         await _buildingRef(projectId: projectId, facilityId: facilityId).get();

//     if (!buildingSnapshot.exists) {
//       throw Exception('Facility/building not found.');
//     }
//   }

//   Stream<List<DrawingBundle>> watchBundles({
//     required String projectId,
//     required String facilityId,
//   }) {
//     final controller = StreamController<List<DrawingBundle>>();
//     var facilityBundles = <DrawingBundle>[];
//     var buildingBundles = <DrawingBundle>[];
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? facilitySub;
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? buildingSub;

//     void emit() {
//       final byKey = <String, DrawingBundle>{};

//       for (final bundle in buildingBundles) {
//         byKey[bundle.id] = bundle;
//       }

//       for (final bundle in facilityBundles) {
//         byKey[bundle.id] = bundle;
//       }

//       final bundles = byKey.values.toList();

//       bundles.sort((a, b) {
//         final aDate =
//             a.updatedAt ??
//             a.createdAt ??
//             DateTime.fromMillisecondsSinceEpoch(0);

//         final bDate =
//             b.updatedAt ??
//             b.createdAt ??
//             DateTime.fromMillisecondsSinceEpoch(0);

//         return bDate.compareTo(aDate);
//       });

//       if (!controller.isClosed) {
//         controller.add(bundles);
//       }
//     }

//     controller.onListen = () {
//       facilitySub = _bundlesRef(
//         projectId: projectId,
//         facilityId: facilityId,
//       ).snapshots().listen((snapshot) {
//         facilityBundles =
//             snapshot.docs.map(DrawingBundle.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);

//       buildingSub = _buildingBundlesRef(
//         projectId: projectId,
//         facilityId: facilityId,
//       ).snapshots().listen((snapshot) {
//         buildingBundles =
//             snapshot.docs.map(DrawingBundle.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);
//     };

//     controller.onCancel = () async {
//       await facilitySub?.cancel();
//       await buildingSub?.cancel();
//     };

//     return controller.stream;
//   }

//   Future<void> incrementMeasurementCount({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//   }) async {
//     await _drawingsRef(projectId, facilityId).doc(drawingId).update({
//       'measurementCount': FieldValue.increment(1),

//       'status': 'measured',

//       'updatedAt': FieldValue.serverTimestamp(),
//     });
//   }

//   Stream<DrawingBundle?> watchBundle({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) {
//     return _bundlesRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).doc(bundleId).snapshots().map((doc) {
//       if (!doc.exists) {
//         return null;
//       }

//       return DrawingBundle.fromFirestore(doc);
//     });
//   }

//   Stream<List<DrawingSheet>> watchDrawings({
//     required String projectId,
//     required String facilityId,
//   }) {
//     final controller = StreamController<List<DrawingSheet>>();
//     var facilityDrawings = <DrawingSheet>[];
//     var buildingDrawings = <DrawingSheet>[];
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? facilitySub;
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? buildingSub;

//     void emit() {
//       final byKey = <String, DrawingSheet>{};
//       for (final drawing in buildingDrawings) {
//         byKey[drawing.id] = drawing;
//       }
//       for (final drawing in facilityDrawings) {
//         byKey[drawing.id] = drawing;
//       }
//       final drawings = byKey.values.toList();
//       drawings.sort((a, b) {
//         final drawingNoCompare = a.drawingNumber.compareTo(b.drawingNumber);

//         if (drawingNoCompare != 0) {
//           return drawingNoCompare;
//         }

//         return a.pageNumber.compareTo(b.pageNumber);
//       });

//       if (!controller.isClosed) {
//         controller.add(drawings);
//       }
//     }

//     controller.onListen = () {
//       facilitySub = _drawingsRef(projectId, facilityId).snapshots().listen((
//         snapshot,
//       ) {
//         facilityDrawings =
//             snapshot.docs.map(DrawingSheet.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);

//       buildingSub = _buildingDrawingsRef(
//         projectId: projectId,
//         facilityId: facilityId,
//       ).snapshots().listen((snapshot) {
//         buildingDrawings =
//             snapshot.docs.map(DrawingSheet.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);
//     };

//     controller.onCancel = () async {
//       await facilitySub?.cancel();
//       await buildingSub?.cancel();
//     };

//     return controller.stream;
//   }

//   Stream<List<DrawingSheet>> watchBundleDrawings({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) {
//     final controller = StreamController<List<DrawingSheet>>();
//     var facilityDrawings = <DrawingSheet>[];
//     var buildingDrawings = <DrawingSheet>[];
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? facilitySub;
//     StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? buildingSub;

//     void emit() {
//       final byKey = <String, DrawingSheet>{};

//       for (final drawing in buildingDrawings) {
//         byKey[drawing.id] = drawing;
//       }

//       for (final drawing in facilityDrawings) {
//         byKey[drawing.id] = drawing;
//       }

//       final drawings = byKey.values.toList();
//       drawings.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

//       if (!controller.isClosed) {
//         controller.add(drawings);
//       }
//     }

//     controller.onListen = () {
//       facilitySub = _drawingsRef(
//         projectId,
//         facilityId,
//       ).where('bundleId', isEqualTo: bundleId).snapshots().listen((snapshot) {
//         facilityDrawings =
//             snapshot.docs.map(DrawingSheet.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);

//       buildingSub = _buildingDrawingsRef(
//         projectId: projectId,
//         facilityId: facilityId,
//       ).where('bundleId', isEqualTo: bundleId).snapshots().listen((snapshot) {
//         buildingDrawings =
//             snapshot.docs.map(DrawingSheet.fromFirestore).toList();
//         emit();
//       }, onError: controller.addError);
//     };

//     controller.onCancel = () async {
//       await facilitySub?.cancel();
//       await buildingSub?.cancel();
//     };

//     return controller.stream;
//   }

//   Stream<DrawingSheet?> watchDrawing({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//   }) {
//     return _drawingsRef(projectId, facilityId).doc(drawingId).snapshots().map((
//       doc,
//     ) {
//       if (!doc.exists) {
//         return null;
//       }

//       return DrawingSheet.fromFirestore(doc);
//     });
//   }

//   Future<DocumentSnapshot<Map<String, dynamic>>> drawingSnapshot({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//   }) async {
//     final facilityDoc =
//         await _drawingsRef(projectId, facilityId).doc(drawingId).get();

//     if (facilityDoc.exists) {
//       return facilityDoc;
//     }

//     return _buildingDrawingsRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).doc(drawingId).get();
//   }

//   Future<List<String>> createDrawingSheetsBatch({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//     required String discipline,
//     required String revision,
//     required String sourceFileName,
//     required String pdfPath,
//     Map<int, String>? pdfPathByPageIndex,
//     Map<int, String>? downloadUrlByPageIndex,
//     String storageProvider = 'firebase',
//     required List<PendingDrawingPage> pages,
//   }) async {
//     final user = _requireUser();

//     if (pages.isEmpty) {
//       return [];
//     }

//     await _verifyFacilityAccess(projectId: projectId, facilityId: facilityId);

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     final bundleRef = workspaceRef.collection('drawingBundles').doc(bundleId);

//     final bundleSnapshot = await bundleRef.get();

//     if (!bundleSnapshot.exists) {
//       throw Exception('Drawing bundle not found.');
//     }

//     final facilityRef = workspaceRef;

//     final drawingsCollection = workspaceRef.collection('drawings');

//     //
//     // Only selected pages should become
//     // drawing register records.
//     //
//     final selectedPages =
//         pages.where((page) => page.selected).toList()
//           ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//     if (selectedPages.isEmpty) {
//       throw Exception('Select at least one drawing page.');
//     }

//     final createdIds = <String>[];

//     //
//     // Firestore batches have a finite operation
//     // limit, so we intentionally keep each batch
//     // comfortably below the maximum.
//     //
//     const maxWritesPerBatch = 400;

//     var index = 0;

//     while (index < selectedPages.length) {
//       final end = (index + maxWritesPerBatch).clamp(0, selectedPages.length);

//       final chunk = selectedPages.sublist(index, end);

//       final batch = _db.batch();

//       for (final page in chunk) {
//         final drawingRef = drawingsCollection.doc();

//         createdIds.add(drawingRef.id);

//         final cleanDrawingNumber = page.drawingNumber.trim();

//         final cleanTitle = page.title.trim();

//         final needsReview = cleanDrawingNumber.isEmpty || cleanTitle.isEmpty;
//         final pagePdfPath = pdfPathByPageIndex?[page.pageIndex] ?? pdfPath;
//         final pageDownloadUrl = downloadUrlByPageIndex?[page.pageIndex] ?? '';

//         batch.set(drawingRef, {
//           'drawingId': drawingRef.id,

//           'projectId': projectId,

//           'facilityId': facilityId,

//           'bundleId': bundleId,

//           'drawingNumber': cleanDrawingNumber,

//           'title':
//               cleanTitle.isEmpty
//                   ? 'Drawing Page ${page.sourcePageNumber}'
//                   : cleanTitle,

//           'discipline':
//               discipline.trim().isEmpty ? 'general' : discipline.trim(),

//           'revision': revision.trim(),

//           //
//           // Register position.
//           //
//           'pageNumber': page.sortOrder - 1,

//           //
//           // Original source PDF page.
//           //
//           'sourcePageNumber': page.sourcePageNumber,

//           //
//           // QS-defined working order.
//           //
//           'sortOrder': page.sortOrder,

//           'sourceFileName': sourceFileName.trim(),

//           'estimatedPdfSizeBytes': page.estimatedPdfSizeBytes,

//           'pdfSizeBytes': page.pdfSizeBytes ?? page.estimatedPdfSizeBytes,

//           'storageBytes': page.displayPdfSizeBytes,

//           //
//           // Individual drawing currently points
//           // to the original bundle PDF.
//           //
//           'pdfPath': pagePdfPath.trim(),

//           'filePath': pagePdfPath.trim(),

//           'downloadUrl': pageDownloadUrl.trim(),

//           'storageProvider':
//               storageProvider.trim().isEmpty
//                   ? 'firebase'
//                   : storageProvider.trim(),

//           'thumbnailPath': '',

//           'scaleType': 'unknown',

//           'scaleRatio': null,

//           'status': needsReview ? 'needs_review' : 'needs_calibration',

//           'calibrated': false,

//           'measurementCount': 0,

//           'createdBy': user.uid,

//           'createdAt': FieldValue.serverTimestamp(),

//           'updatedAt': FieldValue.serverTimestamp(),
//         });
//       }

//       await batch.commit();

//       index = end;
//     }

//     //
//     // Update the facility once,
//     // not once per drawing.
//     //
//     await facilityRef.update({
//       'drawingCount': FieldValue.increment(selectedPages.length),

//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     return createdIds;
//   }

//   Future<String> createDrawingBundle({
//     required String projectId,
//     required String facilityId,
//     required String name,
//     required String discipline,
//     required String issueType,
//     required String revision,
//     required String description,
//     required String fileName,
//     required String storagePath,
//     int pageCount = 0,
//     int originalSizeBytes = 0,
//     int selectedSizeBytes = 0,
//     String status = 'uploading',
//   }) async {
//     final user = _requireUser();

//     await _verifyFacilityAccess(projectId: projectId, facilityId: facilityId);

//     final cleanName = name.trim();

//     if (cleanName.isEmpty) {
//       throw Exception('Drawing bundle name is required.');
//     }

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     final bundleRef = workspaceRef.collection('drawingBundles').doc();

//     final facilityRef = workspaceRef;

//     final batch = _db.batch();

//     batch.set(bundleRef, {
//       'bundleId': bundleRef.id,

//       'projectId': projectId,

//       'facilityId': facilityId,

//       'name': cleanName,

//       'discipline': discipline.trim().isEmpty ? 'general' : discipline.trim(),

//       'issueType': issueType.trim().isEmpty ? 'construction' : issueType.trim(),

//       'revision': revision.trim(),

//       'description': description.trim(),

//       'fileName': fileName.trim(),

//       'storagePath': storagePath.trim(),

//       'pageCount': pageCount,

//       'originalSizeBytes': originalSizeBytes,

//       'selectedSizeBytes': selectedSizeBytes,

//       'status': status.trim().isEmpty ? 'uploading' : status.trim(),

//       'createdBy': user.uid,

//       'createdAt': FieldValue.serverTimestamp(),

//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     batch.update(facilityRef, {
//       'drawingBundleCount': FieldValue.increment(1),

//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     await batch.commit();

//     return bundleRef.id;
//   }

//   Future<void> deleteDrawing({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//   }) async {
//     _requireUser();

//     await _verifyFacilityAccess(projectId: projectId, facilityId: facilityId);

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     final drawingRef = workspaceRef.collection('drawings').doc(drawingId);
//     final drawingSnapshot = await drawingRef.get();

//     if (!drawingSnapshot.exists) {
//       final fallbackRef =
//           workspaceRef.id == facilityId
//               ? _buildingRef(
//                 projectId: projectId,
//                 facilityId: facilityId,
//               ).collection('drawings').doc(drawingId)
//               : _facilityRef(
//                 projectId: projectId,
//                 facilityId: facilityId,
//               ).collection('drawings').doc(drawingId);
//       final fallbackSnapshot = await fallbackRef.get();

//       if (!fallbackSnapshot.exists) {
//         throw Exception('Drawing not found.');
//       }

//       await _deleteDrawingDoc(
//         workspaceRef: fallbackRef.parent.parent!,
//         drawingRef: fallbackRef,
//         drawingData: fallbackSnapshot.data() ?? <String, dynamic>{},
//       );

//       return;
//     }

//     await _deleteDrawingDoc(
//       workspaceRef: workspaceRef,
//       drawingRef: drawingRef,
//       drawingData: drawingSnapshot.data() ?? <String, dynamic>{},
//     );
//   }

//   Future<void> _deleteDrawingDoc({
//     required DocumentReference<Map<String, dynamic>> workspaceRef,
//     required DocumentReference<Map<String, dynamic>> drawingRef,
//     required Map<String, dynamic> drawingData,
//   }) async {
//     final bundleId = (drawingData['bundleId'] ?? '').toString().trim();

//     await _deleteDrawingStoredFiles(drawingData);

//     final batch = _db.batch();

//     batch.delete(drawingRef);

//     batch.update(workspaceRef, {
//       'drawingCount': FieldValue.increment(-1),
//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     if (bundleId.isNotEmpty) {
//       batch.update(workspaceRef.collection('drawingBundles').doc(bundleId), {
//         'selectedPageCount': FieldValue.increment(-1),
//         'pageCount': FieldValue.increment(-1),
//         'updatedAt': FieldValue.serverTimestamp(),
//       });
//     }

//     await batch.commit();
//   }

//   Future<void> _deleteDrawingStoredFiles(Map<String, dynamic> data) async {
//     final provider = (data['storageProvider'] ?? '').toString().trim();
//     final pdfPath =
//         (data['pdfPath'] ?? data['filePath'] ?? '').toString().trim();
//     final imagePath =
//         (data['thumbnailPath'] ?? data['imagePath'] ?? '').toString().trim();
//     final downloadUrl = (data['downloadUrl'] ?? '').toString();
//     final imageUrl = (data['imageUrl'] ?? '').toString();
//     final usesFirebase =
//         provider == 'firebase' ||
//         downloadUrl.contains('firebasestorage.googleapis.com') ||
//         imageUrl.contains('firebasestorage.googleapis.com');

//     Future<void> deleteFirebaseObject(String path) async {
//       if (path.isEmpty) {
//         return;
//       }

//       try {
//         await FirebaseStorage.instance.ref(path).delete();
//       } catch (_) {}
//     }

//     Future<void> deleteGatewayObject(String key) async {
//       if (key.isEmpty || _uploadToken.isEmpty) {
//         return;
//       }

//       try {
//         final client = dio.Dio(
//           dio.BaseOptions(
//             headers: {'Authorization': 'Bearer $_uploadToken'},
//             validateStatus: (status) {
//               return status != null && status >= 200 && status < 300;
//             },
//           ),
//         );

//         await client.delete(
//           '$_filesGatewayBase/upload/${Uri.encodeComponent(key)}',
//         );
//       } catch (_) {}
//     }

//     if (usesFirebase) {
//       await Future.wait([
//         deleteFirebaseObject(pdfPath),
//         deleteFirebaseObject(imagePath),
//       ]);
//     } else {
//       await Future.wait([
//         deleteGatewayObject(pdfPath),
//         deleteGatewayObject(imagePath),
//       ]);
//     }
//   }

//   Future<String> createDrawingSheet({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//     required String drawingNumber,
//     required String title,
//     required String discipline,
//     required String revision,

//     required int pageNumber,

//     required int sourcePageNumber,
//     required int sortOrder,
//     required String sourceFileName,

//     required String pdfPath,
//     required String thumbnailPath,

//     String scaleType = 'unknown',
//     double? scaleRatio,
//     String status = 'needs_calibration',
//     bool calibrated = false,
//   }) async {
//     _requireUser();

//     await _verifyFacilityAccess(projectId: projectId, facilityId: facilityId);

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     final bundleSnapshot =
//         await workspaceRef.collection('drawingBundles').doc(bundleId).get();

//     if (!bundleSnapshot.exists) {
//       throw Exception('Drawing bundle not found.');
//     }

//     final drawingRef = workspaceRef.collection('drawings').doc();

//     final facilityRef = workspaceRef;

//     final batch = _db.batch();

//     batch.set(drawingRef, {
//       'drawingId': drawingRef.id,

//       'projectId': projectId,

//       'facilityId': facilityId,

//       'bundleId': bundleId,

//       'drawingNumber': drawingNumber.trim(),

//       'title':
//           title.trim().isEmpty
//               ? 'Drawing Page ${pageNumber + 1}'
//               : title.trim(),

//       'discipline': discipline.trim().isEmpty ? 'general' : discipline.trim(),

//       'revision': revision.trim(),

//       'pageNumber': pageNumber,

//       'pdfPath': pdfPath.trim(),

//       'thumbnailPath': thumbnailPath.trim(),

//       'scaleType': scaleType,

//       'scaleRatio': scaleRatio,

//       'status': status,

//       'calibrated': calibrated,
//       'sourcePageNumber': sourcePageNumber,

//       'sortOrder': sortOrder,

//       'sourceFileName': sourceFileName,

//       'measurementCount': 0,

//       'createdAt': FieldValue.serverTimestamp(),

//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     batch.update(facilityRef, {
//       'drawingCount': FieldValue.increment(1),

//       'updatedAt': FieldValue.serverTimestamp(),
//     });

//     await batch.commit();

//     return drawingRef.id;
//   }

//   Future<void> updateBundle({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//     String? name,
//     String? discipline,
//     String? issueType,
//     String? revision,
//     String? description,
//     String? status,
//     String? storagePath,
//     int? pageCount,
//     int? selectedPageCount,
//     int? originalSizeBytes,
//     int? selectedSizeBytes,
//     int? storageBytes,
//   }) async {
//     _requireUser();

//     final changes = <String, dynamic>{
//       'updatedAt': FieldValue.serverTimestamp(),
//     };

//     if (name != null) {
//       changes['name'] = name.trim();
//     }
//     if (selectedPageCount != null) {
//       changes['selectedPageCount'] = selectedPageCount;
//     }

//     if (discipline != null) {
//       changes['discipline'] = discipline.trim();
//     }

//     if (issueType != null) {
//       changes['issueType'] = issueType.trim();
//     }

//     if (revision != null) {
//       changes['revision'] = revision.trim();
//     }

//     if (description != null) {
//       changes['description'] = description.trim();
//     }

//     if (status != null) {
//       changes['status'] = status.trim();
//     }

//     if (pageCount != null) {
//       changes['pageCount'] = pageCount;
//     }
//     if (originalSizeBytes != null) {
//       changes['originalSizeBytes'] = originalSizeBytes;
//     }
//     if (selectedSizeBytes != null) {
//       changes['selectedSizeBytes'] = selectedSizeBytes;
//     }
//     if (storageBytes != null) {
//       changes['storageBytes'] = storageBytes;
//     }
//     if (storagePath != null) {
//       changes['storagePath'] = storagePath.trim();
//     }

//     final bundleRef = await _bundleDocRef(
//       projectId: projectId,
//       facilityId: facilityId,
//       bundleId: bundleId,
//     );

//     await bundleRef.update(changes);
//   }

//   Future<DocumentReference<Map<String, dynamic>>> _bundleDocRef({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) async {
//     final facilityBundleRef = _facilityRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).collection('drawingBundles').doc(bundleId);
//     final facilityBundleSnapshot = await facilityBundleRef.get();

//     if (facilityBundleSnapshot.exists) {
//       return facilityBundleRef;
//     }

//     final buildingBundleRef = _buildingRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     ).collection('drawingBundles').doc(bundleId);
//     final buildingBundleSnapshot = await buildingBundleRef.get();

//     if (buildingBundleSnapshot.exists) {
//       return buildingBundleRef;
//     }

//     return facilityBundleRef;
//   }

//   Future<void> deleteBundle({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) async {
//     _requireUser();

//     await _verifyFacilityAccess(projectId: projectId, facilityId: facilityId);

//     final bundleRef = await _bundleDocRef(
//       projectId: projectId,
//       facilityId: facilityId,
//       bundleId: bundleId,
//     );
//     final workspaceRef = bundleRef.parent.parent!;

//     final drawingsSnapshot =
//         await workspaceRef
//             .collection('drawings')
//             .where('bundleId', isEqualTo: bundleId)
//             .get();

//     for (final drawingDoc in drawingsSnapshot.docs) {
//       await _deleteDrawingStoredFiles(drawingDoc.data());
//     }

//     const maxWritesPerBatch = 400;
//     var index = 0;

//     while (index < drawingsSnapshot.docs.length) {
//       final end = (index + maxWritesPerBatch).clamp(
//         0,
//         drawingsSnapshot.docs.length,
//       );
//       final batch = _db.batch();

//       for (final drawingDoc in drawingsSnapshot.docs.sublist(index, end)) {
//         batch.delete(drawingDoc.reference);
//       }

//       if (end >= drawingsSnapshot.docs.length) {
//         batch.delete(bundleRef);
//         batch.update(workspaceRef, {
//           'drawingBundleCount': FieldValue.increment(-1),
//           'drawingCount': FieldValue.increment(-drawingsSnapshot.docs.length),
//           'updatedAt': FieldValue.serverTimestamp(),
//         });
//       }

//       await batch.commit();
//       index = end;
//     }

//     if (drawingsSnapshot.docs.isEmpty) {
//       final batch = _db.batch();
//       batch.delete(bundleRef);
//       batch.update(workspaceRef, {
//         'drawingBundleCount': FieldValue.increment(-1),
//         'updatedAt': FieldValue.serverTimestamp(),
//       });
//       await batch.commit();
//     }
//   }

//   Future<void> updateDrawing({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//     String? drawingNumber,
//     String? title,
//     String? revision,
//     String? discipline,
//     String? status,
//     String? scaleType,
//     double? scaleRatio,
//     bool? calibrated,
//     String? thumbnailPath,
//   }) async {
//     _requireUser();

//     final changes = <String, dynamic>{
//       'updatedAt': FieldValue.serverTimestamp(),
//     };

//     if (drawingNumber != null) {
//       changes['drawingNumber'] = drawingNumber.trim();
//     }

//     if (title != null) {
//       changes['title'] = title.trim();
//     }

//     if (revision != null) {
//       changes['revision'] = revision.trim();
//     }

//     if (discipline != null) {
//       changes['discipline'] = discipline.trim();
//     }

//     if (status != null) {
//       changes['status'] = status.trim();
//     }

//     if (scaleType != null) {
//       changes['scaleType'] = scaleType.trim();
//     }

//     if (scaleRatio != null) {
//       changes['scaleRatio'] = scaleRatio;
//     }

//     if (calibrated != null) {
//       changes['calibrated'] = calibrated;
//     }

//     if (thumbnailPath != null) {
//       changes['thumbnailPath'] = thumbnailPath.trim();
//     }

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     await workspaceRef.collection('drawings').doc(drawingId).update(changes);
//   }

//   Future<void> saveCalibration({
//     required String projectId,
//     required String facilityId,
//     required String drawingId,
//     required double scaleRatio,
//     required double point1X,
//     required double point1Y,
//     required double point2X,
//     required double point2Y,
//     required double realLength,
//     String unit = 'm',
//   }) async {
//     _requireUser();

//     if (scaleRatio <= 0) {
//       throw Exception('Scale ratio must be greater than zero.');
//     }

//     if (realLength <= 0) {
//       throw Exception('Calibration length must be greater than zero.');
//     }

//     final workspaceRef = await _workspaceRef(
//       projectId: projectId,
//       facilityId: facilityId,
//     );

//     await workspaceRef.collection('drawings').doc(drawingId).update({
//       'scaleType': 'calibrated',

//       'scaleRatio': scaleRatio,

//       'calibrated': true,

//       'status': 'ready',

//       'calibration': {
//         'point1': {'x': point1X, 'y': point1Y},

//         'point2': {'x': point2X, 'y': point2Y},

//         'realLength': realLength,

//         'unit': unit,

//         'calibratedAt': FieldValue.serverTimestamp(),
//       },

//       'updatedAt': FieldValue.serverTimestamp(),
//     });
//   }

//   Future<void> markBundleReady({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//     required int pageCount,
//   }) async {
//     await updateBundle(
//       projectId: projectId,
//       facilityId: facilityId,
//       bundleId: bundleId,
//       status: 'ready',
//       pageCount: pageCount,
//     );
//   }

//   Future<void> markBundleFailed({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) async {
//     await updateBundle(
//       projectId: projectId,
//       facilityId: facilityId,
//       bundleId: bundleId,
//       status: 'failed',
//     );
//   }

//   Future<void> markBundleSuperseded({
//     required String projectId,
//     required String facilityId,
//     required String bundleId,
//   }) async {
//     await updateBundle(
//       projectId: projectId,
//       facilityId: facilityId,
//       bundleId: bundleId,
//       status: 'superseded',
//     );
//   }
// }
