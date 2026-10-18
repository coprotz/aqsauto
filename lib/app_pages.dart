import 'package:aqs/features/admin/views/admin_dashboard_page.dart';
import 'package:aqs/features/admin/views/admin_messages_page.dart';
import 'package:aqs/features/auth/create_project.dart';
import 'package:aqs/features/auth/login_page.dart';
import 'package:aqs/features/auth/register_page.dart';
import 'package:aqs/features/bindings/boq_import_excel_binding.dart';
import 'package:aqs/features/bindings/boq_template_manage_binding.dart';
import 'package:aqs/features/bindings/boq_template_pick_binding.dart';
import 'package:aqs/features/bindings/bulding_details_binding.dart';
import 'package:aqs/features/bindings/image_takeoff_binding.dart';
import 'package:aqs/features/bindings/project_detail_binding.dart';
import 'package:aqs/features/bindings/project_list_binding.dart';
import 'package:aqs/features/boq/views/boq_import_excel.dart';
import 'package:aqs/features/boq/views/boq_template_items_page.dart';
import 'package:aqs/features/boq/views/boq_template_pick_items_page.dart';
import 'package:aqs/features/boq/views/boq_templates_page_getx.dart';
import 'package:aqs/features/buildings/views/building_detail_page_getx.dart';
import 'package:aqs/features/build_up_rates/views/rate_builder_page.dart';
import 'package:aqs/features/build_up_rates/views/build_up_rates_page.dart';
import 'package:aqs/features/build_up_rates/views/labour_rates_page.dart';
import 'package:aqs/features/build_up_rates/views/rate_details_page.dart';
import 'package:aqs/features/build_up_rates/views/resource_library_page.dart';
// import 'package:aqs/features/dashboards/views/dashboard_page.dart';
import 'package:aqs/features/dashboards/views/building_workspace_page.dart';
import 'package:aqs/features/dashboards/views/dashboard_page.dart';
import 'package:aqs/features/dashboards/views/project_buildings_page.dart';
import 'package:aqs/features/landings/pages/about_page.dart';
import 'package:aqs/features/landings/pages/landing_page.dart';
import 'package:aqs/features/material_prices/views/material_prices_page.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';
import 'package:aqs/features/projects/views/project_detail_page_getx.dart';
import 'package:aqs/features/projects/views/projects_list_page_getx.dart';
import 'package:aqs/features/team/views/invite_accept_page.dart';
import 'package:aqs/features/takeoff/image_takeoff_page_getx.dart';
import 'package:aqs/features/tutorials/views/admin_tutorial_videos_page.dart';
import 'package:aqs/features/tutorials/views/tutorial_videos_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app_routes.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ Existing pages + bindings

class AppPages {
  static final pages = <GetPage>[
    GetPage(
      name: AppRoutes.projects,
      page: () => const ProjectsListPageGetX(),
      binding: ProjectsListBinding(),
    ),
    GetPage(
      name: AppRoutes.imageTakeoff,
      page: () => const ImageTakeoffPageGetX(),
      binding: ImageTakeoffBinding(),
    ),
    GetPage(
      name: AppRoutes.projectDetail,
      page: () => const ProjectDetailPageGetX(),
      binding: ProjectDetailBinding(),
    ),
    GetPage(
      name: AppRoutes.takeoff,
      page: () => const ImageTakeoffPageGetX(),
      binding: ImageTakeoffBinding(),
    ),
    GetPage(
      name: AppRoutes.buildingDetail,
      page: () => const BuildingDetailPageGetX(),
      binding: BuildingDetailBinding(),
    ),

    // ✅ BOQ Templates list
    GetPage(
      name: AppRoutes.boqTemplates,
      page: () => const BoqTemplatesPageGetX(),
      binding: BoqTemplateManageBinding(),
    ),

    // ✅ BOQ Template items page
    // GetPage(
    //   name: AppRoutes.boqTemplateItems,
    //   page: () => BoqTemplateItemsPage(),
    //   binding: BoqTemplateBinding(),
    // ),

    // ✅ Project BOQ Excel import
    GetPage(
      name: AppRoutes.boqImportExcel,
      page: () => BoqImportExcelPageGetX(),
      binding: BoqImportExcelBinding(),
    ),

    GetPage(
      name: AppRoutes.boqTemplatesManage,
      page: () => const BoqTemplatesPageGetX(),
      binding: BoqTemplateManageBinding(),
    ),

    GetPage(
      name: AppRoutes.boqTemplateItemsManage,
      page: () {
        final args = Map<String, dynamic>.from(Get.arguments ?? {});
        return BoqTemplateItemsPage(
          templateId: (args['templateId'] ?? '').toString(),
          templateName: (args['templateName'] ?? 'Template').toString(),
        );
      },
      binding: BoqTemplateManageBinding(),
    ),

    GetPage(
      name: AppRoutes.boqTemplatePickItems,
      page: () => const BoqTemplatePickItemsPageGetX(),
      binding: BoqTemplatePickBinding(),
    ),
    GetPage(
      name: AppRoutes.landing,
      page: () => const LandingPage(),
      // binding: ProjectsListBinding(),
    ),
    GetPage(name: AppRoutes.about, page: () => const AboutPage()),
    GetPage(
      name: AppRoutes.contact,
      page: () => const LandingPage(openContact: true),
    ),
    GetPage(
      name: AppRoutes.dashboard,
      page: () => const DashboardPage(),
      // binding: ProjectsListBinding(),
    ),
    GetPage(
      name: AppRoutes.tutorialVideos,
      page: () => const TutorialVideosPage(),
    ),
    GetPage(
      name: AppRoutes.adminTutorialVideos,
      page:
          () => Scaffold(
            appBar: AppBar(title: const Text('Tutorial videos')),
            body: const AdminTutorialVideosPage(),
          ),
    ),
    GetPage(
      name: AppRoutes.inviteAccept,
      page: () => InviteAcceptPage(token: Get.parameters['token'] ?? ''),
    ),
    GetPage(
      name: AppRoutes.projectBuildings,
      page:
          () => ProjectBuildingsPage(
            projectId: Get.parameters['projectId'] ?? '',
            projectName: Get.parameters['projectName'] ?? 'Project',
          ),
    ),
    GetPage(
      name: AppRoutes.projectBuildingWorkspace,
      page:
          () => ProjectBuildingDetailsPage(
            projectId: Get.parameters['projectId'] ?? '',
            projectName: Get.parameters['projectName'] ?? 'Project',
            buildingId: Get.parameters['buildingId'] ?? '',
            buildingName: Get.parameters['buildingName'] ?? 'Building',
            buildingCode: Get.parameters['buildingCode'] ?? '',
            initialTabIndex:
                int.tryParse(Get.parameters['tab'] ?? '')?.clamp(0, 3) ?? 0,
          ),
    ),
    GetPage(
      name: AppRoutes.drawingMeasurement,
      page: () => const ImageTakeoffPageGetX(),
      binding: ImageTakeoffBinding(),
    ),
    GetPage(
      name: AppRoutes.register,
      page: () => RegisterPage(),
      // binding: ProjectsListBinding(),
    ),
    GetPage(
      name: AppRoutes.admin,
      page: () => AdminDashboardPage(),
      // binding: ProjectsListBinding(),
    ),
    GetPage(
      name: AppRoutes.materialPrices,
      page: () => const MaterialPricesPage(),
    ),
    GetPage(
      name: AppRoutes.pricing,
      page:
          () => PricingPlansPage(
            initialPlanId: Get.parameters['plan'],
            initialYearly: Get.parameters['yearly'] == 'true',
          ),
    ),
    GetPage(
      name: AppRoutes.adminMaterialPrices,
      page: () => const AdminMaterialPricesPage(),
    ),
    GetPage(
      name: AppRoutes.adminMessages,
      page: () => const AdminMessagesPage(),
    ),
    GetPage(
      name: AppRoutes.login,
      page:
          () => LoginPage(
            onLoggedInGoTo: () {
              // run async work but return a Widget synchronously as required
              () async {
                final user = FirebaseAuth.instance.currentUser;

                if (user == null) {
                  return;
                }

                try {
                  final userDoc =
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get();

                  final data = userDoc.data();
                  final role =
                      (data?['role'] ?? '').toString().trim().toLowerCase();

                  if (role == 'admin') {
                    Get.offAllNamed(AppRoutes.admin);
                  } else {
                    Get.offAllNamed(AppRoutes.dashboard);
                  }
                } catch (e) {
                  debugPrint('Error checking user role: $e');
                  Get.offAllNamed(AppRoutes.dashboard);
                }
              }();

              return const SizedBox.shrink();
            },
          ),
    ),
    GetPage(
      name: AppRoutes.createProject,
      page: () => RegisterAndCreateProjectPage(),
      // binding: ProjectsListBinding(),
    ),
    GetPage(name: AppRoutes.buildUpRates, page: () => const BuildUpRatesPage()),
    GetPage(name: AppRoutes.labourRates, page: () => const LabourRatesPage()),
    GetPage(
      name: AppRoutes.buildUpRateNew,
      page: () => const RateBuilderPage(),
    ),
    GetPage(
      name: AppRoutes.buildUpRateResources,
      page: () => const ResourceLibraryPage(),
    ),
    GetPage(
      name: AppRoutes.buildUpRateEdit,
      page: () => RateBuilderPage(rateId: Get.parameters['rateId']),
    ),
    GetPage(
      name: AppRoutes.buildUpRateDetails,
      page: () => RateDetailsPage(rateId: Get.parameters['rateId'] ?? ''),
    ),
  ];
}
