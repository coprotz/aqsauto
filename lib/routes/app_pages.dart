// import 'package:aqs/features/auth/login_page.dart';
// import 'package:aqs/features/drawings/pages/drawing_register_page.dart';
// import 'package:aqs/features/drawings/pages/drawing_viewer_page.dart';
// import 'package:aqs/features/landings/pages/landing_page.dart';
// import 'package:aqs/features/takeoff/pages/takeoff_workspace_page.dart';
// import 'package:get/get.dart';

// import 'package:aqs/routes/app_routes.dart';

// import 'package:aqs/features/projects/pages/projects_page.dart';
// import 'package:aqs/features/projects/pages/project_dashboard_page.dart';
// import 'package:aqs/features/projects/pages/facilities_page.dart';
// import 'package:aqs/features/projects/pages/facility_dashboard_page.dart';

// import 'package:aqs/features/drawings/pages/facility_drawings_page.dart';
// import 'package:aqs/features/drawings/pages/upload_drawing_bundle_page.dart';

// import 'package:aqs/features/boq2/pages/upload_boq_page.dart';

// class AppPages {
//   static final routes = <GetPage>[
//     // GetPage(name: AppRoutes.login, page: () => const LoginPage()),
//     GetPage(name: AppRoutes.landing, page: () => const LandingPage()),
//     GetPage(name: AppRoutes.projects, page: () => const ProjectsPage()),

//     GetPage(
//       name: AppRoutes.projectDashboard,
//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         return ProjectDashboardPage(projectId: projectId);
//       },
//     ),

//     GetPage(
//       name: AppRoutes.facilities,
//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         final projectName = Get.parameters['projectName'] ?? '';

//         return FacilitiesPage(projectId: projectId, projectName: projectName);
//       },
//     ),

//     GetPage(
//       name: AppRoutes.facilityDashboard,
//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         final facilityId = Get.parameters['facilityId'] ?? '';

//         return FacilityDashboardPage(
//           projectId: projectId,
//           facilityId: facilityId,
//         );
//       },
//     ),

//     // GetPage(
//     //   name: AppRoutes.facilityDrawings,
//     //   page: () {
//     //     final projectId = Get.parameters['projectId'] ?? '';

//     //     final facilityId = Get.parameters['facilityId'] ?? '';

//     //     final facilityName = Get.parameters['facilityName'] ?? '';

//     //     return FacilityDrawingsPage(
//     //       projectId: projectId,
//     //       facilityId: facilityId,
//     //       facilityName: facilityName,
//     //     );
//     //   },
//     // ),

//     // GetPage(
//     //   name: AppRoutes.uploadDrawingBundle,

//     //   page: () {
//     //     final projectId = Get.parameters['projectId'] ?? '';

//     //     final facilityId = Get.parameters['facilityId'] ?? '';

//     //     final facilityName = Get.parameters['facilityName'] ?? '';

//     //     final bundleId = Get.parameters['bundleId'];

//     //     final mode = Get.parameters['mode'];

//     //     return UploadDrawingBundlePage(
//     //       projectId: projectId,

//     //       facilityId: facilityId,

//     //       facilityName: facilityName,

//     //       bundleId: bundleId,

//     //       appendMode: mode == 'append',
//     //     );
//     //   },
//     // ),

//     GetPage(
//       name: AppRoutes.uploadBoq,
//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         final facilityId = Get.parameters['facilityId'] ?? '';

//         return UploadBoqPage(projectId: projectId, facilityId: facilityId);
//       },
//     ),
//     GetPage(
//       name: AppRoutes.drawingRegister,
//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         final facilityId = Get.parameters['facilityId'] ?? '';

//         final facilityName = Get.parameters['facilityName'] ?? '';

//         final bundleId = Get.parameters['bundleId'];

//         return DrawingRegisterPage(
//           projectId: projectId,

//           facilityId: facilityId,

//           facilityName: facilityName,

//           bundleId: bundleId?.isEmpty == true ? null : bundleId,
//         );
//       },
//     ),
//     GetPage(
//       name: AppRoutes.drawingViewer,

//       page: () {
//         final projectId = Get.parameters['projectId'] ?? '';

//         final facilityId = Get.parameters['facilityId'] ?? '';

//         final drawingId = Get.parameters['drawingId'] ?? '';

//         return DrawingViewerPage(
//           projectId: projectId,

//           facilityId: facilityId,

//           drawingId: drawingId,
//         );
//       },
//     ),
//     GetPage(
//       name: AppRoutes.takeoffWorkspace,

//       page: () {
//         return TakeOffWorkspacePage(
//           projectId: Get.parameters['projectId'] ?? '',

//           facilityId: Get.parameters['facilityId'] ?? '',

//           drawingId: Get.parameters['drawingId'] ?? '',
//         );
//       },
//     ),
//   ];
// }
