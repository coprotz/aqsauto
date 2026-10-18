import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/projects/controllers/project_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectDetailPageGetX extends GetView<ProjectDetailController> {
  const ProjectDetailPageGetX({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AqsAppBarTitle(
          title: controller.projectName,
          subtitle: 'Project workspace',
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorText.value.isNotEmpty) {
          return Center(child: Text('Error: ${controller.errorText.value}'));
        }

        final docs = controller.buildings;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No buildings yet for this project.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: controller.showAddBuildingDialog,
                  icon: const Icon(Icons.add_business),
                  label: const Text('Create first building'),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final buildingId = doc.id;
            final name = (data['name'] ?? 'Unnamed building').toString();
            final code = (data['code'] ?? '').toString();

            return ListTile(
              leading: const Icon(Icons.apartment),
              title: Text(name),
              subtitle: code.isNotEmpty ? Text(code) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.toNamed(
                  '/building-detail',
                  arguments: {
                    'projectId': controller.projectId,
                    'buildingId': buildingId,
                    'buildingName': name,
                  },
                );
              },
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.showAddBuildingDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
