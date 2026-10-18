import 'package:aqs/features/projects/controllers/project_detail_controller.dart';
import 'package:get/get.dart';

class ProjectDetailBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments ?? {}) as Map;

    Get.put(
      ProjectDetailController(
        projectId: (args['projectId'] ?? '').toString(),
        projectName: (args['projectName'] ?? '').toString(),
      ),
    );
  }
}
