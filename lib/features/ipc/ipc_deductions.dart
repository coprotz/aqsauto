import 'dart:math' as math;

/// Contract-configured deductions on this period's gross work, not on advances.
Map<String, double> calculateIpcDeductions({
  required double gross,
  required double contract,
  required double advancePercent,
  required double recoveryPercent,
  required double retentionPercent,
  required double retentionLimitPercent,
  double recovered = 0,
  double retained = 0,
  bool advance = false,
}) {
  final values = [
    gross,
    contract,
    advancePercent,
    recoveryPercent,
    retentionPercent,
    retentionLimitPercent,
    recovered,
    retained,
  ];
  if (values.any((v) => !v.isFinite || v < 0) ||
      [
        advancePercent,
        recoveryPercent,
        retentionPercent,
        retentionLimitPercent,
      ].any((v) => v > 100) ||
      recoveryPercent + retentionPercent > 100) {
    throw ArgumentError('Invalid contract amounts or deduction percentages.');
  }
  double money(double v) => (v * 100).round() / 100;
  final advanceAmount = money(contract * advancePercent / 100);
  final recovery =
      advance
          ? 0.0
          : money(
            math.min(
              gross * recoveryPercent / 100,
              math.max(0, advanceAmount - recovered),
            ),
          );
  final retention =
      advance
          ? 0.0
          : money(
            math.min(
              gross * retentionPercent / 100,
              math.max(
                0,
                money(contract * retentionLimitPercent / 100) - retained,
              ),
            ),
          );
  final applied = advance ? advanceAmount : money(gross);
  return {
    'grossWorkValue': advance ? 0 : money(gross),
    'advanceAmount': advanceAmount,
    'advanceRecovery': recovery,
    'retentionDeduction': retention,
    'advancePaymentRecovered': money(recovered + recovery),
    'retentionHeld': money(retained + retention),
    'amountApplied': money(applied - recovery - retention),
    'advanceOutstanding': money(
      math.max(0, advanceAmount - recovered - recovery),
    ),
  };
}
