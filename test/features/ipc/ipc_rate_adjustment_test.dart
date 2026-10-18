import 'package:flutter_test/flutter_test.dart';
import 'package:aqs/features/ipc/ipc_rate_adjustment.dart';
import 'package:aqs/features/ipc/ipc_boq_table.dart';

void main() {
  const opening = <String, dynamic>{
    'rate': 25000, 'previousExecutedQuantity': 120,
    'cumulativeExecutedQuantity': 120,
  };
  test('historical 3m stays fixed; 1.8m is included in current IPC', () {
    final row = {...opening, ...ipcRateAdjustment(opening, 40000), 'rate': 40000};
    expect(row['rateAdjustmentAmount'], 1800000);
    expect(ipcItemExecutionAmounts(row, {}), [3000000, 1800000, 4800000]);
    expect(ipcRateAdjustment(row, 40000), ipcRateAdjustment(opening, 40000));
  });
  test('new work and later rate changes retain original opening valuation', () {
    final row = {...opening, ...ipcRateAdjustment(opening, 40000), 'rate': 40000,
      'cumulativeExecutedQuantity': 130};
    expect(ipcItemExecutionAmounts(row, {}), [3000000, 2200000, 5200000]);
    expect(ipcRateAdjustment(row, 30000)['rateAdjustmentAmount'], 600000);
    expect(ipcRateAdjustment(row, 20000)['rateAdjustmentAmount'], -600000);
  });
  test('next IPC carries revised cumulative amount without repeating adjustment', () {
    final row = {...opening, ...ipcRateAdjustment(opening, 40000), 'rate': 40000};
    final next = ipcCarryForwardRow(row);
    expect(next['rateAdjustmentAmount'], 0);
    expect(ipcItemExecutionAmounts(next, {}), [4800000, 0, 4800000]);
  });
}
