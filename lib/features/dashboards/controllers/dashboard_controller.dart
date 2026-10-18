import 'package:get/get.dart';

class DashboardController extends GetxController {
  final RxInt selectedSection = 0.obs;

  void openSection(int index) {
    selectedSection.value = index + 1;
  }

  void openHome() {
    selectedSection.value = 0;
  }

  void reset() {
    selectedSection.value = 0;
  }
}
