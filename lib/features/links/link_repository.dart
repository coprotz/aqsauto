import 'package:aqs/features/links/links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'link_models.dart';

class LinkRepository {
  const LinkRepository();

  String _sourceMode(QtySourceDoc source) =>
      source.sourceKind == QtySourceMode.measured ? 'doc' : 'boq';

  String _sourceId(QtySourceDoc source) =>
      source.sourceKind == QtySourceMode.measured
          ? (source.docId ?? '').trim()
          : (source.boqItemId ?? '').trim();

  Map<String, dynamic> _sourceFields(QtySourceDoc source) {
    final mode = _sourceMode(source);
    final sourceId = _sourceId(source);
    if (sourceId.isEmpty) {
      throw StateError('The selected link source has no document identifier.');
    }

    return {
      'derivedFromMode': mode,
      'derivedFromDocId': mode == 'doc' ? sourceId : null,
      'derivedFromBoqItemId': mode == 'boq' ? sourceId : null,
      'sourceBoqItemId': sourceId,
      'sourceBoqCode': source.boqCode,
      'sourceBoqDescription': source.boqDescription,
      'sourceUnit': source.unit,
      'sourceValue': source.value,
    };
  }

  Future<void> upsertDerivedLinks({
    required CollectionReference<Map<String, dynamic>> measurementsRef,
    required String projectId,
    required String buildingId,
    required String drawingId,
    required QtySourceDoc source,
    required List<LinkedBoqTarget> targets,
  }) async {
    if (targets.isEmpty) return;

    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();

    for (final t in targets) {
      final derivedValue = (source.value * t.factor) + t.offset;

      final sourceMode = _sourceMode(source);
      final sourceId = _sourceId(source);
      if (sourceId.isEmpty) {
        throw StateError(
          'The selected link source has no document identifier.',
        );
      }

      Query<Map<String, dynamic>> existingQuery = measurementsRef
          .where('drawingId', isEqualTo: drawingId)
          .where('isDerived', isEqualTo: true)
          .where('derivedFromMode', isEqualTo: sourceMode);
      existingQuery =
          sourceMode == 'doc'
              ? existingQuery.where('derivedFromDocId', isEqualTo: sourceId)
              : existingQuery.where(
                'derivedFromBoqItemId',
                isEqualTo: sourceId,
              );
      final qs =
          await existingQuery
              .where(
                'boqItemId',
                isEqualTo: t.boq.id.isNotEmpty ? t.boq.id : t.boq.code,
              )
              .limit(1)
              .get();

      if (qs.docs.isNotEmpty) {
        // update existing
        batch.update(qs.docs.first.reference, {
          ..._sourceFields(source),
          'derivedRule': 'linear',
          'derivedFactor': t.factor,
          'derivedOffset': t.offset,

          'unit': source.unit,
          'value': derivedValue,
          'updatedAt': now,
        });
      } else {
        // create new
        final id = measurementsRef.doc().id;
        batch.set(measurementsRef.doc(id), {
          'projectId': projectId,
          'buildingId': buildingId,
          'drawingId': drawingId,

          'isDerived': true,
          ..._sourceFields(source),
          'derivedRule': 'linear',
          'derivedFactor': t.factor,
          'derivedOffset': t.offset,

          'boqItemId': t.boq.id.isNotEmpty ? t.boq.id : t.boq.code,
          'boqCode': t.boq.code,
          'boqDescription': t.boq.description,

          'unit': source.unit,
          'value': derivedValue,

          'createdAt': now,
          'updatedAt': now,
        });
      }
    }

    await batch.commit();
  }

  Future<void> replaceDerivedSource({
    required DocumentReference<Map<String, dynamic>> derivedRef,
    required QtySourceDoc source,
    required double factor,
    required double offset,
  }) {
    return derivedRef.update({
      ..._sourceFields(source),
      'derivedRule': 'linear',
      'derivedFactor': factor,
      'derivedOffset': offset,
      'unit': source.unit,
      'value': (source.value * factor) + offset,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> replaceDerivedTarget({
    required DocumentReference<Map<String, dynamic>> derivedRef,
    required BoqPick target,
  }) {
    final targetId = target.id.isNotEmpty ? target.id : target.code;
    if (targetId.trim().isEmpty) {
      throw StateError('The selected target BOQ item has no identifier.');
    }
    return derivedRef.update({
      'boqItemId': targetId,
      'boqCode': target.code,
      'boqDescription': target.description,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
