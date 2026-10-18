import 'package:aqs/features/ipc/ipc_draft_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('take-off description changes and explicit clears propagate', () {
    expect(ipcTakeoffPatch({'description': 'Revised concrete bed'}, 12)['description'], 'Revised concrete bed');
    expect(ipcTakeoffPatch({'description': ''}, 12)['description'], '');
    expect(ipcTakeoffPatch({}, 12).containsKey('description'), isFalse);
    final patch = ipcTakeoffPatch({'description': 'Revised', 'unit': 'm', 'rate': 50}, 12);
    expect(patch['amount'], 600);
    expect(patch.containsKey('previousExecutedQuantity'), isFalse);
    expect(patch.containsKey('cumulativeExecutedQuantity'), isFalse);
  });
  test('description sync remains limited to active draft and submitted IPCs', () {
    for (final status in ['draft', 'submitted']) {
      expect(ipcCanSyncTakeoff({'status': status}), isTrue);
      expect(ipcCanSyncTakeoff({'status': status, 'isDeleted': true}), isFalse);
    }
    for (final status in ['reviewed', 'certified', 'sent_to_employer', 'paid']) {
      expect(ipcCanSyncTakeoff({'status': status}), isFalse);
    }
    expect(ipcCanSyncTakeoff(null), isFalse);
  });
}
