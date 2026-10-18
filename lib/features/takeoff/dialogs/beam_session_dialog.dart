import 'package:aqs/core/state/firestore_state.dart';
import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';
import 'package:aqs/features/utils/customs/custom_get_boq_code.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get_rx/get_rx.dart';

class BeamSessionDialog extends StatefulWidget {
  final String projectId;
  final String buildingId;
  const BeamSessionDialog({
    super.key,
    this.suggestedBeamType,
    required this.buildingId,
    required this.projectId,
  });

  final String? suggestedBeamType;

  @override
  State<BeamSessionDialog> createState() => _BeamSessionDialogState();
}

class _BeamSessionDialogState extends State<BeamSessionDialog> {
  @override
  Widget build(BuildContext context) {
    final beamTypeCtrl = TextEditingController(
      text: widget.suggestedBeamType ?? 'GB01',
    );
    final bCtrl = TextEditingController(text: '0.30'); // 300mm
    final hCtrl = TextEditingController(text: '0.45'); // 450mm

    // final concBoqCtrl = TextEditingController();
    // final sideBoqCtrl = TextEditingController();
    // final soffitBoqCtrl = TextEditingController();

    bool includeConcrete = true;
    bool includeSide = true;
    bool includeSoffit = true;
    bool isGroundBeam = false;

    bool isSaving = false;
    String? error;

    String? concBoq;
    String? sideBoq;
    String? soffitBoq;

    Future<BoqPick?> showBoqPickerDialog({
      required BuildContext context,
      required CollectionReference<Map<String, dynamic>> boqRef,
    }) async {
      return showDialog<BoqPick?>(
        context: context,
        builder: (ctx) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
              child: StatefulBuilder(
                builder: (ctx, setState) {
                  String q = '';

                  // Query BOQ once as stream
                  final stream =
                      boqRef
                          // Optional: if you have headings, filter out using your rowType:
                          // .where('rowType', isEqualTo: 'item')
                          .orderBy(
                            'order',
                          ) // if you have 'order'. Otherwise use resolvedBoqCode
                          // .orderBy('resolvedBoqCode')
                          .stateSnapshots();

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Select BOQ item',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search BOQ code / description',
                          ),
                          onChanged:
                              (v) => setState(() => q = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 12),

                        Expanded(
                          child: StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: stream,
                            builder: (ctx, snap) {
                              if (snap.hasError) {
                                return Center(
                                  child: Text('Failed: ${snap.error}'),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final docs = snap.data!.docs;

                              // Build list using ONLY the two fields you asked
                              final items =
                                  docs
                                      .map((d) {
                                        final data = d.data();
                                        final code =
                                            (data['resolvedBoqCode'] ?? '')
                                                .toString()
                                                .trim();
                                        final desc =
                                            (data['description'] ?? '')
                                                .toString()
                                                .trim();
                                        final unit =
                                            (data['unit'] ?? '')
                                                .toString()
                                                .trim();
                                        return BoqPick(
                                          code: code,
                                          description: desc,

                                          id: d.id,
                                        );
                                      })
                                      .where(
                                        (b) =>
                                            b.code.isNotEmpty &&
                                            b.description.isNotEmpty &&
                                            b.id.isNotEmpty,
                                      )
                                      .toList();

                              final filtered =
                                  q.isEmpty
                                      ? items
                                      : items.where((b) {
                                        return b.code.toLowerCase().contains(
                                              q,
                                            ) ||
                                            b.description
                                                .toLowerCase()
                                                .contains(q);
                                      }).toList();

                              if (filtered.isEmpty) {
                                return const Center(
                                  child: Text('No matching BOQ items'),
                                );
                              }

                              return ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder:
                                    (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final b = filtered[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(b.code),
                                    subtitle: Text(
                                      b.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => Navigator.pop(ctx, b),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    return StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> onSave() async {
          if (isSaving) return;

          final beamType = beamTypeCtrl.text.trim();
          final bM = double.tryParse(bCtrl.text.trim()) ?? 0;
          final hM = double.tryParse(hCtrl.text.trim()) ?? 0;

          // basic validation
          if (beamType.isEmpty) {
            setState(() => error = 'Beam type is required (e.g. GB01).');
            return;
          }
          if (bM <= 0 || hM <= 0) {
            setState(() => error = 'Beam width (b) and depth (h) must be > 0.');
            return;
          }

          // If a component is enabled, BOQ must be provided
          if (includeConcrete && concBoq == '') {
            setState(() => error = 'Concrete BOQ code is required.');
            return;
          }
          if (includeSide && sideBoq == '') {
            setState(() => error = 'Side formwork BOQ code is required.');
            return;
          }
          if (!isGroundBeam && includeSoffit && soffitBoq == '') {
            setState(() => error = 'Soffit formwork BOQ code is required.');
            return;
          }

          setState(() {
            error = null;
            isSaving = true;
          });

          // You can persist config here if you want (optional).
          // For now we just return config.

          final cfg = BeamSessionConfig(
            beamType: beamType,
            concreteBoqCode: concBoq ?? '',
            sideFormworkBoqCode: sideBoq ?? '',
            soffitFormworkBoqCode: soffitBoq ?? '',
            bM: bM,
            hM: hM,
            includeConcrete: includeConcrete,
            includeSideFormwork: includeSide,
            includeSoffitFormwork: includeSoffit,
            isGroundBeam: isGroundBeam,
          );

          // ✅ IMPORTANT: pop using ctx/context, NOT "_"
          Navigator.pop(ctx, cfg);
        }

        return AlertDialog(
          title: const Text('Start Beam Session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: beamTypeCtrl,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Beam type/name',
                    hintText: 'GB01',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: bCtrl,
                        enabled: !isSaving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Width b (m)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: hCtrl,
                        enabled: !isSaving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Depth h (m)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                SwitchListTile(
                  value: isGroundBeam,
                  onChanged:
                      isSaving ? null : (v) => setState(() => isGroundBeam = v),
                  title: const Text('Ground beam (no soffit formwork)'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),

                const Divider(),

                CheckboxListTile(
                  value: includeConcrete,
                  onChanged:
                      isSaving
                          ? null
                          : (v) => setState(() => includeConcrete = v ?? true),
                  title: const Text('Include concrete'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (includeConcrete) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Add Concrete BOQ code'),
                    onPressed: () async {
                      final boqRef = FirebaseFirestore.instance
                          .collection('projects')
                          .doc(widget.projectId)
                          .collection('buildings')
                          .doc(widget.buildingId)
                          .collection('boq');

                      final pick = await showBoqPickerDialog(
                        context: context,
                        boqRef: boqRef,
                      );

                      if (pick == null) return;
                      setState(() => concBoq = pick.code);
                    },
                  ),
                  // CustomGetBoqCode(
                  //   projectId: widget.projectId,
                  //   buildingId: widget.buildingId,
                  //   code: concBoq.value,
                  //   text: 'Add Concrete BOQ code',
                  // ),
                  Text(concBoq ?? 'No code'),
                ],
                // TextField(
                //   controller: concBoqCtrl,
                //   enabled: !isSaving,
                //   decoration: const InputDecoration(
                //     labelText: 'Concrete BOQ code',
                //     border: OutlineInputBorder(),
                //   ),
                // ),
                const SizedBox(height: 10),

                CheckboxListTile(
                  value: includeSide,
                  onChanged:
                      isSaving
                          ? null
                          : (v) => setState(() => includeSide = v ?? true),
                  title: const Text('Include side formwork'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (includeSide) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Add Side formwork BOQ code'),
                    onPressed: () async {
                      final boqRef = FirebaseFirestore.instance
                          .collection('projects')
                          .doc(widget.projectId)
                          .collection('buildings')
                          .doc(widget.buildingId)
                          .collection('boq');

                      final pick = await showBoqPickerDialog(
                        context: context,
                        boqRef: boqRef,
                      );

                      if (pick == null) return;
                      setState(() => sideBoq = pick.code);
                    },
                  ),
                  Text(sideBoq ?? 'No code'),
                ],

                const SizedBox(height: 10),

                CheckboxListTile(
                  value: includeSoffit,
                  onChanged:
                      isSaving
                          ? null
                          : (v) => setState(() => includeSoffit = v ?? true),
                  title: const Text('Include soffit formwork'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!isGroundBeam && includeSoffit) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Add Side formwork BOQ code'),
                    onPressed: () async {
                      final boqRef = FirebaseFirestore.instance
                          .collection('projects')
                          .doc(widget.projectId)
                          .collection('buildings')
                          .doc(widget.buildingId)
                          .collection('boq');

                      final pick = await showBoqPickerDialog(
                        context: context,
                        boqRef: boqRef,
                      );

                      if (pick == null) return;
                      setState(() => sideBoq = pick.code);
                    },
                  ),
                  // FilledButton.icon(
                  //   icon: const Icon(Icons.add),
                  //   label: Text('Add Soffit formwork BOQ code'),
                  //   onPressed: () async {
                  //     final boqRef = FirebaseFirestore.instance
                  //         .collection('projects')
                  //         .doc(widget.projectId)
                  //         .collection('buildings')
                  //         .doc(widget.buildingId)
                  //         .collection('boq');

                  //     final pick = await showBoqPickerDialog(
                  //       context: context,
                  //       boqRef: boqRef,
                  //     );

                  //     if (pick == null) return;
                  //     setState(() => soffitBoq = pick.code);
                  //   },
                  // ),
                  // CustomGetBoqCode(
                  //   projectId: widget.projectId,
                  //   buildingId: widget.buildingId,
                  //   code: soffitBoq,
                  //   text: 'Add Soffit formwork BOQ code',
                  // ),
                  Text(soffitBoq ?? 'No code'),
                ],

                // TextField(
                //   controller: soffitBoqCtrl,
                //   enabled: !isSaving,
                //   decoration: const InputDecoration(
                //     labelText: 'Soffit formwork BOQ code',
                //     border: OutlineInputBorder(),
                //   ),
                // ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],

                if (isSaving) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Saving...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving ? null : onSave,
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
  }
}
