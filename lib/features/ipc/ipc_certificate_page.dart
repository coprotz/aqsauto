import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'ipc_summary_export.dart';
import 'ipc_summary_model.dart';
import 'ipc_certificate_amount.dart';
import 'ipc_previous_certificates_page.dart';

/// Convert the final, rounded certificate amount to formal English words.
/// Integers are used for cents to avoid binary floating point wording errors.
String ipcAmountInWords(double amount) {
  if (!amount.isFinite || amount < 0) return 'Amount unavailable';
  final centsTotal = (amount * 100).round();
  final whole = centsTotal ~/ 100;
  final cents = centsTotal % 100;
  String belowThousand(int value) {
    const units = ['Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine','Ten',
      'Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
    const tens = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
    if (value < 20) return units[value];
    if (value < 100) return '${tens[value ~/ 10]}${value % 10 == 0 ? '' : '-${units[value % 10]}'}';
    final tail = value % 100;
    final tailText = tail == 0 ? '' : (tail < 20 ? units[tail] : '${tens[tail ~/ 10]}${tail % 10 == 0 ? '' : '-${units[tail % 10]}'}');
    return '${units[value ~/ 100]} Hundred${tail == 0 ? '' : ' and $tailText'}';
  }
  String words(int value) {
    if (value < 1000) return belowThousand(value);
    const scales = [(1000000000000, 'Trillion'),(1000000000, 'Billion'),(1000000, 'Million'),(1000, 'Thousand')];
    final pieces = <String>[];
    var remainder = value;
    for (final scale in scales) {
      final group = remainder ~/ scale.$1;
      if (group > 0) { pieces.add('${belowThousand(group)} ${scale.$2}'); remainder %= scale.$1; }
    }
    if (remainder > 0) pieces.add(belowThousand(remainder));
    return pieces.join(', ');
  }
  return 'Tanzanian Shillings ${words(whole)} and ${words(cents)} Cents Only';
}

/// A printable certificate, separate from the three-column QS payment summary.
/// Contract particulars are saved to the project, not copied to each new IPC.
class IpcCertificatePage extends StatefulWidget {
  const IpcCertificatePage({super.key, required this.certificate});
  final DocumentReference<Map<String, dynamic>> certificate;
  @override
  State<IpcCertificatePage> createState() => _IpcCertificatePageState();
}

class _IpcCertificatePageState extends State<IpcCertificatePage> {
  StreamSubscription? _ipcSub, _projectSub, _historySub;
  Map<String, dynamic>? ipc, project;
  List<Map<String, dynamic>>? history;
  bool exporting = false;
  final money = NumberFormat('#,##0.00');
  DocumentReference<Map<String, dynamic>> get projectRef => widget.certificate.parent.parent!;

  @override
  void initState() {
    super.initState();
    _ipcSub = widget.certificate.stateSnapshots().listen((s) { if (mounted) setState(() => ipc = s.data()); });
    _projectSub = projectRef.stateSnapshots().listen((s) { if (mounted) setState(() => project = s.data() ?? {}); });
    _historySub = widget.certificate.parent.stateSnapshots().listen((s) { if (mounted) setState(() => history = s.docs.map((d) => d.data()).toList()); });
  }

  @override
  void dispose() {
    _ipcSub?.cancel(); _projectSub?.cancel(); _historySub?.cancel();
    super.dispose();
  }

  String field(String key) {
    final v = ipc?[key] ?? project?[key];
    return v == null || '$v'.trim().isEmpty ? 'Not recorded' : '$v';
  }
  String formatted(num? n) => n == null ? 'Not available' : money.format(n);

  Future<void> editDetails() async {
    const labels = <String, String>{
      'contractNumber':'Contract number', 'contractValue':'Contract sum (TZS)',
      'financier':'Financier', 'employer':'Employer', 'contractorName':'Contractor',
      'projectManager':'Project manager', 'certificateHeading':'Project / programme heading',
      'bankName':'Contractor bank name', 'bankBranch':'Bank branch',
      'bankAccountName':'Bank account name', 'bankAccountNumber':'Bank account number',
      'bankSwift':'SWIFT code',
      'preparedName':'Statement prepared by — name', 'preparedTitle':'Statement prepared by — designation', 'preparedOrganisation':'Statement prepared by — organisation', 'preparedDate':'Statement prepared by — date',
      'checkedName':'Checked and certified by — name', 'checkedTitle':'Checked and certified by — designation', 'checkedOrganisation':'Checked and certified by — organisation', 'checkedDate':'Checked and certified by — date',
      'verifiedName':'Verified by — name', 'verifiedTitle':'Verified by — designation', 'verifiedOrganisation':'Verified by — organisation', 'verifiedDate':'Verified by — date',
      'certifiedName':'Certified by — name', 'certifiedTitle':'Certified by — designation', 'certifiedOrganisation':'Certified by — organisation', 'certifiedDate':'Certified by — date',
      'approvedName':'Approved by — name', 'approvedTitle':'Approved by — designation', 'approvedOrganisation':'Approved by — organisation', 'approvedDate':'Approved by — date',
      'paymentDueDate':'Payment due date',
    };
    final controllers = {for (final e in labels.entries) e.key: TextEditingController(text: field(e.key) == 'Not recorded' ? '' : field(e.key))};
    final form = GlobalKey<FormState>();
    bool saving = false;
    try {
      await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Edit certificate details'),
        content: SizedBox(width: 620, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          children: labels.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
            controller: controllers[e.key], enabled: !saving,
            keyboardType: e.key == 'contractValue' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
            validator: e.key == 'contractValue' && controllers[e.key]!.text.trim().isNotEmpty && summaryNumber(controllers[e.key]!.text) == null
              ? (_) => 'Enter a valid amount' : null,
          ))).toList(),
        )))),
        actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: saving ? null : () async {
            if (!form.currentState!.validate()) return;
            update(() => saving = true);
            try {
              final values = <String, dynamic>{for (final k in labels.keys) k: controllers[k]!.text.trim()};
              values['contractValue'] = summaryNumber(values['contractValue']) ?? 0.0;
              await projectRef.set(values, SetOptions(merge: true));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (e) {
              update(() => saving = false);
              if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Could not save details: $e')));
            }
          }, child: Text(saving ? 'Saving…' : 'Save details'))],
      )));
    } finally { for (final c in controllers.values) { c.dispose(); } }
  }

  List<IpcSummaryRow> get rows => ipcSummaryRows(ipc!, history!);
  double? value(String code, int index) {
    for (final row in rows) { if (row.code == code) return row.values.length > index ? row.values[index] : null; }
    return null;
  }
  double? get earlierCertified => ipc == null || history == null
      ? null : ipcPreviouslyCertified(ipc!, history!);
  double? get payable => ipcCertificatePayable(ipc!, history!);
  String get certificationText {
    final amount = payable;
    if (amount == null) return 'The amount payable cannot be certified until the previous certified payments schedule is completed.';
    final contractor = field('contractorName');
    return 'We have prepared the valuation of works under the terms of the Contract and hereby certify the amount of ${ipcAmountInWords(amount)} VAT ${summaryNumber(project?['certificateVatRate']) == null ? 'exclusive' : 'as configured'} to be paid to Contractor ${contractor == 'Not recorded' ? '[Contractor name to be entered]' : contractor}.';
  }
  Uint8List? get certificateLogo {
    final data = project?['ipcCertificateLogoBase64'];
    if (data is! String || data.isEmpty) return null;
    try { return base64Decode(data); } catch (_) { return null; }
  }


  Future<void> editPriorCertificates() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => IpcPreviousCertificatesPage(certificate:widget.certificate,projectRef:projectRef,project:project!,ipc:ipc!)));
  }

  List<(String, String, double?, bool)> get lines => [
    ('1', 'Total value of works executed to date', value('1', 2), false),
    ('', 'Additions to payment', null, true),
    ('2', 'Release of retention', 0, false),
    ('3', 'Advance payment', value('2', 2), false),
    ('A', 'Sub-total – Additions [2 + 3]', value('A', 2), true),
    ('', 'Deductions from payment', null, true),
    ('4', 'Retention', value('3', 2), false),
    ('5', 'Advance repayment', value('4', 2), false),
    ('B', 'Sub-total – Deductions [4 + 5]', value('B', 2), true),
    ('C', 'Sub-total VAT exclusive [1 + A - B]', value('C', 2), true),
    ('6', 'VAT (not configured)', 0, false),
    ('D', 'Sub-total including configured VAT [C + 6]', value('C', 2), true),
    ('7', 'Less: previously certified amount', earlierCertified, false),
    ('E', 'Total amount due for this certificate [D - 7]', payable, true),
  ];

  Future<void> export(bool asPdf) async {
    setState(() => exporting = true);
    try {
      final title = 'INTERIM PAYMENT CERTIFICATE NO. ${field('number')}';
      final details = <String, String>{'Project':field('certificateHeading') == 'Not recorded' ? '${project?['name'] ?? ''}' : field('certificateHeading'),
        'Contract No.':field('contractNumber'), 'Contract Sum (TZS)':formatted(summaryNumber(project?['contractValue'] ?? ipc?['contractValue'])),
        for (final key in ['financier','employer','contractorName','projectManager','bankName','bankBranch','bankAccountName','bankAccountNumber','bankSwift']) key:field(key)};
      final certRows = lines.map((l) => IpcSummaryRow(l.$1, l.$2, [l.$3], total:l.$4)).toList();
      final safeName = 'IPC_${field('number').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_Certificate';
      if (!asPdf) {
        final bytes = ipcSummaryExcel(title, details, certRows, headers: const ['Ref','Description','Amount (TZS)']);
        await FileSaver.instance.saveFile(name:safeName, bytes:bytes, fileExtension:'xlsx', mimeType:MimeType.microsoftExcel);
      } else {
        final doc = pdf.PdfDocument();
        doc.pageSettings.size = pdf.PdfPageSize.a4;
        doc.pageSettings.margins.all = 0;
        final page = doc.pages.add();
        final g = page.graphics;
        const left = 29.0, right = 566.0, content = right - left;
        final ink = pdf.PdfColor(28, 42, 64);
        final stroke = pdf.PdfPen(pdf.PdfColor(110, 123, 139), width: 0.65);
        final light = pdf.PdfSolidBrush(pdf.PdfColor(235, 240, 246));
        final regular = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8);
        final small = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 7.3);
        final bold = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8, style: pdf.PdfFontStyle.bold);
        final headerFont = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 10, style: pdf.PdfFontStyle.bold);
        var y = 23.0;
        void line(double x1, double yy, double x2) => g.drawLine(stroke, Offset(x1, yy), Offset(x2, yy));
        void textAt(String t, double x, double yy, double w, double h, {pdf.PdfFont? font, pdf.PdfTextAlignment align = pdf.PdfTextAlignment.left}) {
          g.drawString(t, font ?? regular, brush: pdf.PdfSolidBrush(ink), bounds: Rect.fromLTWH(x, yy, w, h),
            format: pdf.PdfStringFormat(alignment: align, lineAlignment: pdf.PdfVerticalAlignment.middle));
        }
        // Every figure uses a dedicated right-aligned 150pt column; never crop it.
        final logo = certificateLogo;
        if (logo != null) {
          try { g.drawImage(pdf.PdfBitmap(logo), Rect.fromLTWH(left + 3, y, 80, 36)); } catch (_) {}
        }
        final head = field('certificateHeading') == 'Not recorded' ? '${project?['name'] ?? 'PROJECT'}' : field('certificateHeading');
        textAt(head.toUpperCase(), left + 85, y, content - 88, 33, font: headerFont, align: pdf.PdfTextAlignment.center);
        y += 33;
        textAt(title, left, y, content, 17, font:headerFont, align:pdf.PdfTextAlignment.center);
        y += 19;
        line(left,y,right); y += 6;
        final particulars = <String,String>{
          'CONTRACT NO.':field('contractNumber'),
          'CONTRACT SUM (TZS)':formatted(summaryNumber(project?['contractValue'] ?? ipc?['contractValue'])),
          'FINANCIER':field('financier'),
          'EMPLOYER':field('employer'),
          'CONTRACTOR':field('contractorName'),
          'PROJECT MANAGER':field('projectManager'),
        };
        for (final d in particulars.entries) {
          textAt(d.key,left+5,y,168,14,font:bold);
          textAt(d.value,left+175,y,content-180,14,align:pdf.PdfTextAlignment.right);
          y+=15;
        }
        line(left,y+2,right); y+=9;
        const refWidth = 29.0, moneyWidth = 151.0;
        final descWidth = content - refWidth - moneyWidth;
        for (final item in lines) {
          final isHeading = item.$1.isEmpty;
          final isTotal = item.$4 && !isHeading;
          final rowHeight = isHeading ? 17.0 : (item.$1 == 'E' ? 21.0 : 17.0);
          if (isHeading || isTotal) g.drawRectangle(brush:light,bounds:Rect.fromLTWH(left,y,content,rowHeight));
          g.drawRectangle(pen:stroke,bounds:Rect.fromLTWH(left,y,content,rowHeight));
          textAt(item.$1,left+6,y+2,refWidth-8,rowHeight-4,font:isTotal?bold:regular);
          textAt(item.$2,left+refWidth+3,y+2,descWidth-7,rowHeight-4,font:(isTotal||isHeading)?bold:regular);
          if (!isHeading && item.$3 != null) {
            textAt(formatted(item.$3),right-moneyWidth+3,y+2,moneyWidth-10,rowHeight-4,
              font:isTotal?bold:regular,align:pdf.PdfTextAlignment.right);
          }
          y += rowHeight;
        }
        y+=5;
        final certHeight=65.0;
        g.drawRectangle(pen:stroke,bounds:Rect.fromLTWH(left,y,content,certHeight));
        textAt('CERTIFICATION OF PAYMENT',left+8,y+4,content-16,15,font:bold,align:pdf.PdfTextAlignment.center);
        textAt(certificationText,left+13,y+20,content-26,certHeight-23,font:small,align:pdf.PdfTextAlignment.center);
        y+=certHeight+4;
        textAt('CONTRACTOR BANK DETAILS',left+5,y,content-10,14,font:bold,align:pdf.PdfTextAlignment.center); y+=16;
        final bankDetails = <String,String>{'Bank name':field('bankName'),'Branch':field('bankBranch'),
          'Account name':field('bankAccountName'),'Account number':field('bankAccountNumber'),'SWIFT':field('bankSwift')};
        // Bank details shown as clear label/value pairs across two columns.
        var i=0;
        for (final d in bankDetails.entries) {
          final col=i%2, row=i~/2;
          final x=left+6+col*(content/2);
          textAt('${d.key}: ${d.value}',x,y+row*13,content/2-12,14,font:small);
          i++;
        }
        y+=41;
        line(left,y,right);y+=4;
        // Keep the complete approval panel together and give actual signing room.
        // Positions are measured from each box top, not from the previous text line.
        const topBoxHeight = 112.0;
        const bottomBoxHeight = 112.0;
        const panelHeight = topBoxHeight + bottomBoxHeight + 18.0;
        var sigPage = page;
        var sigY = y;
        if (842.0 - y - 23.0 < panelHeight) {
          sigPage = doc.pages.add();
          sigY = 35;
        }
        final sigG = sigPage.graphics;
        final labelFont = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 8,
            style: pdf.PdfFontStyle.bold);
        final valueFont = pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 7.5);
        void signatureOnPage(String label, String prefix, double x,
            double top, double w, double h) {
          sigG.drawRectangle(pen: stroke, bounds: Rect.fromLTWH(x, top, w, h));
          final inset = w < 190 ? 7.0 : 10.0;
          final innerWidth = w - 2 * inset;
          void printLine(String t, double offset, {bool heading = false,
              double height = 15}) {
            sigG.drawString(t, heading ? labelFont : valueFont,
              brush: pdf.PdfSolidBrush(ink),
              bounds: Rect.fromLTWH(x + inset, top + offset, innerWidth, height),
              format: pdf.PdfStringFormat(
                alignment: pdf.PdfTextAlignment.left,
                lineAlignment: pdf.PdfVerticalAlignment.middle));
          }
          String data(String suffix) {
            final v = field('$prefix$suffix');
            return v == 'Not recorded' ? '' : v;
          }
          printLine(label, 7, heading: true, height: 17);
          printLine('Name: ${data('Name')}', 23);
          printLine('Designation: ${data('Title')}', 38);
          // Organisation gets its own two-line area (no overlapping signature).
          printLine('Organisation: ${data('Organisation')}', 53, height: 22);
          // Deliberate vertical space to sign by hand, separated from text.
          printLine(w < 190 ? 'Signature: _____________' : 'Signature: ______________________', h - 34);
          printLine('Date: ${data('Date')}', h - 18);
        }
        final half = content / 2;
        final third = content / 3;
        signatureOnPage('STATEMENT PREPARED BY', 'prepared', left, sigY,
            half, topBoxHeight);
        signatureOnPage('CHECKED AND CERTIFIED BY', 'checked', left + half,
            sigY, half, topBoxHeight);
        final lowerY = sigY + topBoxHeight;
        signatureOnPage('VERIFIED BY', 'verified', left, lowerY,
            third, bottomBoxHeight);
        signatureOnPage('CERTIFIED BY', 'certified', left + third, lowerY,
            third, bottomBoxHeight);
        signatureOnPage('APPROVED BY', 'approved', left + 2 * third, lowerY,
            third, bottomBoxHeight);
        final due = field('paymentDueDate');
        if (due != 'Not recorded') {
          sigG.drawString('Payment due date: $due', bold,
            bounds: Rect.fromLTWH(left, lowerY + bottomBoxHeight + 4,
                content, 14));
        }
        final bytes = Uint8List.fromList(await doc.save());
        doc.dispose();
        await FileSaver.instance.saveFile(name:safeName, bytes:bytes, fileExtension:'pdf', mimeType:MimeType.pdf);

      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export failed: $e')));
    } finally { if (mounted) setState(() => exporting = false); }
  }

  Widget _signatoryPreview(String label,String prefix) {
    String shown(String suffix,String placeholder) {
      final v=field('$prefix$suffix'); return v=='Not recorded'?placeholder:v;
    }
    return Padding(padding:const EdgeInsets.all(11),child:SizedBox(height:165,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(label.toUpperCase(),style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
      const SizedBox(height:9),Text(shown('Name','Name: __________________')), 
      Text(shown('Title','Designation: ________________'),style:const TextStyle(fontSize:12)),
      Text(shown('Organisation','Organisation: ______________'),style:const TextStyle(fontSize:12)),
      const Spacer(),const Text('Signature: __________________'),
      Text('Date: ${shown('Date','__________________')}'),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    final ready = ipc != null && project != null && history != null;
    return Scaffold(appBar:AppBar(title:const Text('IPC certificate')),
      backgroundColor:const Color(0xFFF4F6FA),
      body: !ready ? const Center(child:CircularProgressIndicator()) : ListView(padding:const EdgeInsets.all(20), children:[
        Wrap(spacing:12, runSpacing:12, alignment:WrapAlignment.center, children:[
          OutlinedButton.icon(onPressed:editDetails, icon:const Icon(Icons.edit_outlined), label:const Text('Edit certificate details')),
          FilledButton.icon(onPressed:exporting ? null : () => export(false), icon:const Icon(Icons.table_chart_outlined), label:const Text('Download Excel')),
          FilledButton.icon(onPressed:exporting ? null : () => export(true), icon:const Icon(Icons.picture_as_pdf_outlined), label:const Text('Download PDF')),
        ]),
        const SizedBox(height:20),
        Center(child:Container(constraints:const BoxConstraints(maxWidth:950), padding:const EdgeInsets.all(28),
          decoration:BoxDecoration(color:Colors.white, border:Border.all(color:Colors.blueGrey.shade300)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[
            if (certificateLogo != null) Center(child:Padding(padding:const EdgeInsets.only(bottom:14), child:Image.memory(certificateLogo!,height:64,fit:BoxFit.contain))),
            Text(field('certificateHeading') == 'Not recorded' ? '${project?['name'] ?? 'PROJECT'}' : field('certificateHeading'), textAlign:TextAlign.center, style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
            const SizedBox(height:8),
            Text('INTERIM PAYMENT CERTIFICATE (IPC) NO. ${field('number')}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
            const Divider(height:32),
            for (final detail in <String,String>{'CONTRACT NO.':field('contractNumber'), 'CONTRACT SUM (TZS)':formatted(summaryNumber(project?['contractValue'] ?? ipc?['contractValue'])),
              'FINANCIER':field('financier'),'EMPLOYER':field('employer'),'CONTRACTOR':field('contractorName'),'PROJECT MANAGER':field('projectManager')}.entries)
              Padding(padding:const EdgeInsets.symmetric(vertical:5), child:Row(children:[Expanded(child:Text(detail.key,style:const TextStyle(fontWeight:FontWeight.bold))),Expanded(child:Text(detail.value,textAlign:TextAlign.right))])),
            const Divider(height:30),
            InkWell(onTap:editPriorCertificates,child:const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Row(children:[Icon(Icons.edit_note,color:Colors.blue),SizedBox(width:8),Text('Click item 7 below to edit previous certified payments',style:TextStyle(color:Colors.blue,fontWeight:FontWeight.w600))]))),
            Table(columnWidths:const {0:FixedColumnWidth(40),2:FixedColumnWidth(175)}, border:TableBorder(horizontalInside:BorderSide(color:Color(0xFFE2E5EA))),
              children:[for (final l in lines) TableRow(decoration:BoxDecoration(color:l.$4?const Color(0xFFF1F4F8):Colors.white),children:[
                Padding(padding:const EdgeInsets.all(9),child:Text(l.$1,style:TextStyle(fontWeight:l.$4?FontWeight.bold:null))),
                Padding(padding:const EdgeInsets.all(9),child:l.$1 == '7' ? InkWell(onTap:editPriorCertificates,child:Row(children:[Expanded(child:Text(l.$2,style:const TextStyle(color:Colors.blue,fontWeight:FontWeight.bold))),const Icon(Icons.open_in_new,size:17,color:Colors.blue)])) : Text(l.$2,style:TextStyle(fontWeight:l.$4?FontWeight.bold:null))),
                Padding(padding:const EdgeInsets.all(9),child:Text(l.$3==null?'':formatted(l.$3),textAlign:TextAlign.right,style:TextStyle(fontWeight:l.$4?FontWeight.bold:null))),
              ])]),
            const SizedBox(height:14),
            Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(border:Border.all(color:Colors.blueGrey.shade400)),
              child:Column(children:[const Text('CERTIFICATION OF PAYMENT',style:TextStyle(fontWeight:FontWeight.bold)),
                const SizedBox(height:10),Text(certificationText,textAlign:TextAlign.center,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600,height:1.5))])),
            const Divider(height:32),
            const Text('CONTRACTOR BANK DETAILS',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold)),
            for (final e in <String,String>{'bankName':'Bank Name','bankBranch':'Branch','bankAccountName':'Account Name','bankAccountNumber':'Account Number','bankSwift':'SWIFT Code'}.entries) Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Text('${e.value}: ${field(e.key)}')),
            const SizedBox(height:18),
            Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:editDetails,icon:const Icon(Icons.draw_outlined),label:const Text('Edit signatories / dates'))),
            const SizedBox(height:10),
            Table(border:TableBorder.all(color:Colors.blueGrey.shade300),children:[
              TableRow(children:[_signatoryPreview('Statement prepared by','prepared'),_signatoryPreview('Checked and certified by','checked')]),
            ]),
            Table(border:TableBorder.all(color:Colors.blueGrey.shade300),children:[
              TableRow(children:[_signatoryPreview('Verified by','verified'),_signatoryPreview('Certified by','certified'),_signatoryPreview('Approved by','approved')]),
            ]),
            if (field('paymentDueDate')!='Not recorded') Padding(padding:const EdgeInsets.all(12),child:Text('Payment due date: ${field('paymentDueDate')}',textAlign:TextAlign.right)),
          ]))),
      ]));
  }
}
