class IpcSummaryRow {
  const IpcSummaryRow(
    this.code,
    this.label,
    this.values, {
    this.total = false,
    this.section = false,
    this.formula,
  });
  final String code, label;
  final List<double?> values; // Previous, this IPC, cumulative.
  final bool total, section;
  final String? formula; // Row-code references, expanded by the Excel exporter.
}

class IpcGrossRow {
  const IpcGrossRow(this.label, this.revisedValue, this.cumulativeValue, this.percent);
  final String label;
  final double revisedValue, cumulativeValue, percent;
}

double? summaryNumber(dynamic value) {
  final n = double.tryParse('$value'.replaceAll(',', ''));
  return n != null && n.isFinite ? n : null;
}

List<IpcSummaryRow> ipcSummaryRows(
  Map<String, dynamic> data,
  List<Map<String, dynamic>> history,
) {
  final first = summaryNumber(data['number']) == 1;
  final advance = data['ipcType'] == 'advance';
  final gross = summaryNumber(data['grossWorkValue']);
  final previous =
      summaryNumber(data['previousExecutedAmount']) ?? (first ? 0.0 : null);
  final cumulative =
      summaryNumber(data['cumulativeExecutedAmount']) ??
      (previous != null && gross != null ? previous + gross : null);
  List<double?> deduction(String currentKey, String cumulativeKey) {
    final current = summaryNumber(data[currentKey]);
    final total =
        summaryNumber(data[cumulativeKey]) ?? (first ? current : null);
    return [
      total != null && current != null ? total - current : null,
      current,
      total,
    ];
  }

  final earlier = history.where(
    (d) =>
        d['isDeleted'] != true &&
        [
          'submitted',
          'reviewed',
          'certified',
          'sent_to_employer',
          'paid',
        ].contains(d['status']) &&
        (summaryNumber(d['number']) ?? double.infinity) <
            (summaryNumber(data['number']) ?? 0),
  );
  double? previousAdvance = 0;
  for (final d in earlier.where((d) => d['ipcType'] == 'advance')) {
    final amount =
        summaryNumber(d['advanceAmount']) ?? summaryNumber(d['amountApplied']);
    previousAdvance =
        previousAdvance != null && amount != null
            ? previousAdvance + amount
            : null;
  }
  final currentAdvance =
      advance
          ? summaryNumber(data['advanceAmount']) ??
              summaryNumber(data['amountApplied'])
          : 0.0;
  final additions = <double?>[
    previousAdvance,
    currentAdvance,
    previousAdvance != null && currentAdvance != null
        ? previousAdvance + currentAdvance
        : null,
  ];
  // Derive the displayed valuation deductions from the same work amounts
  // shown in the three summary columns. Legacy saved deduction totals can
  // reflect a different previous-work baseline after BOQ adjustments.
  // This is a presentation reconciliation: certified documents are NOT edited.
  final terms = data['terms'] is Map
      ? Map<String, dynamic>.from(data['terms'] as Map)
      : <String, dynamic>{};
  double money(double value) => (value * 100).roundToDouble() / 100;
  List<double?> reconciledDeduction({
    required String currentKey,
    required String totalKey,
    required String percentageKey,
    required double? cap,
  }) {
    final fallback = deduction(currentKey, totalKey);
    // Older IPC documents may have no saved terms. Use the agreed
    // labour-independent IPC deduction defaults for legacy presentation.
    // Explicit contract terms always take precedence.
    final configuredRate = summaryNumber(terms[percentageKey]);
    final percentage = configuredRate ??
        (percentageKey == 'retentionPercent' ? 10.0 : 15.0);
    if (percentage == null || percentage < 0 || percentage > 100 ||
        previous == null || gross == null || cumulative == null ||
        previous < 0 || gross < 0 || cumulative < 0) {
      return fallback;
    }
    double calculated(double work) {
      final amount = money(work * percentage / 100);
      return cap == null ? amount : money(amount.clamp(0.0, cap));
    }
    final prev = advance ? 0.0 : calculated(previous);
    final total = advance ? 0.0 : calculated(cumulative);
    return [prev, money(total - prev), total];
  }
  final contract = summaryNumber(terms['contractPrice']) ??
      summaryNumber(data['contractValue']);
  final retentionLimit = summaryNumber(terms['retentionLimitPercent']);
  final retentionCap = contract != null && retentionLimit != null
      ? money(contract * retentionLimit / 100)
      : null;
  // Only apply an advance cap if an actual advance is recorded. When
  // earlier advance history is missing, never turn recovery into zero.
  final advanceAmount = summaryNumber(data['advanceAmount']);
  final advanceCap = (previousAdvance ?? 0) + (currentAdvance ?? 0) > 0
      ? money((previousAdvance ?? 0) + (currentAdvance ?? 0))
      : (advanceAmount != null && advanceAmount > 0 ? advanceAmount : null);
  final retention = reconciledDeduction(
    currentKey: 'retentionDeduction',
    totalKey: 'retentionHeld',
    percentageKey: 'retentionPercent',
    cap: retentionCap,
  );
  final recovery = reconciledDeduction(
    currentKey: 'advanceRecovery',
    totalKey: 'advancePaymentRecovered',
    percentageKey: 'recoveryPercent',
    cap: advanceCap,
  );
  final work = <double?>[previous, gross, cumulative];
  final deductions = List<double?>.generate(
    3,
    (i) =>
        retention[i] != null && recovery[i] != null
            ? retention[i]! + recovery[i]!
            : null,
  );
  final net = List<double?>.generate(
    3,
    (i) =>
        work[i] != null && additions[i] != null && deductions[i] != null
            ? work[i]! + additions[i]! - deductions[i]!
            : null,
  );
  return [
    IpcSummaryRow('1', 'Value of works executed', work),
    const IpcSummaryRow('', 'Additions to payment', [], section: true),
    IpcSummaryRow('2', 'Advance payment', additions),
    IpcSummaryRow(
      'A',
      'Total additions',
      additions,
      total: true,
      formula: '{2}',
    ),
    const IpcSummaryRow('', 'Deductions from payment', [], section: true),
    IpcSummaryRow('3', 'Retention', retention),
    IpcSummaryRow('4', 'Advance payment recovery', recovery),
    IpcSummaryRow(
      'B',
      'Total deductions',
      deductions,
      total: true,
      formula: '{3}+{4}',
    ),
    IpcSummaryRow(
      'C',
      'Net valuation / This IPC value',
      net,
      total: true,
      formula: '{1}+{A}-{B}',
    ),
  ];
}
