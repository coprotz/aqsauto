// import 'package:aqs/app_pages.dart';
// import 'package:aqs/app_routes.dart';
import 'package:aqs/app_pages.dart';
import 'package:aqs/app_routes.dart';
import 'package:aqs/core/controlers/aqs_data_controller.dart';
import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/features/ipc/execution_outbox.dart';
import 'package:aqs/features/ipc/ipc_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/buildings/views/building_detail_page_getx.dart';
// import 'package:aqs/features/bindings/bulding_details_binding.dart';
// import 'package:aqs/features/bindings/project_detail_binding.dart';
// import 'package:aqs/features/bindings/project_list_binding.dart';
// import 'package:aqs/features/bindings/image_takeoff_binding.dart';
// import 'package:aqs/features/takeoff/image_takeoff_page_getx.dart';
import 'package:aqs/firebase_options.dart';
// import 'package:aqs/routes/app_pages.dart';
// import 'package:aqs/routes/app_routes.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// 🔹 GetX pages (use your new GetX versions)
// import 'package:aqs/features/projects/views/projects_list_page_getx.dart';
// import 'package:aqs/features/projects/controllers/projects_list_binding.dart';

// import 'package:aqs/features/projects/views/project_detail_page_getx.dart';
import 'package:get_storage/get_storage.dart';
// import 'package:aqs/features/projects/controllers/project_detail_binding.dart';

// (optional) if you have BuildingDetail GetX
// import 'package:aqs/features/buildings/views/building_detail_page_getx.dart';
// import 'package:aqs/features/buildings/controllers/building_detail_binding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else {
    await Firebase.initializeApp();
  }
  // if (kDebugMode) {
  //   FirebaseFunctions.instanceFor(
  //     region: 'us-central1',
  //   ).useFunctionsEmulator('127.0.0.1', 5002);
  // }
  Get.put(AqsDataController(), permanent: true);
  var stateUserId = FirebaseAuth.instance.currentUser?.uid;
  executionOutbox.send = (command) async {
    final db = FirebaseFirestore.instance;
    await IpcDetail(
      certificate: db.doc(command['certificate'] as String),
    ).syncExecution(
      db.doc(command['package'] as String),
      command['item'] as String,
      command['rfi'] as String,
      command['sheet'] as String,
      (command['quantity'] as num).toDouble(),
      rawQuantity: (command['rawQuantity'] as num).toDouble(),
      factor: (command['factor'] as num).toDouble(),
      correctionReason: command['reason'] as String,
      entryId: command['entry'] as String,
      delete: command['delete'] == true,
      newEntry: command['newEntry'] == true,
      operationId: command['id'] as String,
      owner: command['user'] as String,
    );
  };
  FirebaseAuth.instance
      .authStateChanges()
      .map((user) => user?.uid)
      .distinct()
      .listen((uid) {
        if (uid != stateUserId) firestoreState.clear();
        stateUserId = uid;
        executionOutbox.setUser(uid);
      });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AQS AUTOboq',
      debugShowCheckedModeBanner: false,
      theme: AqsTheme.light,
      builder:
          (context, child) => ListenableBuilder(
            listenable: executionOutbox,
            builder:
                (context, _) => Column(
                  children: [
                    const SafeArea(
                      bottom: false,
                      child: ExecutionSyncBanner(packagePath: null),
                    ),
                    Expanded(child: child ?? const SizedBox.shrink()),
                  ],
                ),
          ),

      initialRoute: AppRoutes.landing, // pick your start route
      getPages: AppPages.pages,
    );
  }
}
