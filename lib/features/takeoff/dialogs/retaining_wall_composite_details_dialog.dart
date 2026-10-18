import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PendingWallRebarSet {
  PendingWallRebarSet({
    required this.direction, // 'vertical' | 'horizontal'
    required this.diaMm,
    required this.boqCode,
    this.spacingMm = 0,
    this.qtyOverride = 0,
    this.embedM = 0.30,
    this.extraM = 0.00,
    this.note = '',
  });

  final String direction;
  final int diaMm;
  final String boqCode;

  /// Provide either spacing OR qtyOverride
  final int spacingMm;
  final int qtyOverride;

  final double embedM;
  final double extraM;
  final String note;
}

class RetainingWallCompositeDetailsDialog extends StatefulWidget {
  const RetainingWallCompositeDetailsDialog({
    super.key,
    required this.wallId,
    required this.initialDocs,
    // required this.initialDocs,
    required this.measurementsRef,
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.currentColor,
    required this.drawingData,
    required this.activeSegmentDocId,
  });

  final String wallId;

  /// All line-segment docs in this group
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs;

  /// Existing composite docs (concrete/formwork/rebar)
  // final List<QueryDocumentSnapshot<Map<String, dynamic>>> initialDocs;

  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String projectId;
  final String buildingId;
  final String drawingId;
  final Color currentColor;
  final Map<String, dynamic> drawingData;
  final String activeSegmentDocId;

  @override
  State<RetainingWallCompositeDetailsDialog> createState() =>
      _RetainingWallCompositeDetailsDialogState();
}

class _RetainingWallCompositeDetailsDialogState
    extends State<RetainingWallCompositeDetailsDialog> {
  // base inputs
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');

  final heightCtrl = TextEditingController(text: '3.00');
  final thicknessCtrl = TextEditingController(text: '0.25');

  final boqConcCtrl = TextEditingController();
  final boqFwCtrl = TextEditingController();
  final boqRebarCtrl = TextEditingController(); // optional default

  final extendCtrl = TextEditingController(text: '0.50'); // meters
  final rotateCtrl = TextEditingController(text: '5'); // degrees

  int faces = 1; // 1 or 2

  // add rebar set inputs
  String dir = 'vertical';
  final diaCtrl = TextEditingController(text: '16');
  final spacingCtrl = TextEditingController(text: '200');
  final qtyOverrideCtrl = TextEditingController(); // optional
  final embedCtrl = TextEditingController(text: '0.30');
  final extraCtrl = TextEditingController(text: '0.00');
  final setBoqCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  // state
  bool saving = false;
  String? err;

  late List<DocumentSnapshot<Map<String, dynamic>>> localDocs;
  final pendingSets = <PendingWallRebarSet>[];

  String? activeSegId;
  Offset? p1Px;
  Offset? p2Px;

  late List<QueryDocumentSnapshot<Map<String, dynamic>>> localSegDocs;

  double get _ppu =>
      (widget.drawingData['pixelsPerUnit'] ??
              widget.drawingData['pxPerMeter'] ??
              0)
          .toDouble();

  @override
  void initState() {
    // super.initState();
    super.initState();
    localDocs = List<DocumentSnapshot<Map<String, dynamic>>>.of(
      widget.initialDocs,
    );

    // localSegDocs = List.of(widget.segmentDocs);

    // activeSegId = widget.activeSegmentDocId;
    _loadActiveSegmentPoints();
    Map<String, dynamic>? _data(DocumentSnapshot<Map<String, dynamic>> d) =>
        d.data();

    // Prefill from existing docs if any
    for (final d in localDocs) {
      final m = _data(d);
      if (m == null) continue;
      final t = (m['type'] ?? '').toString();

      if (nameCtrl.text.trim().isEmpty) {
        final n = (m['wallName'] ?? '').toString().trim();
        if (n.isNotEmpty) nameCtrl.text = n;
      }
      if (qtyCtrl.text.trim().isEmpty || qtyCtrl.text.trim() == '1') {
        final q = (m['sides'] as num?)?.toInt() ?? 1;
        qtyCtrl.text = '$q';
      }

      final h = _num(m['heightM']);
      final th = _num(m['thicknessM']);
      if (h > 0) heightCtrl.text = h.toStringAsFixed(2);
      if (th > 0) thicknessCtrl.text = th.toStringAsFixed(3);

      final f = (m['fases'] as num?)?.toInt();
      if (f == 1 || f == 2) faces = f!;

      if (t == 'retainingWallConcrete') {
        if (boqConcCtrl.text.trim().isEmpty) {
          boqConcCtrl.text = (m['boqCode'] ?? '').toString();
        }
      }
      if (t == 'retainingWallFormwork') {
        if (boqFwCtrl.text.trim().isEmpty) {
          boqFwCtrl.text = (m['boqCode'] ?? '').toString();
        }
      }
      if (t == 'rebarRetainingWall') {
        if (boqRebarCtrl.text.trim().isEmpty) {
          boqRebarCtrl.text = (m['boqCode'] ?? '').toString();
        }
      }
    }

    if (nameCtrl.text.trim().isEmpty) {
      nameCtrl.text = 'Retaining Wall';
    }
  }

  void _loadActiveSegmentPoints() {
    final d = widget.initialDocs.firstWhereOrNull((e) => e.id == activeSegId);
    if (d == null) return;

    final m = d.data();
    final p1m = (m['p1'] ?? const {}) as Map<String, dynamic>;
    final p2m = (m['p2'] ?? const {}) as Map<String, dynamic>;

    if (p1m.isNotEmpty && p2m.isNotEmpty) {
      p1Px = Offset((p1m['x'] ?? 0).toDouble(), (p1m['y'] ?? 0).toDouble());
      p2Px = Offset((p2m['x'] ?? 0).toDouble(), (p2m['y'] ?? 0).toDouble());
    }
  }

  Offset _rotatePoint(Offset p, Offset c, double a) {
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    final ca = math.cos(a);
    final sa = math.sin(a);
    return Offset(c.dx + dx * ca - dy * sa, c.dy + dx * sa + dy * ca);
  }

  void _applyExtendMeters(double dm) {
    final ppu = _ppu;
    if (ppu <= 0) {
      setState(() => err = 'Drawing not calibrated (pixelsPerUnit missing).');
      return;
    }
    if (p1Px == null || p2Px == null) return;

    final v = p2Px! - p1Px!;
    final len = v.distance;
    if (len <= 0) return;

    final dir = Offset(v.dx / len, v.dy / len);
    final deltaPx = dm * ppu;

    setState(() {
      p2Px = p2Px! + dir * deltaPx; // extend at end-2
    });
  }

  void _applyRotateDeg(double deg) {
    if (p1Px == null || p2Px == null) return;
    final a = deg * math.pi / 180.0;
    final mid = Offset((p1Px!.dx + p2Px!.dx) / 2, (p1Px!.dy + p2Px!.dy) / 2);

    setState(() {
      p1Px = _rotatePoint(p1Px!, mid, a);
      p2Px = _rotatePoint(p2Px!, mid, a);
    });
  }

  double _segmentLengthMFromPoints(Offset a, Offset b) {
    final ppu = _ppu;
    if (ppu <= 0) return 0.0;
    return (b - a).distance / ppu;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    heightCtrl.dispose();
    thicknessCtrl.dispose();
    boqConcCtrl.dispose();
    boqFwCtrl.dispose();
    boqRebarCtrl.dispose();

    diaCtrl.dispose();
    spacingCtrl.dispose();
    qtyOverrideCtrl.dispose();
    embedCtrl.dispose();
    extraCtrl.dispose();
    setBoqCtrl.dispose();
    noteCtrl.dispose();

    extendCtrl.dispose();
    rotateCtrl.dispose();
    super.dispose();
  }

  double _num(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  double _uw(int diaMm) => 0.00617 * diaMm * diaMm;

  double _sumLengthFromSegments() {
    double L = 0.0;
    for (final d in widget.initialDocs) {
      final m = d.data();
      L += _num(m['baseLengthM'] ?? m['totalLengthM'] ?? m['lengthM']);
    }
    return L;
  }

  int _qty() {
    final q = int.tryParse(qtyCtrl.text.trim()) ?? 1;
    return q <= 0 ? 1 : q;
  }

  double _height() => double.tryParse(heightCtrl.text.trim()) ?? 0.0;
  double _thickness() => double.tryParse(thicknessCtrl.text.trim()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final L = _sumLengthFromSegments();
    final H = _height();
    final t = _thickness();
    final q = _qty();

    final concM3 = (L > 0 && H > 0 && t > 0) ? (L * H * t * q) : 0.0;
    final fwM2 = (L > 0 && H > 0) ? (faces * L * H * q) : 0.0;

    // existing rebar kg
    double existingKg = 0.0;
    for (final d in localDocs) {
      final m = d.data();
      // print(m);
      if (m == null) continue;
      if ((m['type'] ?? '') == 'rebarRetainingWall') {
        existingKg += _num(m['totalWeightKg'] ?? m['value']);
      }
    }

    // pending preview
    final pendingKg = _computePendingKg(L: L, H: H) * q;
    // print(widget.activeSegmentDocId);
    // print(widget.initialDocs);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Column(
          children: [
            _header(),
            if (saving) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryBlock(L, concM3, fwM2, existingKg, pendingKg),
                    const Divider(height: 22),
                    _segmentEditBlock(),
                    const Divider(height: 22),
                    _baseInputsBlock(),
                    const Divider(height: 22),
                    _addRebarSetBlock(),
                    const Divider(height: 22),
                    _pendingSetsBlock(),
                    const Divider(height: 22),
                    _existingDocsBlock(),
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
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.view_quilt, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Composite Retaining Wall – ${nameCtrl.text.trim()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh from Firestore',
            onPressed: saving ? null : _reloadDocs,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: saving ? null : () => Get.back(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _summaryBlock(
    double L,
    double concM3,
    double fwM2,
    double existingKg,
    double pendingKg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wall ID: ${widget.wallId}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text('Total length (from segments): ${L.toStringAsFixed(3)} m'),
        Text('Qty: ${_qty()}'),
        Text('Faces (formwork): $faces'),
        const SizedBox(height: 6),
        Text('Concrete: ${concM3.toStringAsFixed(3)} m³'),
        Text('Formwork: ${fwM2.toStringAsFixed(3)} m²'),
        if (existingKg > 0)
          Text('Existing rebar: ${existingKg.toStringAsFixed(2)} kg'),
        if (pendingKg > 0)
          Text('Pending rebar: ${pendingKg.toStringAsFixed(2)} kg'),
      ],
    );
  }

  Widget _segmentEditBlock() {
    final hasPts = p1Px != null && p2Px != null;
    final Lseg = hasPts ? _segmentLengthMFromPoints(p1Px!, p2Px!) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Segment edit (active line)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text('Active segment: ${activeSegId ?? "-"}'),
        Text('Segment length: ${Lseg.toStringAsFixed(3)} m'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: extendCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Extend (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  saving || !hasPts
                      ? null
                      : () {
                        final dm = double.tryParse(extendCtrl.text.trim()) ?? 0;
                        if (dm != 0) _applyExtendMeters(dm);
                      },
              child: const Text('Apply'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: rotateCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rotate (deg)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  saving || !hasPts
                      ? null
                      : () {
                        final dg = double.tryParse(rotateCtrl.text.trim()) ?? 0;
                        if (dg != 0) _applyRotateDeg(dg);
                      },
              child: const Text('Apply'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Note: geometry changes will be saved to the active segment when you press "Save changes".',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _baseInputsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Base inputs + BOQ',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Wall name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: heightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Height H (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: thicknessCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Thickness t (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: faces,
                decoration: const InputDecoration(
                  labelText: 'Formwork faces',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 face')),
                  DropdownMenuItem(value: 2, child: Text('2 faces')),
                ],
                onChanged:
                    saving ? null : (v) => setState(() => faces = v ?? 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
        TextField(
          controller: boqRebarCtrl,
          decoration: const InputDecoration(
            labelText: 'Default BOQ – Rebar (optional)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _addRebarSetBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add rebar set (pending)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: dir,
                decoration: const InputDecoration(
                  labelText: 'Direction',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'vertical',
                    child: Text('Vertical bars'),
                  ),
                  DropdownMenuItem(
                    value: 'horizontal',
                    child: Text('Horizontal bars'),
                  ),
                ],
                onChanged:
                    saving
                        ? null
                        : (v) => setState(() => dir = v ?? 'vertical'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: diaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ø (mm)',
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
                controller: spacingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Spacing (mm) (or use Qty override)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: qtyOverrideCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Qty override (optional)',
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
                controller: embedCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Embed/anchorage each end (m)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: extraCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Extra / laps (m)',
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
                controller: setBoqCtrl,
                decoration: const InputDecoration(
                  labelText: 'BOQ for this set (leave empty to use default)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        TextField(
          controller: noteCtrl,
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
            onPressed: saving ? null : _addPendingSet,
            icon: const Icon(Icons.add),
            label: const Text('Add rebar set'),
          ),
        ),
      ],
    );
  }

  void _addPendingSet() {
    setState(() => err = null);

    final dia = int.tryParse(diaCtrl.text.trim()) ?? 0;
    if (dia <= 0) {
      setState(() => err = 'Enter diameter (mm).');
      return;
    }

    final spacing = int.tryParse(spacingCtrl.text.trim()) ?? 0;
    final qtyOv = int.tryParse(qtyOverrideCtrl.text.trim()) ?? 0;

    if (qtyOv <= 0 && spacing <= 0) {
      setState(() => err = 'Provide spacing OR qty override.');
      return;
    }

    final boq =
        (setBoqCtrl.text.trim().isNotEmpty
            ? setBoqCtrl.text.trim()
            : boqRebarCtrl.text.trim());

    if (boq.isEmpty) {
      setState(() => err = 'Provide BOQ for rebar (default or set BOQ).');
      return;
    }

    final embed = double.tryParse(embedCtrl.text.trim()) ?? 0.30;
    final extra = double.tryParse(extraCtrl.text.trim()) ?? 0.00;

    pendingSets.add(
      PendingWallRebarSet(
        direction: dir,
        diaMm: dia,
        boqCode: boq,
        spacingMm: spacing,
        qtyOverride: qtyOv,
        embedM: embed,
        extraM: extra,
        note: noteCtrl.text.trim(),
      ),
    );

    // reset small inputs
    qtyOverrideCtrl.clear();
    noteCtrl.clear();
    setState(() {});
  }

  double _computePendingKg({required double L, required double H}) {
    if (pendingSets.isEmpty) return 0.0;

    double total = 0.0;
    for (final s in pendingSets) {
      final uw = _uw(s.diaMm);

      // count
      int n = s.qtyOverride;
      if (n <= 0) {
        final spacingM = (s.spacingMm / 1000.0);
        if (spacingM > 0) {
          final span = (s.direction == 'vertical') ? L : H;
          n = (span / spacingM).ceil() + 1;
        } else {
          n = 0;
        }
      }

      // bar length
      final baseLen = (s.direction == 'vertical') ? H : L;
      final barLen = baseLen + 2 * s.embedM + s.extraM;

      final totalLen = n * barLen;
      total += totalLen * uw;
    }
    return total;
  }

  Widget _pendingSetsBlock() {
    if (pendingSets.isEmpty) {
      return const Text(
        'No pending rebar sets yet.',
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pending rebar sets',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ...pendingSets.map((s) {
          final mode =
              s.qtyOverride > 0
                  ? 'qty=${s.qtyOverride}'
                  : 'spacing=${s.spacingMm}mm';
          return ListTile(
            dense: true,
            title: Text('${s.direction} Ø${s.diaMm} ($mode)'),
            subtitle: Text(
              'BOQ: ${s.boqCode} | embed=${s.embedM}m extra=${s.extraM}m'
              '${s.note.isEmpty ? "" : " | ${s.note}"}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed:
                  saving ? null : () => setState(() => pendingSets.remove(s)),
            ),
          );
        }),
      ],
    );
  }

  Widget _existingDocsBlock() {
    if (localDocs.isEmpty) {
      return const Text(
        'No saved composite docs yet.',
        style: TextStyle(color: Colors.black54),
      );
    }

    // show only this wallId docs
    final filtered =
        localDocs.where((d) {
          final m = d.data();
          return (m!['wallGroupId'] ?? '').toString() == widget.wallId;
        }).toList();

    if (filtered.isEmpty) {
      return const Text(
        'No saved docs for this wallId in loaded list.',
        style: TextStyle(color: Colors.black54),
      );
    }

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
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (_, i) {
            final d = filtered[i];
            final m = d.data();
            final type = (m!['type'] ?? '').toString();
            final boq = (m['boqCode'] ?? '').toString();
            final unit = (m['unit'] ?? '').toString();
            final v = _num(m['value']);

            final canDelete = type == 'rebarRetainingWall';

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
                '${v.toStringAsFixed(3)} $unit'
                '${boq.isEmpty ? "" : " (BOQ: $boq)"}',
              ),
              trailing:
                  canDelete
                      ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: saving ? null : () => _deleteDoc(d),
                      )
                      : null,
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteDoc(DocumentSnapshot<Map<String, dynamic>> d) async {
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
      await _reloadDocs();
    } catch (e) {
      setState(() => err = 'Delete failed: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  Widget _actionsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          TextButton(
            onPressed: saving ? null : () => Get.back(),
            child: const Text('Close'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: saving ? null : _saveAll,
            icon: const Icon(Icons.save),
            label: const Text('Save changes'),
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

    // blocking progress dialog (optional)
    if (Get.isDialogOpen != true) {
      Get.dialog(
        const AlertDialog(
          content: SizedBox(
            height: 54,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Saving retaining wall...')),
              ],
            ),
          ),
        ),
        barrierDismissible: false,
      );
    }

    try {
      final L = _sumLengthFromSegments();
      final H = _height();
      final t = _thickness();
      final q = _qty();
      if (L <= 0 || H <= 0 || t <= 0) {
        throw Exception('Length/Height/Thickness must be > 0');
      }

      final wallName = nameCtrl.text.trim();
      final concBoq = boqConcCtrl.text.trim();
      final fwBoq = boqFwCtrl.text.trim();

      if (concBoq.isEmpty) throw Exception('BOQ – Concrete is required');
      if (fwBoq.isEmpty) throw Exception('BOQ – Formwork is required');

      final concM3 = L * H * t * q;
      final fwM2 = faces * L * H * q;

      final batch = FirebaseFirestore.instance.batch();

      // upsert concrete + formwork docs (find existing first)
      DocumentReference<Map<String, dynamic>>? concRef;
      DocumentReference<Map<String, dynamic>>? fwRef;

      for (final d in localDocs) {
        final m = d.data();
        if (m == null) continue;
        if ((m['wallGroupId'] ?? '').toString() != widget.wallId) continue;
        if (m['type'] == 'retainingWallConcrete') {
          concRef = widget.measurementsRef.doc(d.id);
        } else if (m['type'] == 'retainingWallFormwork') {
          fwRef = widget.measurementsRef.doc(d.id);
        }
      }

      final ppu = _ppu;
      if (ppu <= 0) {
        throw Exception('Drawing not calibrated (pixelsPerUnit missing).');
      }

      if (activeSegId != null && p1Px != null && p2Px != null) {
        final segRef = widget.measurementsRef.doc(activeSegId);
        final segLenM = _segmentLengthMFromPoints(p1Px!, p2Px!);

        batch.set(segRef, {
          'p1': {'x': p1Px!.dx, 'y': p1Px!.dy},
          'p2': {'x': p2Px!.dx, 'y': p2Px!.dy},
          'baseLengthM': segLenM,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      concRef ??= widget.measurementsRef.doc();
      fwRef ??= widget.measurementsRef.doc();

      final baseCommon = <String, dynamic>{
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': widget.drawingId,
        'measureType': 'compositeRetainingWall',
        'wallGroupId': widget.wallId,
        'wallName': wallName,
        'wallQty': q,
        'totalLengthM': L,
        'heightM': H,
        'thicknessM': t,
        'faces': faces,
        'color': widget.currentColor.value,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(concRef, {
        ...baseCommon,
        'type': 'retainingWallConcrete',
        'unit': 'm3',
        'value': concM3,
        'boqCode': concBoq,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(fwRef, {
        ...baseCommon,
        'type': 'retainingWallFormwork',
        'unit': 'm2',
        'value': fwM2,
        'boqCode': fwBoq,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // add pending rebar sets as new docs
      for (final s in pendingSets) {
        final uw = _uw(s.diaMm);

        int n = s.qtyOverride;
        if (n <= 0) {
          final spacingM = (s.spacingMm / 1000.0);
          final span = (s.direction == 'vertical') ? L : H;
          n = (span / spacingM).ceil() + 1;
        }

        final baseLen = (s.direction == 'vertical') ? H : L;
        final barLen = baseLen + 2 * s.embedM + s.extraM;
        final totalLen = n * barLen * q; // multiply by qty
        final totalKg = totalLen * uw;

        final ref = widget.measurementsRef.doc();
        batch.set(ref, {
          ...baseCommon,
          'type': 'rebarRetainingWall',
          'unit': 'kg',
          'value': totalKg,
          'totalWeightKg': totalKg,
          'totalLengthM': totalLen,
          'unitWeightKgPerM': uw,

          'direction': s.direction,
          'diameterMm': s.diaMm,
          'spacingMm': s.qtyOverride > 0 ? null : s.spacingMm,
          'barsCount': n,
          'embedEachEndM': s.embedM,
          'extraLengthM': s.extraM,
          'barLengthM': barLen,
          'boqCode': s.boqCode,
          'note': s.note,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      await _reloadSegments();
      await _reloadDocs();

      // refresh local docs so reopen shows everything (including rebars)
      // await _reloadSegments();

      setState(() {
        pendingSets.clear();
      });

      Get.snackbar('Saved', 'Retaining wall composite saved.');
    } catch (e) {
      setState(() => err = 'Save failed: $e');
      Get.snackbar('Error', 'Save failed: $e');
    } finally {
      // ✅ close progress dialog ALWAYS
      if (Get.isDialogOpen == true) {
        Get.back(); // closes the progress dialog
      }

      setState(() => saving = false);
    }
  }

  Future<void> _reloadDocs() async {
    try {
      final qs =
          await widget.measurementsRef
              .where('drawingId', isEqualTo: widget.drawingId)
              .where('measureType', isEqualTo: 'compositeretainingWall')
              .where('wallGroupId', isEqualTo: widget.wallId)
              .get();

      setState(() => localDocs = qs.docs);
    } catch (e) {
      setState(() => err = 'Reload failed: $e');
    }
  }

  Future<void> _reloadSegments() async {
    try {
      final qs =
          await widget.measurementsRef
              .where('drawingId', isEqualTo: widget.drawingId)
              .where('measureType', isEqualTo: 'compositerretainingWall')
              .where('wallGroupId', isEqualTo: widget.wallId)
              .get();

      setState(() => localDocs = qs.docs);
    } catch (e) {
      setState(() => err = 'Reload failed: $e');
    }

    // ⚠️ Hapa huwezi kubadili widget.segmentDocs (ni final).
    // Njia rahisi: usitumie widget.segmentDocs kwenye sum, tumia localSegments list.
  }
}
