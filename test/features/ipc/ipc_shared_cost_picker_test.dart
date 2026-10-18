import 'package:aqs/features/ipc/ipc_shared_cost_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared BOQ preserves full value and source with percentage execution', () {
    final row = sharedCostIpcRow({'code': 'A', 'quantity': 4, 'rate': 500, 'amount': 2000, 'sortOrder': 3});
    expect(row['quantity'], 100);
    expect(row['rate'], 20);
    expect(row['amount'], 2000);
    expect(row['order'], 3);
    expect(row['boqCode'], 'A');
    expect((row['sourceBoq'] as Map)['quantity'], 4);
    expect(row['cumulativeExecutedQuantity'], 0);
  });
  test('headings remain headings and invalid amounts are rejected', () {
    expect(sharedCostIpcRow({'rowType': 'heading', 'description': 'Section'})['rowType'], 'heading');
    expect(() => sharedCostIpcRow({'amount': -1}), throwsStateError);
  });
}
