import 'dart:ui';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/admin/models/admin_dashboard_data.dart';
import 'package:aqs/features/admin/models/admin_models.dart';
import 'package:aqs/features/admin/models/admin_user_row.dart';
import 'package:aqs/features/admin/models/payment_row.dart';
import 'package:aqs/features/admin/models/project_admin_data.dart';
import 'package:aqs/features/admin/models/project_client_row.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminDashboardController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------
  // SECTION
  // ---------------------------------------------------------

  final RxInt selectedSection = 0.obs;

  void selectSection(int index) {
    if (selectedSection.value == index) return;
    selectedSection.value = index;
  }

  // ---------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------

  final RxString searchQuery = ''.obs;

  void setSearchQuery(String value) {
    searchQuery.value = value.trim().toLowerCase();
  }

  // ---------------------------------------------------------
  // LOADING STATES
  // ---------------------------------------------------------

  final RxBool checkingAccess = true.obs;

  final RxBool loadingUsers = false.obs;
  final RxBool loadingSubscribers = false.obs;
  final RxBool loadingBilling = false.obs;
  final RxBool loadingProjects = false.obs;
  final RxBool loadingSpaceUsage = false.obs;

  final RxString errorMessage = ''.obs;

  // ---------------------------------------------------------
  // CACHE STATE
  // ---------------------------------------------------------

  final RxBool usersLoaded = false.obs;
  final RxBool billingLoaded = false.obs;
  final RxBool projectsLoaded = false.obs;
  final RxBool spaceUsageLoaded = false.obs;

  DateTime? _usersLoadedAt;
  DateTime? _billingLoadedAt;
  DateTime? _projectsLoadedAt;
  DateTime? _spaceUsageLoadedAt;

  // ---------------------------------------------------------
  // DATA
  // ---------------------------------------------------------

  final RxList<AdminUserRow> users = <AdminUserRow>[].obs;

  final RxList<AdminUserRow> spaceUsageUsers = <AdminUserRow>[].obs;

  final Rxn<AdminDashboardData> billingData = Rxn<AdminDashboardData>();

  final Rxn<ProjectsAdminData> projectsData = Rxn<ProjectsAdminData>();

  // ---------------------------------------------------------
  // ACCESS
  // ---------------------------------------------------------

  @override
  void onInit() {
    super.onInit();

    initialize();
  }

  Future<void> initialize() async {
    checkingAccess.value = true;
    errorMessage.value = '';

    try {
      await assertAdminAccess();

      // Load only the first section initially.
      await loadUsers();
    } catch (e) {
      errorMessage.value = 'Admin access could not be verified.';
    } finally {
      checkingAccess.value = false;
    }
  }

  Future<void> assertAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw const AdminAccessDeniedException();
    }

    final token = await user.getIdTokenResult();

    final claims = token.claims ?? {};

    if (claims['admin'] == true) {
      return;
    }

    throw const AdminAccessDeniedException();
  }

  // ---------------------------------------------------------
  // CACHE
  // ---------------------------------------------------------

  bool _cacheFresh(DateTime? loadedAt, {int minutes = 10}) {
    if (loadedAt == null) return false;

    return DateTime.now().difference(loadedAt).inMinutes < minutes;
  }

  // ---------------------------------------------------------
  // COLLECTION
  // ---------------------------------------------------------

  Future<QuerySnapshot<Map<String, dynamic>>?> _tryCollection(
    String collection,
  ) async {
    try {
      return await _firestore.collection(collection).get();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------
  // USERS
  // ---------------------------------------------------------

  Future<void> loadUsers({bool forceRefresh = false}) async {
    if (loadingUsers.value) return;

    if (!forceRefresh && usersLoaded.value && _cacheFresh(_usersLoadedAt)) {
      return;
    }

    loadingUsers.value = true;

    try {
      final snapshot = await _tryCollection('users');

      users.assignAll(_buildUserRows(snapshot?.docs ?? []));

      usersLoaded.value = true;
      _usersLoadedAt = DateTime.now();
    } finally {
      loadingUsers.value = false;
    }
  }

  List<AdminUserRow> get subscribers {
    return users.where((user) => user.isSubscribed).toList();
  }

  List<AdminUserRow> get filteredUsers {
    return _filterRows(users);
  }

  List<AdminUserRow> get filteredSubscribers {
    return _filterRows(subscribers);
  }

  List<AdminUserRow> _filterRows(List<AdminUserRow> rows) {
    final q = searchQuery.value.trim().toLowerCase();

    if (q.isEmpty) return rows;

    return rows.where((user) {
      return user.name.toLowerCase().contains(q) ||
          user.email.toLowerCase().contains(q) ||
          user.role.toLowerCase().contains(q) ||
          user.status.toLowerCase().contains(q) ||
          user.plan.toLowerCase().contains(q) ||
          user.provider.toLowerCase().contains(q) ||
          user.totalProjects.toString().contains(q) ||
          user.buildings.toString().contains(q) ||
          user.drawings.toString().contains(q) ||
          user.measurements.toString().contains(q) ||
          user.boqItems.toString().contains(q);
    }).toList();
  }

  // ---------------------------------------------------------
  // PROJECTS
  // ---------------------------------------------------------

  Future<void> loadProjects({bool forceRefresh = false}) async {
    if (loadingProjects.value) return;

    if (!forceRefresh &&
        projectsLoaded.value &&
        _cacheFresh(_projectsLoadedAt)) {
      return;
    }

    loadingProjects.value = true;

    try {
      projectsData.value = await _fetchProjectsData();

      projectsLoaded.value = true;
      _projectsLoadedAt = DateTime.now();
    } finally {
      loadingProjects.value = false;
    }
  }

  // ---------------------------------------------------------
  // BILLING
  // ---------------------------------------------------------

  Future<void> loadBilling({bool forceRefresh = false}) async {
    if (loadingBilling.value) return;

    if (!forceRefresh && billingLoaded.value && _cacheFresh(_billingLoadedAt)) {
      return;
    }

    loadingBilling.value = true;

    try {
      billingData.value = await _fetchBillingData();

      billingLoaded.value = true;
      _billingLoadedAt = DateTime.now();
    } finally {
      loadingBilling.value = false;
    }
  }

  // ---------------------------------------------------------
  // SPACE USAGE
  // ---------------------------------------------------------

  Future<void> loadSpaceUsage({bool forceRefresh = false}) async {
    if (loadingSpaceUsage.value) return;

    if (!forceRefresh &&
        spaceUsageLoaded.value &&
        _cacheFresh(_spaceUsageLoadedAt, minutes: 20)) {
      return;
    }

    loadingSpaceUsage.value = true;

    try {
      final usersSnap = await _tryCollection('users');

      final projectsSnap = await _tryCollection('projects');

      final usageByUser = await _loadUserUsageTotals(projectsSnap?.docs ?? []);

      spaceUsageUsers.assignAll(
        _buildUserRows(usersSnap?.docs ?? [], usageByUser: usageByUser),
      );

      spaceUsageLoaded.value = true;
      _spaceUsageLoadedAt = DateTime.now();
    } finally {
      loadingSpaceUsage.value = false;
    }
  }

  List<AdminUserRow> get filteredSpaceUsageUsers {
    return _filterRows(spaceUsageUsers);
  }

  // ---------------------------------------------------------
  // SECTION LOADING
  // ---------------------------------------------------------

  Future<void> openSection(int index) async {
    selectSection(index);

    switch (index) {
      case 0:
        await loadUsers();
        break;

      case 1:
        await loadUsers();
        break;

      case 2:
        await loadBilling();
        break;

      case 3:
        await loadProjects();
        break;

      case 4:
        await loadSpaceUsage();
        break;

      case 5:
        break;
    }
  }

  // ---------------------------------------------------------
  // REFRESH CURRENT SECTION
  // ---------------------------------------------------------

  Future<void> refreshCurrentSection() async {
    switch (selectedSection.value) {
      case 0:
      case 1:
        await loadUsers(forceRefresh: true);
        break;

      case 2:
        await loadBilling(forceRefresh: true);
        break;

      case 3:
        await loadProjects(forceRefresh: true);
        break;

      case 4:
        await loadSpaceUsage(forceRefresh: true);
        break;
    }
  }

  // ---------------------------------------------------------
  // USER STATUS
  // ---------------------------------------------------------

  Future<void> setUserStatus(
    AdminUserRow row,
    String status, {
    bool deleted = false,
  }) async {
    final normalized = status.trim().toLowerCase();

    final actor = FirebaseAuth.instance.currentUser;

    await _firestore.collection('users').doc(row.uid).set({
      'status': normalized,
      'disabled': normalized != 'active',
      'accessBlocked': normalized != 'active',
      'updatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedBy': actor?.uid ?? '',
      if (deleted) 'deletedAt': FieldValue.serverTimestamp(),
      if (deleted) 'deletedBy': actor?.uid ?? '',
    }, SetOptions(merge: true));

    // Update local state immediately.
    final index = users.indexWhere((user) => user.uid == row.uid);

    if (index != -1) {
      final current = users[index];

      users[index] = current.copyWith(status: normalized);
    }
  }

  // ---------------------------------------------------------
  // LOGOUT CLEANUP
  // ---------------------------------------------------------

  void clear() {
    users.clear();
    spaceUsageUsers.clear();

    billingData.value = null;
    projectsData.value = null;

    usersLoaded.value = false;
    billingLoaded.value = false;
    projectsLoaded.value = false;
    spaceUsageLoaded.value = false;

    _usersLoadedAt = null;
    _billingLoadedAt = null;
    _projectsLoadedAt = null;
    _spaceUsageLoadedAt = null;

    selectedSection.value = 0;
    searchQuery.value = '';
  }

  Future<Map<String, _AdminUsageTotals>> _loadUserUsageTotals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> projects,
  ) async {
    final usageByUser = <String, _AdminUsageTotals>{};
    _AdminUsageTotals usageFor(String uid) =>
        usageByUser.putIfAbsent(uid, () => _AdminUsageTotals());

    final projectUsages = await Future.wait(
      projects.map((project) async {
        final data = project.data();
        return _ProjectUserUsage(
          ownerId: asString(data['ownerId']),
          memberIds: projectMemberIds(data),
          usage: await _loadProjectUsage(project.reference),
        );
      }),
    );

    for (final project in projectUsages) {
      if (project.ownerId.isNotEmpty) {
        usageFor(project.ownerId).addProject(project.usage, owned: true);
      }

      for (final uid in project.memberIds) {
        if (uid.isNotEmpty && uid != project.ownerId) {
          usageFor(uid).addProject(project.usage, owned: false);
        }
      }
    }

    return usageByUser;
  }

  Future<_ProjectUsageCounts> _loadProjectUsage(
    DocumentReference<Map<String, dynamic>> projectRef,
  ) async {
    QuerySnapshot<Map<String, dynamic>> buildingsSnap;
    try {
      buildingsSnap = await projectRef.collection('buildings').get();
    } catch (_) {
      return const _ProjectUsageCounts.empty();
    }

    final buildingUsages = await Future.wait(
      buildingsSnap.docs.map((doc) => _loadBuildingUsage(doc.reference)),
    );

    return _ProjectUsageCounts(
      buildings: buildingsSnap.docs.length,
      drawings: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.drawings,
      ),
      measurements: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.measurements,
      ),
      boqItems: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.boqItems,
      ),
    );
  }

  Future<_ProjectUsageCounts> _loadBuildingUsage(
    DocumentReference<Map<String, dynamic>> buildingRef,
  ) async {
    final drawings = await _countCollection(buildingRef.collection('drawings'));
    final measurements = await _countCollection(
      buildingRef.collection('measurements'),
    );
    var boqItems = await _countCollection(buildingRef.collection('boq'));
    if (boqItems == 0) {
      boqItems = await _countCollection(buildingRef.collection('boqItems'));
    }

    return _ProjectUsageCounts(
      buildings: 0,
      drawings: drawings,
      measurements: measurements,
      boqItems: boqItems,
    );
  }

  Future<int> _countCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      return (await collection.count().get()).count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<_ProjectUsageCounts> loadProjectUsage(
    DocumentReference<Map<String, dynamic>> projectRef,
  ) async {
    QuerySnapshot<Map<String, dynamic>> buildingsSnap;
    try {
      buildingsSnap = await projectRef.collection('buildings').get();
    } catch (_) {
      return const _ProjectUsageCounts.empty();
    }

    final buildingUsages = await Future.wait(
      buildingsSnap.docs.map((doc) => _loadBuildingUsage(doc.reference)),
    );

    return _ProjectUsageCounts(
      buildings: buildingsSnap.docs.length,
      drawings: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.drawings,
      ),
      measurements: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.measurements,
      ),
      boqItems: buildingUsages.fold<int>(
        0,
        (sum, usage) => sum + usage.boqItems,
      ),
    );
  }

  Future<Map<String, _AdminUsageTotals>> loadUserUsageTotals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> projects,
  ) async {
    final usageByUser = <String, _AdminUsageTotals>{};
    _AdminUsageTotals usageFor(String uid) =>
        usageByUser.putIfAbsent(uid, () => _AdminUsageTotals());

    final projectUsages = await Future.wait(
      projects.map((project) async {
        final data = project.data();
        return _ProjectUserUsage(
          ownerId: asString(data['ownerId']),
          memberIds: projectMemberIds(data),
          usage: await _loadProjectUsage(project.reference),
        );
      }),
    );

    for (final project in projectUsages) {
      if (project.ownerId.isNotEmpty) {
        usageFor(project.ownerId).addProject(project.usage, owned: true);
      }

      for (final uid in project.memberIds) {
        if (uid.isNotEmpty && uid != project.ownerId) {
          usageFor(uid).addProject(project.usage, owned: false);
        }
      }
    }

    return usageByUser;
  }

  Future<List<SubscriptionPaymentRow>> _loadSubscriptionPayments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, Map<String, dynamic>> usersById,
  ) async {
    final rows = await Future.wait(
      docs.map((doc) => _buildSubscriptionPaymentRow(doc, usersById)),
    );
    rows.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return rows;
  }

  Future<SubscriptionPaymentRow> _buildSubscriptionPaymentRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, Map<String, dynamic>> usersById,
  ) async {
    final data = doc.data();
    final uid = firstText(data, ['uid', 'userId', 'ownerId']);
    final userData =
        uid.isNotEmpty
            ? usersById[uid] ?? const <String, dynamic>{}
            : const <String, dynamic>{};
    final paymentName = firstText(data, [
      'name',
      'displayName',
      'userName',
      'fullName',
    ]);
    final paymentEmail = firstText(data, ['email', 'userEmail']);
    final rawStatus = firstText(data, [
      'paymentStatus',
      'status',
      'subscriptionStatus',
      'stage',
    ]);
    final status = rawStatus.isEmpty ? 'unknown' : rawStatus;
    final isSuccessful = isSuccessfulPaymentStatus(status);
    final isFailed = isFailedPaymentStatus(status);
    final isPending = !isSuccessful && !isFailed;
    final createdAt = readDate(data['createdAt']);
    final updatedAt = readDate(data['updatedAt']);
    final callbackReceivedAt = readDate(data['callbackReceivedAt']);
    final resolvedAt =
        callbackReceivedAt ??
        readDate(data['paidAt']) ??
        readDate(data['completedAt']);
    final delayEnd =
        resolvedAt ??
        (isPending
            ? DateTime.now()
            : readDate(data['checkoutUpdatedAt']) ?? updatedAt);
    Duration? delay;
    if (createdAt != null &&
        delayEnd != null &&
        !delayEnd.isBefore(createdAt)) {
      delay = delayEnd.difference(createdAt);
    }

    QuerySnapshot<Map<String, dynamic>>? attemptsSnap;
    try {
      attemptsSnap = await doc.reference.collection('attempts').get();
    } catch (_) {
      attemptsSnap = null;
    }

    final attempts =
        (attemptsSnap?.docs ?? []).map((attemptDoc) {
            final attemptData = attemptDoc.data();
            final successValue = attemptData['success'];
            final successText = asString(successValue);
            final success =
                successValue is bool
                    ? successValue
                    : successText.isEmpty
                    ? null
                    : isSuccessfulPaymentStatus(successText);
            return PaymentAttemptRow(
              id: attemptDoc.id,
              stage: firstText(attemptData, ['stage', 'status']),
              success: success,
              errorMessage: firstText(attemptData, [
                'error',
                'errorMessage',
                'message',
              ]),
              statusCode: asString(attemptData['statusCode']),
              createdAt:
                  readDate(attemptData['createdAt']) ??
                  readDate(attemptData['failedAt']),
            );
          }).toList()
          ..sort((a, b) {
            final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          });

    final isDelayed =
        (delay != null && delay > _paymentDelayThreshold) ||
        (isPending &&
            createdAt != null &&
            DateTime.now().difference(createdAt) > _paymentDelayThreshold);

    return SubscriptionPaymentRow(
      id: doc.id,
      uid: uid,
      userName:
          paymentName.isNotEmpty
              ? paymentName
              : firstText(userData, ['name', 'displayName', 'fullName']),
      email:
          paymentEmail.isNotEmpty ? paymentEmail : asString(userData['email']),
      phone: firstText(data, [
        'maskedAccountNumber',
        'accountNumber',
        'phone',
        'msisdn',
      ]),
      plan: firstText(data, [
        'plan',
        'subscriptionPlan',
        'planName',
        'billingPlan',
      ]),
      amount: firstNum(data, [
        'amount',
        'subscriptionAmount',
        'price',
        'total',
      ]),
      currency: firstText(data, ['currency']),
      provider: firstText(data, ['provider', 'gateway', 'operator']),
      status: status,
      stage: firstText(data, ['stage']),
      errorMessage: firstText(data, ['error', 'errorMessage', 'message']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      callbackReceivedAt: callbackReceivedAt,
      delay: delay,
      isSuccessful: isSuccessful,
      isFailed: isFailed,
      isPending: isPending,
      isDelayed: isDelayed,
      attempts: attempts,
    );
  }

  List<AdminUserRow> _buildUserRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users, {
    Map<String, _AdminUsageTotals> usageByUser = const {},
  }) {
    final rows =
        users.map((doc) {
            final data = doc.data();
            final uid =
                asString(data['uid']).isNotEmpty
                    ? asString(data['uid'])
                    : doc.id;
            final plan = firstText(data, [
              'subscriptionPlan',
              'plan',
              'planName',
              'productCode',
            ]);
            final storageBytes = firstInt(data, [
              'storageUsedBytes',
              'spaceUsedBytes',
              'storageBytes',
              'usedStorageBytes',
            ]);
            final usage = usageByUser[uid] ?? _AdminUsageTotals();
            return AdminUserRow(
              uid: uid,
              name: firstText(data, ['name', 'displayName', 'fullName']),
              email: asString(data['email']),
              role:
                  asString(data['role']).isEmpty
                      ? 'user'
                      : asString(data['role']),
              status:
                  asString(data['status']).isEmpty
                      ? 'active'
                      : asString(data['status']),
              provider:
                  asString(data['provider']).isEmpty
                      ? 'email'
                      : asString(data['provider']),
              plan: plan.isEmpty ? 'Not subscribed' : plan,
              storageBytes: storageBytes,
              ownedProjects: usage.ownedProjects,
              sharedProjects: usage.sharedProjects,
              buildings: usage.buildings,
              drawings: usage.drawings,
              measurements: usage.measurements,
              boqItems: usage.boqItems,
              createdAt: readDate(data['createdAt']),
              lastLoginAt: readDate(data['lastLoginAt']),
            );
          }).toList()
          ..sort((a, b) => b.totalProjects.compareTo(a.totalProjects));
    return rows;
  }

  Future<List<AdminUserRow>> _loadUsers({bool includeUsage = false}) async {
    await assertAdminAccess();

    final usersSnap = await _tryCollection('users');
    final users = usersSnap?.docs ?? [];
    if (!includeUsage) return _buildUserRows(users);

    final projectsSnap = await _tryCollection('projects');
    final usageByUser = await _loadUserUsageTotals(projectsSnap?.docs ?? []);
    return _buildUserRows(users, usageByUser: usageByUser);
  }

  Future<AdminDashboardData> _fetchBillingData() async {
    await assertAdminAccess();

    final usersSnap = await _tryCollection('users');
    final subscriptionPaymentsSnap = await _tryCollection('payment-attempts');
    final usersById = <String, Map<String, dynamic>>{};
    for (final user in usersSnap?.docs ?? []) {
      final data = user.data();
      usersById[user.id] = data;
      final uid = asString(data['uid']);
      if (uid.isNotEmpty) usersById[uid] = data;
    }
    final subscriptionPayments = await _loadSubscriptionPayments(
      subscriptionPaymentsSnap?.docs ?? [],
      usersById,
    );

    return AdminDashboardData(
      users: const [],
      projectCount: 0,
      clientCount: 0,
      inviteCount: 0,
      workspaceMemberCount: 0,
      totalStorageBytes: 0,
      contactMessages: const [],
      subscriptionPayments: subscriptionPayments,
    );
  }

  Future<ProjectsAdminData> _fetchProjectsData() async {
    await assertAdminAccess();

    final results = await Future.wait([
      _tryCollection('projects'),
      _tryCollection('clients'),
      _tryCollection('teamInvites'),
      _tryCollection('workspaceMembers'),
      _tryCollection('users'),
    ]);

    final projectsSnap = results[0];
    final clientsSnap = results[1];
    final invitesSnap = results[2];
    final membersSnap = results[3];
    final usersSnap = results[4];

    final projects = projectsSnap?.docs ?? [];
    final clients = clientsSnap?.docs ?? [];
    final invites = invitesSnap?.docs ?? [];
    final members = membersSnap?.docs ?? [];
    final users = usersSnap?.docs ?? [];

    // --------------------------------------------------
    // USERS LOOKUP
    // --------------------------------------------------

    final usersById = <String, Map<String, dynamic>>{};

    for (final doc in users) {
      final data = doc.data();

      usersById[doc.id] = data;

      final uid = asString(data['uid']);

      if (uid.isNotEmpty) {
        usersById[uid] = data;
      }
    }

    // --------------------------------------------------
    // PROJECTS
    // --------------------------------------------------

    final projectRows = await Future.wait(
      projects.map((projectDoc) async {
        final data = projectDoc.data();

        final ownerId = firstText(data, [
          'ownerId',
          'ownerUid',
          'userId',
          'createdBy',
        ]);

        final ownerData = usersById[ownerId] ?? const <String, dynamic>{};

        final ownerName = firstText(ownerData, [
          'name',
          'displayName',
          'fullName',
          'email',
        ]);

        final usage = await _loadProjectUsage(projectDoc.reference);

        return AdminProjectRow(
          id: projectDoc.id,

          name: firstText(data, ['projectName', 'name', 'title']),

          ownerId: ownerId,
          ownerName: ownerName,

          clientName: firstText(data, ['clientName', 'client']),

          facilities: usage.buildings,
          drawings: usage.drawings,
          measurements: usage.measurements,
          boqItems: usage.boqItems,

          createdAt: readDate(data['createdAt']),
        );
      }),
    );

    projectRows.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return bd.compareTo(ad);
    });

    // --------------------------------------------------
    // CLIENTS
    // --------------------------------------------------

    final clientRows =
        clients.map((doc) {
          final data = doc.data();

          return AdminClientRow(
            id: doc.id,

            name: firstText(data, ['name', 'clientName', 'contactName']),

            email: firstText(data, ['email']),

            phone: firstText(data, ['phone', 'phoneNumber', 'mobile']),

            company: firstText(data, [
              'company',
              'companyName',
              'organization',
            ]),

            createdAt: readDate(data['createdAt']),
          );
        }).toList();

    // --------------------------------------------------
    // INVITES
    // --------------------------------------------------

    final inviteRows =
        invites.map((doc) {
          final data = doc.data();

          return AdminInviteRow(
            id: doc.id,

            email: firstText(data, ['email']),

            name: firstText(data, ['name', 'displayName', 'fullName']),

            role: firstText(data, ['role']),

            status: firstText(data, ['status']),

            projectName: firstText(data, ['projectName', 'workspaceName']),

            createdAt: readDate(data['createdAt']),
          );
        }).toList();

    // --------------------------------------------------
    // WORKSPACE MEMBERS
    // --------------------------------------------------

    final workspaceRows =
        members.map((doc) {
          final data = doc.data();

          final uid = firstText(data, ['uid', 'userId', 'memberUid']);

          final userData = usersById[uid] ?? const <String, dynamic>{};

          return AdminWorkspaceMemberRow(
            id: doc.id,
            uid: uid,

            name:
                firstText(data, ['name', 'displayName', 'fullName']).isNotEmpty
                    ? firstText(data, ['name', 'displayName', 'fullName'])
                    : firstText(userData, ['name', 'displayName', 'fullName']),

            email:
                firstText(data, ['email']).isNotEmpty
                    ? firstText(data, ['email'])
                    : firstText(userData, ['email']),

            role: firstText(data, ['role']),

            status: firstText(data, ['status']),

            createdAt: readDate(data['createdAt']),
          );
        }).toList();

    return ProjectsAdminData(
      projectCount: projectRows.length,
      clientCount: clientRows.length,
      inviteCount: inviteRows.length,
      workspaceMemberCount: workspaceRows.length,

      projects: projectRows,
      clients: clientRows,
      invites: inviteRows,
      workspaceMembers: workspaceRows,
    );
  }

  // =========================================================
  // MOVE YOUR EXISTING DATA METHODS BELOW
  // =========================================================

  //
  // These methods can be moved almost unchanged from your
  // current AdminDashboardPage:
  //
  // _projectMemberIds()
  // _countCollection()
  // _loadBuildingUsage()
  // _loadProjectUsage()
  // _loadUserUsageTotals()
  // _loadSubscriptionPayments()
  // _buildSubscriptionPaymentRow()
  // _buildUserRows()
  //
  // Rename:
  //
  // _loadWebhookData()
  //      ↓
  // _fetchBillingData()
  //
  // _loadProjectsData()
  //      ↓
  // _fetchProjectsData()
  //
}

const _paymentDelayThreshold = Duration(minutes: 10);

// class _AdminDashboardData {
//   const _AdminDashboardData({
//     required this.users,
//     required this.projectCount,
//     required this.clientCount,
//     required this.inviteCount,
//     required this.workspaceMemberCount,
//     required this.totalStorageBytes,
//     required this.contactMessages,
//     required this.subscriptionPayments,
//   });

//   factory _AdminDashboardData.empty() => const _AdminDashboardData(
//     users: [],
//     projectCount: 0,
//     clientCount: 0,
//     inviteCount: 0,
//     workspaceMemberCount: 0,
//     totalStorageBytes: 0,
//     contactMessages: [],
//     subscriptionPayments: [],
//   );

//   final List<AdminUserRow> users;
//   final int projectCount;
//   final int clientCount;
//   final int inviteCount;
//   final int workspaceMemberCount;
//   final int totalStorageBytes;
//   final List<_ContactMessageRow> contactMessages;
//   final List<_SubscriptionPaymentRow> subscriptionPayments;

//   int get activeUsers =>
//       users.where((user) => user.status.toLowerCase() == 'active').length;

//   int get subscribedUsers => users.where((user) => user.isSubscribed).length;

//   int get adminUsers =>
//       users.where((user) {
//         final role = user.role.toLowerCase();
//         return role == 'admin' || role == 'owner';
//       }).length;

//   int get newContactMessages =>
//       contactMessages
//           .where((message) => message.status.toLowerCase() == 'new')
//           .length;

//   int get successfulSubscriptionPayments =>
//       subscriptionPayments.where((payment) => payment.isSuccessful).length;

//   int get failedSubscriptionPayments =>
//       subscriptionPayments.where((payment) => payment.isFailed).length;

//   int get pendingSubscriptionPayments =>
//       subscriptionPayments.where((payment) => payment.isPending).length;

//   int get delayedSubscriptionPayments =>
//       subscriptionPayments.where((payment) => payment.isDelayed).length;

//   int get subscriptionAttempts => subscriptionPayments.fold<int>(
//     0,
//     (sum, payment) => sum + payment.attemptCount,
//   );

//   int get successfulSubscriptionAttempts => subscriptionPayments.fold<int>(
//     0,
//     (sum, payment) => sum + payment.successAttempts,
//   );

//   int get failedSubscriptionAttempts => subscriptionPayments.fold<int>(
//     0,
//     (sum, payment) => sum + payment.failedAttempts,
//   );

//   double get subscriptionSuccessRate =>
//       subscriptionPayments.isEmpty
//           ? 0
//           : successfulSubscriptionPayments / subscriptionPayments.length * 100;

//   double get subscriptionFailureRate =>
//       subscriptionPayments.isEmpty
//           ? 0
//           : failedSubscriptionPayments / subscriptionPayments.length * 100;

//   double get subscriptionDelayRate =>
//       subscriptionPayments.isEmpty
//           ? 0
//           : delayedSubscriptionPayments / subscriptionPayments.length * 100;

//   num get subscriptionRevenue => subscriptionPayments.fold<num>(
//     0,
//     (sum, payment) => payment.isSuccessful ? sum + (payment.amount ?? 0) : sum,
//   );

//   Duration? get averagePaymentDelay {
//     final delays =
//         subscriptionPayments
//             .map((payment) => payment.delay)
//             .whereType<Duration>()
//             .toList();
//     if (delays.isEmpty) return null;
//     final totalMilliseconds = delays.fold<int>(
//       0,
//       (sum, delay) => sum + delay.inMilliseconds,
//     );
//     return Duration(milliseconds: totalMilliseconds ~/ delays.length);
//   }

//   List<AdminUserRow> filtered(String query) {
//     final q = query.trim().toLowerCase();
//     if (q.isEmpty) return users;
//     return users.where((user) {
//       return user.name.toLowerCase().contains(q) ||
//           user.email.toLowerCase().contains(q) ||
//           user.role.toLowerCase().contains(q) ||
//           user.status.toLowerCase().contains(q) ||
//           user.plan.toLowerCase().contains(q) ||
//           user.provider.toLowerCase().contains(q) ||
//           user.totalProjects.toString().contains(q) ||
//           user.buildings.toString().contains(q) ||
//           user.drawings.toString().contains(q) ||
//           user.measurements.toString().contains(q) ||
//           user.boqItems.toString().contains(q);
//     }).toList();
//   }
// }

class _ProjectUserUsage {
  const _ProjectUserUsage({
    required this.ownerId,
    required this.memberIds,
    required this.usage,
  });

  final String ownerId;
  final Set<String> memberIds;
  final _ProjectUsageCounts usage;
}

class _ProjectUsageCounts {
  const _ProjectUsageCounts({
    required this.buildings,
    required this.drawings,
    required this.measurements,
    required this.boqItems,
  });

  const _ProjectUsageCounts.empty()
    : buildings = 0,
      drawings = 0,
      measurements = 0,
      boqItems = 0;

  final int buildings;
  final int drawings;
  final int measurements;
  final int boqItems;
}

// class _AdminUserRow {
//   const _AdminUserRow({
//     required this.uid,
//     required this.name,
//     required this.email,
//     required this.role,
//     required this.status,
//     required this.provider,
//     required this.plan,
//     required this.storageBytes,
//     required this.ownedProjects,
//     required this.sharedProjects,
//     required this.buildings,
//     required this.drawings,
//     required this.measurements,
//     required this.boqItems,
//     required this.createdAt,
//     required this.lastLoginAt,
//   });

//   final String uid;
//   final String name;
//   final String email;
//   final String role;
//   final String status;
//   final String provider;
//   final String plan;
//   final int? storageBytes;
//   final int ownedProjects;
//   final int sharedProjects;
//   final int buildings;
//   final int drawings;
//   final int measurements;
//   final int boqItems;
//   final DateTime? createdAt;
//   final DateTime? lastLoginAt;

//   int get totalProjects => ownedProjects + sharedProjects;

//   String get normalizedStatus => status.trim().toLowerCase();

//   bool get isActive => normalizedStatus == 'active';

//   bool get isSuspended => normalizedStatus == 'suspended';

//   bool get isDeleted => normalizedStatus == 'deleted';

//   bool get isSubscribed {
//     final p = plan.trim().toLowerCase();
//     return p.isNotEmpty &&
//         p != 'free' &&
//         p != 'none' &&
//         p != 'not subscribed' &&
//         p != 'trial';
//   }

//   String get displayName {
//     if (name.trim().isNotEmpty) return name.trim();
//     if (email.trim().isNotEmpty) return email.trim().split('@').first;
//     return 'Unnamed user';
//   }

//   String get initials {
//     final text = displayName.trim();
//     if (text.isEmpty) return 'U';
//     final parts =
//         text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
//     if (parts.length >= 2) {
//       return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
//     }
//     return text.substring(0, 1).toUpperCase();
//   }

//   String get storageLabel =>
//       storageBytes == null || storageBytes == 0
//           ? '—'
//           : formatBytes(storageBytes!);

//   String get lastLoginLabel => formatDate(lastLoginAt ?? createdAt);
// }

// class _ProjectsAdminData {
//   const _ProjectsAdminData({
//     required this.projectCount,
//     required this.clientCount,
//     required this.inviteCount,
//     required this.workspaceMemberCount,
//     required this.projects,
//     required this.clients,
//     required this.invites,
//     required this.workspaceMembers,
//   });

//   final int projectCount;
//   final int clientCount;
//   final int inviteCount;
//   final int workspaceMemberCount;

//   final List<_AdminProjectRow> projects;
//   final List<_AdminClientRow> clients;
//   final List<_AdminInviteRow> invites;
//   final List<_AdminWorkspaceMemberRow> workspaceMembers;
// }

// class _AdminProjectRow {
//   const _AdminProjectRow({
//     required this.id,
//     required this.name,
//     required this.ownerId,
//     required this.ownerName,
//     required this.clientName,
//     required this.facilities,
//     required this.drawings,
//     required this.measurements,
//     required this.boqItems,
//     required this.createdAt,
//   });

//   final String id;
//   final String name;

//   final String ownerId;
//   final String ownerName;

//   final String clientName;

//   final int facilities;
//   final int drawings;
//   final int measurements;
//   final int boqItems;

//   final DateTime? createdAt;

//   String get displayName {
//     if (name.trim().isNotEmpty) return name.trim();
//     return 'Unnamed project';
//   }

//   String get ownerLabel {
//     if (ownerName.trim().isNotEmpty) return ownerName.trim();
//     if (ownerId.trim().isNotEmpty) return ownerId.trim();
//     return 'Unknown owner';
//   }
// }

// class _AdminClientRow {
//   const _AdminClientRow({
//     required this.id,
//     required this.name,
//     required this.email,
//     required this.phone,
//     required this.company,
//     required this.createdAt,
//   });

//   final String id;
//   final String name;
//   final String email;
//   final String phone;
//   final String company;
//   final DateTime? createdAt;

//   String get displayName {
//     if (name.trim().isNotEmpty) return name;
//     if (company.trim().isNotEmpty) return company;
//     return 'Unnamed client';
//   }
// }

// class _AdminInviteRow {
//   const _AdminInviteRow({
//     required this.id,
//     required this.email,
//     required this.name,
//     required this.role,
//     required this.status,
//     required this.projectName,
//     required this.createdAt,
//   });

//   final String id;
//   final String email;
//   final String name;
//   final String role;
//   final String status;
//   final String projectName;
//   final DateTime? createdAt;

//   String get displayName {
//     if (name.trim().isNotEmpty) return name;
//     if (email.trim().isNotEmpty) return email;
//     return 'Invited user';
//   }
// }

// class _AdminWorkspaceMemberRow {
//   const _AdminWorkspaceMemberRow({
//     required this.id,
//     required this.uid,
//     required this.name,
//     required this.email,
//     required this.role,
//     required this.status,
//     required this.createdAt,
//   });

//   final String id;
//   final String uid;
//   final String name;
//   final String email;
//   final String role;
//   final String status;
//   final DateTime? createdAt;

//   String get displayName {
//     if (name.trim().isNotEmpty) return name;
//     if (email.trim().isNotEmpty) return email;
//     return 'Workspace member';
//   }
// }

// class _SubscriptionPaymentRow {
//   const _SubscriptionPaymentRow({
//     required this.id,
//     required this.uid,
//     required this.userName,
//     required this.email,
//     required this.phone,
//     required this.plan,
//     required this.amount,
//     required this.currency,
//     required this.provider,
//     required this.status,
//     required this.stage,
//     required this.errorMessage,
//     required this.createdAt,
//     required this.updatedAt,
//     required this.callbackReceivedAt,
//     required this.delay,
//     required this.isSuccessful,
//     required this.isFailed,
//     required this.isPending,
//     required this.isDelayed,
//     required this.attempts,
//   });

//   final String id;
//   final String uid;
//   final String userName;
//   final String email;
//   final String phone;
//   final String plan;
//   final num? amount;
//   final String currency;
//   final String provider;
//   final String status;
//   final String stage;
//   final String errorMessage;
//   final DateTime? createdAt;
//   final DateTime? updatedAt;
//   final DateTime? callbackReceivedAt;
//   final Duration? delay;
//   final bool isSuccessful;
//   final bool isFailed;
//   final bool isPending;
//   final bool isDelayed;
//   final List<PaymentAttemptRow> attempts;

//   int get attemptCount => attempts.length;

//   int get successAttempts =>
//       attempts.where((attempt) => attempt.success == true).length;

//   int get failedAttempts =>
//       attempts.where((attempt) => attempt.isFailed).length;

//   String get userLabel {
//     if (userName.trim().isNotEmpty) return userName.trim();
//     if (email.trim().isNotEmpty) return email.trim().split('@').first;
//     return 'Unknown user';
//   }

//   String get contactLabel {
//     final pieces = <String>[];
//     if (email.trim().isNotEmpty) pieces.add(email.trim());
//     if (phone.trim().isNotEmpty) pieces.add(phone.trim());
//     pieces.add(uid.trim().isEmpty ? 'No UID' : 'UID: ${uid.trim()}');
//     return pieces.join(' • ');
//   }

//   String get planLabel =>
//       plan.trim().isEmpty ? 'No plan' : titleCaseStatus(plan);

//   String get amountLabel => formatMoney(amount, currency);

//   String get providerLabel {
//     final gateway =
//         provider.trim().isEmpty ? 'Payment provider unknown' : provider;
//     final currentStage =
//         stage.trim().isEmpty ? '' : ' • ${titleCaseStatus(stage)}';
//     return '$gateway$currentStage';
//   }

//   String get statusLabel => titleCaseStatus(status);

//   String get delayLabel =>
//       isDelayed
//           ? 'Delayed ${formatDuration(delay)}'
//           : 'Delay ${formatDuration(delay)}';

//   String get attemptSummary {
//     if (attemptCount == 0) return 'No attempts';
//     return '$attemptCount attempts';
//   }

//   IconData get statusIcon {
//     if (isSuccessful) return Icons.check_circle_outline_rounded;
//     if (isFailed) return Icons.error_outline_rounded;
//     if (isDelayed) return Icons.timer_outlined;
//     return Icons.pending_outlined;
//   }
// }

// class _PaymentAttemptRow {
//   const _PaymentAttemptRow({
//     required this.id,
//     required this.stage,
//     required this.success,
//     required this.errorMessage,
//     required this.statusCode,
//     required this.createdAt,
//   });

//   final String id;
//   final String stage;
//   final bool? success;
//   final String errorMessage;
//   final String statusCode;
//   final DateTime? createdAt;

//   bool get isFailed => success == false || errorMessage.trim().isNotEmpty;

//   String get stageLabel =>
//       stage.trim().isEmpty ? 'Payment attempt' : titleCaseStatus(stage);

//   String get detailLabel {
//     final details = <String>[];
//     if (success == true) details.add('Successful checkout request');
//     if (isFailed) {
//       details.add(
//         errorMessage.trim().isEmpty ? 'Failed attempt' : errorMessage.trim(),
//       );
//     }
//     if (statusCode.trim().isNotEmpty) details.add('Status $statusCode');
//     return details.join(' • ');
//   }

//   IconData get icon {
//     if (success == true) return Icons.check_circle_outline_rounded;
//     if (isFailed) return Icons.error_outline_rounded;
//     return Icons.radio_button_unchecked_rounded;
//   }
// }
class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();
}

class _ContactMessageRow {
  const _ContactMessageRow({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.subject,
    required this.message,
    required this.source,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String subject;
  final String message;
  final String source;
  final String status;
  final DateTime? createdAt;

  String get nameLabel => name.trim().isEmpty ? 'Anonymous' : name.trim();

  String get emailLabel => email.trim().isEmpty ? 'No email' : email.trim();

  String get phoneLabel => phone.trim().isEmpty ? 'No phone' : phone.trim();
}

class _AdminUsageTotals {
  int ownedProjects = 0;
  int sharedProjects = 0;
  int buildings = 0;
  int drawings = 0;
  int measurements = 0;
  int boqItems = 0;

  void addProject(_ProjectUsageCounts usage, {required bool owned}) {
    if (owned) {
      ownedProjects += 1;
    } else {
      sharedProjects += 1;
    }
    buildings += usage.buildings;
    drawings += usage.drawings;
    measurements += usage.measurements;
    boqItems += usage.boqItems;
  }
}

class _Metric {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String note;
}

enum _PillTone { blue, green, grey, red, amber }

({Color bg, Color fg, Color border}) _pillColors(_PillTone tone) {
  return switch (tone) {
    _PillTone.blue => (
      bg: AqsColors.primarySoft,
      fg: AqsColors.primary,
      border: const Color(0xFFD1E0FF),
    ),
    _PillTone.green => (
      bg: AqsColors.successSoft,
      fg: AqsColors.success,
      border: const Color(0xFFA6F4C5),
    ),
    _PillTone.grey => (
      bg: const Color(0xFFF2F4F7),
      fg: AqsColors.muted,
      border: const Color(0xFFE4E7EC),
    ),
    _PillTone.red => (
      bg: const Color(0xFFFFF1F3),
      fg: const Color(0xFFC01048),
      border: const Color(0xFFFECDD6),
    ),
    _PillTone.amber => (
      bg: const Color(0xFFFFFAEB),
      fg: const Color(0xFFB54708),
      border: const Color(0xFFFEDF89),
    ),
  };
}
