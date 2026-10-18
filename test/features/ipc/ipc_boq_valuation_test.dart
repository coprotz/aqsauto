import 'package:aqs/features/ipc/ipc_boq_valuation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('measurements replace stored quantities and override wins', () {
    final result = ipcBoqQuantities({'a': {'boqCode': '1', 'quantity': 1}, 'b': {'boqCode': '2', 'qtyOverride': 7, 'quantity': 1}}, [{'boqItemId': 'a', 'value': 20}, {'boqItemId': 'a', 'value': 5}, {'boqItemId': 'b', 'value': 40}]);
    expect(result['a'], 25);
    expect(result['b'], 7);
  });
  test('unique code fallback and headings', () {
    final result = ipcBoqQuantities({'a': {'boqCode': 'A'}, 'b': {'boqCode': 'B'}, 'h': {'rowType': 'heading'}}, [{'boqCode': 'a', 'value': 9}]);
    expect(result['a'], 9);
    expect(result['b'], 0);
    expect(result.containsKey('h'), false);
  });
  test('duplicate leaf codes are not assigned ambiguously', () {
    final result = ipcBoqQuantities({'a': {'boqCode': 'A'}, 'b': {'boqCode': 'A'}}, [{'boqCode': 'A', 'value': 99}]);
    expect(result.values, everyElement(0));
  });
}
