import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/features/takeoff/models/takeoff_measurement.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TakeOffMeasurementService {
  TakeOffMeasurementService._();

  static final TakeOffMeasurementService instance =
      TakeOffMeasurementService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _measurementsRef({
    required String projectId,
    required String facilityId,
  }) {
    return _firestore
        .collection('projects')
        .doc(projectId)
        .collection('facilities')
        .doc(facilityId)
        .collection('measurements');
  }

  CollectionReference<Map<String, dynamic>> _drawingsRef({
    required String projectId,
    required String facilityId,
  }) {
    return _firestore
        .collection('projects')
        .doc(projectId)
        .collection('facilities')
        .doc(facilityId)
        .collection('drawings');
  }

  Future<String> createLengthMeasurement({
    required String projectId,
    required String facilityId,
    required String drawingId,
    required String bundleId,

    required String category,
    required String subTool,

    required double pointAX,
    required double pointAY,
    required double pointBX,
    required double pointBY,

    required double lengthMeters,
  }) async {
    final ref =
        _measurementsRef(projectId: projectId, facilityId: facilityId).doc();

    await ref.set({
      'id': ref.id,

      'projectId': projectId,

      'facilityId': facilityId,

      'drawingId': drawingId,

      'bundleId': bundleId,

      'category': category,

      'subTool': subTool,

      'measurementType': 'length',

      'points': {
        'a': {'x': pointAX, 'y': pointAY},

        'b': {'x': pointBX, 'y': pointBY},
      },

      'quantity': lengthMeters,

      'unit': 'm',

      'status': 'active',

      'createdAt': FieldValue.serverTimestamp(),

      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  Future<void> deleteMeasurement({
    required String projectId,
    required String facilityId,
    required String measurementId,
  }) async {
    await _measurementsRef(
      projectId: projectId,
      facilityId: facilityId,
    ).doc(measurementId).update({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<TakeOffMeasurement>> watchDrawingMeasurements({
    required String projectId,
    required String facilityId,
    required String drawingId,
  }) {
    return _measurementsRef(
      projectId: projectId,
      facilityId: facilityId,
    ).where('drawingId', isEqualTo: drawingId).stateSnapshots().map((snapshot) {
      final items =
          snapshot.docs
              .map(TakeOffMeasurement.fromFirestore)
              .where((item) => item.status == 'active')
              .toList();

      items.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        return aDate.compareTo(bDate);
      });

      return items;
    });
  }

  // Future<String> createLengthMeasurement({
  //   required String projectId,
  //   required String facilityId,
  //   required String drawingId,
  //   required String bundleId,
  //   required String category,
  //   required String subTool,

  //   required double pointAX,
  //   required double pointAY,
  //   required double pointBX,
  //   required double pointBY,

  //   required double quantityMeters,
  // }) async {
  //   final ref =
  //       _measurementsRef(projectId: projectId, facilityId: facilityId).doc();

  //   await ref.set({
  //     'id': ref.id,

  //     'projectId': projectId,

  //     'facilityId': facilityId,

  //     'drawingId': drawingId,

  //     'bundleId': bundleId,

  //     'category': category,

  //     'subTool': subTool,

  //     'measurementType': 'length',

  //     'points': {
  //       'a': {'x': pointAX, 'y': pointAY},

  //       'b': {'x': pointBX, 'y': pointBY},
  //     },

  //     'quantity': quantityMeters,

  //     'unit': 'm',

  //     'status': 'active',

  //     'createdAt': FieldValue.serverTimestamp(),

  //     'updatedAt': FieldValue.serverTimestamp(),
  //   });

  //   return ref.id;
  // }
}
