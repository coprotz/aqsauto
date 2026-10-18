import 'dart:async';
import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'ipc_loading_overlay.dart';
import 'ipc_summary_export.dart';
import 'ipc_summary_model.dart';
import 'ipc_summary_page.dart';

class IpcGrossSummaryPage extends StatefulWidget {
  const IpcGrossSummaryPage({super.key, required this.certificate});
  final DocumentReference<Map<String, dynamic>> certificate;
  @override
  State<IpcGrossSummaryPage> createState() => _IpcGrossSummaryPageState();
}

class _IpcGrossSummaryPageState extends State<IpcGrossSummaryPage> {
  final subscriptions = <StreamSubscription>[];
  Map<String, dynamic>? cert, project;
  List<QuerySnapshot<Map<String, dynamic>>>? packages;
  Map<String, Map<String, dynamic>> sites = {}, buildings = {};
  String? error;
  bool downloading = false;
  bool downloadingPdf = false;
  @override
  void initState() {
    super.initState();
    final projectRef = widget.certificate.parent.parent!;
    void add<T>(Stream<T> stream, void Function(T) onData) => subscriptions.add(stream.listen(onData, onError: (_) { if (mounted) setState(() => error = 'Could not load gross-work details.'); }));
    add(widget.certificate.stateSnapshots(), (s) => setState(() => cert = s.data()));
    add(projectRef.stateSnapshots(), (s) => setState(() => project = s.data() ?? {}));
    add(projectRef.collection('sites').stateSnapshots(), (s) => setState(() => sites = {for (final d in s.docs) d.id: d.data()}));
    add(projectRef.collection('buildings').stateSnapshots(), (s) => setState(() => buildings = {for (final d in s.docs) d.id: d.data()}));
    add(widget.certificate.collection('boqs').stateSnapshots(), (s) => _setPackage(0, s));
    add(widget.certificate.collection('externalBoqs').stateSnapshots(), (s) => _setPackage(1, s));
  }
  void _setPackage(int index, QuerySnapshot<Map<String, dynamic>> value) {
    final next = [...?packages];
    while (next.length < 2) { next.add(value); }
    next[index] = value;
    if (mounted) setState(() => packages = next);
  }
  @override
  void dispose() { for (final s in subscriptions) { s.cancel(); } super.dispose(); }
  static const _signatoryRoles = <String, String>{
    'prepared': 'PREPARED BY: QUANTITY SURVEYOR',
    'checked': 'CHECKED AND APPROVED BY: RESIDENT ENGINEER',
  };
  Map<String, dynamic> _signatory(String role) {
    final raw = cert?['grossSummarySignatories'];
    if (raw is Map && raw[role] is Map) {
      return Map<String, dynamic>.from(raw[role] as Map);
    }
    return {};
  }

  Future<void> _editSignatories() async {
    final fields = <String, Map<String, TextEditingController>>{};
    for (final role in _signatoryRoles.keys) {
      final data = _signatory(role);
      fields[role] = {
        for (final key in ['name', 'designation', 'organisation', 'date'])
          key: TextEditingController(text: (data[key] ?? '').toString()),
      };
    }
    var saving = false;
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Edit summary signatories & dates'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('These details appear on the Summary of Works and its professional PDF.'),
                  const SizedBox(height: 14),
                  for (final role in _signatoryRoles.keys) ...[
                    Text(_signatoryRoles[role]!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final field in ['name', 'designation', 'organisation', 'date'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: fields[role]![field],
                          decoration: InputDecoration(
                            labelText: field == 'date' ? 'Date (e.g. 24 Apr 2026)' :
                              field[0].toUpperCase() + field.substring(1),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    final updated = <String, dynamic>{
                      for (final role in _signatoryRoles.keys)
                        role: {
                          for (final key in fields[role]!.keys)
                            key: fields[role]![key]!.text.trim(),
                        },
                    };
                    await widget.certificate.update({'grossSummarySignatories': updated});
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Could not save signatories: $e')));
                      setDialogState(() => saving = false);
                    }
                  }
                },
                child: Text(saving ? 'Saving…' : 'Save details'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final roleFields in fields.values) {
        for (final controller in roleFields.values) { controller.dispose(); }
      }
    }
  }

  Widget _signatoryPreview() => LayoutBuilder(builder: (context, constraints) {
    final narrow = constraints.maxWidth < 700;
    final cards = _signatoryRoles.entries.map((entry) {
      final data = _signatory(entry.key);
      String value(String key) => (data[key] ?? '').toString().trim();
      return Container(
        width: narrow ? double.infinity : (constraints.maxWidth - 12) / 2,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFBCC7D5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.value, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Name: ${value('name').isEmpty ? '________________________' : value('name')}'),
          const SizedBox(height: 7),
          Text('Designation: ${value('designation').isEmpty ? '____________________' : value('designation')}'),
          const SizedBox(height: 7),
          Text('Organisation: ${value('organisation').isEmpty ? '___________________' : value('organisation')}'),
          const SizedBox(height: 32),
          const Text('Signature: __________________________'),
          const SizedBox(height: 14),
          Text('Date: ${value('date').isEmpty ? '________________________' : value('date')}'),
        ]),
      );
    }).toList();
    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  });
  double n(dynamic value) => summaryNumber(value) ?? 0;
  String label(String type, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (type == 'externalBoqs') {
      final siteId = d['siteId']?.toString();
      final siteName = siteId == null ? null : sites[siteId]?['name']?.toString();
      final costName = '${d['name'] ?? 'Shared cost'}';
      return siteName == null
          ? 'Project shared cost · $costName'
          : '$siteName · shared cost · $costName';
    }
    final b = buildings[doc.id] ?? {};
    final siteId = d['siteId'] ?? b['siteId'];
    final site = sites[siteId]?['name'];
    return site == null ? '${d['name'] ?? doc.id}' : '$site · ${d['name'] ?? doc.id}';
  }
  List<IpcSummaryRow> rows() {
    final grouped = <String, List<double>>{};
    final siteGroups = <String, List<IpcSummaryRow>>{};
    for (var index = 0; index < (packages?.length ?? 0); index++) {
      final type = index == 0 ? 'boqs' : 'externalBoqs';
      for (final doc in packages![index].docs) {
        final d = doc.data();
        final key = label(type, doc);
        final item = grouped.putIfAbsent(key, () => [0, 0, 0]);
        item[0] += n(d['contractValue']);
        item[1] += n(d['previousExecutedAmount']);
        item[2] += n(d['executedAmount']);
      }
    }
    for (final entry in grouped.entries) {
      final site = entry.key.split(' · ').first;
      final separator = entry.key.indexOf(' · ');
      final childLabel = separator < 0 ? entry.key : entry.key.substring(separator + 3);
      final contract = entry.value[0];
      final previous = entry.value[1];
      final cumulative = entry.value[2];
      final current = cumulative - previous;
      siteGroups.putIfAbsent(site, () => []).add(
        IpcSummaryRow('', childLabel, [
          contract,
          previous,
          contract == 0 ? 0 : previous / contract * 100,
          cumulative,
          contract == 0 ? 0 : cumulative / contract * 100,
          current,
          contract == 0 ? 0 : current / contract * 100,
        ]),
      );
    }
    final revised = grouped.values.fold<double>(0, (sum, value) => sum + value[0]);
    final previous = grouped.values.fold<double>(0, (sum, value) => sum + value[1]);
    final cumulative = grouped.values.fold<double>(0, (sum, value) => sum + value[2]);
    final current = cumulative - previous;
    final result = <IpcSummaryRow>[
      IpcSummaryRow('T', 'Total gross work', [
        revised,
        previous,
        revised == 0 ? 0 : previous / revised * 100,
        cumulative,
        revised == 0 ? 0 : cumulative / revised * 100,
        current,
        revised == 0 ? 0 : current / revised * 100,
      ], total: true),
    ];
    final sortedSites = siteGroups.keys.toList()..sort();
    for (final site in sortedSites) {
      final children = siteGroups[site]!..sort((a, b) => a.label.compareTo(b.label));
      final siteRevised = children.fold<double>(0, (sum, row) => sum + (row.values[0] ?? 0));
      final sitePrevious = children.fold<double>(0, (sum, row) => sum + (row.values[1] ?? 0));
      final siteCurrent = children.fold<double>(0, (sum, row) => sum + (row.values[5] ?? 0));
      final siteCumulative = children.fold<double>(0, (sum, row) => sum + (row.values[3] ?? 0));
      result.add(IpcSummaryRow('S', site, [
        siteRevised,
        sitePrevious,
        siteRevised == 0 ? 0 : sitePrevious / siteRevised * 100,
        siteCumulative,
        siteRevised == 0 ? 0 : siteCumulative / siteRevised * 100,
        siteCurrent,
        siteRevised == 0 ? 0 : siteCurrent / siteRevised * 100,
      ], total: true));
      result.addAll(children);
    }
    return result;
  }
  // The formal printout deliberately uses currency columns only. Percentages
  // are shown in a separate progress line so that no amount is clipped.
  Future<Uint8List> _professionalPdf(List<IpcSummaryRow> data) async {
    final document = pdf.PdfDocument();
    document.pageSettings.size = pdf.PdfPageSize.a4;
    document.pageSettings.orientation = pdf.PdfPageOrientation.landscape;
    document.pageSettings.margins.all = 29;
    final navy = pdf.PdfColor(25, 50, 89);
    final border = pdf.PdfPen(pdf.PdfColor(145, 156, 172), width: .55);
    final white = pdf.PdfSolidBrush(pdf.PdfColor(255, 255, 255));
    final body = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8);
    final bold = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8, style: pdf.PdfFontStyle.bold);
    final header = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 10, style: pdf.PdfFontStyle.bold);
    final fmt = NumberFormat('#,##0.00');
    final projectData = project ?? {};
    final detail = (String key) => (projectData[key] ?? cert?[key] ?? '').toString();
    final pageWidth = 841.89 - 58;
    const widths = <double>[37, 278, 116, 116, 116, 116];
    late pdf.PdfPage page;
    late pdf.PdfGraphics g;
    var y = 0.0;
    var pageNo = 0;
    void write(String value, double x, double top, double width, double height, {pdf.PdfFont? font, bool right = false, bool center = false, pdf.PdfBrush? brush}) {
      g.drawString(value, font ?? body, brush: brush ?? pdf.PdfSolidBrush(navy), bounds: Rect.fromLTWH(x, top, width, height),
        format: pdf.PdfStringFormat(alignment: right ? pdf.PdfTextAlignment.right : center ? pdf.PdfTextAlignment.center : pdf.PdfTextAlignment.left,
          lineAlignment: pdf.PdfVerticalAlignment.middle));
    }
    void newPage() {
      page = document.pages.add(); g = page.graphics; pageNo++;
      y = 12;
      write('SUMMARY OF WORKS RE-MEASUREMENTS  |  IPC NO. ${cert?['number'] ?? ''}', 0, y, pageWidth, 17, font: header, center: true);
      y += 21;
      g.drawLine(border, Offset(0, y), Offset(pageWidth, y));
      y += 8;
    }
    void cells(List<String> values, {bool emphasized = false, bool site = false, double height = 22.0}) {
      if (y + height > 525) newPage();
      if (emphasized) g.drawRectangle(brush: pdf.PdfSolidBrush(site ? pdf.PdfColor(244, 233, 190) : pdf.PdfColor(232, 240, 251)), bounds: Rect.fromLTWH(0, y, pageWidth, height));
      var x = 0.0;
      for (var i = 0; i < 6; i++) {
        g.drawRectangle(pen: border, bounds: Rect.fromLTWH(x, y, widths[i], height));
        write(values[i], x + 4, y + 1, widths[i] - 8, height - 2, font: emphasized ? bold : body, right: i >= 2);
        x += widths[i];
      }
      y += height;
    }
    newPage();
    // Letterhead details appear on first page only.
    write((projectData['certificateProjectHeading'] ?? projectData['name'] ?? 'PROJECT').toString().toUpperCase(), 0, y, pageWidth, 30, font: header, center: true);
    y += 31;
    write('Employer: ${detail('employer')}', 0, y, 360, 14);
    write('IPC No: ${cert?['number'] ?? ''}', 480, y, 300, 14);
    y += 16;
    write('Consultant: ${detail('projectManager')}', 0, y, 450, 14);
    write('Evaluation date: ${_date(cert?['evaluationDate'])}', 480, y, 300, 14);
    y += 16;
    write('Contractor: ${detail('contractorName')}', 0, y, 450, 14);
    write('IPC period: ${_date(cert?['periodFrom'])} - ${_date(cert?['periodTo'])}', 480, y, 300, 14);
    y += 23;
    cells(['S/N','SITE / BUILDING / SHARED COST','CONTRACT (TZS)','PREVIOUS (TZS)','CUMULATIVE (TZS)','THIS IPC (TZS)'], emphasized: true, height: 32);
    // Display sites and children first, then total as a concluding row.
    for (final row in [...data.where((r) => r.code != 'T'), ...data.where((r) => r.code == 'T')]) {
      final v = row.values;
      String money(int i) => i < v.length && v[i] != null ? fmt.format(v[i]) : '-';
      cells([row.code, row.label, money(0), money(1), money(3), money(5)], emphasized: row.total, site: row.code == 'S', height: row.label.length > 58 ? 30 : 22);
    }
    if (data.isNotEmpty) {
      final v = data.first.values;
      if (y + 65 > 525) newPage();
      y += 6;
      cells(['','OVERALL PROGRESS', '', '${v[2]?.toStringAsFixed(2) ?? '0.00'}%', '${v[4]?.toStringAsFixed(2) ?? '0.00'}%', '${v[6]?.toStringAsFixed(2) ?? '0.00'}%'], emphasized: true);
    }
    // Keep the two signature panels together on the same sheet.
    const signatureHeight = 112.0;
    if (y + signatureHeight + 12 > 525) newPage();
    y += 6;
    final signY = y;
    for (var i = 0; i < 2; i++) {
      final role = i == 0 ? 'prepared' : 'checked';
      final data = _signatory(role);
      String detail(String key) => (data[key] ?? '').toString().trim();
      final x = i * pageWidth / 2;
      final panelWidth = pageWidth / 2;
      g.drawRectangle(pen: border, bounds: Rect.fromLTWH(x, signY, panelWidth, signatureHeight));
      write(_signatoryRoles[role]!, x + 8, signY + 5, panelWidth - 16, 13, font: bold);
      write('Name: ${detail('name')}', x + 8, signY + 23, panelWidth - 16, 13);
      write('Designation: ${detail('designation')}', x + 8, signY + 40, panelWidth - 16, 13);
      write('Organisation: ${detail('organisation')}', x + 8, signY + 57, panelWidth - 16, 13);
      write('Signature: ______________________________', x + 8, signY + 77, panelWidth - 16, 13);
      write('Date: ${detail('date')}', x + 8, signY + 95, panelWidth - 16, 13);
    }
    final bytes = Uint8List.fromList(await document.save());
    document.dispose();
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final ready = cert != null && project != null && packages?.length == 2 && error == null;
    final detail = <String, String>{
      'Project': '${project?['name'] ?? 'Not recorded'}',
      'Employer': '${project?['employer'] ?? 'Not recorded'}',
      'Consultant': '${project?['projectManager'] ?? 'Not recorded'}',
      'Contractor': '${project?['contractorName'] ?? 'Not recorded'}',
      'IPC': '${cert?['number'] ?? ''}',
      'Period': '${_date(cert?['periodFrom'])} - ${_date(cert?['periodTo'])}',
      'Status': '${cert?['status'] ?? ''}',
    };
    final summaryRows = ready ? rows() : <IpcSummaryRow>[];
    const headers = ['Ref','Site / building or shared cost','Revised contract BOQ (TZS)',
      'Previous amount (TZS)','Previous %','Cumulative amount (TZS)','Cumulative %',
      'This IPC amount (TZS)','This IPC %'];
    const percentColumns = {2,4,6};
    return Scaffold(
      appBar: AppBar(title: const Text('Summary of works re-measurements')),
      backgroundColor: const Color(0xFFF6F8FC),
      body: IpcLoadingOverlay(loading: !ready && error == null,
        child: error != null ? Center(child: Text(error!)) : ListView(
          padding: const EdgeInsets.all(24), children: [
            Align(alignment: Alignment.centerRight, child: Wrap(spacing: 12, runSpacing: 10, children: [
              OutlinedButton.icon(icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Edit signatories & dates'),
                onPressed: !ready ? null : _editSignatories),
              OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(downloadingPdf ? 'Preparing PDF…' : 'Download professional PDF'),
                onPressed: !ready || downloadingPdf ? null : () async {
                  setState(() => downloadingPdf = true);
                  try {
                    final bytes = await _professionalPdf(summaryRows);
                    await FileSaver.instance.saveFile(name: 'IPC_${cert!['number']}_Summary_of_Works', bytes: bytes,
                      fileExtension: 'pdf', mimeType: MimeType.pdf);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
                  } finally { if (mounted) setState(() => downloadingPdf = false); }
                }),
              FilledButton.icon(icon: const Icon(Icons.download_outlined),
                label: Text(downloading ? 'Preparing Excel…' : 'Download Excel'),
                onPressed: !ready || downloading ? null : () async {
                  setState(() => downloading = true);
                  try {
                    await FileSaver.instance.saveFile(name: 'IPC_${cert!['number']}_Gross_Work',
                      bytes: ipcSummaryExcel('SUMMARY OF WORKS RE-MEASUREMENTS - IPC ${cert!['number']}',
                        detail, summaryRows, headers: headers, percentValueIndexes: percentColumns, groupedExecuted: true),
                      fileExtension: 'xlsx', mimeType: MimeType.microsoftExcel);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
                  } finally { if (mounted) setState(() => downloading = false); }
                }),
            ])),
            const SizedBox(height: 20),
            IpcSummaryDocument(title: 'SUMMARY OF WORKS RE-MEASUREMENTS - IPC ${cert?['number'] ?? ''}',
              details: detail, rows: summaryRows, headers: headers,
              percentValueIndexes: percentColumns, groupedExecuted: true),
            const SizedBox(height: 22),
            if (ready) _signatoryPreview(),
          ])),
    );
  }
  String _date(dynamic value) => value is Timestamp ? DateFormat('dd MMM yyyy').format(value.toDate()) : 'Not recorded';
}
