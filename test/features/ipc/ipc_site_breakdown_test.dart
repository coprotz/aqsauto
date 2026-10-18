import 'package:aqs/features/ipc/ipc_site_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allocates by gross share and reconciles rounding', () {
    expect(allocateIpcSites(100, {'Inala': 75, 'CBD': 25}), {'Inala': 75, 'CBD': 25});
    final values = allocateIpcSites(100, {'A': 1, 'B': 1, 'C': 1});
    expect(values.values.fold<double>(0, (a, b) => a + b), closeTo(100, 0.001));
  });
  test('does not invent site allocations with no work', () {
    expect(allocateIpcSites(2500, {'A': 0}), {'Unallocated': 2500});
  });
}
