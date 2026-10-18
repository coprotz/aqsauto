import 'package:aqs/features/ipc/ipc_draft_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('contract total reuses patched rows and excludes headings', () {
    final rows = <String, Map<String, dynamic>>{
      'heading': {'rowType': 'heading', 'quantity': 100, 'rate': 100},
      'item': {'quantity': 2, 'rate': 7000},
      'other': {'qtyOverride': 3, 'quantity': 10, 'rate': 1000},
    };
    expect(ipcContractTotal(rows.values), 17000);
    rows['item'] = {...rows['item']!, ...ipcTakeoffPatch({'rate': 9000}, 2)};
    expect(ipcContractTotal(rows.values), 21000);
  });

  test('quota detection distinguishes exhausted quota from other failures', () {
    expect(ipcQuotaExceeded(FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted')), isTrue);
    expect(ipcQuotaExceeded(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), isFalse);
    expect(ipcQuotaExceeded(StateError('other failure')), isFalse);
  });
  test('takeoff sync uses changed rate and recalculates BOQ amount', () {
    final patch = ipcTakeoffPatch({'unit': 'm3', 'rate': 280000}, 7);
    expect(patch['rate'], 280000);
    expect(patch['amount'], 1960000);
    expect(patch['unit'], 'm3');
    expect(patch.containsKey('cumulativeExecutedQuantity'), isFalse);
    expect(patch.containsKey('previousExecutedQuantity'), isFalse);
  });
  test('sync permits draft and submitted only', () {
    for (final status in ['draft', 'submitted']) {
      expect(ipcCanSyncTakeoff({'status': status}), isTrue);
      expect(ipcCanSyncTakeoff({'status': status, 'isDeleted': true}), isFalse);
    }
    for (final status in ['reviewed', 'certified', 'sent_to_employer', 'paid', 'unknown']) {
      expect(ipcCanSyncTakeoff({'status': status}), isFalse);
    }
    expect(ipcCanSyncTakeoff(null), isFalse);
  });
}
