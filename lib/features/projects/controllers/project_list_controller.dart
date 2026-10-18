import 'dart:async';

import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectsListController extends GetxController {
  final CollectionReference<Map<String, dynamic>> _projectsRef =
      FirebaseFirestore.instance.collection('projects');

  final RxList<QueryDocumentSnapshot<Map<String, dynamic>>> projects =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[].obs;

  final RxBool isLoading = true.obs;
  final RxString errorText = ''.obs;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void onInit() {
    super.onInit();
    _listenProjects();
  }

  void _listenProjects() {
    isLoading.value = true;
    errorText.value = '';

    _sub = _projectsRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snap) {
            projects.assignAll(snap.docs);
            isLoading.value = false;
          },
          onError: (e) {
            errorText.value = e.toString();
            isLoading.value = false;
          },
        );
  }

  Future<void> createProjectDialog() async {
    final nameController = TextEditingController();
    final clientController = TextEditingController();
    final currencyController = TextEditingController(text: 'TZS');

    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Project name'),
            ),
            TextField(
              controller: clientController,
              decoration: const InputDecoration(labelText: 'Client (optional)'),
            ),
            TextField(
              controller: currencyController,
              decoration: const InputDecoration(labelText: 'Currency'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Create'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final client = clientController.text.trim();
    final currency =
        currencyController.text.trim().isEmpty
            ? 'TZS'
            : currencyController.text.trim();

    if (name.isEmpty) {
      Get.snackbar(
        'Missing info',
        'Project name is required',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final canCreateProject =
        await SubscriptionService.instance.canCreateProject(user: user);
    if (!canCreateProject) {
      Get.snackbar(
        'Subscription required',
        'Free plan allows 1 project only. Please subscribe to add more projects.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await _projectsRef.add({
      'name': name,
      'clientName': client.isEmpty ? null : client,
      'currency': currency,
      'ownerId': user?.uid,
      'members': user == null ? <String>[] : [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void openProject(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = (data['name'] ?? 'Untitled').toString();

    Get.toNamed(
      '/project-detail',
      arguments: {'projectId': doc.id, 'projectName': name},
    );
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}
