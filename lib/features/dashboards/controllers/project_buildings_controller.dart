import 'package:aqs/features/dashboards/models/buildings_models.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class ProjectBuildingsController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RxMap<String, List<BuildingRowFs>> buildingsByProject =
      <String, List<BuildingRowFs>>{}.obs;

  final RxMap<String, bool> loadingByProject = <String, bool>{}.obs;

  final RxMap<String, String> errorByProject = <String, String>{}.obs;

  final RxMap<String, BuildingCounts> countsCache =
      <String, BuildingCounts>{}.obs;

  final RxSet<String> loadingCounts = <String>{}.obs;

  final RxMap<String, List<Map<String, dynamic>>> measurementsByBuilding =
      <String, List<Map<String, dynamic>>>{}.obs;

  final RxMap<String, List<Map<String, dynamic>>> boqByBuilding =
      <String, List<Map<String, dynamic>>>{}.obs;

  final RxSet<String> loadingMeasurements = <String>{}.obs;
  final RxSet<String> loadingBoq = <String>{}.obs;

  final RxMap<String, BuildingFinancialSummary> financialSummaryCache =
      <String, BuildingFinancialSummary>{}.obs;
  final RxSet<String> loadingFinancialSummaries = <String>{}.obs;

  // Deduplicate BOQ loads so every picker awaits the same in-flight request
  // instead of starting a second Firestore read while the workspace preload is running.
  final Map<String, Future<void>> _boqInFlight = <String, Future<void>>{};

  final RxMap<String, String> measurementErrors = <String, String>{}.obs;

  final RxMap<String, String> boqErrors = <String, String>{}.obs;

  String _countKey(String projectId, String buildingId) {
    return '$projectId::$buildingId';
  }

  String buildingKey(String projectId, String buildingId) {
    return '$projectId::$buildingId';
  }

  List<Map<String, dynamic>> boqFor(String projectId, String buildingId) {
    return boqByBuilding[buildingKey(projectId, buildingId)] ??
        const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> measurementsFor(
    String projectId,
    String buildingId,
  ) {
    return measurementsByBuilding[buildingKey(projectId, buildingId)] ??
        const <Map<String, dynamic>>[];
  }

  bool boqLoaded(String projectId, String buildingId) {
    return boqByBuilding.containsKey(buildingKey(projectId, buildingId));
  }

  bool measurementsLoaded(String projectId, String buildingId) {
    return measurementsByBuilding.containsKey(
      buildingKey(projectId, buildingId),
    );
  }

  BuildingFinancialSummary? cachedFinancialSummary(
    String projectId,
    String buildingId,
  ) => financialSummaryCache[buildingKey(projectId, buildingId)];

  bool isLoadingFinancialSummary(String projectId, String buildingId) =>
      loadingFinancialSummaries.contains(buildingKey(projectId, buildingId));

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '').trim()) ?? 0;
  }

  String _textKey(dynamic value) =>
      (value ?? '')
          .toString()
          .trim()
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();

  Future<void> loadBuildingFinancialSummary(
    String projectId,
    String buildingId, {
    bool forceRefresh = false,
  }) async {
    final key = buildingKey(projectId, buildingId);
    if (!forceRefresh && financialSummaryCache.containsKey(key)) return;
    if (loadingFinancialSummaries.contains(key)) return;

    loadingFinancialSummaries.add(key);
    try {
      final buildingRef = _firestore
          .collection('projects')
          .doc(projectId)
          .collection('buildings')
          .doc(buildingId);

      var boqSnapshot = await buildingRef.collection('boq').get();
      if (boqSnapshot.docs.isEmpty) {
        boqSnapshot = await buildingRef.collection('boqItems').get();
      }
      final results = await Future.wait([
        buildingRef.collection('measurements').get(),
        buildingRef.collection('generalAllowances').get(),
      ]);
      final measurementSnapshot = results[0];
      final allowanceSnapshot = results[1];
      final boqRows =
          boqSnapshot.docs
              .map((doc) => Map<String, dynamic>.from(doc.data()))
              .toList();

      final totalsByItem = <String, double>{};
      final totalsByCode = <String, double>{};
      for (final doc in measurementSnapshot.docs) {
        final data = doc.data();
        final quantity = _number(data['value']);
        final itemId = (data['boqItemId'] ?? '').toString().trim();
        if (itemId.isNotEmpty) {
          totalsByItem.update(
            itemId,
            (old) => old + quantity,
            ifAbsent: () => quantity,
          );
          continue;
        }
        final aliases = <String>{
          _textKey(data['boqCode']),
          _textKey(data['resolvedBoqCode']),
          _textKey(data['boqCodeNorm']),
        }..removeWhere((value) => value.isEmpty);
        for (final alias in aliases) {
          totalsByCode.update(
            alias,
            (old) => old + quantity,
            ifAbsent: () => quantity,
          );
        }
      }

      final aliasCounts = <String, int>{};
      for (final data in boqRows) {
        final rowType =
            (data['rowType'] ?? 'item').toString().trim().toLowerCase();
        if (rowType.isNotEmpty && rowType != 'item') continue;
        final aliases = <String>{
          _textKey(data['resolvedBoqCode']),
          _textKey(data['displayCode']),
          _textKey(data['boqCode']),
          _textKey(hierarchicalBoqCodeFromRows(data, boqRows)),
        }..removeWhere((value) => value.isEmpty);
        for (final alias in aliases) {
          aliasCounts.update(alias, (count) => count + 1, ifAbsent: () => 1);
        }
      }

      var totalItems = 0;
      var measuredItems = 0;
      var measuredAmount = 0.0;
      for (final doc in boqSnapshot.docs) {
        final data = doc.data();
        final rowType =
            (data['rowType'] ?? 'item').toString().trim().toLowerCase();
        if (rowType.isNotEmpty && rowType != 'item') continue;
        totalItems++;

        final resolved = (data['resolvedBoqCode'] ?? '').toString().trim();
        final raw = (data['boqCode'] ?? '').toString().trim();
        final display = (data['displayCode'] ?? '').toString().trim();
        final canonical = hierarchicalBoqCodeFromRows(data, boqRows);
        var measuredQuantity = totalsByItem[doc.id];
        if (measuredQuantity == null) {
          final aliases = <String>{
            _textKey(resolved.isNotEmpty ? resolved : raw),
            _textKey(display),
            _textKey(raw),
            _textKey(canonical),
          }..removeWhere((value) => value.isEmpty);
          for (final alias in aliases) {
            if (aliasCounts[alias] != 1) continue;
            final matched = totalsByCode[alias];
            if (matched != null) {
              measuredQuantity = matched;
              break;
            }
          }
        }
        measuredQuantity ??= 0;
        final override = data['qtyOverride'];
        final quantity =
            override == null ? measuredQuantity : _number(override);
        if (quantity > 0) measuredItems++;
        measuredAmount += quantity * _number(data['rate']);
      }

      var allowanceAmount = 0.0;
      for (final doc in allowanceSnapshot.docs) {
        final data = doc.data();
        if (data['includedInTotal'] == false) continue;
        allowanceAmount +=
            data['amount'] == null
                ? _number(data['quantity']) * _number(data['rate'])
                : _number(data['amount']);
      }

      financialSummaryCache[key] = BuildingFinancialSummary(
        totalBoqItems: totalItems,
        measuredBoqItems: measuredItems,
        measuredWorksAmount: measuredAmount,
        buildingAllowancesAmount: allowanceAmount,
      );
    } catch (error) {
      debugPrint('Building financial summary error: $error');
    } finally {
      loadingFinancialSummaries.remove(key);
    }
  }

  String _buildingKey(String projectId, String buildingId) {
    return '$projectId::$buildingId';
  }

  // List<Map<String, dynamic>> measurementsFor(
  //   String projectId,
  //   String buildingId,
  // ) {
  //   return measurementsByBuilding[_buildingKey(projectId, buildingId)] ??
  //       const [];
  // }

  bool hasMeasurementsLoaded(String projectId, String buildingId) {
    return measurementsByBuilding.containsKey(
      _buildingKey(projectId, buildingId),
    );
  }

  BuildingCounts? cachedCounts(String projectId, String buildingId) {
    return countsCache[_countKey(projectId, buildingId)];
  }

  bool isLoadingCounts(String projectId, String buildingId) {
    return loadingCounts.contains(_countKey(projectId, buildingId));
  }

  final Map<String, Future<BuildingCounts>> _countsInFlight = {};

  bool hasProject(String projectId) {
    return buildingsByProject.containsKey(projectId);
  }

  List<BuildingRowFs> buildingsFor(String projectId) {
    return buildingsByProject[projectId] ?? const [];
  }

  bool isLoading(String projectId) {
    return loadingByProject[projectId] ?? false;
  }

  String errorFor(String projectId) {
    return errorByProject[projectId] ?? '';
  }

  Future<void> loadMeasurements(
    String projectId,
    String buildingId, {
    bool forceRefresh = false,
  }) async {
    final key = _buildingKey(projectId, buildingId);

    if (!forceRefresh && measurementsByBuilding.containsKey(key)) {
      return;
    }

    if (loadingMeasurements.contains(key)) {
      return;
    }

    loadingMeasurements.add(key);
    measurementErrors.remove(key);

    try {
      final snapshot =
          await _firestore
              .collection('projects')
              .doc(projectId)
              .collection('buildings')
              .doc(buildingId)
              .collection('measurements')
              .get();

      measurementsByBuilding[key] =
          snapshot.docs.map((doc) {
            return {'id': doc.id, ...doc.data()};
          }).toList();

      // Keep the card count synchronized.
      _syncMeasurementCount(projectId, buildingId);
    } catch (e) {
      measurementErrors[key] = e.toString();
    } finally {
      loadingMeasurements.remove(key);
    }
  }

  void _syncMeasurementCount(String projectId, String buildingId) {
    final key = _buildingKey(projectId, buildingId);

    final measurements = measurementsByBuilding[key];

    if (measurements == null) {
      return;
    }

    final current = countsCache[key];

    // Do not create fake zero counts.
    if (current == null) {
      return;
    }

    countsCache[key] = BuildingCounts(
      drawings: current.drawings,
      measurements: measurements.length,
      boqItems: current.boqItems,
    );
  }

  // void _syncMeasurementCount(String projectId, String buildingId) {
  //   final key = _buildingKey(projectId, buildingId);

  //   final measurements = measurementsByBuilding[key];

  //   if (measurements == null) {
  //     return;
  //   }

  //   final current = countsCache[key];

  //   if (current == null) {
  //     countsCache[key] = BuildingCounts(
  //       drawings: 0,
  //       measurements: measurements.length,
  //       boqItems: 0,
  //     );

  //     return;
  //   }

  //   countsCache[key] = BuildingCounts(
  //     drawings: current.drawings,
  //     measurements: measurements.length,
  //     boqItems: current.boqItems,
  //   );
  // }

  Future<void> loadBoq(
    String projectId,
    String buildingId, {
    bool forceRefresh = false,
  }) async {
    final key = _buildingKey(projectId, buildingId);

    if (!forceRefresh && boqByBuilding.containsKey(key)) {
      return;
    }

    // If a background preload is already running, callers (including the BOQ
    // picker) wait for that exact request instead of returning early and then
    // falling back to another Firestore query.
    final existing = _boqInFlight[key];
    if (existing != null) {
      await existing;
      if (!forceRefresh) return;
    }

    Future<void> doLoad() async {
      loadingBoq.add(key);
      boqErrors.remove(key);

      try {
        final buildingRef = _firestore
            .collection('projects')
            .doc(projectId)
            .collection('buildings')
            .doc(buildingId);

        var snapshot = await buildingRef.collection('boq').get();
        if (snapshot.docs.isEmpty) {
          snapshot = await buildingRef.collection('boqItems').get();
        }

        final rows =
            snapshot.docs.map((doc) {
              return <String, dynamic>{'id': doc.id, ...doc.data()};
            }).toList();

        rows.sort((a, b) {
          final aOrder = a['order'];
          final bOrder = b['order'];
          final aNumber =
              aOrder is num
                  ? aOrder.toDouble()
                  : double.tryParse('$aOrder') ?? 0;
          final bNumber =
              bOrder is num
                  ? bOrder.toDouble()
                  : double.tryParse('$bOrder') ?? 0;
          final orderCompare = aNumber.compareTo(bNumber);
          if (orderCompare != 0) return orderCompare;

          final aOrderKey = (a['orderKey'] ?? '').toString().trim();
          final bOrderKey = (b['orderKey'] ?? '').toString().trim();
          if (aOrderKey.isNotEmpty || bOrderKey.isNotEmpty) {
            final keyCompare = aOrderKey.compareTo(bOrderKey);
            if (keyCompare != 0) return keyCompare;
          }

          final aCreatedAt = a['createdAt'];
          final bCreatedAt = b['createdAt'];
          if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
            return aCreatedAt.compareTo(bCreatedAt);
          }
          return 0;
        });

        boqByBuilding[key] = rows;
        _syncBoqCount(projectId, buildingId);
      } catch (e) {
        boqErrors[key] = e.toString();
        debugPrint(
          'loadBoq failed project=$projectId building=$buildingId error=$e',
        );
      } finally {
        loadingBoq.remove(key);
      }
    }

    final future = doLoad();
    _boqInFlight[key] = future;
    try {
      await future;
    } finally {
      if (identical(_boqInFlight[key], future)) {
        _boqInFlight.remove(key);
      }
    }
  }

  void _syncBoqCount(String projectId, String buildingId) {
    final key = _buildingKey(projectId, buildingId);

    final boq = boqByBuilding[key];

    if (boq == null) {
      return;
    }

    final current = countsCache[key];

    // IMPORTANT:
    // If the real building counts have not been loaded yet,
    // don't invent Drawings=0 and Measurements=0 here.
    if (current == null) {
      return;
    }

    countsCache[key] = BuildingCounts(
      drawings: current.drawings,
      measurements: current.measurements,
      boqItems: boq.length,
    );
  }

  // void _syncBoqCount(String projectId, String buildingId) {
  //   final key = _buildingKey(projectId, buildingId);

  //   final boq = boqByBuilding[key];

  //   if (boq == null) {
  //     return;
  //   }

  //   final current = countsCache[key];

  //   if (current == null) {
  //     countsCache[key] = BuildingCounts(
  //       drawings: 0,
  //       measurements: 0,
  //       boqItems: boq.length,
  //     );

  //     return;
  //   }

  //   countsCache[key] = BuildingCounts(
  //     drawings: current.drawings,
  //     measurements: current.measurements,
  //     boqItems: boq.length,
  //   );
  // }

  Future<void> loadBuildings(
    String projectId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && hasProject(projectId)) {
      return;
    }

    if (isLoading(projectId)) return;

    loadingByProject[projectId] = true;
    errorByProject.remove(projectId);

    try {
      final snapshot =
          await _firestore
              .collection('projects')
              .doc(projectId)
              .collection('buildings')
              .orderBy('createdAt', descending: true)
              .get();

      buildingsByProject[projectId] =
          snapshot.docs
              .where((doc) => doc.data()['isDeleted'] != true)
              .map(BuildingRowFs.fromDoc)
              .toList();
    } catch (e) {
      errorByProject[projectId] = e.toString();
    } finally {
      loadingByProject[projectId] = false;
    }
  }

  Future<void> refreshBuildings(String projectId) {
    return loadBuildings(projectId, forceRefresh: true);
  }

  Future<BuildingCounts> getBuildingCounts(
    String projectId,
    String buildingId, {
    bool forceRefresh = false,
  }) {
    final cacheKey = '$projectId::$buildingId';

    if (!forceRefresh) {
      final cached = countsCache[cacheKey];
      if (cached != null) {
        return Future.value(cached);
      }

      final inflight = _countsInFlight[cacheKey];
      if (inflight != null) {
        return inflight;
      }
    }

    final future = _computeBuildingCounts(projectId, buildingId);

    _countsInFlight[cacheKey] = future;

    return future;
  }

  Future<void> loadBuildingCounts(
    String projectId,
    String buildingId, {
    bool forceRefresh = false,
  }) async {
    final key = _buildingKey(projectId, buildingId);

    if (!forceRefresh && countsCache.containsKey(key)) {
      return;
    }

    if (loadingCounts.contains(key)) {
      return;
    }

    loadingCounts.add(key);

    try {
      final buildingRef = _firestore
          .collection('projects')
          .doc(projectId)
          .collection('buildings')
          .doc(buildingId);

      int drawings = 0;
      int measurements = 0;
      int boqItems = 0;

      // --------------------------------------------------
      // DRAWINGS
      // --------------------------------------------------

      try {
        final result = await buildingRef.collection('drawings').count().get();

        drawings = result.count ?? 0;
      } catch (e) {
        debugPrint('Drawing count error: $e');
      }

      // --------------------------------------------------
      // MEASUREMENTS
      // --------------------------------------------------

      try {
        final result =
            await buildingRef.collection('measurements').count().get();

        measurements = result.count ?? 0;
      } catch (e) {
        debugPrint('Measurement count error: $e');
      }

      // --------------------------------------------------
      // BOQ
      // --------------------------------------------------

      try {
        final result = await buildingRef.collection('boq').count().get();

        boqItems = result.count ?? 0;
      } catch (e) {
        debugPrint('BOQ count error: $e');
      }

      // Legacy collection only if required.
      if (boqItems == 0) {
        try {
          final result = await buildingRef.collection('boqItems').count().get();

          boqItems = result.count ?? 0;
        } catch (e) {
          debugPrint('Legacy BOQ count error: $e');
        }
      }

      // --------------------------------------------------
      // NOW OVERRIDE WITH ACTUAL LOADED CACHE
      // IF THE FULL DATASET IS ALREADY AVAILABLE.
      // --------------------------------------------------

      final loadedMeasurements = measurementsByBuilding[key];

      if (loadedMeasurements != null) {
        measurements = loadedMeasurements.length;
      }

      final loadedBoq = boqByBuilding[key];

      if (loadedBoq != null) {
        boqItems = loadedBoq.length;
      }

      countsCache[key] = BuildingCounts(
        drawings: drawings,
        measurements: measurements,
        boqItems: boqItems,
      );

      debugPrint(
        '📊 BUILDING COUNTS '
        '$buildingId → '
        'drawings=$drawings '
        'measurements=$measurements '
        'boq=$boqItems',
      );
    } catch (e) {
      debugPrint('❌ loadBuildingCounts error: $e');
    } finally {
      loadingCounts.remove(key);
    }
  }

  // Future<void> loadBuildingCounts(
  //   String projectId,
  //   String buildingId, {
  //   bool forceRefresh = false,
  // }) async {
  //   final key = _countKey(projectId, buildingId);

  //   if (!forceRefresh && countsCache.containsKey(key)) {
  //     return;
  //   }

  //   if (loadingCounts.contains(key)) {
  //     return;
  //   }

  //   loadingCounts.add(key);

  //   try {
  //     final buildingRef = _firestore
  //         .collection('projects')
  //         .doc(projectId)
  //         .collection('buildings')
  //         .doc(buildingId);

  //     int drawings = 0;
  //     int measurements = 0;
  //     int boq = 0;

  //     try {
  //       drawings =
  //           (await buildingRef.collection('drawings').count().get()).count ?? 0;
  //     } catch (_) {}

  //     try {
  //       measurements =
  //           (await buildingRef.collection('measurements').count().get())
  //               .count ??
  //           0;
  //     } catch (_) {}

  //     try {
  //       boq = (await buildingRef.collection('boq').count().get()).count ?? 0;
  //     } catch (_) {}

  //     if (boq == 0) {
  //       try {
  //         boq =
  //             (await buildingRef.collection('boqItems').count().get()).count ??
  //             0;
  //       } catch (_) {}
  //     }

  //     countsCache[key] = BuildingCounts(
  //       drawings: drawings,
  //       measurements: measurements,
  //       boqItems: boq,
  //     );
  //   } finally {
  //     loadingCounts.remove(key);
  //   }
  // }

  Future<BuildingCounts> _computeBuildingCounts(
    String projectId,
    String buildingId,
  ) async {
    final cacheKey = '$projectId::$buildingId';

    try {
      final buildingRef = _firestore
          .collection('projects')
          .doc(projectId)
          .collection('buildings')
          .doc(buildingId);

      int drawings = 0;
      int measurements = 0;
      int boq = 0;

      try {
        drawings =
            (await buildingRef.collection('drawings').count().get()).count ?? 0;
      } catch (_) {}

      try {
        measurements =
            (await buildingRef.collection('measurements').count().get())
                .count ??
            0;
      } catch (_) {}

      try {
        boq = (await buildingRef.collection('boq').count().get()).count ?? 0;
      } catch (_) {}

      if (boq == 0) {
        try {
          boq =
              (await buildingRef.collection('boqItems').count().get()).count ??
              0;
        } catch (_) {}
      }

      final result = BuildingCounts(
        drawings: drawings,
        measurements: measurements,
        boqItems: boq,
      );

      countsCache[cacheKey] = result;

      return result;
    } finally {
      _countsInFlight.remove(cacheKey);
    }
  }

  Future<BuildingRowFs> addBuilding({
    required String projectId,
    required String code,
    required String name,
    String siteId = '',
    String siteName = '',
  }) async {
    final ref =
        _firestore
            .collection('projects')
            .doc(projectId)
            .collection('buildings')
            .doc();

    await ref.set({
      'code': code,
      'name': name,
      'siteId': siteId,
      'siteName': siteName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final row = BuildingRowFs(
      id: ref.id,
      code: code,
      name: name,
      siteId: siteId,
      siteName: siteName,
      createdAt: Timestamp.now(),
    );

    final current = List<BuildingRowFs>.from(buildingsFor(projectId));

    current.insert(0, row);

    buildingsByProject[projectId] = current;

    return row;
  }

  Future<void> updateBuilding({
    required String projectId,
    required BuildingRowFs building,
    required String name,
    required String code,
  }) async {
    await _firestore
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(building.id)
        .update({
          'name': name,
          'code': code,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    final current = List<BuildingRowFs>.from(buildingsFor(projectId));

    final index = current.indexWhere((item) => item.id == building.id);

    if (index != -1) {
      current[index] = BuildingRowFs(
        id: building.id,
        code: code,
        name: name,
        siteId: building.siteId,
        siteName: building.siteName,

        // Preserve the original creation date.
        createdAt: building.createdAt,
      );

      buildingsByProject[projectId] = current;
    }
  }

  Future<void> deleteBuilding({
    required String projectId,
    required BuildingRowFs building,
  }) async {
    await _firestore
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(building.id)
        .update({
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

    final current = List<BuildingRowFs>.from(buildingsFor(projectId))
      ..removeWhere((item) => item.id == building.id);
    buildingsByProject[projectId] = current;

    final key = buildingKey(projectId, building.id);
    countsCache.remove(key);
    loadingCounts.remove(key);
    measurementsByBuilding.remove(key);
    boqByBuilding.remove(key);
    loadingMeasurements.remove(key);
    loadingBoq.remove(key);
    measurementErrors.remove(key);
    boqErrors.remove(key);
    financialSummaryCache.remove(key);
    loadingFinancialSummaries.remove(key);
  }

  void invalidateBuildingCounts(String projectId, String buildingId) {
    countsCache.remove('$projectId::$buildingId');
  }

  void clearProject(String projectId) {
    buildingsByProject.remove(projectId);
    loadingByProject.remove(projectId);
    errorByProject.remove(projectId);

    final prefix = '$projectId::';

    countsCache.removeWhere((key, value) => key.startsWith(prefix));
    financialSummaryCache.removeWhere((key, value) => key.startsWith(prefix));
  }

  void clearAll() {
    buildingsByProject.clear();
    loadingByProject.clear();
    errorByProject.clear();
    countsCache.clear();
    financialSummaryCache.clear();
    loadingFinancialSummaries.clear();
    _countsInFlight.clear();
  }
}
