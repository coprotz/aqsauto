import 'package:aqs/features/takeoff/models/pending_rebars_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ColumnCompositeDetailsDialog extends StatefulWidget {
  const ColumnCompositeDetailsDialog({
    super.key,
    required this.columnId,
    required this.initialDocs,
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.currentColor,
    this.defaultLabel,
  });

  final String columnId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String projectId;
  final String buildingId;
  final String drawingId;
  final Color currentColor;
  final String? defaultLabel;

  @override
  State<ColumnCompositeDetailsDialog> createState() =>
      _ColumnCompositeDetailsDialogState();
}

class _ColumnCompositeDetailsDialogState
    extends State<ColumnCompositeDetailsDialog> {
  late List<QueryDocumentSnapshot<Map<String, dynamic>>> localDocs;

  // editable geometry + boq
  final widthCtrl = TextEditingController();
  final lengthCtrl = TextEditingController();
  final heightCtrl = TextEditingController();

  final colNameCtrl = TextEditingController();
  final colQtyCtrl = TextEditingController(text: '1');

  final boqConcCtrl = TextEditingController();
  final boqFwCtrl = TextEditingController();

  // add main bars inputs
  final mainMarkCtrl = TextEditingController(); // 8Y16
  final mainBoqCtrl = TextEditingController();
  final mainEmbedCtrl = TextEditingController(text: '0.30');
  final mainExtraCtrl = TextEditingController(text: '0.00');
  final mainNoteCtrl = TextEditingController();

  // add rings inputs
  final ringLabelCtrl = TextEditingController(); // R10-150
  final ringBoqCtrl = TextEditingController();
  final ringDiaCtrl = TextEditingController(text: '10');
  final ringSpacingCtrl = TextEditingController(text: '150');
  final ringCountCtrl = TextEditingController(); // optional override
  final ringCoverCtrl = TextEditingController(text: '0.05');
  final ringHookCtrl = TextEditingController(text: '0.10');
  final ringNoteCtrl = TextEditingController();

  final pendingMainBars = <PendingMainBar>[];
  final pendingRings = <PendingRing>[];

  bool saving = false;
  String? err;

  Offset dialogOffset = Offset.zero;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchColumnDocs() async {
    final byGroup =
        await widget.measurementsRef
            .where('drawingId', isEqualTo: widget.drawingId)
            .where('columnGroupId', isEqualTo: widget.columnId)
            .limit(500)
            .get();
    if (byGroup.docs.isNotEmpty) return byGroup.docs;
    final byLegacyId =
        await widget.measurementsRef
            .where('drawingId', isEqualTo: widget.drawingId)
            .where('columnId', isEqualTo: widget.columnId)
            .limit(500)
            .get();
    return byLegacyId.docs;
  }

  double _num(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  int _int(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  String _str(dynamic v) => (v ?? '').toString().trim();

  void _prefillFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Defaults
    String name = '';
    int qty = 1;
    String boqConc = '';
    String boqFw = '';

    double w = 0, l = 0, h = 0;

    for (final d in docs) {
      final m = d.data();
      final t = _str(m['type']);

      // meta
      if (name.isEmpty) name = _str(m['columnName'] ?? m['columnType']);
      if (qty == 1) {
        final q = _int(
          m['qtyPerBuilding'] ?? m['columnQty'] ?? m['qty'],
          fallback: 0,
        );
        if (q > 0) qty = q;
      }

      // geometry (take first non-zero)
      w = w > 0 ? w : _num(m['widthM'] ?? m['columnWidthM']);
      l = l > 0 ? l : _num(m['lengthM'] ?? m['columnLengthM']);
      h = h > 0 ? h : _num(m['heightM'] ?? m['columnHeightM']);

      // BOQs (type-specific)
      if (t == 'columnConcrete' && boqConc.isEmpty) {
        boqConc = _str(m['boqCode']);
      }
      if ((t == 'columnFormwork' ||
              t == 'columnSideFormwork' ||
              t == 'columnFormworkSides') &&
          boqFw.isEmpty) {
        boqFw = _str(m['boqCode']);
      }
    }

    colNameCtrl.text = name;
    colQtyCtrl.text = qty.toString();

    if (w > 0) widthCtrl.text = w.toStringAsFixed(3);
    if (l > 0) lengthCtrl.text = l.toStringAsFixed(3);
    if (h > 0) heightCtrl.text = h.toStringAsFixed(3);

    boqConcCtrl.text = boqConc;
    boqFwCtrl.text = boqFw;
  }

  @override
  void initState() {
    super.initState();
    localDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(
      widget.initialDocs,
    );

    // Prefill from docs if exist
    double w = 0, l = 0, h = 0;
    String boqC = '', boqF = '', name = '';
    int qty = 1;

    for (final d in localDocs) {
      final m = d.data();
      w = w > 0 ? w : _num(m['widthM'] ?? m['columnWidthM']);
      l = l > 0 ? l : _num(m['lengthM'] ?? m['columnLengthM']);
      h = h > 0 ? h : _num(m['heightM'] ?? m['columnHeightM']);

      if (name.isEmpty) {
        name = (m['columnName'] ?? m['columnType'] ?? '').toString();
      }
      final q = _int(
        m['qtyPerBuilding'] ?? m['columnQty'] ?? m['qty'],
        fallback: 0,
      );
      if (q > 0) qty = q;

      if (boqC.isEmpty && (m['type'] == 'columnConcrete')) {
        boqC = (m['boqCode'] ?? '').toString();
      }
      if (boqF.isEmpty &&
          (m['type'] == 'columnFormwork' ||
              m['type'] == 'columnSideFormwork' ||
              m['type'] == 'columnFormworkSides')) {
        boqF = (m['boqCode'] ?? '').toString();
      }
    }

    if (w > 0) widthCtrl.text = w.toStringAsFixed(3);
    if (l > 0) lengthCtrl.text = l.toStringAsFixed(3);
    if (h > 0) heightCtrl.text = h.toStringAsFixed(3);

    boqConcCtrl.text = boqC;
    boqFwCtrl.text = boqF;
    colNameCtrl.text = name;
    colQtyCtrl.text = qty.toString();

    // ✅ Critical: load fresh docs from Firestore so rebars appear
    Future.microtask(() async {
      try {
        final docs = await _fetchColumnDocs();
        setState(() => localDocs = docs);
        _prefillFromDocs(docs); // ✅ align initial with Firestore
        setState(() {}); // refresh UI after controllers updated
      } catch (e) {
        setState(() => err = 'Load failed: $e');
      }
    });
  }

  Future<void> _reloadDocsFromFirestore() async {
    final docs = await _fetchColumnDocs();
    setState(() => localDocs = docs);
  }

  @override
  void dispose() {
    widthCtrl.dispose();
    lengthCtrl.dispose();
    heightCtrl.dispose();
    boqConcCtrl.dispose();
    boqFwCtrl.dispose();

    mainMarkCtrl.dispose();
    mainBoqCtrl.dispose();
    mainEmbedCtrl.dispose();
    mainExtraCtrl.dispose();
    mainNoteCtrl.dispose();

    ringLabelCtrl.dispose();
    ringBoqCtrl.dispose();
    ringDiaCtrl.dispose();
    ringSpacingCtrl.dispose();
    ringCountCtrl.dispose();
    ringCoverCtrl.dispose();
    ringHookCtrl.dispose();
    ringNoteCtrl.dispose();

    colNameCtrl.dispose();
    colQtyCtrl.dispose();
    super.dispose();
  }

  // double _num(dynamic v) =>
  //     (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  double _uw(int diaMm) => 0.00617 * diaMm * diaMm;

  ({int qty, int dia}) _parseMarkSimple(String raw) {
    final m = RegExp(r'^\s*(\d+)\s*[Yy]\s*(\d+)\s*$').firstMatch(raw);
    if (m == null) throw FormatException('Use mark like 8Y16');
    return (qty: int.parse(m.group(1)!), dia: int.parse(m.group(2)!));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => setState(() => dialogOffset += d.delta),
      child: Transform.translate(
        offset: dialogOffset,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
            child: Column(
              children: [
                _dragHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryBlock(),
                        const Divider(height: 22),
                        _editGeometryBlock(),
                        const Divider(height: 22),
                        _addMainBarsBlock(),
                        const Divider(height: 22),
                        _addRingsBlock(),
                        const Divider(height: 22),
                        _pendingListBlock(),
                        const Divider(height: 22),
                        _existingDocsList(),
                        if (err != null) ...[
                          const SizedBox(height: 8),
                          Text(err!, style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                ),
                _actionsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dragHeader() {
    final title =
        widget.defaultLabel?.trim().isNotEmpty == true
            ? 'Composite Column – ${widget.defaultLabel!.trim()}'
            : 'Composite Column details';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_handle, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (saving)
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _summaryBlock() {
    final w = double.tryParse(widthCtrl.text.trim()) ?? 0;
    final l = double.tryParse(lengthCtrl.text.trim()) ?? 0;
    final h = double.tryParse(heightCtrl.text.trim()) ?? 0;

    // final concVol = (w > 0 && l > 0 && h > 0) ? (w * l * h) : 0.0;
    // final formArea = (w > 0 && l > 0 && h > 0) ? (2 * (w + l) * h) : 0.0;
    final qty = int.tryParse(colQtyCtrl.text.trim()) ?? 1;

    final concVolOne = (w > 0 && l > 0 && h > 0) ? (w * l * h) : 0.0;
    final formAreaOne = (w > 0 && l > 0 && h > 0) ? (2 * (w + l) * h) : 0.0;

    final concVol = concVolOne * qty;
    final formArea = formAreaOne * qty;

    // Existing rebar totals (from docs)
    double rebarLenM = 0, rebarKg = 0;
    for (final d in localDocs) {
      final m = d.data();
      final t = (m['type'] ?? '').toString();
      if (t == 'rebarColumnMain' ||
          t == 'rebarColumnRings' ||
          t == 'columnMainRebar' ||
          t == 'columnStirrups') {
        rebarLenM += _num(
          m['totalLengthM'] ??
              m['totalLengthAllBarsM'] ??
              m['totalLengthAllRingsM'] ??
              m['totalLengthPerColumnM'] ??
              m['stirrupTotalLenPerColumnM'],
        );
        rebarKg += _num(m['totalWeightKg'] ?? m['value']);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Column ID: ${widget.columnId}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (w > 0 && l > 0)
          Text(
            'Size: ${w.toStringAsFixed(3)} × ${l.toStringAsFixed(3)} m',
            style: const TextStyle(fontSize: 12),
          ),
        if (h > 0)
          Text(
            'Height: ${h.toStringAsFixed(3)} m',
            style: const TextStyle(fontSize: 12),
          ),
        if (concVol > 0)
          Text(
            'Concrete: ${concVol.toStringAsFixed(3)} m³',
            style: const TextStyle(fontSize: 12),
          ),
        if (formArea > 0)
          Text(
            'Formwork (4 sides): ${formArea.toStringAsFixed(3)} m²',
            style: const TextStyle(fontSize: 12),
          ),
        if (rebarKg > 0)
          Text(
            'Existing rebar: ${rebarKg.toStringAsFixed(2)} kg',
            style: const TextStyle(fontSize: 12),
          ),
        if (rebarLenM > 0)
          Text(
            'Existing rebar length: ${rebarLenM.toStringAsFixed(2)} m',
            style: const TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  Widget _editGeometryBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Edit BOQ + Geometry',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: boqConcCtrl,
                decoration: const InputDecoration(
                  labelText: 'BOQ – Concrete',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: boqFwCtrl,
                decoration: const InputDecoration(
                  labelText: 'BOQ – Formwork',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widthCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Width (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: lengthCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Length (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: heightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Height (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: colNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Column name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                controller: colQtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Column qty',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}), // update totals live
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        const Text(
          'Note: Concrete = W×L×H, Formwork = 2(W+L)×H (4 sides).',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _addMainBarsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add main rebars (pending)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mainMarkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mark (e.g. 8Y16)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: mainBoqCtrl,
                decoration: const InputDecoration(
                  labelText: 'BOQ code',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mainEmbedCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Embed each end (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: mainExtraCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Extra (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: mainNoteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : _addPendingMain,
            icon: const Icon(Icons.add),
            label: const Text('Add main bars'),
          ),
        ),
      ],
    );
  }

  void _addPendingMain() {
    setState(() => err = null);

    final raw = mainMarkCtrl.text.trim();
    final boq = mainBoqCtrl.text.trim();
    if (raw.isEmpty || boq.isEmpty) {
      setState(() => err = 'Main rebars: Enter mark and BOQ code.');
      return;
    }

    final h = double.tryParse(heightCtrl.text.trim()) ?? 0;
    if (h <= 0) {
      setState(() => err = 'Set column height first.');
      return;
    }

    final embed = double.tryParse(mainEmbedCtrl.text.trim()) ?? 0;
    final extra = double.tryParse(mainExtraCtrl.text.trim()) ?? 0;

    try {
      _parseMarkSimple(raw); // validate
    } catch (e) {
      setState(() => err = e.toString());
      return;
    }

    pendingMainBars.add(
      PendingMainBar(
        rawMark: raw,
        boqCode: boq,
        embedEachEndM: embed,
        extraM: extra,
        note: mainNoteCtrl.text.trim(),
      ),
    );

    mainMarkCtrl.clear();
    mainBoqCtrl.clear();
    mainNoteCtrl.clear();
    setState(() {});
  }

  Widget _addRingsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add rings/ties (pending)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ringLabelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (e.g. R10-150)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ringBoqCtrl,
                decoration: const InputDecoration(
                  labelText: 'BOQ code',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ringDiaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ø (mm)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ringSpacingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Spacing (mm) (or use Count)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ringCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Count override (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ringCoverCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cover (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ringHookCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Hook each (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ringNoteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : _addPendingRing,
            icon: const Icon(Icons.add),
            label: const Text('Add rings'),
          ),
        ),
      ],
    );
  }

  void _addPendingRing() {
    setState(() => err = null);

    final label = ringLabelCtrl.text.trim();
    final boq = ringBoqCtrl.text.trim();
    if (label.isEmpty || boq.isEmpty) {
      setState(() => err = 'Rings: Enter label and BOQ code.');
      return;
    }

    final w = double.tryParse(widthCtrl.text.trim()) ?? 0;
    final l = double.tryParse(lengthCtrl.text.trim()) ?? 0;
    final h = double.tryParse(heightCtrl.text.trim()) ?? 0;
    if (w <= 0 || l <= 0 || h <= 0) {
      setState(() => err = 'Set width/length/height first.');
      return;
    }

    final dia = int.tryParse(ringDiaCtrl.text.trim()) ?? 0;
    if (dia <= 0) {
      setState(() => err = 'Enter ring diameter.');
      return;
    }

    final spacingMm = int.tryParse(ringSpacingCtrl.text.trim()) ?? 0;
    final countOv = int.tryParse(ringCountCtrl.text.trim()) ?? 0;

    if (countOv <= 0 && spacingMm <= 0) {
      setState(() => err = 'Provide spacing or count override.');
      return;
    }

    pendingRings.add(
      PendingRing(
        rawLabel: label,
        boqCode: boq,
        diaMm: dia,
        spacingMm: spacingMm,
        countOverride: countOv,
        coverM: double.tryParse(ringCoverCtrl.text.trim()) ?? 0.05,
        hookM: double.tryParse(ringHookCtrl.text.trim()) ?? 0.10,
        note: ringNoteCtrl.text.trim(),
      ),
    );

    ringLabelCtrl.clear();
    ringBoqCtrl.clear();
    ringCountCtrl.clear();
    ringNoteCtrl.clear();
    setState(() {});
  }

  Widget _pendingListBlock() {
    if (pendingMainBars.isEmpty && pendingRings.isEmpty) {
      return const Text(
        'No pending items yet.',
        style: TextStyle(color: Colors.black54),
      );
    }

    double h = double.tryParse(heightCtrl.text.trim()) ?? 0;
    double w = double.tryParse(widthCtrl.text.trim()) ?? 0;
    double l = double.tryParse(lengthCtrl.text.trim()) ?? 0;

    double pendingKg = 0;

    // compute quick preview totals
    for (final p in pendingMainBars) {
      final mk = _parseMarkSimple(p.rawMark);
      final barLen = h + 2 * p.embedEachEndM + p.extraM;
      final totalLen = mk.qty * barLen;
      pendingKg += totalLen * _uw(mk.dia);
    }

    for (final r in pendingRings) {
      final cover = r.coverM;
      final bInner = (w - 2 * cover).clamp(0.0, double.infinity);
      final lInner = (l - 2 * cover).clamp(0.0, double.infinity);
      final perRing = 2 * (bInner + lInner) + 2 * r.hookM;

      int n = r.countOverride;
      if (n <= 0) {
        final spacingM = (r.spacingMm / 1000.0);
        n = (h / spacingM).ceil() + 1;
      }
      final totalLen = n * perRing;
      pendingKg += totalLen * _uw(r.diaMm);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending items (to be saved):  Rebar ~ ${pendingKg.toStringAsFixed(2)} kg',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        if (pendingMainBars.isNotEmpty) ...[
          const Text(
            'Main bars',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          ...pendingMainBars.map((p) {
            return ListTile(
              dense: true,
              title: Text('${p.rawMark}  (BOQ: ${p.boqCode})'),
              subtitle: Text(
                'embed=${p.embedEachEndM}m extra=${p.extraM}m ${p.note.isEmpty ? "" : "| ${p.note}"}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed:
                    saving
                        ? null
                        : () => setState(() => pendingMainBars.remove(p)),
              ),
            );
          }),
          const SizedBox(height: 10),
        ],

        if (pendingRings.isNotEmpty) ...[
          const Text(
            'Rings/Ties',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          ...pendingRings.map((r) {
            final s =
                r.countOverride > 0
                    ? 'count=${r.countOverride}'
                    : 'spacing=${r.spacingMm}mm';
            return ListTile(
              dense: true,
              title: Text(
                '${r.rawLabel} Ø${r.diaMm} ($s)  (BOQ: ${r.boqCode})',
              ),
              subtitle: Text(
                'cover=${r.coverM}m hook=${r.hookM}m ${r.note.isEmpty ? "" : "| ${r.note}"}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed:
                    saving
                        ? null
                        : () => setState(() => pendingRings.remove(r)),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _existingDocsList() {
    if (localDocs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Saved items',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: localDocs.length,
          separatorBuilder: (_, __) => const Divider(height: 10),
          itemBuilder: (_, i) {
            final d = localDocs[i];
            final m = d.data();
            final type = (m['type'] ?? '').toString();
            final boq = (m['boqCode'] ?? '').toString();
            final unit = (m['unit'] ?? '').toString();
            final v =
                (m['value'] is num) ? (m['value'] as num).toDouble() : 0.0;

            final canDelete =
                type == 'rebarColumnMain' ||
                type == 'rebarColumnRings' ||
                type == 'columnMainRebar' ||
                type == 'columnStirrups';
            return ListTile(
              dense: true,
              title: Text(
                type,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                '${v.toStringAsFixed(3)} $unit${boq.isEmpty ? "" : " (BOQ: $boq)"}',
              ),
              trailing:
                  canDelete
                      ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: saving ? null : () => _deleteExistingDoc(i),
                      )
                      : null,
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteExistingDoc(int index) async {
    final d = localDocs[index];
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete?'),
        content: const Text('Delete this rebar item?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => saving = true);
    try {
      await widget.measurementsRef.doc(d.id).delete();
      setState(() => localDocs.removeAt(index));
    } catch (e) {
      setState(() => err = 'Delete failed: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  Widget _actionsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          TextButton(
            onPressed: saving ? null : () => Get.back(),
            child: const Text('Close'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: saving ? null : _saveAll,
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAll() async {
    setState(() {
      saving = true;
      err = null;
    });

    try {
      final w = double.tryParse(widthCtrl.text.trim()) ?? 0;
      final l = double.tryParse(lengthCtrl.text.trim()) ?? 0;
      final h = double.tryParse(heightCtrl.text.trim()) ?? 0;
      if (w <= 0 || l <= 0 || h <= 0) {
        throw Exception('Width/Length/Height must be > 0');
      }

      final concBoq = boqConcCtrl.text.trim();
      final fwBoq = boqFwCtrl.text.trim();
      final qty = int.tryParse(colQtyCtrl.text.trim()) ?? 1;
      final columnName = colNameCtrl.text.trim();
      final columnQty = int.tryParse(colQtyCtrl.text.trim()) ?? 1;
      final buildingFactor =
          localDocs.isEmpty
              ? 1
              : _int(
                localDocs.first.data()['buildingFactor'],
                fallback: 1,
              ).clamp(1, 999999);
      final totalQty = columnQty * buildingFactor;

      // Update / upsert base docs: concrete + formwork
      final batch = FirebaseFirestore.instance.batch();

      // Find existing base docs
      DocumentReference<Map<String, dynamic>>? concRef;
      DocumentReference<Map<String, dynamic>>? fwRef;

      for (final d in localDocs) {
        final m = d.data();
        if (m['type'] == 'columnConcrete') {
          concRef = widget.measurementsRef.doc(d.id);
        }
        if (m['type'] == 'columnFormwork' ||
            m['type'] == 'columnSideFormwork' ||
            m['type'] == 'columnFormworkSides') {
          fwRef = widget.measurementsRef.doc(d.id);
        }
        final t = _str(m['type']);
        if (t == 'rebarColumnMain' || t == 'rebarColumnRings') {
          batch.update(widget.measurementsRef.doc(d.id), {
            'columnName': columnName,
            'columnQty': columnQty,
          });
        } else if (t == 'columnMainRebar') {
          final bars = _int(m['barsPerColumn'], fallback: 0);
          final dia = _int(m['diameterMm'], fallback: 0);
          final barLength =
              h +
              _num(m['embedTopM']) +
              _num(m['embedBotM']) +
              _num(m['extraM']);
          final lengthPerColumn = bars * barLength;
          final weightPerColumn = lengthPerColumn * _uw(dia);
          batch.update(widget.measurementsRef.doc(d.id), {
            'columnName': columnName,
            'qtyPerBuilding': columnQty,
            'totalQty': totalQty,
            'heightM': h,
            'barLengthM': barLength,
            'totalLengthPerColumnM': lengthPerColumn,
            'valuePerColumn': weightPerColumn,
            'valuePerBuilding': weightPerColumn * columnQty,
            'value': weightPerColumn * totalQty,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else if (t == 'columnStirrups') {
          final dia = _int(m['stirrupDiaMm'], fallback: 10);
          final spacing = _num(m['spacingM']);
          final cover = _num(m['coverM']);
          final hooks = _num(m['hookExtraM']);
          final oneLength =
              2 *
                  ((w - 2 * cover).clamp(0.0, double.infinity) +
                      (l - 2 * cover).clamp(0.0, double.infinity)) +
              hooks;
          final count = spacing > 0 ? (h / spacing).ceil() + 1 : 0;
          final lengthPerColumn = oneLength * count;
          final weightPerColumn = lengthPerColumn * _uw(dia);
          batch.update(widget.measurementsRef.doc(d.id), {
            'columnName': columnName,
            'qtyPerBuilding': columnQty,
            'totalQty': totalQty,
            'heightM': h,
            'planLengthUsedM': l,
            'planWidthUsedM': w,
            'stirrupCountPerColumn': count,
            'stirrupLenOneM': oneLength,
            'stirrupTotalLenPerColumnM': lengthPerColumn,
            'valuePerColumn': weightPerColumn,
            'valuePerBuilding': weightPerColumn * columnQty,
            'value': weightPerColumn * totalQty,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      final concVol = w * l * h;
      final fwArea = 2 * (w + l) * h;
      final concVolOne = w * l * h;
      final fwAreaOne = 2 * (w + l) * h;

      final concVolTotal = concVolOne * totalQty;
      final fwAreaTotal = fwAreaOne * totalQty;

      // Concrete doc
      concRef ??= widget.measurementsRef.doc();
      batch.set(concRef, {
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': widget.drawingId,
        'columnId': widget.columnId, // ✅ IMPORTANT for reopen
        'columnGroupId': widget.columnId,
        'columnName': columnName,
        'columnQty': columnQty,
        'qtyPerBuilding': columnQty,
        'buildingFactor': buildingFactor,
        'totalQty': totalQty,
        'type': 'columnConcrete',
        'measureType': 'compositecolumn',
        'unit': 'm3',
        'value': concVolTotal,
        'valuePerColumn': concVolOne,
        'widthM': w,
        'lengthM': l,
        'heightM': h,
        'boqCode': concBoq,
        'color': widget.currentColor.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Formwork doc
      fwRef ??= widget.measurementsRef.doc();
      batch.set(fwRef, {
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': widget.drawingId,
        'columnId': widget.columnId,
        'columnGroupId': widget.columnId,
        'type': 'columnSideFormwork',
        'measureType': 'compositecolumn',
        'unit': 'm2',
        // 'value': fwArea,
        'columnName': columnName,
        'columnQty': columnQty,
        'qtyPerBuilding': columnQty,
        'buildingFactor': buildingFactor,
        'totalQty': totalQty,
        'widthM': w,
        'lengthM': l,
        'heightM': h,
        'value': fwAreaTotal,
        'valuePerColumn': fwAreaOne,
        // 'widthM': w,
        // 'lengthM': l,
        // 'heightM': h,
        'boqCode': fwBoq,
        'color': widget.currentColor.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Pending main bars => new docs
      for (final p in pendingMainBars) {
        final mk = _parseMarkSimple(p.rawMark);
        final barLen = h + 2 * p.embedEachEndM + p.extraM;
        final totalLenPerCol = mk.qty * barLen;
        final totalLenAll = totalLenPerCol * qty;

        final uw = _uw(mk.dia);
        final totalKgPerCol = totalLenPerCol * uw;
        final totalKgAll = totalKgPerCol * qty;
        // final barLen = h + 2 * p.embedEachEndM + p.extraM;
        final totalLen = mk.qty * barLen;
        // final uw = _uw(mk.dia);
        final totalKg = totalLen * uw;

        final ref = widget.measurementsRef.doc();
        batch.set(ref, {
          'projectId': widget.projectId,
          'buildingId': widget.buildingId,
          'drawingId': widget.drawingId,
          'columnId': widget.columnId,
          'columnGroupId': widget.columnId,
          'type': 'rebarColumnMain',
          'measureType': 'compositecolumn',
          'unit': 'kg',
          'columnName': columnName,
          'columnQty': columnQty,

          'value': totalKgAll,
          'valuePerColumn': totalKgPerCol,

          'totalLengthM': totalLenAll,
          'totalLengthPerColumnM': totalLenPerCol,

          // 'columnName': colName,
          // 'columnQty': qty,

          // 'value': totalKgAll,
          // 'valuePerColumn': totalKgPerCol,

          // 'totalLengthM': totalLenAll,
          // 'totalLengthPerColumnM': totalLenPerCol,
          // 'value': totalKg,
          'rawMark': p.rawMark,
          'diameterMm': mk.dia,
          'barsCount': mk.qty,
          'heightM': h,
          'embedEachEndM': p.embedEachEndM,
          'extraLengthM': p.extraM,
          'barLengthM': barLen,
          // 'totalLengthM': totalLen,
          'unitWeightKgPerM': uw,
          'totalWeightKg': totalKg,
          'boqCode': p.boqCode,
          'note': p.note,
          'color': widget.currentColor.value,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Pending rings => new docs
      for (final r in pendingRings) {
        final bInner = (w - 2 * r.coverM).clamp(0.0, double.infinity);
        final lInner = (l - 2 * r.coverM).clamp(0.0, double.infinity);
        final perRing = 2 * (bInner + lInner) + 2 * r.hookM;

        int n = r.countOverride;
        if (n <= 0) {
          final spacingM = (r.spacingMm / 1000.0);
          n = (h / spacingM).ceil() + 1;
        }
        final uw = _uw(r.diaMm);
        final totalLenPerCol = n * perRing;
        final totalLenAll = totalLenPerCol * qty;

        final totalKgPerCol = totalLenPerCol * uw;
        final totalKgAll = totalKgPerCol * qty;
        final totalLen = n * perRing;

        final totalKg = totalLen * uw;

        final ref = widget.measurementsRef.doc();
        batch.set(ref, {
          'projectId': widget.projectId,
          'buildingId': widget.buildingId,
          'drawingId': widget.drawingId,
          'columnId': widget.columnId,
          'columnGroupId': widget.columnId,
          'type': 'rebarColumnRings',
          'measureType': 'compositecolumn',
          'unit': 'kg',
          'value': totalKgAll,
          'columnName': columnName,
          'columnQty': columnQty,
          'rawLabel': r.rawLabel,
          'diameterMm': r.diaMm,
          'spacingMm': r.spacingMm > 0 ? r.spacingMm : null,
          'count': n,
          'coverM': r.coverM,
          'hookM': r.hookM,
          'perimeterPerRingM': perRing,
          'totalKgPerCol': totalKgPerCol,
          'totalLenPerCol': totalLenPerCol,
          'totalLengthM': totalLenAll,
          'unitWeightKgPerM': uw,
          'totalWeightKg': totalKgAll,
          'boqCode': r.boqCode,
          'note': r.note,
          'color': widget.currentColor.value,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Refresh localDocs from Firestore so reopen shows
      final qs =
          await widget.measurementsRef
              .where('drawingId', isEqualTo: widget.drawingId)
              .where('measureType', isEqualTo: 'compositecolumn')
              .where('columnId', isEqualTo: widget.columnId)
              .get();

      await _reloadDocsFromFirestore();

      final docs = await _fetchColumnDocs();
      setState(() {
        localDocs = docs;
        pendingMainBars.clear();
        pendingRings.clear();
      });
      _prefillFromDocs(docs); // keep controllers in sync with saved data
      setState(() {});

      Get.snackbar('Saved', 'Column composite updated successfully.');
    } catch (e) {
      setState(() => err = 'Save failed: $e');
    } finally {
      setState(() => saving = false);
    }
  }
}
