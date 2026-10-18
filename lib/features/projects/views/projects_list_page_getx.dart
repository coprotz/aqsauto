import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/boq/views/boq_templates_page_getx.dart';
import 'package:aqs/features/projects/controllers/project_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectsListPageGetX extends GetView<ProjectsListController> {
  const ProjectsListPageGetX({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AqsAppBarTitle(
          title: 'Projects',
          subtitle: 'AQS AUTOboq',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.to(() => const BoqTemplatesPageGetX()),
            child: const Text('BOQ Templates'),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorText.value.isNotEmpty) {
          return Center(
            child: Text(
              'Error loading projects: ${controller.errorText.value}',
            ),
          );
        }

        final docs = controller.projects;
        if (docs.isEmpty) {
          return const Center(child: Text('No projects yet. Add one.'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final data = doc.data();
            final name = (data['name'] ?? 'Untitled').toString();
            final client = (data['clientName'] ?? '').toString();

            return ListTile(
              title: Text(name),
              subtitle: client.isNotEmpty ? Text(client) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => controller.openProject(doc),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.createProjectDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
