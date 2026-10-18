import 'dart:async';
import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'ipc_loading_overlay.dart';
import 'ipc_summary_model.dart';
import 'ipc_summary_export.dart';

class IpcSummaryPage extends StatefulWidget {
  const IpcSummaryPage({super.key, required this.certificate});
  final DocumentReference<Map<String, dynamic>> certificate;
  @override
  State<IpcSummaryPage> createState() => _IpcSummaryPageState();
}

class _IpcSummaryPageState extends State<IpcSummaryPage> {
  final subscriptions = <StreamSubscription>[];
  Map<String, dynamic>? certificate, project;
  List<Map<String, dynamic>>? history;
  String? error;
  bool downloading = false;
  @override
  void initState() {
    super.initState();
    void failed(Object _) {
      if (mounted)
        setState(
          () =>
              error =
                  'Could not load the summary. Please reopen this page to retry.',
        );
    }

    subscriptions.add(
      widget.certificate.stateSnapshots().listen((s) {
        if (mounted)
          setState(() {
            certificate = s.data();
            if (certificate == null || certificate!['isDeleted'] == true)
              error = 'This IPC is no longer available.';
          });
      }, onError: failed),
    );
    subscriptions.add(
      widget.certificate.parent.parent!.stateSnapshots().listen((s) {
        if (mounted) setState(() => project = s.data() ?? {});
      }, onError: failed),
    );
    subscriptions.add(
      widget.certificate.parent.stateSnapshots().listen((s) {
        if (mounted)
          setState(() => history = s.docs.map((d) => d.data()).toList());
      }, onError: failed),
    );
  }

  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  String date(dynamic value) =>
      value is Timestamp
          ? DateFormat('dd MMM yyyy').format(value.toDate())
          : 'Not recorded';
  String detail(String key) =>
      '${certificate?[key] ?? project?[key] ?? 'Not recorded'}';

  @override
  Widget build(BuildContext context) {
    final ready =
        certificate != null &&
        project != null &&
        history != null &&
        error == null;
    final title =
        'INTERIM PAYMENT CERTIFICATE NO. ${certificate?['number'] ?? ''}';
    final details = <String, String>{
      'Project': '${project?['name'] ?? 'Not recorded'}',
      'Contract number': detail('contractNumber'),
      'Contract sum (TZS)':
          summaryNumber(certificate?['contractValue']) == null
              ? 'Not recorded'
              : NumberFormat(
                '#,##0.00',
              ).format(summaryNumber(certificate?['contractValue'])),
      'Period':
          '${date(certificate?['periodFrom'])} - ${date(certificate?['periodTo'])}',
      'Submission date': date(
        certificate?['submissionDate'] ?? certificate?['submittedAt'],
      ),
      'Status': '${certificate?['status'] ?? ''}',
      'Employer': detail('employer'),
      'Contractor': detail('contractorName'),
      'Project manager': detail('projectManager'),
      'Financier': detail('financier'),
    };
    final rows =
        ready ? ipcSummaryRows(certificate!, history!) : <IpcSummaryRow>[];
    return Scaffold(
      appBar: AppBar(title: const Text('IPC payment summary')),
      backgroundColor: const Color(0xFFF6F8FC),
      body: IpcLoadingOverlay(
        loading: !ready && error == null,
        child:
            error != null
                ? Center(child: Text(error!))
                : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          downloading ? 'Preparing Excel…' : 'Download Excel',
                        ),
                        onPressed:
                            !ready || downloading
                                ? null
                                : () async {
                                  setState(() => downloading = true);
                                  try {
                                    final bytes = ipcSummaryExcel(
                                      title,
                                      details,
                                      rows,
                                    );
                                    await FileSaver.instance.saveFile(
                                      name:
                                          'IPC_${certificate!['number']}_Summary'
                                              .replaceAll(
                                                RegExp(r'[^a-zA-Z0-9_-]'),
                                                '_',
                                              ),
                                      bytes: bytes,
                                      fileExtension: 'xlsx',
                                      mimeType: MimeType.microsoftExcel,
                                    );
                                  } catch (_) {
                                    if (context.mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Excel download failed. Please try again.',
                                          ),
                                        ),
                                      );
                                  } finally {
                                    if (mounted)
                                      setState(() => downloading = false);
                                  }
                                },
                      ),
                    ),
                    const SizedBox(height: 20),
                    IpcSummaryDocument(
                      title: title,
                      details: details,
                      rows: rows,
                    ),
                  ],
                ),
      ),
    );
  }
}

class IpcSummaryDocument extends StatelessWidget {
  const IpcSummaryDocument({
    super.key,
    required this.title,
    required this.details,
    required this.rows,
    this.headers,
    this.percentLast = false,
    this.percentValueIndexes = const {},
    this.groupedExecuted = false,
  });
  final String title;
  final Map<String, String> details;
  final List<IpcSummaryRow> rows;
  final List<String>? headers;
  final bool percentLast;
  final Set<int> percentValueIndexes;
  final bool groupedExecuted;

  @override
  Widget build(BuildContext context) {
    final resolvedHeaders = headers ?? const [
      'Ref',
      'Description',
      'Previous (TZS)',
      'This IPC (TZS)',
      'Cumulative (TZS)',
    ];
    final columnCount = resolvedHeaders.length;
    final widths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(50),
      1: const FlexColumnWidth(2.2),
      for (var i = 2; i < columnCount; i++) i: const FlexColumnWidth(),
    };

    bool isPercent(int valueIndex, int valueCount) =>
        percentValueIndexes.contains(valueIndex) ||
        (percentLast && valueIndex == valueCount - 1);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1250),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFBCCADD)),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFEAF3E5),
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Text(
                      details['Project'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF173565),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    for (final entry in details.entries.where(
                      (e) => e.key != 'Project',
                    ))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: Text(
                                entry.value,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final minimumWidth = groupedExecuted ? 1650.0 : 1050.0;
                  final tableWidth = constraints.maxWidth < minimumWidth
                      ? minimumWidth
                      : constraints.maxWidth;
                  return Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          children: [
                            if (groupedExecuted)
                              const _ExecutedGroupedHeader(),
                            Table(
                              columnWidths: widths,
                              border: const TableBorder(
                                horizontalInside: BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: [
                                if (!groupedExecuted)
                                  TableRow(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF173565),
                                    ),
                                    children: [
                                      for (final text in resolvedHeaders)
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            text,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                for (final row in rows)
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: row.total
                                          ? const Color(0xFFEAF3E5)
                                          : row.section
                                          ? const Color(0xFFF0F4FA)
                                          : Colors.white,
                                    ),
                                    children: [
                                      for (var i = 0; i < columnCount; i++)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                          child: Text(
                                            i == 0
                                                ? row.code
                                                : i == 1
                                                ? row.label
                                                : row.section
                                                ? ''
                                                : row.values[i - 2] == null
                                                ? 'Not available'
                                                : isPercent(
                                                    i - 2,
                                                    row.values.length,
                                                  )
                                                ? '${NumberFormat('0.00').format(row.values[i - 2])}%'
                                                : NumberFormat(
                                                    '#,##0.00',
                                                  ).format(row.values[i - 2]),
                                            textAlign: i >= 2
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            style: TextStyle(
                                              fontWeight:
                                                  row.total || row.section
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: const Color(0xFF173565),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VAT and retention releases are not included: these adjustments are not configured in the IPC calculation.',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Previous and cumulative columns show valuations, not confirmation of amounts certified or paid.',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                    SizedBox(height: 30),
                    Wrap(
                      spacing: 48,
                      runSpacing: 24,
                      children: [
                        Text('Prepared by: ____________________'),
                        Text('Checked by: ____________________'),
                      ],
                    ),
                    SizedBox(height: 26),
                    Text(
                      'Signature: ____________________    Date: ____________________',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExecutedGroupedHeader extends StatelessWidget {
  const _ExecutedGroupedHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 106,
    color: const Color(0xFF173565),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: 50, child: _SummaryHeaderCell('Ref')),
        const Expanded(
          flex: 22,
          child: _SummaryHeaderCell('Site / building or shared cost'),
        ),
        const Expanded(
          flex: 10,
          child: _SummaryHeaderCell('Revised contract BOQ (TZS)'),
        ),
        Expanded(
          flex: 60,
          child: Column(
            children: [
              const SizedBox(
                height: 38,
                child: _SummaryHeaderCell('EXECUTED', centered: true),
              ),
              Row(
                children: const [
                  Expanded(child: _ExecutedGroupCell('Previous IPC')),
                  Expanded(child: _ExecutedGroupCell('This IPC')),
                  Expanded(child: _ExecutedGroupCell('Cumulative')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExecutedGroupCell extends StatelessWidget {
  const _ExecutedGroupCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 34,
        child: _SummaryHeaderCell(label, centered: true),
      ),
      const Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: _SummaryHeaderCell('Amount (TZS)', centered: true),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 34,
              child: _SummaryHeaderCell('%', centered: true),
            ),
          ),
        ],
      ),
    ],
  );
}

class _SummaryHeaderCell extends StatelessWidget {
  const _SummaryHeaderCell(this.text, {this.centered = false});
  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: double.infinity,
    alignment: centered ? Alignment.center : Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white24, width: 0.5),
    ),
    child: Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
}
