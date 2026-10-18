import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:get/get.dart';

class BoqTemplateBinding extends Bindings {
  @override
  void dependencies() {
    final args = Map<String, dynamic>.from(Get.arguments ?? {});

    final projectId = (args['projectId'] ?? '').toString().trim();
    final buildingId = (args['buildingId'] ?? '').toString().trim();
    final drawingId = (args['drawingId'] ?? '').toString().trim();

    if (projectId.isEmpty || buildingId.isEmpty) {
      throw ArgumentError(
        'BuildingDetailBinding missing projectId/buildingId. '
        'Did you forget Get.toNamed(..., arguments: {...}) ?',
      );
    }
    // Get.lazyPut<BoqTemplateController>(() => BoqTemplateController());

    Get.lazyPut<BoqTemplateController>(
      () => BoqTemplateController(
        // projectId: projectId,
        // buildingId: buildingId,
        // drawingId: drawingId,
      ),
    );
  }
}
