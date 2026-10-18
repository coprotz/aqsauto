import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

Future<List<BoqPick>> showBoqMultiPickerDialog({
  required BuildContext context,
  required List<BoqPick> allBoqs,
  String? unitFilter, // e.g. 'm2' to avoid wrong units
}) async {
  final selected = <String, BoqPick>{};
  final searchCtrl = TextEditingController();
  var query = '';

  List<BoqPick> baseList = allBoqs;
  if (unitFilter != null && unitFilter.trim().isNotEmpty) {
    // only if your BoqPick includes unit; otherwise skip filter here
    // baseList = baseList.where((b) => b.unit == unitFilter).toList();
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final filtered = filterBoqs(baseList, query);

          return AlertDialog(
            title: const Text('Add same qty to BOQs'),
            content: SizedBox(
              width: 650,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText:
                          'Search by description (e.g. ceiling covering)',
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final b = filtered[i];
                        final key = b.id.isNotEmpty ? b.id : b.code;
                        final checked = selected.containsKey(key);

                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                selected[key] = b;
                              } else {
                                selected.remove(key);
                              }
                            });
                          },
                          title: Text('${b.code}'),
                          subtitle: Text(
                            b.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use selected'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != true) return [];
  return selected.values.toList();
}
