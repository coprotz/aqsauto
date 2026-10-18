import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/controllers/boq_template_pick_controller.dart';
import 'package:get/get.dart';

class BoqTemplatePickBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<BoqTemplateController>()) {
      Get.lazyPut<BoqTemplateController>(
        () => BoqTemplateController(),
        fenix: true,
      );
    }
    final args = Map<String, dynamic>.from(Get.arguments ?? {});

    final projectId = (args['projectId'] ?? '').toString().trim();
    final buildingId = (args['buildingId'] ?? '').toString().trim();
    final drawingId = (args['drawingId'] ?? '').toString().trim();

    final templateId = (args['templateId'] ?? '').toString().trim();
    final templateName = (args['templateName'] ?? '').toString().trim();

    if (projectId.isEmpty || buildingId.isEmpty) {
      throw ArgumentError('Missing projectId/buildingId.');
    }
    if (templateId.isEmpty) {
      throw ArgumentError('Missing templateId.');
    }

    Get.lazyPut<BoqTemplatePickController>(
      () => BoqTemplatePickController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId.isEmpty ? null : drawingId,
        templateId: templateId,
        templateName: templateName,
      ),
    );
  }
}
