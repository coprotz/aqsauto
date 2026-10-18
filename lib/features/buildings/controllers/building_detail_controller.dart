import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BuildingDetailController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final String projectId;
  final String buildingId;
  final String buildingName;
  final String imageUrl;
  final String drawingTitle;
  final String drawingId;

  BuildingDetailController({
    required this.projectId,
    required this.buildingId,
    required this.buildingName,
    required this.drawingTitle,
    required this.imageUrl,
    required this.drawingId,
  });

  late final TabController tabController;

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }
}
