import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class AqsDataController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------
  // LOADING STATES
  // ---------------------------------------------------------

  final RxBool isInitialLoading = false.obs;

  final RxBool projectsLoaded = false.obs;
  final RxBool clientsLoaded = false.obs;
  final RxBool userLoaded = false.obs;

  // ---------------------------------------------------------
  // DATA
  // ---------------------------------------------------------

  final RxList<Map<String, dynamic>> projects = <Map<String, dynamic>>[].obs;

  final RxList<Map<String, dynamic>> clients = <Map<String, dynamic>>[].obs;

  final RxMap<String, dynamic> currentUser = <String, dynamic>{}.obs;

  // ---------------------------------------------------------
  // INITIAL LOAD
  // ---------------------------------------------------------

  Future<void> loadInitialData({bool forceRefresh = false}) async {
    if (isInitialLoading.value) return;

    if (!forceRefresh &&
        projectsLoaded.value &&
        clientsLoaded.value &&
        userLoaded.value) {
      return;
    }

    isInitialLoading.value = true;

    try {
      await Future.wait([
        loadCurrentUser(forceRefresh: forceRefresh),
        loadProjects(forceRefresh: forceRefresh),
        loadClients(forceRefresh: forceRefresh),
      ]);
    } finally {
      isInitialLoading.value = false;
    }
  }

  // ---------------------------------------------------------
  // USER
  // ---------------------------------------------------------

  Future<void> loadCurrentUser({bool forceRefresh = false}) async {
    if (userLoaded.value && !forceRefresh) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      currentUser.clear();
      userLoaded.value = false;
      return;
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();

    if (doc.exists) {
      currentUser.assignAll({'id': doc.id, ...?doc.data()});
    }

    userLoaded.value = true;
  }

  // ---------------------------------------------------------
  // PROJECTS
  // ---------------------------------------------------------

  Future<void> loadProjects({bool forceRefresh = false}) async {
    if (projectsLoaded.value && !forceRefresh) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      projects.clear();
      projectsLoaded.value = false;
      return;
    }

    final snapshot =
        await _firestore
            .collection('projects')
            .where('ownerId', isEqualTo: uid)
            .get();

    projects.assignAll(
      snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }),
    );

    projectsLoaded.value = true;
  }

  // ---------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------

  Future<void> loadClients({bool forceRefresh = false}) async {
    if (clientsLoaded.value && !forceRefresh) {
      return;
    }

    final snapshot = await _firestore.collection('clients').get();

    clients.assignAll(
      snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }),
    );

    clientsLoaded.value = true;
  }

  // ---------------------------------------------------------
  // REFRESH
  // ---------------------------------------------------------

  Future<void> refreshAll() async {
    await loadInitialData(forceRefresh: true);
  }

  // ---------------------------------------------------------
  // CLEAR AFTER LOGOUT
  // ---------------------------------------------------------

  void clearData() {
    projects.clear();
    clients.clear();
    currentUser.clear();

    projectsLoaded.value = false;
    clientsLoaded.value = false;
    userLoaded.value = false;
  }
}
