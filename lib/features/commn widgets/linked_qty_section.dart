import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/controllers/linked_qty_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LinkedQtySection extends StatelessWidget {
  final LinkedQtyController c;
  final Future<BoqPick?> Function() pickBoq;
  final String unitHint;

  // ✅ NEW: live preview from the current source qty
  final double? sourceValue;
  final String sourceUnit;

  const LinkedQtySection({
    super.key,
    required this.c,
    required this.pickBoq,
    required this.unitHint,
    required this.sourceValue,
    required this.sourceUnit,
  });

  double _parseNum(String s, double fallback) =>
      double.tryParse(s.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Linked items (auto-sync)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await pickBoq();
                  if (p == null) return;
                  c.addTarget(p);
                },
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Add BOQ'),
              ),
              const SizedBox(width: 8),
              if (c.targets.isNotEmpty)
                OutlinedButton(onPressed: c.clear, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'These items will always follow the source value (unit: $unitHint).',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),

          if (c.targets.isEmpty)
            const Text(
              'No linked BOQs selected.',
              style: TextStyle(fontSize: 12),
            )
          else
            ...List.generate(c.targets.length, (i) {
              final t = c.targets[i];
              final factorCtrl = TextEditingController(
                text: t.factor.toString(),
              );
              final offsetCtrl = TextEditingController(
                text: t.offset.toString(),
              );
              final src = sourceValue ?? 0.0;
              final derived = (src * t.factor) + t.offset;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${t.boq.code} — ${t.boq.description}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => c.removeAt(i),
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: factorCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                labelText: 'Factor (×)',
                              ),
                              onChanged:
                                  (v) => c.setFactor(i, _parseNum(v, 1.0)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: offsetCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                labelText: 'Offset (+)',
                              ),
                              onChanged:
                                  (v) => c.setOffset(i, _parseNum(v, 0.0)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Derived qty: ${derived.toStringAsFixed(3)} $sourceUnit',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Derived = Source × Factor + Offset',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Source qty: ${(sourceValue ?? 0).toStringAsFixed(3)} $sourceUnit',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );
    });
  }
}
