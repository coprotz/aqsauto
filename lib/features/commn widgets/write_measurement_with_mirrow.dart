import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> writeMeasurementWithMirrors({
  required WriteBatch batch,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required String primaryDocId,
  required Map<String, dynamic> primaryData,
  required List<BoqPick> mirrorBoqs, // target BOQs
}) async {
  final primaryRef = measurementsRef.doc(primaryDocId);
  batch.set(primaryRef, primaryData);

  for (final b in mirrorBoqs) {
    final mirrorId = measurementsRef.doc().id;
    final mirrorRef = measurementsRef.doc(mirrorId);

    batch.set(mirrorRef, {
      ...primaryData,

      // override BOQ
      'boqItemId': b.id,
      'boqCode': b.code,
      'boqDescription': b.description,

      // mark as derived/mirrored
      'derivedFromDocId': primaryDocId,
      'derivedRule': 'sameQty',
      'isDerived': true,

      // optional: make it clear in type if you want
      // 'type': '${primaryData['type']}_mirror',
    });
  }
}
