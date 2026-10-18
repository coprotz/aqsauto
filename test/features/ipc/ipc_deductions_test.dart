import 'package:aqs/features/ipc/ipc_deductions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('negative correction retains prior recovery and retention balances', () {
    final result = calculateIpcDeductions(
      gross: -10000, contract: 1000000, advancePercent: 15,
      recoveryPercent: 10, retentionPercent: 5, retentionLimitPercent: 5,
      recovered: 20000, retained: 10000,
    );
    expect(result['grossWorkValue'], -10000);
    expect(result['amountApplied'], -10000);
    expect(result['advanceRecovery'], 0);
    expect(result['retentionDeduction'], 0);
    expect(result['advancePaymentRecovered'], 20000);
    expect(result['retentionHeld'], 10000);
  });
  Map<String, double> calculate({
    bool advance = false,
    double recovered = 0,
    double retained = 0,
  }) => calculateIpcDeductions(
    gross: 200000,
    contract: 1000000,
    advancePercent: 15,
    recoveryPercent: 10,
    retentionPercent: 5,
    retentionLimitPercent: 5,
    recovered: recovered,
    retained: retained,
    advance: advance,
  );
  test('IPC 1 advance has no deductions and no executed work', () {
    final result = calculate(advance: true);
    expect(result['amountApplied'], 150000);
    expect(result['advanceRecovery'], 0);
    expect(result['retentionDeduction'], 0);
    expect(result['grossWorkValue'], 0);
  });
  test('both deductions use gross current-period work', () {
    final result = calculate();
    expect(result['advanceRecovery'], 20000);
    expect(result['retentionDeduction'], 10000);
    expect(result['amountApplied'], 170000);
  });
  test('caps final recovery and retention instalments', () {
    final result = calculate(recovered: 145000, retained: 47000);
    expect(result['advanceRecovery'], 5000);
    expect(result['retentionDeduction'], 3000);
    expect(result['amountApplied'], 192000);
  });
  test('no deductions after caps are reached', () {
    final result = calculate(recovered: 150000, retained: 50000);
    expect(result['amountApplied'], 200000);
    expect(result['advanceOutstanding'], 0);
  });
}
