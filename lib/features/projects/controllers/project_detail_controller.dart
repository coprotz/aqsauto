import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectDetailController extends GetxController {
  final String projectId;
  final String projectName;

  ProjectDetailController({required this.projectId, required this.projectName});

  final RxList<QueryDocumentSnapshot<Map<String, dynamic>>> buildings =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[].obs;
  final RxBool isLoading = true.obs;
  final RxString errorText = ''.obs;

  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _sub;

  Query<Map<String, dynamic>> get _buildingsQuery => FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('buildings')
      .orderBy('createdAt', descending: false);

  @override
  void onInit() {
    super.onInit();
    _listenBuildings();
  }

  void _listenBuildings() {
    isLoading.value = true;
    errorText.value = '';

    _sub = _buildingsQuery.snapshots().listen(
      (snap) {
        buildings.assignAll(snap.docs);
        isLoading.value = false;
      },
      onError: (e) {
        errorText.value = e.toString();
        isLoading.value = false;
      },
    );
  }

  Future<void> addBuilding({required String name, String code = ''}) async {
    final n = name.trim();
    if (n.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .add({
          'name': n,
          'code': code.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> showAddBuildingDialog() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    await Get.dialog(
      AlertDialog(
        title: const Text('Add Building'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Building name',
                hintText: 'e.g. Terminal Building',
              ),
            ),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                hintText: 'e.g. TB-01',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text;
              final code = codeController.text;
              await addBuilding(name: name, code: code);
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  @override
  void onClose() {
    _sub.cancel();
    super.onClose();
  }
}
