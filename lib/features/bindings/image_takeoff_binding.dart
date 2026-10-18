import 'dart:typed_data';

import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/poly_draw_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';

class ImageTakeoffBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments ?? {}) as Map;

    final projectId =
        (args['projectId'] ?? Get.parameters['projectId'] ?? '').toString();
    final buildingId =
        (args['buildingId'] ?? Get.parameters['buildingId'] ?? '').toString();
    final drawingId =
        (args['drawingId'] ?? Get.parameters['drawingId'] ?? '').toString();
    final drawingTitle =
        (args['drawingTitle'] ?? Get.parameters['drawingTitle'] ?? '')
            .toString();
    final imageUrl =
        (args['imageUrl'] ?? Get.parameters['imageUrl'] ?? '').toString();

    if (projectId.isEmpty || buildingId.isEmpty || drawingId.isEmpty) {
      throw Exception('Missing args: projectId/buildingId/drawingId');
    }

    registerDrawing(
      projectId: projectId,
      buildingId: buildingId,
      drawingId: drawingId,
      drawingTitle: drawingTitle,
      imageUrl: imageUrl,
    );
  }

  static void registerDrawing({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String drawingTitle,
    required String imageUrl,
    Uint8List? imageBytes,
    double? imageWidth,
    double? imageHeight,
  }) {
    final measRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('measurements');

    // ✅ IMPORTANT: remove previous instances (old drawingId) before re-registering
    _deleteRegistered<ImageTakeoffController>();
    _deleteRegistered<MeasuringItemController>();
    _deleteRegistered<WallingConfigController>();
    _deleteRegistered<CompositeBeamTakeoffController>();
    _deleteRegistered<WallingTakeoffController>();
    _deleteRegistered<PolylineDrawController>();

    final tCtrl = TransformationController();

    final pctr = Get.put<PolylineDrawController>(
      PolylineDrawController(tCtrl: tCtrl),
    );

    // ✅ Create fresh controllers for THIS drawing
    final it = Get.put<ImageTakeoffController>(
      ImageTakeoffController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        imageUrl: imageUrl,
      ),
      permanent: false,
    );

    Get.put(
      MeasuringItemController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        imageUrl: imageUrl,
        imageBytes: imageBytes,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        transformController: tCtrl,
        it: it,
        pctr: pctr,
      ),
      permanent: false,
    );

    final cfg = Get.put(
      WallingConfigController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
      ),
      permanent: false,
    );

    Get.put(
      CompositeBeamTakeoffController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
      ),
      permanent: false,
    );

    Get.put<WallingTakeoffController>(
      WallingTakeoffController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        measurementsRef: measRef,
        configCtrl: cfg,
      ),
      permanent: false,
    );
  }

  static void _deleteRegistered<T>() {
    if (Get.isRegistered<T>()) {
      Get.delete<T>(force: true);
    }
  }
}
