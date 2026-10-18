import 'package:aqs/features/boq/views/boq_tab_getx.dart';
import 'package:aqs/features/buildings/controllers/building_detail_controller.dart';
import 'package:aqs/features/drawings/views/drawings_tab_getx.dart';
import 'package:aqs/features/projects/controllers/project_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BuildingDetailPageGetX extends GetView<BuildingDetailController> {
  const BuildingDetailPageGetX({super.key});

  @override
  Widget build(BuildContext context) {
    final ProjectDetailController pd = Get.find<ProjectDetailController>();
    final c = controller;

    return Scaffold(
      appBar: AppBar(
        title: Text('${pd.projectName} - ${c.buildingName}'),
        bottom: TabBar(
          controller: c.tabController,
          tabs: const [
            Tab(text: 'Drawings', icon: Icon(Icons.picture_as_pdf)),
            Tab(text: 'BOQ', icon: Icon(Icons.list_alt)),
          ],
        ),
      ),
      body: TabBarView(
        controller: c.tabController,
        children: [
          DrawingsTabGetX(projectId: c.projectId, buildingId: c.buildingId),
          BoqTabGetX(
            projectId: c.projectId,
            projectName: pd.projectName,
            buildingId: c.buildingId,
            imageUrl: c.imageUrl,
            drawingTitle: c.drawingTitle,
            drawingId: c.drawingId,
            buildingName: c.buildingName,
          ),
        ],
      ),
    );
  }
}
