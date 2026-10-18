import 'package:aqs/features/boq/controllers/boq_import_excel-controller.dart';
import 'package:get/get.dart';

class BoqImportExcelBinding extends Bindings {
  @override
  void dependencies() {
    final args = Map<String, dynamic>.from(Get.arguments ?? {});
    final projectId = (args['projectId'] ?? '').toString().trim();
    final buildingId = (args['buildingId'] ?? '').toString().trim();
    final drawingId = (args['drawingId'] ?? '').toString().trim();

    if (projectId.isEmpty || buildingId.isEmpty) {
      throw ArgumentError('BoqImportExcelBinding missing projectId/buildingId');
    }

    Get.lazyPut<BoqImportExcelController>(
      () => BoqImportExcelController(
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId.isEmpty ? null : drawingId,
      ),
    );
  }
}
