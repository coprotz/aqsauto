import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/takeoff/controllers/poly_draw_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
// import 'package:aqs/features/takeoff/controllers/walling_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class TakeoffBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments ?? {}) as Map;

    final projectId = (args['projectId'] ?? '').toString();
    final buildingId = (args['buildingId'] ?? '').toString();
    final drawingId = (args['drawingId'] ?? '').toString();
    final drawingTitle = (args['drawingTitle'] ?? '').toString();
    final imageUrl = (args['imageUrl'] ?? '').toString();

    Get.put(
      ImageTakeoffController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: (args['drawingTitle'] ?? '').toString(),
        imageUrl: (args['imageUrl'] ?? '').toString(),
        // it: Get.find<ImageTakeoffController>(),
      ),
    );

    final it = Get.find<ImageTakeoffController>();
    final pctr = Get.find<PolylineDrawController>();

    // core controller (you already have)
    Get.put(
      MeasuringItemController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        drawingTitle: drawingTitle,
        imageUrl: imageUrl,
        it: it,
        pctr: pctr,
      ),
      permanent: false,
    );

    final mi = Get.find<MeasuringItemController>();

    // walling config
    Get.put(
      WallingConfigController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
      ),
      permanent: false,
    );

    final cfg = Get.find<WallingConfigController>();

    // walling takeoff
    Get.put(
      WallingTakeoffController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        measurementsRef: mi.measurementsRef,
        configCtrl: cfg,
      ),
      permanent: false,
    );
  }
}
