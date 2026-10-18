import 'package:aqs/features/utils/customs/custom_get_boq_code.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WallingConfig {
  final String configId;
  final String measureConfigRef;
  final String boqCode;
  final double wallHeightM;

  const WallingConfig({
    required this.configId,
    required this.measureConfigRef,
    required this.boqCode,
    required this.wallHeightM,
  });
}

extension WallingConfigX on WallingConfig {
  DocumentReference<Map<String, dynamic>> get ref =>
      FirebaseFirestore.instance.doc(measureConfigRef);
}

class WallingConfigController extends GetxController {
  WallingConfigController({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;

  late final DocumentReference<Map<String, dynamic>> drawingRef;
  late final CollectionReference<Map<String, dynamic>> configsRef;

  final Rxn<WallingConfig> activeConfig = Rxn<WallingConfig>();
  String? bodCode;

  @override
  void onInit() {
    super.onInit();
    drawingRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('drawings')
        .doc(drawingId);

    configsRef = drawingRef.collection('measureConfigs');
  }

  DocumentReference<Map<String, dynamic>>? get activeConfigRef {
    final cfg = activeConfig.value;
    if (cfg == null) return null;
    return FirebaseFirestore.instance.doc(cfg.measureConfigRef);
  }

  Future<void> updateWallHeight(double newHeightM) async {
    final cfg = activeConfig.value;
    final ref = activeConfigRef;
    if (cfg == null || ref == null) return;

    if (newHeightM <= 0) return;

    await ref.set({
      'wallHeightM': newHeightM,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // keep in-memory active config in sync
    activeConfig.value = WallingConfig(
      configId: cfg.configId,
      measureConfigRef: cfg.measureConfigRef,
      boqCode: cfg.boqCode,
      wallHeightM: newHeightM,
    );

    // ensure drawing still points to the same active config
    await drawingRef.set({
      'activeWallingConfigRef': cfg.measureConfigRef,
    }, SetOptions(merge: true));
  }

  /// load last active config (stored in drawing doc) or fallback to latest config doc
  Future<void> loadActiveConfig() async {
    final snap = await drawingRef.get();
    final data = snap.data() ?? {};
    final refPath = (data['activeWallingConfigRef'] ?? '') as String;

    if (refPath.trim().isNotEmpty) {
      final cfgSnap = await FirebaseFirestore.instance.doc(refPath).get();
      if (cfgSnap.exists) {
        final m = (cfgSnap.data() ?? {});
        activeConfig.value = WallingConfig(
          configId: cfgSnap.id,
          measureConfigRef: cfgSnap.reference.path,
          boqCode: (m['boqCode'] ?? '').toString(),
          wallHeightM: ((m['wallHeightM'] ?? 0) as num).toDouble(),
        );
        return;
      }
    }

    // fallback: latest config
    final q =
        await configsRef
            .where('measureType', isEqualTo: 'walling')
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .get();

    if (q.docs.isEmpty) return;
    final d = q.docs.first;
    final m = d.data();
    activeConfig.value = WallingConfig(
      configId: d.id,
      measureConfigRef: d.reference.path,
      boqCode: (m['boqCode'] ?? '').toString(),
      wallHeightM: ((m['wallHeightM'] ?? 0) as num).toDouble(),
    );

    // store as active
    await drawingRef.set({
      'activeWallingConfigRef': d.reference.path,
    }, SetOptions(merge: true));
  }

  /// show configure dialog and save config
  Future<bool> showConfigureDialog(String code) async {
    final ctx = Get.context;
    if (ctx == null) return false;

    // final boqController = TextEditingController(
    //   text: activeConfig.value?.boqCode ?? '',
    // );
    final hController = TextEditingController(
      text: (activeConfig.value?.wallHeightM ?? 3.0).toStringAsFixed(2),
    );

    final ok = await showDialog<bool>(
      context: ctx,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Configure Walling'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomGetBoqCode(
                  projectId: projectId,
                  buildingId: buildingId,
                  code: code,
                  text: 'Add BOQ',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Default wall height (m)',
                    hintText: 'e.g. 3.0',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (ok != true) return false;

    final boq = code;
    final h = double.tryParse(hController.text.trim()) ?? 0;

    if (boq == null || h <= 0) {
      Get.snackbar('Invalid', 'BOQ code and height are required.');
      return false;
    }

    // create new config doc (or you can update existing, but new is safer for audit)
    final doc = configsRef.doc();
    await doc.set({
      'measureType': 'walling',
      'label': 'Walling',
      'unit': 'm2',
      'boqCode': boq,
      'wallHeightM': h,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // set as active on drawing
    await drawingRef.set({
      'activeWallingConfigRef': doc.path,
    }, SetOptions(merge: true));

    activeConfig.value = WallingConfig(
      configId: doc.id,
      measureConfigRef: doc.path,
      boqCode: boq,
      wallHeightM: h,
    );

    return true;
  }

  Future<bool> ensureConfig() async {
    if (activeConfig.value != null) return true;
    await loadActiveConfig();
    if (activeConfig.value != null) return true;
    return showConfigureDialog(bodCode!);
  }
}
