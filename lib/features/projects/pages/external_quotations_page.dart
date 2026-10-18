import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class ExternalQuotationsPage extends StatefulWidget {
  const ExternalQuotationsPage({super.key, required this.projectId, required this.projectName});
  final String projectId;
  final String projectName;

  @override
  State<ExternalQuotationsPage> createState() => _ExternalQuotationsPageState();
}

class _ExternalQuotationsPageState extends State<ExternalQuotationsPage> {
  CollectionReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection('projects').doc(widget.projectId).collection('externalQuotations');

  double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;
  String _money(double v) => v.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Future<void> _addQuotation() async {
    final contractor = TextEditingController();
    final reference = TextEditingController();
    final discipline = TextEditingController(text: 'Electrical');
    final description = TextEditingController(text: 'Additional works arising from revised drawings');
    final quoted = TextEditingController();
    final assessed = TextEditingController();
    final approved = TextEditingController();
    final notes = TextEditingController();
    String status = 'Under Review';
    bool included = false;
    Uint8List? pdfBytes;
    String? pdfName;
    String? error;

    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          double n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
          final effective = n(approved) > 0 ? n(approved) : (n(assessed) > 0 ? n(assessed) : n(quoted));
          return AlertDialog(
            title: const Text('Add external quotation'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Keep specialist/subcontractor quotations separate from drawing take-off. Only approved or intentionally included amounts should affect the project cost.', style: TextStyle(color: AqsColors.muted)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    SizedBox(width: 360, child: TextField(controller: contractor, decoration: const InputDecoration(labelText: 'Contractor / supplier', border: OutlineInputBorder()))),
                    SizedBox(width: 360, child: TextField(controller: reference, decoration: const InputDecoration(labelText: 'Quotation reference', border: OutlineInputBorder()))),
                    SizedBox(width: 360, child: TextField(controller: discipline, decoration: const InputDecoration(labelText: 'Discipline', border: OutlineInputBorder()))),
                    SizedBox(width: 360, child: DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()), items: const ['Draft','Under Review','Assessed','Approved','Rejected'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged:(v)=>setState(()=>status=v ?? status))),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: description, decoration: const InputDecoration(labelText: 'Description / scope', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: quoted, keyboardType: const TextInputType.numberWithOptions(decimal:true), onChanged:(_)=>setState((){}), decoration: const InputDecoration(labelText:'Quoted amount (TZS)', border:OutlineInputBorder()))),
                    const SizedBox(width:10),
                    Expanded(child: TextField(controller: assessed, keyboardType: const TextInputType.numberWithOptions(decimal:true), onChanged:(_)=>setState((){}), decoration: const InputDecoration(labelText:'QS assessed amount (TZS)', border:OutlineInputBorder()))),
                    const SizedBox(width:10),
                    Expanded(child: TextField(controller: approved, keyboardType: const TextInputType.numberWithOptions(decimal:true), onChanged:(_)=>setState((){}), decoration: const InputDecoration(labelText:'Approved amount (TZS)', border:OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AqsColors.canvas, borderRadius: BorderRadius.circular(12)), child: Row(children:[const Icon(Icons.calculate_outlined), const SizedBox(width:10), Expanded(child:Text('Current cost value: ${_money(effective)} TZS', style:const TextStyle(fontWeight:FontWeight.w800)))])),
                  const SizedBox(height: 12),
                  Row(children:[
                    OutlinedButton.icon(onPressed:() async { final r=await FilePicker.platform.pickFiles(type:FileType.custom, allowedExtensions:['pdf'], withData:true); if(r!=null && r.files.single.bytes!=null){setState((){pdfBytes=r.files.single.bytes; pdfName=r.files.single.name;});}}, icon:const Icon(Icons.picture_as_pdf_outlined), label:Text(pdfName == null ? 'Attach quotation PDF' : 'Replace PDF')),
                    const SizedBox(width:12),
                    if(pdfName!=null) Expanded(child:Text(pdfName!, overflow:TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 12),
                  CheckboxListTile(contentPadding:EdgeInsets.zero, value:included, onChanged:(v)=>setState(()=>included=v ?? false), title:const Text('Include in current project total'), subtitle:const Text('Normally enable this after QS assessment/approval.')),
                  TextField(controller: notes, maxLines:2, decoration: const InputDecoration(labelText:'Notes', border:OutlineInputBorder())),
                  if(error!=null) Padding(padding:const EdgeInsets.only(top:10), child:Text(error!, style:const TextStyle(color:Colors.red))),
                ]),
              ),
            ),
            actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false), child:const Text('Cancel')), FilledButton.icon(onPressed:(){if(contractor.text.trim().isEmpty || n(quoted)<=0){setState(()=>error='Enter contractor/supplier and quoted amount.');return;} Navigator.pop(dialogContext,true);}, icon:const Icon(Icons.save_outlined), label:const Text('Save quotation'))],
          );
        },
      ),
    );
    if(save != true) return;

    final doc = _ref.doc();
    String? pdfUrl;
    String? storagePath;
    if(pdfBytes != null && pdfName != null) {
      storagePath = 'projects/${widget.projectId}/external_quotations/${doc.id}/$pdfName';
      final storage = FirebaseStorage.instance.ref(storagePath);
      await storage.putData(pdfBytes!, SettableMetadata(contentType:'application/pdf'));
      pdfUrl = await storage.getDownloadURL();
    }
    final q = _d(quoted.text), a = _d(assessed.text), ap = _d(approved.text);
    final effective = ap > 0 ? ap : (a > 0 ? a : q);
    await doc.set({
      'contractor': contractor.text.trim(), 'reference': reference.text.trim(), 'discipline': discipline.text.trim(),
      'description': description.text.trim(), 'quotedAmount': q, 'assessedAmount': a, 'approvedAmount': ap,
      'effectiveAmount': effective, 'status': status, 'includedInProjectTotal': included, 'notes': notes.text.trim(),
      'pdfName': pdfName, 'pdfUrl': pdfUrl, 'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _delete(DocumentSnapshot<Map<String,dynamic>> doc) async {
    final ok = await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete quotation?'),content:const Text('This removes the quotation record from AQS and the project cost total.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));
    if(ok!=true)return;
    final path=(doc.data()?['storagePath'] ?? '').toString();
    if(path.isNotEmpty){try{await FirebaseStorage.instance.ref(path).delete();}catch(_){}}
    await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:AqsColors.canvas,
      appBar:AppBar(title:Text('External quotations · ${widget.projectName}')),
      floatingActionButton:FloatingActionButton.extended(onPressed:_addQuotation, icon:const Icon(Icons.add), label:const Text('Add quotation')),
      body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:_ref.orderBy('createdAt', descending:true).snapshots(), builder:(context,snap){
        if(snap.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        if(snap.hasError)return Center(child:Text('Could not load quotations: ${snap.error}'));
        final docs=snap.data?.docs ?? const [];
        final quoted=docs.fold<double>(0,(s,d)=>s+_d(d.data()['quotedAmount']));
        final included=docs.where((d)=>d.data()['includedInProjectTotal']==true).fold<double>(0,(s,d)=>s+_d(d.data()['effectiveAmount']));
        return ListView(padding:const EdgeInsets.all(24),children:[
          Wrap(spacing:14,runSpacing:14,children:[_metric('Quotations','${docs.length}',Icons.request_quote_outlined),_metric('Quoted total','${_money(quoted)} TZS',Icons.receipt_long_outlined),_metric('Included in project','${_money(included)} TZS',Icons.account_balance_wallet_outlined)]),
          const SizedBox(height:22),
          if(docs.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(32),child:Center(child:Text('No external quotations yet. Add contractor quotations here without mixing them with drawing take-off measurements.')))),
          ...docs.map((doc){final d=doc.data(); final eff=_d(d['effectiveAmount']); return Card(margin:const EdgeInsets.only(bottom:12),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:10),leading:const CircleAvatar(child:Icon(Icons.electrical_services_outlined)),title:Text((d['contractor']??'External quotation').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${d['discipline'] ?? ''} · ${d['reference'] ?? ''}\n${d['status'] ?? 'Draft'}${d['includedInProjectTotal']==true ? ' · Included in project total' : ' · Excluded from project total'}'),isThreeLine:true,trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${_money(eff)} TZS',style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(width:12),IconButton(tooltip:'Delete quotation',onPressed:()=>_delete(doc),icon:const Icon(Icons.delete_outline,color:Colors.red))])));}),
          const SizedBox(height:70),
        ]);
      }),
    );
  }

  Widget _metric(String label,String value,IconData icon)=>SizedBox(width:300,child:Card(child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[Icon(icon,size:30),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:AqsColors.muted)),const SizedBox(height:4),Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]))]))));
}
