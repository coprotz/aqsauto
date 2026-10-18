import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:get/get.dart';
import 'package:get/get_instance/src/bindings_interface.dart';

class BoqTemplateManageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BoqTemplateController>(() => BoqTemplateController());
  }
}
