import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'ipc_summary_export.dart';
import 'ipc_summary_model.dart';

/// Editable schedule supporting item 7 of an interim payment certificate.
/// Data is attached to THIS certificate, preserving each historical valuation.
class IpcPreviousCertificatesPage extends StatefulWidget {
  const IpcPreviousCertificatesPage({super.key, required this.certificate, required this.projectRef, required this.project, required this.ipc});
  final DocumentReference<Map<String, dynamic>> certificate;
  final DocumentReference<Map<String, dynamic>> projectRef;
  final Map<String, dynamic> project, ipc;
  @override
  State<IpcPreviousCertificatesPage> createState() => _IpcPreviousCertificatesPageState();
}

class _IpcPreviousCertificatesPageState extends State<IpcPreviousCertificatesPage> {
  final money = NumberFormat('#,##0.00');
  final entries = <_CertifiedEntry>[];
  late final TextEditingController consultant, evaluationDate, periodFrom, periodTo;
  Uint8List? logo;
  bool saving = false, exporting = false;
  double get total => entries.fold(0.0, (sum, e) => sum + (summaryNumber(e.amount.text) ?? 0));
  String get heading => '${widget.project['certificateHeading'] ?? widget.project['name'] ?? 'PROJECT'}';
  @override
  void initState() {
    super.initState();
    final data = widget.ipc['previousCertifiedSchedule'];
    if (data is List) {
      for (final v in data) {
        if (v is Map) entries.add(_CertifiedEntry('${v['number'] ?? ''}', '${v['description'] ?? ''}', '${v['amount'] ?? ''}'));
      }
    }
    consultant = TextEditingController(text:'${widget.project['consultantName'] ?? ''}');
    evaluationDate = TextEditingController(text:'${widget.ipc['scheduleEvaluationDate'] ?? ''}');
    periodFrom = TextEditingController(text:'${widget.ipc['schedulePeriodFrom'] ?? ''}');
    periodTo = TextEditingController(text:'${widget.ipc['schedulePeriodTo'] ?? ''}');
    final encoded = widget.project['ipcCertificateLogoBase64'];
    if (encoded is String && encoded.isNotEmpty) { try { logo = base64Decode(encoded); } catch (_) {} }
  }
  @override
  void dispose() {
    for (final e in entries) {e.dispose();}
    consultant.dispose(); evaluationDate.dispose(); periodFrom.dispose(); periodTo.dispose();
    super.dispose();
  }
  Future<void> pickLogo() async {
    final picked = await FilePicker.platform.pickFiles(type:FileType.image, withData:true);
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) return;
    if (bytes.length > 450000) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select a logo smaller than 450 KB.')));
      return;
    }
    setState(() => logo = bytes);
  }
  Future<bool> save() async {
    for (final e in entries) {
      if (e.number.text.trim().isEmpty || e.description.text.trim().isEmpty ||
          summaryNumber(e.amount.text) == null || summaryNumber(e.amount.text)! < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Each row requires IPC number, description and a valid non-negative amount.')));
        return false;
      }
    }
    setState(() => saving = true);
    try {
      final schedule = entries.map((e) => {'number':e.number.text.trim(), 'description':e.description.text.trim(), 'amount':summaryNumber(e.amount.text)!}).toList();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(widget.certificate, {
        'previousCertifiedSchedule':schedule,
        'previouslyCertifiedAmount':double.parse(total.toStringAsFixed(2)),
        'scheduleEvaluationDate':evaluationDate.text.trim(),
        'schedulePeriodFrom':periodFrom.text.trim(),
        'schedulePeriodTo':periodTo.text.trim(),
      }, SetOptions(merge:true));
      batch.set(widget.projectRef, {
        'consultantName':consultant.text.trim(),
        'ipcCertificateLogoBase64':logo == null ? '' : base64Encode(logo!),
      }, SetOptions(merge:true));
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Schedule saved. Certificate item 7 and E updated.')));
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Save failed: $e')));
      return false;
    } finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> export(bool asPdf) async {
    setState(() => exporting = true);
    try {
      final title = 'SCHEDULE OF PREVIOUS CERTIFIED PAYMENTS';
      final info = <String,String>{'Project':heading,'Employer':'${widget.project['employer'] ?? ''}', 'Consultant':consultant.text,
        'Contractor':'${widget.project['contractorName'] ?? ''}', 'IPC No.':'${widget.ipc['number'] ?? ''}',
        'Evaluation date':evaluationDate.text, 'IPC period':'${periodFrom.text} - ${periodTo.text}'};
      final tableRows = [...entries.map((e) => IpcSummaryRow(e.number.text, e.description.text,[summaryNumber(e.amount.text)])), IpcSummaryRow('', 'TOTAL FOR PREVIOUS CERTIFIED PAYMENTS', [total], total:true)];
      final name = 'IPC_${widget.ipc['number'] ?? ''}_Previous_Certified_Payments';
      if (!asPdf) {
        await FileSaver.instance.saveFile(name:name, bytes:ipcSummaryExcel(title,info,tableRows,headers:const ['IPC No.','Description','Amount (TZS)']),fileExtension:'xlsx',mimeType:MimeType.microsoftExcel);
      } else {
        // Formal A4 schedule: fixed table frame, repeatable header and bottom total.
        final doc = pdf.PdfDocument();
        doc.pageSettings.size = pdf.PdfPageSize.a4;
        // All graphic coordinates below are absolute A4 page coordinates.
        // Syncfusion defaults to non-zero page margins, which previously shifted
        // the frame outside the right and bottom edges of the printable page.
        doc.pageSettings.margins.all = 0;
        final regular = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 9);
        final small = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8);
        final bold = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 9, style: pdf.PdfFontStyle.bold);
        final headingFont = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 10, style: pdf.PdfFontStyle.bold);
        final ink = pdf.PdfBrushes.black;
        final rule = pdf.PdfPen(pdf.PdfColor(70, 78, 91), width: 0.7);
        final pale = pdf.PdfSolidBrush(pdf.PdfColor(222, 232, 245));
        const left = 30.0, right = 560.0;
        const frameWidth = right - left;
        const colOne = 108.0, colTwo = 441.0;
        const tableTop = 216.0, headerBottom = 244.0, totalTop = 771.0, totalBottom = 801.0;
        const rowHeight = 29.0;
        // A full page fits seventeen rows; overflow adds pages without clipping.
        const perPage = 17;
        final pageCount = entries.isEmpty ? 1 : (entries.length / perPage).ceil();
        final formattedTotal = money.format(total);
        for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
          final page = doc.pages.add();
          final g = page.graphics;
          void txt(String value, double x, double y, double width, double height,
              {pdf.PdfFont? font, pdf.PdfTextAlignment alignment = pdf.PdfTextAlignment.left}) {
            g.drawString(value, font ?? regular, brush: ink,
              bounds: Rect.fromLTWH(x, y, width, height),
              format: pdf.PdfStringFormat(alignment: alignment,
                lineAlignment: pdf.PdfVerticalAlignment.middle));
          }
          void hline(double y) => g.drawLine(rule, Offset(left, y), Offset(right, y));
          void vline(double x, double startY, double finishY) => g.drawLine(rule, Offset(x, startY), Offset(x, finishY));
          g.drawRectangle(pen: rule, bounds: Rect.fromLTWH(left, 23, frameWidth, totalBottom - 23));
          if (logo != null) {
            try {
              g.drawImage(pdf.PdfBitmap(logo!), Rect.fromLTWH(left + 8, 34, 85, 48));
            } catch (_) {}
          }
          txt(heading.toUpperCase(), 132, 31, 395, 60,
            font: headingFont, alignment: pdf.PdfTextAlignment.center);
          txt('Employer: ${widget.project['employer'] ?? ''}', left + 7, 105, 285, 18, font: small);
          txt('Consultant: ${consultant.text}', left + 7, 124, 285, 18, font: small);
          txt('Contractor: ${widget.project['contractorName'] ?? ''}', left + 7, 143, 290, 30, font: small);
          txt('IPC NO: ${widget.ipc['number'] ?? ''}', 342, 105, 211, 18, font: small);
          txt('EVALUATION DATE: ${evaluationDate.text}', 342, 126, 211, 18, font: small);
          txt('IPC PERIOD: ${periodFrom.text} - ${periodTo.text}', 342, 147, 211, 26, font: small);
          hline(180);
          g.drawRectangle(brush: pale, bounds: Rect.fromLTWH(left + 0.5, 181, frameWidth - 1, 33));
          txt(title, left + 5, 181, frameWidth - 10, 33,
              font: headingFont, alignment: pdf.PdfTextAlignment.center);
          hline(214);
          hline(tableTop);
          hline(headerBottom);
          vline(colOne, tableTop, totalBottom);
          vline(colTwo, tableTop, totalBottom);
          txt('IPC NO.', left + 4, tableTop + 2, colOne - left - 8, 24,
              font: bold, alignment: pdf.PdfTextAlignment.center);
          txt('DESCRIPTION', colOne + 5, tableTop + 2, colTwo - colOne - 10, 24,
              font: bold, alignment: pdf.PdfTextAlignment.center);
          txt('AMOUNT (TZS)', colTwo + 4, tableTop + 2, right - colTwo - 8, 24,
              font: bold, alignment: pdf.PdfTextAlignment.center);
          final begin = pageIndex * perPage;
          final finish = (begin + perPage < entries.length) ? begin + perPage : entries.length;
          for (var i = begin; i < finish; i++) {
            final rowY = headerBottom + 9 + (i - begin) * rowHeight;
            final e = entries[i];
            txt(e.number.text, left + 6, rowY, colOne - left - 12, 24,
              alignment: pdf.PdfTextAlignment.center);
            txt(e.description.text, colOne + 7, rowY - 2,
              colTwo - colOne - 14, 30, font: small);
            txt(money.format(summaryNumber(e.amount.text) ?? 0), colTwo + 5, rowY,
              right - colTwo - 12, 24, alignment: pdf.PdfTextAlignment.right);
          }
          hline(totalTop);
          hline(totalBottom);
          if (pageIndex == pageCount - 1) {
            txt('TOTAL FOR PREVIOUS CERTIFIED PAYMENTS', colOne + 7, totalTop + 2,
              colTwo - colOne - 12, 26, font: bold);
            txt(formattedTotal, colTwo + 5, totalTop + 2,
              right - colTwo - 12, 26, font: bold,
              alignment: pdf.PdfTextAlignment.right);
          } else {
            txt('CONTINUED ON NEXT PAGE', colOne + 7, totalTop + 2,
                colTwo - colOne - 12, 26, font: bold);
          }
          txt('Page ${pageIndex + 1} of $pageCount', left, 808, frameWidth, 14,
              font: small, alignment: pdf.PdfTextAlignment.center);
        }
        final bytes=Uint8List.fromList(await doc.save());doc.dispose();
        await FileSaver.instance.saveFile(name:name,bytes:bytes,fileExtension:'pdf',mimeType:MimeType.pdf);
      }
    } catch (e) {if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export failed: $e')));} finally {if(mounted)setState(()=>exporting=false);}
  }
  Widget _info(String title, String value, {double width = 280}) =>
      SizedBox(width: width, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: RichText(text: TextSpan(style: const TextStyle(fontSize: 12, color: Color(0xFF1B283D)), children: [
          TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: value.isEmpty ? 'Not recorded' : value),
        ])),
      ));

  // The editing grid deliberately mirrors the columns and bottom-anchored total
  // of the exported A4 document. The form controls remain editable in place.
  Widget _printPreview() {
    const dark = Color(0xFF26364B);
    const edge = Color(0xFF69788B);
    final columnTitleStyle = const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dark);
    Widget line() => const Divider(height: 1, thickness: 1, color: edge);
    return Container(
      width: 820,
      constraints: const BoxConstraints(minHeight: 1100),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: edge, width: 1.3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 145, height: 73, child: logo == null
            ? const Center(child: Text('CONSULTANT LOGO', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)))
            : Image.memory(logo!, fit: BoxFit.contain)),
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 6, right: 12), child: Text(heading.toUpperCase(),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1.3)))),
          const SizedBox(width: 70),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _info('Employer', '${widget.project['employer'] ?? ''}', width: 390),
            _info('Consultant', consultant.text, width: 390),
            _info('Contractor', '${widget.project['contractorName'] ?? ''}', width: 390),
          ])),
          SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _info('IPC NO.', '${widget.ipc['number'] ?? ''}', width: 300),
            _info('EVALUATION DATE', evaluationDate.text, width: 300),
            _info('IPC PERIOD', '${periodFrom.text} – ${periodTo.text}', width: 300),
          ])),
        ])),
        line(),
        Container(height: 37, alignment: Alignment.center, color: const Color(0xFFDCE7F6),
          child: const Text('SCHEDULE OF PREVIOUS CERTIFIED PAYMENTS',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: dark))),
        line(),
        SizedBox(height: 40, child: Row(children: [
          SizedBox(width: 90, child: Center(child: Text('IPC NO.', style: columnTitleStyle))),
          Container(width: 1, color: edge),
          Expanded(child: Center(child: Text('DESCRIPTION', style: columnTitleStyle))),
          Container(width: 1, color: edge),
          SizedBox(width: 162, child: Center(child: Text('AMOUNT (TZS)', style: columnTitleStyle))),
        ])),
        line(),
        SizedBox(height: 645, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 90, child: ListView.builder(physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 7), itemCount: entries.length, itemBuilder: (context, i) =>
              SizedBox(height: 52, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: TextField(controller: entries[i].number, textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'No.'),
                  style: const TextStyle(fontSize: 12))))),
          ),
          Container(width: 1, color: edge),
          Expanded(child: ListView.builder(physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 7), itemCount: entries.length, itemBuilder: (context, i) =>
            SizedBox(height: 52, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: TextField(controller: entries[i].description,
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Certificate description'),
                style: const TextStyle(fontSize: 12)))))),
          Container(width: 1, color: edge),
          SizedBox(width: 162, child: ListView.builder(physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 7), itemCount: entries.length, itemBuilder: (context, i) =>
            SizedBox(height: 52, child: Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: TextField(
                controller: entries[i].amount, textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: '0.00'),
                style: const TextStyle(fontSize: 12)))),
              SizedBox(width: 28, child: IconButton(padding: EdgeInsets.zero, iconSize: 17,
                tooltip: 'Remove certificate', icon: const Icon(Icons.close), onPressed: () {
                  setState(() { final removed = entries.removeAt(i); removed.dispose(); });
                })),
            ])))),
        ])),
        line(),
        SizedBox(height: 48, child: Row(children: [
          const SizedBox(width: 90), Container(width: 1, color: edge),
          const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('TOTAL FOR PREVIOUS CERTIFIED PAYMENTS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))))),
          Container(width: 1, color: edge),
          SizedBox(width: 162, child: Padding(padding: const EdgeInsets.only(right: 9),
            child: Align(alignment: Alignment.centerRight, child: Text(money.format(total),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))))),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Schedule of previous certified payments')),
    backgroundColor: const Color(0xFFF1F4F9),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(
            spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(onPressed: pickLogo, icon: const Icon(Icons.image_outlined),
                label: Text(logo == null ? 'Upload consultant logo' : 'Replace logo')),
              SizedBox(width: 190, child: TextField(controller: consultant, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Consultant', border: OutlineInputBorder()))),
              SizedBox(width: 180, child: TextField(controller: evaluationDate, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Evaluation date', border: OutlineInputBorder()))),
              SizedBox(width: 145, child: TextField(controller: periodFrom, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'IPC from', border: OutlineInputBorder()))),
              SizedBox(width: 145, child: TextField(controller: periodTo, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'IPC to', border: OutlineInputBorder()))),
            ]))),
          const SizedBox(height: 12),
          const Text('Print layout preview • edit certificate rows directly in the table',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _printPreview())),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(onPressed: entries.length >= 12 ? null : () => setState(() => entries.add(_CertifiedEntry('', '', ''))),
              icon: const Icon(Icons.add), label: const Text('Add previous certificate')),
            FilledButton.icon(onPressed: saving ? null : () async { if (await save() && mounted) Navigator.pop(context, true); },
              icon: const Icon(Icons.save), label: Text(saving ? 'Saving…' : 'Save & update item 7')),
            OutlinedButton.icon(onPressed: exporting ? null : () => export(false), icon: const Icon(Icons.table_chart),
              label: const Text('Download Excel')),
            OutlinedButton.icon(onPressed: exporting ? null : () => export(true), icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Download PDF')),
          ]),
        ]))),
    ]),
  );

}
class _CertifiedEntry {
  _CertifiedEntry(String no,String desc,String value):number=TextEditingController(text:no),description=TextEditingController(text:desc),amount=TextEditingController(text:value);
  final TextEditingController number,description,amount;
  void dispose(){number.dispose();description.dispose();amount.dispose();}
}
