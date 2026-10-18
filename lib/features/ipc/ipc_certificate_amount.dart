import 'ipc_summary_model.dart';

/// Certified history is authoritative unless an explicit, editable schedule
/// has been saved for the current certificate. Never infer Item 7 from the
/// legacy `thisIpcValue`: that field may be stale after BOQ reconciliation.
double? ipcPreviouslyCertified(
  Map<String, dynamic> ipc,
  List<Map<String, dynamic>> history,
) {
  final schedule = ipc['previousCertifiedSchedule'];
  if (schedule is List) {
    if (schedule.isEmpty) return 0.0;
    var totalCents = 0;
    for (final item in schedule) {
      if (item is! Map) return null;
      final amount = summaryNumber(item['amount']);
      if (amount == null || amount < 0) return null;
      totalCents += (amount * 100).round();
    }
    return totalCents / 100.0;
  }

  final manuallySaved = summaryNumber(ipc['previouslyCertifiedAmount']) ??
      summaryNumber(ipc['previousCertifiedAmount']);
  if (manuallySaved != null && manuallySaved >= 0) {
    return (manuallySaved * 100).round() / 100.0;
  }

  final currentNumber = summaryNumber(ipc['number']);
  if (currentNumber == null) return null;
  var sumCents = 0;
  var found = false;
  for (final previous in history) {
    if (previous['isDeleted'] == true) continue;
    final number = summaryNumber(previous['number']);
    if (number == null || number >= currentNumber) continue;
    final status = '${previous['status']}'.toLowerCase();
    if (!const {
      'submitted', 'reviewed', 'certified', 'sent_to_employer', 'paid',
    }.contains(status)) continue;
    final amount = summaryNumber(previous['amountCertified']);
    if (amount == null || amount <= 0) continue;
    sumCents += (amount * 100).round();
    found = true;
  }
  if (found) return sumCents / 100.0;
  return currentNumber == 1 ? 0.0 : null;
}

/// Same calculation for certificate, summary card, and history.
double? ipcCertificatePayable(
  Map<String, dynamic> ipc,
  List<Map<String, dynamic>> history,
) {
  final rows = ipcSummaryRows(ipc, history);
  double? cumulative;
  for (final row in rows) {
    if (row.code == 'C' && row.values.length > 2) {
      cumulative = row.values[2];
      break;
    }
  }
  final previous = ipcPreviouslyCertified(ipc, history);
  if (cumulative == null || previous == null) return null;
  return ((cumulative * 100).round() - (previous * 100).round()) / 100.0;
}
