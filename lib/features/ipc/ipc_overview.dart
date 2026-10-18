import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ipc_dashboard.dart';
import 'ipc_certificate_amount.dart';

/// Presentation shared by populated and empty dashboards.
class IpcOverview extends StatefulWidget {
  const IpcOverview({
    super.key,
    required this.records,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
    this.onStatus,
    this.onDates,
  });
  final List<Map<String, dynamic>> records;
  final ValueChanged<String> onOpen;
  final ValueChanged<String>? onEdit;
  final ValueChanged<String>? onDelete;
  final ValueChanged<String>? onStatus;
  final ValueChanged<String>? onDates;
  @override
  State<IpcOverview> createState() => _IpcOverviewState();
}

class _IpcOverviewState extends State<IpcOverview> {
  static const navy = Color(0xFF0A153D);
  static const blue = Color(0xFF064EFF);
  static const green = Color(0xFF078450);
  static const muted = Color(0xFF697993);
  String search = '';
  String status = 'all';
  String date(dynamic value) {
    if (value is! Timestamp) return 'Pending';
    final d = value.toDate();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  String thisIpcValue(Map<String, dynamic> row) {
    final computed = ipcCertificatePayable(row, widget.records);
    if (computed != null) return ipcMoney(computed);
    return 'Complete Item 7';
  }

  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE4EAF3)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
  Widget heading(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w800,
      color: navy,
    ),
  );
  Widget badge(String value) {
    final paid = value == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: paid ? const Color(0xFFCEF5DA) : const Color(0xFFFFE5AE),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        value.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: paid ? green : const Color(0xFF704000),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget metric(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(44),
          child: Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(32),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(60),
          child: Text(
            subtitle ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
        ),
      ],
    ),
  );

  Widget latestPanel(Map<String, dynamic> data) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 12,
          children: [
            heading(
              'Latest IPC${data['period'] == null ? '' : ' — ${data['period']}'}',
            ),
            badge('${data['status'] ?? 'No IPC'}'),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 20, color: muted),
            const SizedBox(width: 10),
            Text(
              'Submitted: ${data.isEmpty ? '—' : date(data['submittedAt'])}',
              style: const TextStyle(color: muted),
            ),
          ],
        ),
        const SizedBox(height: 42),
        LayoutBuilder(
          builder: (context, c) {
            final values = [
              ('Amount Applied', ipcMoney(data['amountApplied']), blue),
              ('Amount Certified', ipcMoney(data['amountCertified']), green),
              ('Amount Paid', ipcMoney(data['amountPaid']), navy),
            ];
            final columns =
                c.maxWidth > 680
                    ? 3
                    : c.maxWidth > 380
                    ? 2
                    : 1;
            return Wrap(
              spacing: 16,
              runSpacing: 20,
              children:
                  values
                      .map(
                        (v) => SizedBox(
                          width: (c.maxWidth - 16 * (columns - 1)) / columns,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.$1, style: const TextStyle(color: muted)),
                              const SizedBox(height: 10),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  v.$2,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: v.$3,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
            );
          },
        ),
        const SizedBox(height: 42),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed:
                  data.isEmpty ? null : () => widget.onOpen('${data['id']}'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open IPC'),
            ),
            Tooltip(
              message: 'Payment recording is not available yet',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.credit_card),
                label: const Text('Record Payment'),
              ),
            ),
            Tooltip(
              message: 'IPC PDF export is not available yet',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.download),
                label: const Text('Download PDF'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget progressPanel(Map<String, dynamic> data) {
    const stages = [
      ('created', 'Draft'),
      ('submitted', 'Submitted'),
      ('reviewed', 'Reviewed'),
      ('certified', 'Certified'),
      ('sentToEmployer', 'Sent to Employer'),
      ('paid', 'Paid'),
    ];
    final contract = ipcNumber(data['contractValue']);
    // Explicit cumulative value is preferred; otherwise sum period certificates.
    final cumulative =
        data['cumulativeCertifiedAmount'] == null
            ? widget.records.fold<double>(
              0,
              (total, row) => total + ipcNumber(row['amountCertified']),
            )
            : ipcNumber(data['cumulativeCertifiedAmount']);
    final percent = contract > 0 ? cumulative / contract * 100 : 0.0;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('IPC Progress'),
          const SizedBox(height: 36),
          LayoutBuilder(
            builder:
                (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: c.maxWidth < 620 ? 620 : c.maxWidth,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < stages.length; i++) ...[
                              if (i > 0)
                                Expanded(
                                  child: Container(
                                    height: 3,
                                    color:
                                        data['${stages[i].$1}At'] is Timestamp
                                            ? green
                                            : const Color(0xFFD6DFEC),
                                  ),
                                ),
                              Icon(
                                data['${stages[i].$1}At'] is Timestamp
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 40,
                                color:
                                    data['${stages[i].$1}At'] is Timestamp
                                        ? green
                                        : const Color(0xFFB8C5D8),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final stage in stages)
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      stage.$2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: navy,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      date(data['${stage.$1}At']),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(
              builder:
                  (context, c) => Wrap(
                    spacing: 24,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        width:
                            c.maxWidth > 450
                                ? (c.maxWidth - 24) / 2
                                : c.maxWidth,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_outlined,
                              color: blue,
                              size: 34,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Contract value',
                                    style: TextStyle(color: muted),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    ipcMoney(contract),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: navy,
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width:
                            c.maxWidth > 450
                                ? (c.maxWidth - 24) / 2
                                : c.maxWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cumulative certified',
                              style: TextStyle(color: muted),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.pie_chart, color: blue),
                                const SizedBox(width: 10),
                                Text(
                                  '${percent.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: navy,
                                    fontSize: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: (percent / 100).clamp(0, 1),
                                    color: blue,
                                    backgroundColor: const Color(0xFFDDE6F2),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data =
        widget.records.isEmpty ? <String, dynamic>{} : widget.records.first;
    // Certificate amounts are period values, including advance certificates.
    // Do not add the advance separately or sum cumulative work snapshots.
    final certifiedToDate = widget.records
        .where(
          (row) =>
              row['isDeleted'] != true &&
              const [
                'certified',
                'sent_to_employer',
                'paid',
              ].contains(row['status']),
        )
        .fold<double>(
          0,
          (total, row) => total + ipcNumber(row['amountCertified']),
        );
    final workDone = ipcNumber(data['cumulativeExecutedAmount']);
    final contract = ipcNumber(data['contractValue']);
    final filtered =
        widget.records
            .where(
              (row) =>
                  (status == 'all' || row['status'] == status) &&
                  '${row['number']} ${row['period']}'.toLowerCase().contains(
                    search.toLowerCase(),
                  ),
            )
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final columns =
                c.maxWidth > 1550
                    ? 6
                    : c.maxWidth > 1050
                    ? 4
                    : c.maxWidth > 750
                    ? 3
                    : c.maxWidth > 520
                    ? 2
                    : 1;
            final cards = [
              metric(
                'Latest IPC',
                'IPC No. ${ipcNumber(data['number']).toInt().toString().padLeft(2, '0')}',
                Icons.description_outlined,
                navy,
                subtitle: 'Most recent interim payment certificate',
              ),
              metric(
                'Amount Applied',
                ipcMoney(data['amountApplied']),
                Icons.calculate_outlined,
                blue,
                subtitle: 'Application amount for the latest IPC',
              ),
              metric(
                'Amount certified to date',
                ipcMoney(certifiedToDate),
                Icons.verified_outlined,
                green,
                subtitle: 'Previous + this IPC · including advance payment',
              ),
              metric(
                'Value of work done to date',
                ipcMoney(workDone),
                Icons.construction_outlined,
                green,
                subtitle:
                    contract > 0
                        ? '${(workDone / contract * 100).toStringAsFixed(2)}% of contract sum'
                        : 'Contract sum unavailable · percentage not available',
              ),
              metric(
                'Retention Held',
                ipcMoney(data['retentionHeld']),
                Icons.shield_outlined,
                navy,
                subtitle: 'Retention held as recorded in the latest IPC',
              ),
              metric(
                'Advance payment recovered',
                ipcMoney(data['advancePaymentRecovered']),
                Icons.currency_exchange,
                blue,
                subtitle: 'Advance recovered as recorded in the latest IPC',
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children:
                  cards
                      .map(
                        (card) => SizedBox(
                          width: (c.maxWidth - (columns - 1) * 12) / columns,
                          child: card,
                        ),
                      )
                      .toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder:
              (context, c) =>
                  c.maxWidth > 1100
                      ? Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.intrinsicHeight,
                        columnWidths: const {
                          0: FlexColumnWidth(11),
                          1: FixedColumnWidth(20),
                          2: FlexColumnWidth(10),
                        },
                        children: [
                          TableRow(
                            children: [
                              latestPanel(data),
                              const SizedBox.shrink(),
                              progressPanel(data),
                            ],
                          ),
                        ],
                      )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          latestPanel(data),
                          const SizedBox(height: 20),
                          progressPanel(data),
                        ],
                      ),
        ),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final filters = Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: c.maxWidth < 360 ? c.maxWidth : 320,
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search IPC, period…',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() => search = value),
                        ),
                      ),
                      SizedBox(
                        width: 175,
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items:
                              [
                                    'all',
                                    'draft',
                                    'submitted',
                                    'reviewed',
                                    'certified',
                                    'partially_paid',
                                    'paid',
                                  ]
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s == 'all'
                                            ? 'All Statuses'
                                            : s.replaceAll('_', ' '),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) =>
                                  setState(() => status = value ?? 'all'),
                        ),
                      ),
                    ],
                  );
                  return c.maxWidth > 850
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [heading('IPC History'), filters],
                      )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading('IPC History'),
                          const SizedBox(height: 16),
                          filters,
                        ],
                      );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder:
                    (context, c) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: c.maxWidth),
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFF0F4F9),
                          ),
                          columnSpacing: 24,
                          columns: [
                            for (final label in [
                              'IPC',
                              'Period',
                              'Submitted',
                              'Amount Applied',
                              'This IPC Value',
                              'Amount Certified',
                              'Amount Paid',
                              'Status',
                              'Actions',
                            ])
                              DataColumn(
                                label: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: muted,
                                  ),
                                ),
                              ),
                          ],
                          rows:
                              filtered
                                  .map(
                                    (row) => DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            'IPC No. ${ipcNumber(row['number']).toInt().toString().padLeft(2, '0')}',
                                          ),
                                        ),
                                        DataCell(
                                          Text('${row['period'] ?? '—'}'),
                                        ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(date(row['submittedAt'])),
                                              IconButton(
                                                tooltip:
                                                    'Edit period and submitted date',
                                                icon: const Icon(
                                                  Icons.date_range_outlined,
                                                ),
                                                onPressed:
                                                    widget.onDates == null
                                                        ? null
                                                        : () => widget.onDates!(
                                                          '${row['id']}',
                                                        ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Text(ipcMoney(row['amountApplied'])),
                                        ),
                                        DataCell(Text(thisIpcValue(row))),
                                        DataCell(
                                          Text(
                                            ipcMoney(row['amountCertified']),
                                          ),
                                        ),
                                        DataCell(
                                          Text(ipcMoney(row['amountPaid'])),
                                        ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              badge(
                                                '${row['status'] ?? 'draft'}',
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Change status and action date',
                                                icon: const Icon(
                                                  Icons.edit_calendar_outlined,
                                                ),
                                                onPressed:
                                                    widget.onStatus == null
                                                        ? null
                                                        : () =>
                                                            widget.onStatus!(
                                                              '${row['id']}',
                                                            ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              OutlinedButton(
                                                onPressed:
                                                    () => widget.onOpen(
                                                      '${row['id']}',
                                                    ),
                                                child: const Text('View'),
                                              ),
                                              IconButton(
                                                tooltip: 'Edit IPC',
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  color: blue,
                                                ),
                                                onPressed:
                                                    widget.onEdit == null
                                                        ? null
                                                        : () => widget.onEdit!(
                                                          '${row['id']}',
                                                        ),
                                              ),
                                              IconButton(
                                                tooltip: 'Delete IPC',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                ),
                                                onPressed:
                                                    widget.onDelete == null
                                                        ? null
                                                        : () =>
                                                            widget.onDelete!(
                                                              '${row['id']}',
                                                            ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ),
              ),
              if (widget.records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    'No IPC submitted before.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 17),
                  ),
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching IPCs.', textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
