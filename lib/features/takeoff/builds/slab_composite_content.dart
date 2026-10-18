import 'package:aqs/features/takeoff/builds/panel_selector.dart';
import 'package:aqs/features/takeoff/models/rebar_set.dart';
import 'package:flutter/material.dart';

Widget buildSlabCompositeContent({
  required StateSetter setStateDialog,
  required double areaM2,
  required double lengthM,
  required double widthM,
  required double perimeterM,

  required TextEditingController thicknessController,
  required TextEditingController edgeDepthController,

  required bool includeConcrete,
  required bool includeSoffit,
  required bool includeEdge,
  required bool includeRebar,

  required TextEditingController boqConcController,
  required TextEditingController boqSoffitController,
  required TextEditingController boqEdgeController,
  required TextEditingController boqRebarController,
  required TextEditingController markBoqController,

  required List<RebarSet> rebarSets,
  required TextEditingController markController,
  required TextEditingController embedController,
  required TextEditingController extraController,
  required String barDirection,
  required String? errorText,
  required int selectedEdgeCase,
  required ValueChanged<int> onEdgeCaseChanged,

  // 👇 NEW callbacks – must match what you pass from the controller
  required ValueChanged<bool> onToggleConcrete,
  required ValueChanged<bool> onToggleSoffit,
  required ValueChanged<bool> onToggleEdge,
  required ValueChanged<bool> onToggleRebar,
  required ValueChanged<String> onBarDirectionChanged,
  required VoidCallback onAddRebarSet,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // --- basic info ---
      Text(
        'Area: ${areaM2.toStringAsFixed(3)} m²  '
        'L ≈ ${lengthM.toStringAsFixed(3)} m, '
        'W ≈ ${widthM.toStringAsFixed(3)} m',
        style: const TextStyle(fontSize: 12),
      ),
      Text(
        'Perimeter ≈ ${perimeterM.toStringAsFixed(3)} m',
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 8),

      // --- thickness / edge depth ---
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: thicknessController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Slab thickness (m)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: edgeDepthController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Edge depth (m)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),

      // --- toggles + BOQ codes ---
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Include concrete', style: TextStyle(fontSize: 13)),
        value: includeConcrete,
        onChanged: (v) {
          if (v == null) return;
          onToggleConcrete(v);
        },
        dense: true,
      ),
      if (includeConcrete)
        Padding(
          padding: const EdgeInsets.only(left: 24.0, bottom: 6),
          child: TextField(
            controller: boqConcController,
            decoration: const InputDecoration(
              labelText: 'Concrete BOQ code',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),

      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Include soffit formwork',
          style: TextStyle(fontSize: 13),
        ),
        value: includeSoffit,
        onChanged: (v) {
          if (v == null) return;
          onToggleSoffit(v);
        },
        dense: true,
      ),
      if (includeSoffit)
        Padding(
          padding: const EdgeInsets.only(left: 24.0, bottom: 6),
          child: TextField(
            controller: boqSoffitController,
            decoration: const InputDecoration(
              labelText: 'Soffit formwork BOQ code',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),

      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Include edge formwork',
          style: TextStyle(fontSize: 13),
        ),
        value: includeEdge,
        onChanged: (v) {
          if (v == null) return;
          onToggleEdge(v);
        },
        dense: true,
      ),
      if (includeEdge) ...[
        Padding(
          padding: const EdgeInsets.only(left: 24.0, bottom: 6),
          child: TextField(
            controller: boqEdgeController,
            decoration: const InputDecoration(
              labelText: 'Edge formwork BOQ code',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Edge formwork depth (m):',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 90,
          child: TextField(
            controller: edgeDepthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '0.15',
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Edge pattern (free sides):',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 4),

        _EdgePatternGrid(
          selectedCase: selectedEdgeCase,
          onChanged: onEdgeCaseChanged,
        ),
      ],

      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Include rebar', style: TextStyle(fontSize: 13)),
        value: includeRebar,
        onChanged: (v) {
          if (v == null) return;
          onToggleRebar(v);
        },
        dense: true,
      ),

      if (includeRebar) ...[
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Row(
            children: [
              const Text('Bars along:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Length'),
                selected: barDirection == 'along length',
                onSelected: (_) => onBarDirectionChanged('along length'),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('Width'),
                selected: barDirection == 'along width',
                onSelected: (_) => onBarDirectionChanged('along width'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Column(
            children: [
              TextField(
                controller: markController,
                decoration: const InputDecoration(
                  labelText: 'Rebar mark (e.g. 38Y12-01-150B2)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: boqRebarController,
                decoration: const InputDecoration(
                  labelText: 'Rebar BOQ code (this mark only)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: embedController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Embed each end (m)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: extraController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Extra length (laps/hooks, m)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add rebar mark'),
                  onPressed: onAddRebarSet,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        if (rebarSets.isEmpty)
          const Text(
            'No rebar marks added yet.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          )
        else
          SizedBox(
            height: 140,
            child: ListView.builder(
              itemCount: rebarSets.length,
              itemBuilder: (ctx, i) {
                final s = rebarSets[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${s.rawMark} (${s.direction})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    'L/bar: ${s.barLengthM.toStringAsFixed(3)} m, '
                    'Total: ${s.totalLengthM!.toStringAsFixed(3)} m, '
                    'Wt: ${s.totalWeightKg!.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
      ],

      // You can add any other notes/summary here…
    ],
  );
}

class _EdgePatternGrid extends StatelessWidget {
  final int selectedCase;
  final ValueChanged<int> onChanged;

  const _EdgePatternGrid({
    Key? key,
    required this.selectedCase,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.2,
      children: List.generate(9, (i) {
        final caseNo = i + 1;
        final isSelected = caseNo == selectedCase;

        return InkWell(
          onTap: () => onChanged(caseNo),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade400,
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Center(
              child: Text(
                '$caseNo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.blue : Colors.black87,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
