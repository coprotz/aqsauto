import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'ipc_measurement_sheets.dart';
import 'ipc_boq_details_pdf.dart';

/// Percentage points are stored separately from the original BOQ basis.
Map<String, dynamic> ipcDisplayBoq(
  Map<String, dynamic> row,
  Map<String, dynamic> package,
) {
  if (package['executionMode'] != 'percentage') return row;
  double n(dynamic v) => double.tryParse('$v'.replaceAll(',', '')) ?? 0;
  final source = Map<String, dynamic>.from(row['sourceBoq'] ?? {});
  final originalQty = n(
    source['qtyOverride'] ?? source['quantity'] ?? source['qty'],
  );
  final qty = originalQty > 0 ? originalQty : 1.0;
  final amount =
      row['amount'] == null ? n(row['rate']) * 100 : n(row['amount']);
  return {
    ...row,
    'qtyOverride': qty,
    'quantity': qty,
    'rate': amount / qty,
    'unit': source['unit'] ?? 'Item',
  };
}

/// Execution quantities are separate from the contract BOQ quantity.
bool _isMeasuredSharedTrade(Map<String, dynamic> package) {
  final name = '${package['name'] ?? ''}'.toLowerCase();
  return name.contains('electric') || name.contains('plumbing');
}

/// Existing electricity/plumbing snapshots retain percentage storage for compatibility.
/// The entry form converts to/from the original measurable BOQ quantity.
double ipcEntryQuantityScale(
  Map<String, dynamic> row,
  Map<String, dynamic> package,
) {
  if (package['executionMode'] != 'percentage' ||
      !_isMeasuredSharedTrade(package))
    return 1;
  final source = Map<String, dynamic>.from(row['sourceBoq'] ?? {});
  final qty = double.tryParse(
    '${source['qtyOverride'] ?? source['quantity'] ?? source['qty'] ?? ''}'
        .replaceAll(',', ''),
  );
  return qty != null && qty.isFinite && qty > 0 ? qty / 100 : 1;
}

bool ipcUsesMeasuredEntry(
  Map<String, dynamic> row,
  Map<String, dynamic> package,
) =>
    package['executionMode'] == 'percentage' &&
    _isMeasuredSharedTrade(package) &&
    (double.tryParse(
              '${(row['sourceBoq'] as Map?)?['qtyOverride'] ?? (row['sourceBoq'] as Map?)?['quantity'] ?? (row['sourceBoq'] as Map?)?['qty'] ?? ''}'
                  .replaceAll(',', ''),
            ) ??
            0) >
        0;

/// Execution quantities are separate from the contract BOQ quantity.
/// Legacy building-level percentages are never distributed across items.
List<double?> ipcItemExecution(
  Map<String, dynamic> row,
  Map<String, dynamic> package,
) {
  double? number(dynamic value) =>
      double.tryParse('${value ?? ''}'.replaceAll(',', ''));
  final previous =
      number(row['previousExecutedQuantity']) ??
      (number(package['previousExecutedAmount']) == 0 ||
              package['itemExecutionBaselineZero'] == true
          ? 0.0
          : null);
  final cumulative =
      number(row['cumulativeExecutedQuantity']) ??
      (number(package['executedAmount']) == 0 ||
              package['itemExecutionBaselineZero'] == true
          ? 0.0
          : null);
  return [
    previous,
    previous != null && cumulative != null ? cumulative - previous : null,
    cumulative,
  ];
}

/// Null means at least one item has no execution breakdown; do not understate it.
List<double?> ipcBoqExecutionTotals(
  List<Map<String, dynamic>> rows,
  Map<String, dynamic> package,
) {
  final totals = <double?>[0, 0, 0];
  for (final row in rows) {
    final type = '${row['rowType'] ?? ''}'.trim().toLowerCase();
    if (type.isNotEmpty && type != 'item') continue;
    final rate =
        double.tryParse('${row['rate'] ?? 0}'.replaceAll(',', '')) ?? 0;
    final values = ipcItemExecution(row, package);
    for (var i = 0; i < 3; i++) {
      totals[i] =
          totals[i] == null || values[i] == null
              ? null
              : totals[i]! + values[i]! * rate;
    }
  }
  return totals;
}

class IpcBoqTable extends StatefulWidget {
  const IpcBoqTable({
    super.key,
    required this.rows,
    required this.package,
    this.onExecute,
    this.entries,
    this.ipcNumber = '',
    this.sheetDetails = const {},
    this.onSaveSheetDetails,
  });
  final Stream<List<Map<String, dynamic>>> Function(Map<String, dynamic> row)?
  entries;
  final Future<void> Function(
    Map<String, dynamic> row,
    String rfi,
    String sheet,
    double qty,
  )?
  onExecute;
  final String ipcNumber;
  final Map<String, dynamic> sheetDetails;
  final Future<void> Function(Map<String, dynamic>)? onSaveSheetDetails;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> package;

  @override
  State<IpcBoqTable> createState() => _IpcBoqTableState();
}

class _IpcBoqTableState extends State<IpcBoqTable> {
  bool printingSheets = false;
  bool printingBoqDetails = false;

  Future<void> editSheetDetails() async {
    final keys = [
      'sheetPrefix',
      'preparedBy',
      'preparedDate',
      'verifiedBy',
      'verifiedDate',
    ];
    final controllers = {
      for (final key in keys)
        key: TextEditingController(text: '${widget.sheetDetails[key] ?? ''}'),
    };
    final labels = {
      'sheetPrefix': 'Default measurement sheet prefix',
      'preparedBy': 'Prepared by Quantity Surveyor – name',
      'preparedDate': 'Prepared date (DD/MM/YYYY)',
      'verifiedBy': 'Reviewed / Verified by Resident Engineer – name',
      'verifiedDate': 'Verification date (DD/MM/YYYY)',
    };
    bool busy = false;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (context, update) => AlertDialog(
                    title: const Text('Edit measurement sheet details'),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Details apply to all measurement sheets for this building and IPC. Existing item RFI numbers and sheet numbers remain unchanged.',
                            ),
                            const SizedBox(height: 16),
                            for (final key in keys)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextField(
                                  controller: controllers[key],
                                  decoration: InputDecoration(
                                    labelText: labels[key],
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            busy ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed:
                            busy || widget.onSaveSheetDetails == null
                                ? null
                                : () async {
                                  update(() => busy = true);
                                  try {
                                    await widget.onSaveSheetDetails!({
                                      for (final key in keys)
                                        key: controllers[key]!.text.trim(),
                                    });
                                    if (dialogContext.mounted)
                                      Navigator.pop(dialogContext);
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      update(() => busy = false);
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Could not save: $e'),
                                        ),
                                      );
                                    }
                                  }
                                },
                        child: Text(busy ? 'Saving…' : 'Save details'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      for (final c in controllers.values) {
        c.dispose();
      }
    }
  }

  String search = '';
  int page = 0;
  static const pageSize = 25;
  final horizontal = ScrollController();
  static const navy = Color(0xFF102E68);
  static const widths = <double>[
    110,
    460,
    100,
    110,
    140,
    160,
    110,
    85,
    160,
    110,
    85,
    160,
    110,
    85,
    160,
  ];
  final quantity = NumberFormat('#,##0.###');
  final money = NumberFormat('#,##0.00');

  Widget executionSummary(Map<String, dynamic> row) {
    final measured = ipcUsesMeasuredEntry(row, widget.package);
    final scale = ipcEntryQuantityScale(row, widget.package);
    final values =
        ipcItemExecution(
          row,
          widget.package,
        ).map((v) => v == null ? null : v * scale).toList();
    final basis = measured ? ipcDisplayBoq(row, widget.package) : row;
    final percentage =
        widget.package['executionMode'] == 'percentage' && !measured;
    final total =
        percentage
            ? 100.0
            : double.tryParse(
              '${basis['qtyOverride'] ?? basis['quantity'] ?? basis['qty'] ?? ''}'
                  .replaceAll(',', ''),
            );
    final unit = percentage ? '%' : '${basis['unit'] ?? ''}';
    final remaining =
        total != null && values[2] != null ? total - values[2]! : null;
    final figures = <(String, double?)>[
      (percentage ? 'Total execution basis' : 'Total BOQ quantity', total),
      ('Previously executed', values[0]),
      ('Executed in this IPC', values[1]),
      ('Cumulative executed', values[2]),
      ('Remaining quantity', remaining),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final figure in figures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      figure.$1,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      figure.$2 == null
                          ? 'Not available'
                          : '${quantity.format(figure.$2)} $unit'.trim(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Remaining = total − cumulative execution. Previous execution is not confirmation of payment.',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          if (remaining != null && remaining < 0)
            const Text(
              'Negative remaining quantity indicates execution above the BOQ quantity.',
              style: TextStyle(fontSize: 11, color: Colors.deepOrange),
            ),
        ],
      ),
    );
  }

  Future<void> viewEntries(Map<String, dynamic> row) async {
    final stream =
        widget.entries?.call(row) ?? Stream.value(<Map<String, dynamic>>[]);
    String? error;
    bool busy = false;
    final addNew = await showDialog<bool>(
      context: context,
      builder:
          (dialog) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text('Executed quantities'),
                  content: SizedBox(
                    width: 640,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.package['siteName'] ?? ''} · ${widget.package['name'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${row['displayCode'] ?? row['boqCode'] ?? ''} · ${row['description'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        executionSummary(row),
                        const SizedBox(height: 16),
                        const Text(
                          'Entries recorded in this IPC. Previous IPC quantities remain unchanged.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: StreamBuilder<List<Map<String, dynamic>>>(
                            stream: stream,
                            builder: (context, snapshot) {
                              if (snapshot.hasError)
                                return const Text(
                                  'Could not load entries. Close and retry.',
                                );
                              if (!snapshot.hasData)
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              final entries = snapshot.data!;
                              if (entries.isEmpty)
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No executed quantities added yet.',
                                  ),
                                );
                              return ListView.separated(
                                shrinkWrap: true,
                                itemCount: entries.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  final e = entries[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${quantity.format(number(e['quantity']) * ipcEntryQuantityScale(row, widget.package))} ${ipcUsesMeasuredEntry(row, widget.package) ? ipcDisplayBoq(row, widget.package)['unit'] : row['unit'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: navy,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${e['_pendingSync'] == true ? 'Saved on device · Pending sync\n' : ''}RFI: ${e['rfiNumber'] ?? '—'}\nMeasurement sheet: ${e['measurementSheetNumber'] == '' ? '—' : e['measurementSheetNumber'] ?? '—'}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit entry',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed:
                                              busy
                                                  ? null
                                                  : () => execute(row, e),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete entry',
                                          color: Colors.red,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed:
                                              busy
                                                  ? null
                                                  : () async {
                                                    final confirmed = await showDialog<
                                                      bool
                                                    >(
                                                      context: context,
                                                      builder:
                                                          (c) => AlertDialog(
                                                            title: const Text(
                                                              'Delete executed quantity?',
                                                            ),
                                                            content: const Text(
                                                              'This entry will be removed from this IPC’s cumulative quantity and totals.',
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed:
                                                                    () =>
                                                                        Navigator.pop(
                                                                          c,
                                                                          false,
                                                                        ),
                                                                child:
                                                                    const Text(
                                                                      'Cancel',
                                                                    ),
                                                              ),
                                                              FilledButton(
                                                                onPressed:
                                                                    () =>
                                                                        Navigator.pop(
                                                                          c,
                                                                          true,
                                                                        ),
                                                                child:
                                                                    const Text(
                                                                      'Delete',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                    );
                                                    if (confirmed != true ||
                                                        !context.mounted)
                                                      return;
                                                    update(() {
                                                      busy = true;
                                                      error = null;
                                                    });
                                                    try {
                                                      await widget.onExecute!(
                                                        {
                                                          ...row,
                                                          '_entryId':
                                                              e['_entryId'],
                                                          '_oldEntryQuantity': e['quantity'],
                                                          '_delete': true,
                                                        },
                                                        '${e['rfiNumber'] ?? ''}',
                                                        '${e['measurementSheetNumber'] ?? ''}',
                                                        number(e['quantity']),
                                                      );
                                                    } catch (e) {
                                                      if (context.mounted)
                                                        update(
                                                          () =>
                                                              error =
                                                                  'Could not delete entry. $e',
                                                        );
                                                    } finally {
                                                      if (context.mounted)
                                                        update(
                                                          () => busy = false,
                                                        );
                                                    }
                                                  },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(dialog),
                      child: const Text('Close'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          busy ? null : () => Navigator.pop(dialog, true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add new executed qty'),
                    ),
                  ],
                ),
          ),
    );
    if (addNew == true && mounted) {
      await execute(row);
    }
  }

  Future<void> execute(
    Map<String, dynamic> row, [
    Map<String, dynamic>? entry,
  ]) async {
    final display = ipcDisplayBoq(row, widget.package);
    final measured = ipcUsesMeasuredEntry(row, widget.package);
    final entryScale = ipcEntryQuantityScale(row, widget.package);
    final rfi = TextEditingController(text: entry?['rfiNumber']?.toString()),
        sheet = TextEditingController(
          text: entry?['measurementSheetNumber']?.toString(),
        ),
        qty = TextEditingController(
          text:
              entry == null
                  ? null
                  : '${number(entry['rawQuantity'] ?? entry['quantity']) * entryScale}',
        );
    final factor = TextEditingController(
      text:
          '${entry != null ? entry['factor'] ?? 1 : row['executionFactor'] ?? 1}',
    );
    final form = GlobalKey<FormState>();
    bool correction = number(entry?['quantity']) < 0;
    final reason = TextEditingController(
      text: entry?['correctionReason']?.toString(),
    );
    const reasons = [
      'Measurement correction',
      'Duplicate execution entry',
      'Previously over-certified quantity',
      'Work omitted or cancelled',
      'Rejected or defective work',
      'Revised measurement / remeasurement',
      'Incorrect BOQ item allocation',
      'Percentage execution correction',
      'Other',
    ];
    String? selectedReason =
        reasons.contains(reason.text)
            ? reason.text
            : reason.text.isNotEmpty
            ? 'Other'
            : null;
    bool saving = false;
    String? error;
    InputDecoration field(String label, IconData icon, {String? helper}) =>
        InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          prefixIcon: Icon(icon, size: 20, color: navy),
          filled: true,
          fillColor: const Color(0xFFF8FAFD),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE3EF)),
          ),
        );
    final quantityRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  actionsPadding: const EdgeInsets.all(24),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF0FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.straighten,
                          color: Color(0xFF1557E8),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry == null
                                  ? 'Add executed quantity'
                                  : 'Edit executed quantity',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: navy,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${widget.package['siteName'] ?? 'Site not specified'} · ${widget.package['name'] ?? 'BOQ'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 540,
                    child: Form(
                      key: form,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F5FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFDCE6FA),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BOQ ITEM · ${row['displayCode'] ?? row['boqCode'] ?? '—'}',
                                    style: const TextStyle(
                                      color: Color(0xFF1557E8),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${row['description'] ?? row['billLabel'] ?? ''}',
                                    style: const TextStyle(
                                      color: navy,
                                      fontSize: 15,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 24,
                                    runSpacing: 10,
                                    children: [
                                      Text('Unit: ${display['unit'] ?? '—'}'),
                                      Text(
                                        'BOQ qty: ${quantity.format(number(display['qtyOverride'] ?? display['quantity'] ?? display['qty']))}',
                                      ),
                                      Text(
                                        'Rate: TZS ${money.format(number(display['rate']))}',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: sheet,
                              enabled: !saving,
                              decoration: field(
                                'Measurement sheet number',
                                Icons.description_outlined,
                                helper:
                                    'Optional — leave blank if not available.',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: rfi,
                              enabled: !saving,
                              decoration: field(
                                'RFI number',
                                Icons.assignment_outlined,
                              ),
                              validator:
                                  (v) =>
                                      (v ?? '').trim().isEmpty
                                          ? 'Enter the RFI number.'
                                          : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: qty,
                              onChanged: (_) => update(() {}),
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: field(
                                widget.package['executionMode'] ==
                                            'percentage' &&
                                        !measured
                                    ? 'Executed percentage (%)'
                                    : 'Executed quantity (${display['unit'] ?? ''})',
                                Icons.straighten,
                              ),
                              validator: (v) {
                                final n = double.tryParse(
                                  (v ?? '').replaceAll(',', ''),
                                );
                                return n == null ||
                                        !n.isFinite ||
                                        (correction ? n >= 0 : n <= 0)
                                    ? (correction
                                        ? 'Enter a negative quantity for the correction.'
                                        : 'Enter a quantity greater than zero, or enable correction.')
                                    : null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Deduction / correction'),
                              subtitle: const Text(
                                'Enter a negative quantity or percentage to reverse earlier execution in this IPC.',
                              ),
                              value: correction,
                              onChanged:
                                  saving
                                      ? null
                                      : (value) =>
                                          update(() => correction = value),
                            ),
                            if (correction) ...[
                              DropdownButtonFormField<String>(
                                initialValue: selectedReason,
                                isExpanded: true,
                                decoration: field(
                                  'Correction reason *',
                                  Icons.edit_note,
                                ),
                                items:
                                    reasons
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(r),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    saving
                                        ? null
                                        : (value) => update(() {
                                          selectedReason = value;
                                          reason.text =
                                              value == 'Other'
                                                  ? ''
                                                  : value ?? '';
                                        }),
                                validator:
                                    (value) =>
                                        value == null
                                            ? 'Select a correction reason.'
                                            : null,
                              ),
                              if (selectedReason == 'Other')
                                TextFormField(
                                  controller: reason,
                                  decoration: field(
                                    'Describe the correction *',
                                    Icons.edit_note,
                                  ),
                                  validator:
                                      (value) =>
                                          (value ?? '').trim().isEmpty
                                              ? 'Enter the correction reason.'
                                              : null,
                                ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: factor,
                              enabled: !saving,
                              onChanged: (_) => update(() {}),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: field(
                                'X factor',
                                Icons.close,
                                helper:
                                    'Remembered for this BOQ item in the next IPC. Default: 1.',
                              ),
                              validator: (v) {
                                final f = double.tryParse(
                                  (v ?? '').replaceAll(',', ''),
                                );
                                return f == null ||
                                        !f.isFinite ||
                                        f <= 0 ||
                                        !(number(qty.text) * f).isFinite
                                    ? 'Enter a valid factor greater than zero.'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Final quantity: ${quantity.format(number(qty.text))} × ${quantity.format(number(factor.text))} = ${quantity.format(number(qty.text) * number(factor.text))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: navy,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F8F6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: Color(0xFF087F68),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Added to cumulative work.\nThis IPC = cumulative − previous.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: Color(0xFF087F68),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          saving
                              ? null
                              : () async {
                                if (!form.currentState!.validate()) return;
                                update(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await widget.onExecute!(
                                    {
                                      ...row,
                                      '_rawQuantity':
                                          number(qty.text) / entryScale,
                                      '_factor': number(factor.text),
                                      '_correctionReason':
                                          correction ? reason.text.trim() : '',
                                      if (entry != null)
                                        '_entryId': entry['_entryId'],
                                      if (entry != null)
                                        '_oldEntryQuantity': entry['quantity'],
                                    },
                                    rfi.text.trim(),
                                    sheet.text.trim(),
                                    number(qty.text) *
                                        number(factor.text) /
                                        entryScale,
                                  );
                                  if (dialogContext.mounted)
                                    Navigator.pop(dialogContext);
                                } catch (e) {
                                  if (context.mounted)
                                    update(() {
                                      saving = false;
                                      error = 'Could not save quantity. $e';
                                    });
                                }
                              },
                      child: Text(saving ? 'Saving…' : 'Save quantity'),
                    ),
                  ],
                ),
          ),
    );
    await Navigator.of(context, rootNavigator: true).push(quantityRoute);
    await quantityRoute.completed;
    rfi.dispose();
    sheet.dispose();
    qty.dispose();
    factor.dispose();
    reason.dispose();
  }

  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  double number(dynamic value) =>
      double.tryParse('$value'.replaceAll(',', '')) ?? 0;

  Widget cell(
    String text, {
    bool bold = false,
    bool right = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 13,
        height: 1.45,
        color: color ?? const Color(0xFF344054),
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final totals = ipcBoqExecutionTotals(widget.rows, widget.package);
    final rows =
        widget.rows
            .where(
              (r) =>
                  search.isEmpty ||
                  '${r['boqCode']} ${r['description']} ${r['billLabel']} ${r['unit']}'
                      .toLowerCase()
                      .contains(search),
            )
            .toList();
    final visibleRows = rows.take((page + 1) * pageSize).toList();
    // Both panes use the same table layout so wrapped rows stay aligned.
    Widget buildTable() => SizedBox(
      width: widths.fold<double>(0, (a, b) => a + b),
      child: Column(
        children: [
          Row(
            children: [
              for (final group in [
                ('BOQ', 1080.0),
                ('Previous', 355.0),
                ('This IPC', 355.0),
                ('Cumulative', 355.0),
              ])
                Container(
                  width: group.$2,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: navy,
                    border: Border.all(color: Colors.white24),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    group.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          Table(
            columnWidths: {
              for (var i = 0; i < widths.length; i++)
                i: FixedColumnWidth(widths[i]),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFE4E9F2)),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: navy),
                children: [
                  for (final title in [
                    'BOQ CODE',
                    'DESCRIPTION',
                    'UNIT',
                    'QTY',
                    'RATE',
                    'AMOUNT',
                    'QTY',
                    '%',
                    'AMOUNT',
                    'QTY',
                    '%',
                    'AMOUNT',
                    'QTY',
                    '%',
                    'AMOUNT',
                  ])
                    cell(
                      title,
                      bold: true,
                      color: Colors.white,
                      right: ['QTY', 'RATE', 'AMOUNT', '%'].contains(title),
                    ),
                ],
              ),
              for (final row in visibleRows) _row(row),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFEAF0FF)),
                children: [
                  for (var i = 0; i < 15; i++)
                    cell(
                      i == 1
                          ? 'FULL BOQ TOTAL (TZS)'
                          : [8, 11, 14].contains(i)
                          ? (totals[(i - 8) ~/ 3] == null
                              ? '—'
                              : money.format(totals[(i - 8) ~/ 3]))
                          : '',
                      bold: true,
                      right: i >= 3,
                      color: navy,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Bill of Quantities',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: navy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'IPC snapshot • Amounts in TZS. Percentages are relative to each item’s BOQ quantity.',
        ),
        const SizedBox(height: 8),
        const Text(
          '“—” means an item-level execution breakdown is unavailable. Building-level progress is not allocated to individual items.',
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed:
                  widget.onSaveSheetDetails == null ? null : editSheetDetails,
              icon: const Icon(Icons.edit_note),
              label: const Text('Edit measurement sheet details'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart_outlined),
              label: Text(
                printingBoqDetails
                    ? 'Preparing BOQ Details…'
                    : 'Print BOQ Details (PDF)',
              ),
              onPressed:
                  printingBoqDetails
                      ? null
                      : () async {
                        setState(() => printingBoqDetails = true);
                        try {
                          await IpcBoqDetailsPdf.printBuilding(
                            rows: widget.rows,
                            package: widget.package,
                            ipcNumber: widget.ipcNumber,
                            signatories: widget.sheetDetails,
                          );
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('BOQ Details PDF: $e')),
                            );
                        } finally {
                          if (mounted)
                            setState(() => printingBoqDetails = false);
                        }
                      },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                printingSheets
                    ? 'Preparing measurement sheets…'
                    : 'Print all measurement sheets (PDF)',
              ),
              onPressed:
                  printingSheets || widget.entries == null
                      ? null
                      : () async {
                        setState(() => printingSheets = true);
                        try {
                          await IpcMeasurementSheets.printBuilding(
                            rows: widget.rows,
                            package: widget.package,
                            ipcNumber: widget.ipcNumber,
                            sheetDetails: widget.sheetDetails,
                            loadEntries: (row) => widget.entries!(row).first,
                          );
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Measurement sheet PDF: $e'),
                              ),
                            );
                        } finally {
                          if (mounted) setState(() => printingSheets = false);
                        }
                      },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                constraints: const BoxConstraints(minWidth: 220),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        'Previous total',
                        'This IPC total',
                        'Cumulative total',
                      ][i],
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totals[i] == null
                          ? 'Breakdown unavailable'
                          : 'TZS ${money.format(totals[i])}',
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Totals cover the complete BOQ, including items hidden by search.',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged:
              (v) => setState(() {
                search = v.trim().toLowerCase();
                page = 0;
              }),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search BOQ code, description, heading or unit…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              rows.isEmpty
                  ? '0 rows'
                  : 'Rows 1–${visibleRows.length} of ${rows.length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Scrollbar(
              controller: horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: RepaintBoundary(child: buildTable()),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: widths.first,
              child: AnimatedBuilder(
                animation: horizontal,
                // Build the frozen pane only when BOQ data changes, never on
                // each scroll tick. Isolate its paint from the moving table.
                child: RepaintBoundary(
                  child: ClipRect(
                    key: const ValueKey('fixed-boq-code'),
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: widths.fold<double>(0, (a, b) => a + b),
                      maxWidth: widths.fold<double>(0, (a, b) => a + b),
                      child: buildTable(),
                    ),
                  ),
                ),
                builder: (context, child) {
                  if (!horizontal.hasClients || horizontal.offset <= 0)
                    return const SizedBox.shrink();
                  return child!;
                },
              ),
            ),
          ],
        ),
        if (visibleRows.length < rows.length)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => page += 1),
                icon: const Icon(Icons.expand_more),
                label: const Text('View more items'),
              ),
            ),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching BOQ items.'),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  TableRow _row(Map<String, dynamic> row) {
    final type = '${row['rowType'] ?? ''}'.trim().toLowerCase();
    final heading = type.isNotEmpty && type != 'item';
    final display = ipcDisplayBoq(row, widget.package);
    final qty = number(
      display['qtyOverride'] ?? display['quantity'] ?? display['qty'],
    );
    final rate = number(display['rate']);
    final execution =
        ipcItemExecution(row, widget.package)
            .map(
              (v) =>
                  v == null
                      ? null
                      : widget.package['executionMode'] == 'percentage'
                      ? v * qty / 100
                      : v,
            )
            .toList();
    return TableRow(
      decoration: BoxDecoration(
        color: heading ? const Color(0xFFEEF3FF) : Colors.white,
      ),
      children:
          [
                cell(
                  '${row['displayCode'] ?? row['boqCode'] ?? ''}',
                  bold: true,
                  color: heading ? navy : const Color(0xFF1557E8),
                ),
                cell(
                  '${row['description'] ?? row['billLabel'] ?? ''}',
                  bold: heading,
                  color: heading ? navy : null,
                ),
                cell(heading ? '' : '${display['unit'] ?? ''}'),
                for (final value in [
                  quantity.format(qty),
                  money.format(rate),
                  money.format(qty * rate),
                ])
                  cell(heading ? '' : value, right: true),
                for (final value in execution) ...[
                  cell(
                    heading
                        ? ''
                        : value == null
                        ? '—'
                        : quantity.format(value),
                    right: true,
                  ),
                  cell(
                    heading
                        ? ''
                        : value == null || qty == 0
                        ? '—'
                        : '${(value / qty * 100).toStringAsFixed(2)}%',
                    right: true,
                  ),
                  cell(
                    heading
                        ? ''
                        : value == null
                        ? '—'
                        : money.format(value * rate),
                    right: true,
                    bold: true,
                  ),
                ],
              ]
              .map(
                (child) =>
                    heading || widget.onExecute == null
                        ? child
                        : TableRowInkWell(
                          onTap: () => viewEntries(row),
                          child: child,
                        ),
              )
              .toList(),
    );
  }
}
