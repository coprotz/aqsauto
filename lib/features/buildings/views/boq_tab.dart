import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BoqTab extends StatefulWidget {
  final String projectId;
  final String buildingId; // 👈 NEW

  const BoqTab({super.key, required this.projectId, required this.buildingId});

  @override
  State<BoqTab> createState() => _BoqTabState();
}

class _BoqTabState extends State<BoqTab> {
  late final CollectionReference<Map<String, dynamic>> _boqRef;
  late final CollectionReference<Map<String, dynamic>> _measRef;

  @override
  void initState() {
    super.initState();

    // 🔹 BOQ items now under the building
    _boqRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('buildings')
        .doc(widget.buildingId)
        .collection('boqItems');

    // 🔹 Measurements also under the same building
    _measRef = FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('buildings')
        .doc(widget.buildingId)
        .collection('measurements');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // header + add button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text('BOQ items', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showBoqItemDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add BOQ item'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // BOQ list + totals
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _boqRef.orderBy('order', descending: false).stateSnapshots(),
            builder: (ctx, boqSnap) {
              if (boqSnap.hasError) {
                return Center(
                  child: Text('Error loading BOQ items:\n${boqSnap.error}'),
                );
              }

              if (!boqSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final boqDocs = boqSnap.data!.docs;

              // If there are no BOQ items yet, show friendly message
              if (boqDocs.isEmpty) {
                return Center(
                  child: Text(
                    'No BOQ items yet.\nUse "Add BOQ item" to create one.',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              // Now load all measurements once and aggregate totals by boqCode
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _measRef.stateSnapshots(),
                    builder: (ctx, measSnap) {
                      final totalsByBoq = <String, double>{};
                      final countByBoq = <String, int>{};

                      if (measSnap.hasData) {
                        for (final d in measSnap.data!.docs) {
                          final m = d.data();
                          final boqCode = (m['boqCode'] ?? '') as String;
                          if (boqCode.isEmpty) continue;

                          final val = m['value'];
                          if (val == null) continue;

                          final q = (val as num).toDouble();
                          totalsByBoq[boqCode] =
                              (totalsByBoq[boqCode] ?? 0) + q;
                          countByBoq[boqCode] = (countByBoq[boqCode] ?? 0) + 1;
                        }
                      }

                      return ListView.separated(
                        itemCount: boqDocs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final doc = boqDocs[index];
                          final data = doc.data();

                          final code = (data['boqCode'] ?? '') as String;
                          final desc = (data['description'] ?? '') as String;
                          final unit = (data['unit'] ?? '') as String;
                          final rateNum = data['rate'];
                          final rate =
                              rateNum != null
                                  ? (rateNum as num).toDouble()
                                  : null;

                          final totalQty = totalsByBoq[code] ?? 0;
                          final count = countByBoq[code] ?? 0;
                          final amount =
                              (rate != null) ? totalQty * rate : null;

                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListTile(
                              dense: false,
                              title: Text(
                                '$code  -  $desc',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Qty: ${totalQty.toStringAsFixed(3)} $unit'
                                    '  (from $count measurements)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (rate != null)
                                    Text(
                                      'Rate: ${rate.toStringAsFixed(2)} per $unit',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (amount != null)
                                    Text(
                                      'Amount: ${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed:
                                    () => _showBoqItemDialog(
                                      existingId: doc.id,
                                      existingData: data,
                                    ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showBoqItemDialog({
    String? existingId,
    Map<String, dynamic>? existingData,
  }) async {
    final isEdit = existingId != null && existingData != null;

    // 1) Load existing structures + subheadings
    final existingStructures = <String>{};
    final existingSubheadingsByBill = <String, Set<String>>{};

    const Map<String, List<String>> kStandardSubheadingsByBill = {
      '3': [
        'Excavation works',
        'Backfills',
        'Disposal',
        'Hardcore',
        'Anti-termite treatment',
        'Concrete works',
        'DPM',
        'DPC',
        'Formwork',
        'Reinforcements',
      ],
      '4': ['Concrete works', 'Formworks', 'Reinforcements'],
      '5': ['Concrete works', 'Formworks', 'Reinforcements', 'Balustade'],
      '6': ['Concrete', 'Blockworks'],
      '7': ['Roof Coverings', 'Roof Structure'],
      '8': ['Frames', 'Doors', 'Iron Mongeries', 'Glass', 'Grills'],
      '9': ['Aluminium', 'Grills'],
      '10': [
        'Floor Finish',
        'Wall Finish',
        'Ceiling Finish',
        'Painting & Decoration',
      ],
    };

    try {
      final snap = await _boqRef.get();
      for (final d in snap.docs) {
        final data = d.data();
        final s = (data['structure'] ?? '') as String;
        if (s.trim().isNotEmpty) existingStructures.add(s.trim());

        final bCode = (data['billCode'] ?? '') as String;
        final sub = (data['subheading'] ?? '') as String;
        if (bCode.isNotEmpty && sub.trim().isNotEmpty) {
          existingSubheadingsByBill
              .putIfAbsent(bCode, () => <String>{})
              .add(sub.trim());
        }
      }
    } catch (e, st) {
      // ignore but log in debug
      // ignore: avoid_print
      print('Error pre-loading BOQ items: $e');
      // ignore: avoid_print
      print(st);
    }

    final structuresList = existingStructures.toList()..sort();

    // Standard Bill options
    const billOptions = <Map<String, String>>[
      {'boqCode': '1', 'label': 'Bill 1: Preliminaries & General'},
      {'boqCode': '2', 'label': 'Bill 2: Demolitions & Alterations'},
      {'boqCode': '3', 'label': 'Bill 3: Substructure'},
      {'boqCode': '4', 'label': 'Bill 4: Frame'},
      {'boqCode': '5', 'label': 'Bill 5: Stairs'},
      {'boqCode': '6', 'label': 'Bill 6: Walling'},
      {'boqCode': '7', 'label': 'Bill 7: Roofing'},
      {'boqCode': '8', 'label': 'Bill 8: Doors'},
      {'boqCode': '9', 'label': 'Bill 9: Windows'},
      {'boqCode': '10', 'label': 'Bill 10: Finishing'},
    ];

    // Units
    const unitOptions = <String>['m', 'm2', 'm3', 'kg', 'tonne', 'item', 'ps'];

    // --- initial values for edit / add ---
    final codeController = TextEditingController(
      text: existingData?['boqCode'] ?? '',
    );
    final descController = TextEditingController(
      text: existingData?['description'] ?? '',
    );
    final rateController = TextEditingController(
      text: existingData?['rate']?.toString() ?? '',
    );

    // Structure
    final existingStructureValue = (existingData?['structure'] ?? '') as String;
    const newStructureKey = '__NEW_STRUCTURE__';

    String? selectedStructure =
        existingStructureValue.isNotEmpty ? existingStructureValue : null;
    String newStructureName = '';

    // Bill
    final existingBillCode = (existingData?['billCode'] ?? '') as String;
    String selectedBillCode =
        billOptions.any((b) => b['boqCode'] == existingBillCode)
            ? existingBillCode
            : billOptions.first['boqCode']!;

    // Subheading
    final existingSubheading = (existingData?['subheading'] ?? '') as String;
    const newSubheadingKey = '__NEW_SUBHEADING__';
    String? selectedSubheading =
        existingSubheading.isNotEmpty ? existingSubheading : null;
    String newSubheadingName = '';

    // Unit
    String selectedUnit =
        (() {
          final raw = (existingData?['unit'] ?? '') as String;
          if (unitOptions.contains(raw)) return raw;
          return 'm';
        })();

    // local UI state inside the dialog
    bool isSaving = false;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            String displayUnit(String u) =>
                u == 'm2'
                    ? 'm²'
                    : u == 'm3'
                    ? 'm³'
                    : u;

            final selectedBill = billOptions.firstWhere(
              (b) => b['boqCode'] == selectedBillCode,
            );

            // Build subheading list for selected bill:
            final stdSubs =
                kStandardSubheadingsByBill[selectedBillCode] ?? const [];
            final usedSubs =
                existingSubheadingsByBill[selectedBillCode] ?? <String>{};

            final allSubOptions =
                <String>{...stdSubs, ...usedSubs}.toList()..sort();

            Future<void> handleSave() async {
              if (isSaving) return;

              final code = codeController.text.trim();
              if (code.isEmpty) {
                setStateDialog(() {
                  errorText = 'Item code is required.';
                });
                return;
              }

              final desc = descController.text.trim();
              final rateStr = rateController.text.trim();
              final rate = rateStr.isNotEmpty ? double.tryParse(rateStr) : null;

              // final structure name
              String structureName;
              if (selectedStructure != null) {
                structureName = selectedStructure!;
              } else {
                structureName = newStructureName.trim();
              }
              if (structureName.isEmpty) {
                setStateDialog(() {
                  errorText = 'Structure name is required.';
                });
                return;
              }

              // final subheading name
              String finalSubheading;
              if (selectedSubheading != null) {
                finalSubheading = selectedSubheading!;
              } else {
                finalSubheading = newSubheadingName.trim();
              }
              if (finalSubheading.isEmpty) {
                setStateDialog(() {
                  errorText = 'Subheading is required.';
                });
                return;
              }

              final bill = billOptions.firstWhere(
                (b) => b['boqCode'] == selectedBillCode,
              );
              final billCode = bill['boqCode']!;
              final billLabel = bill['label']!;

              final baseData = <String, dynamic>{
                'boqCode': code,
                'description': desc,
                'unit': selectedUnit,
                'rate': rate,
                'structure': structureName,
                'billCode': billCode,
                'billLabel': billLabel,
                'subheading': finalSubheading,
                'updatedAt': FieldValue.serverTimestamp(),
              };

              setStateDialog(() {
                isSaving = true;
                errorText = null;
              });

              try {
                if (isEdit) {
                  await _boqRef.doc(existingId!).update(baseData);
                } else {
                  await _boqRef.add({
                    ...baseData,
                    'order': DateTime.now().millisecondsSinceEpoch,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                // success → close dialog with true
                Navigator.pop(ctx, true);
              } catch (e, st) {
                // ignore: avoid_print
                print('Error saving BOQ item: $e');
                // ignore: avoid_print
                print(st);
                setStateDialog(() {
                  isSaving = false;
                  errorText = 'Failed to save BOQ item: $e';
                });
              }
            }

            return AlertDialog(
              title: Text(isEdit ? 'Edit BOQ item' : 'Add BOQ item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // STRUCTURE / BUILDING (inside this building; you can rename label later if you want)
                    const Text(
                      'Structure / building:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value:
                          selectedStructure ??
                          (structuresList.isNotEmpty
                              ? structuresList.first
                              : newStructureKey),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ...structuresList.map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s),
                          ),
                        ),
                        const DropdownMenuItem<String>(
                          value: newStructureKey,
                          child: Text('+ New building / structure...'),
                        ),
                      ],
                      onChanged:
                          isSaving
                              ? null
                              : (val) {
                                if (val == null) return;
                                setStateDialog(() {
                                  if (val == newStructureKey) {
                                    selectedStructure = null;
                                  } else {
                                    selectedStructure = val;
                                    newStructureName = '';
                                  }
                                });
                              },
                    ),
                    if (selectedStructure == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          enabled: !isSaving,
                          decoration: const InputDecoration(
                            labelText: 'New structure name',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. Toilet block, Food vendors',
                          ),
                          onChanged: (val) {
                            newStructureName = val;
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    // BILL NO.
                    const Text(
                      'Bill No.:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: selectedBillCode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items:
                          billOptions.map((b) {
                            return DropdownMenuItem<String>(
                              value: b['boqCode'],
                              child: Text(b['label']!),
                            );
                          }).toList(),
                      onChanged:
                          isSaving
                              ? null
                              : (val) {
                                if (val == null) return;
                                setStateDialog(() {
                                  selectedBillCode = val;
                                  // reset subheading selection when bill changes
                                  selectedSubheading = null;
                                  newSubheadingName = '';
                                });
                              },
                    ),

                    const SizedBox(height: 12),

                    // SUBHEADING
                    const Text(
                      'Subheading:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value:
                          selectedSubheading ??
                          (allSubOptions.isNotEmpty
                              ? allSubOptions.first
                              : newSubheadingKey),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ...allSubOptions.map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s),
                          ),
                        ),
                        const DropdownMenuItem<String>(
                          value: newSubheadingKey,
                          child: Text('+ New subheading...'),
                        ),
                      ],
                      onChanged:
                          isSaving
                              ? null
                              : (val) {
                                if (val == null) return;
                                setStateDialog(() {
                                  if (val == newSubheadingKey) {
                                    selectedSubheading = null;
                                  } else {
                                    selectedSubheading = val;
                                    newSubheadingName = '';
                                  }
                                });
                              },
                    ),
                    if (selectedSubheading == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          enabled: !isSaving,
                          decoration: const InputDecoration(
                            labelText: 'New subheading',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. Excavation works',
                          ),
                          onChanged: (val) {
                            newSubheadingName = val;
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    // ITEM CODE
                    TextField(
                      controller: codeController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Item code',
                        hintText: 'e.g. 3.9(ii)',
                      ),
                    ),
                    const SizedBox(height: 8),

                    // DESCRIPTION
                    TextField(
                      controller: descController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),

                    // UNIT
                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          unitOptions.map((u) {
                            return DropdownMenuItem<String>(
                              value: u,
                              child: Text(displayUnit(u)),
                            );
                          }).toList(),
                      onChanged:
                          isSaving
                              ? null
                              : (val) {
                                if (val == null) return;
                                setStateDialog(() {
                                  selectedUnit = val;
                                });
                              },
                    ),

                    const SizedBox(height: 8),

                    // RATE
                    TextField(
                      controller: rateController,
                      enabled: !isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Rate (optional)',
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (errorText != null)
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),

                    if (isSaving) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: const [
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
                  onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : handleSave,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    // If dialog was closed with success, show SnackBar
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'BOQ item updated successfully'
                : 'BOQ item created successfully',
          ),
        ),
      );
    }
  }
}
