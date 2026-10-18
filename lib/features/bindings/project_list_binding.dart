import 'package:aqs/features/projects/controllers/project_list_controller.dart';
import 'package:get/get.dart';

class ProjectsListBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ProjectsListController());
  }
}
