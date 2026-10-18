import 'package:aqs/features/boq/controllers/boq_controller.dart';
import 'package:get/get.dart';

class BoqBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments ?? {}) as Map;

    Get.lazyPut(
      () => BoqController(
        projectId: (args['projectId'] ?? '').toString(),
        buildingId: (args['buildingId'] ?? '').toString(),
        builldingName: (args['buildingName'] ?? '').toString(),
      ),
    );
  }
}
