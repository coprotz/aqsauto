import 'package:aqs/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../models/project_facility.dart';

class FacilityService {
  FacilityService._();

  static final FacilityService instance = FacilityService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? _requireUser() {
    final user = _auth.currentUser;

    if (user == null) {
      Get.toNamed(AppRoutes.dashboard);
    }

    return user;
  }

  CollectionReference<Map<String, dynamic>> _facilities(String projectId) {
    return _db.collection('projects').doc(projectId).collection('facilities');
  }

  Stream<List<ProjectFacility>> watchFacilities(String projectId) {
    return _facilities(projectId).snapshots().map((snapshot) {
      final facilities =
          snapshot.docs.map(ProjectFacility.fromFirestore).toList();

      facilities.sort((a, b) {
        final aDate =
            a.updatedAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final bDate =
            b.updatedAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      });

      return facilities;
    });
  }

  Stream<ProjectFacility?> watchFacility({
    required String projectId,
    required String facilityId,
  }) {
    return _facilities(projectId).doc(facilityId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }

      return ProjectFacility.fromFirestore(doc);
    });
  }

  Future<String> createFacility({
    required String projectId,
    required String name,
    required String code,
    required String type,
    required String description,
    String siteId = '',
    String siteName = '',
  }) async {
    final user = _requireUser();

    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw Exception('Facility name is required.');
    }

    final projectRef = _db.collection('projects').doc(projectId);

    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw Exception('Project not found.');
    }

    final projectData = projectSnapshot.data() ?? <String, dynamic>{};

    final ownerId = (projectData['ownerId'] ?? '').toString();

    final members =
        (projectData['members'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();

    if (ownerId != user!.uid && !members.contains(user.uid)) {
      throw Exception('You do not have access to this project.');
    }

    final facilityRef = _facilities(projectId).doc();

    final batch = _db.batch();

    batch.set(facilityRef, {
      'facilityId': facilityRef.id,

      'projectId': projectId,

      'siteId': siteId.trim(),

      'siteName': siteName.trim(),

      'name': cleanName,

      'code': code.trim(),

      'type': type.trim().isEmpty ? 'building' : type.trim(),

      'description': description.trim(),

      'status': 'active',

      'drawingBundleCount': 0,

      'drawingCount': 0,

      'boqTemplateCount': 0,

      'boqItemCount': 0,

      'measurementCount': 0,

      'takeoffProgress': 0.0,

      'createdBy': user.uid,

      'createdAt': FieldValue.serverTimestamp(),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    /*
     * Keep a project-level facility
     * counter for quick dashboard use.
     */
    batch.update(projectRef, {
      'facilityCount': FieldValue.increment(1),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return facilityRef.id;
  }

  Future<void> updateFacility({
    required String projectId,
    required String facilityId,
    String? name,
    String? code,
    String? type,
    String? description,
    String? status,
  }) async {
    _requireUser();

    final changes = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      final cleanName = name.trim();

      if (cleanName.isEmpty) {
        throw Exception('Facility name cannot be empty.');
      }

      changes['name'] = cleanName;
    }

    if (code != null) {
      changes['code'] = code.trim();
    }

    if (type != null) {
      changes['type'] = type.trim();
    }

    if (description != null) {
      changes['description'] = description.trim();
    }

    if (status != null) {
      changes['status'] = status.trim();
    }

    await _facilities(projectId).doc(facilityId).update(changes);
  }
}
