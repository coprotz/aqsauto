import 'package:aqs/app_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../models/aqs_project.dart';

class ProjectService {
  ProjectService._();

  static final ProjectService instance = ProjectService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _projects {
    return _db.collection('projects');
  }

  User? _requireUser() {
    final user = _auth.currentUser;

    if (user == null) {
      Get.toNamed(AppRoutes.dashboard);
    }

    return user;
  }

  Stream<List<AqsProject>> watchMyProjects() {
    final user = _requireUser();

    return _projects.where('members', arrayContains: user!.uid).snapshots().map(
      (snapshot) {
        final projects = snapshot.docs.map(AqsProject.fromFirestore).toList();

        projects.sort((a, b) {
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

        return projects;
      },
    );
  }

  Stream<AqsProject?> watchProject(String projectId) {
    return _projects.doc(projectId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }

      return AqsProject.fromFirestore(doc);
    });
  }

  Future<String> createProject({
    required String name,
    required String code,
    required String clientName,
    required String location,
    required String description,
    String currency = 'TZS',
    String measurementStandard = 'Standard',
  }) async {
    final user = _requireUser();

    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw Exception('Project name is required.');
    }

    final projectRef = _projects.doc();

    await projectRef.set({
      'projectId': projectRef.id,

      'name': cleanName,

      'code': code.trim(),

      'clientName': clientName.trim(),

      'location': location.trim(),

      'description': description.trim(),

      'status': 'active',

      'ownerId': user!.uid,

      'members': [user.uid],

      'currency': currency,

      'measurementStandard': measurementStandard,

      // Single-site keeps the simple building-first workflow. Projects can
      // opt into an explicit site layer later from Project Details.
      'structureMode': 'singleSite',

      /*
       * Dashboard counters.
       *
       * These can later be maintained
       * by Cloud Functions.
       */
      'drawingBundleCount': 0,

      'drawingCount': 0,

      'facilityCount': 0,

      'boqTemplateCount': 0,

      'boqItemCount': 0,

      'measurementCount': 0,

      'takeoffProgress': 0.0,

      'createdBy': user.uid,

      'createdAt': FieldValue.serverTimestamp(),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    return projectRef.id;
  }

  Future<void> updateProject({
    required String projectId,
    String? name,
    String? clientName,
    String? location,
    String? description,
    String? status,
  }) async {
    final user = _requireUser();

    final projectRef = _projects.doc(projectId);

    final snapshot = await projectRef.get();

    if (!snapshot.exists) {
      throw Exception('Project not found.');
    }

    final data = snapshot.data() ?? {};

    if (data['ownerId'] != user!.uid) {
      throw Exception('Only the project owner can update this project.');
    }

    final changes = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      changes['name'] = name.trim();
    }

    if (clientName != null) {
      changes['clientName'] = clientName.trim();
    }

    if (location != null) {
      changes['location'] = location.trim();
    }

    if (description != null) {
      changes['description'] = description.trim();
    }

    if (status != null) {
      changes['status'] = status.trim();
    }

    await projectRef.update(changes);
  }
}
