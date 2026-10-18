import 'package:aqs/features/boq/dialogs/boq_picker_dialog.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// class BoqPick {
//   final String code; // resolvedBoqCode
//   final String description;

//   BoqPick({required this.code, required this.description});
// }

class CustomGetBoqCode extends StatelessWidget {
  const CustomGetBoqCode({
    super.key,
    required this.projectId,
    required this.buildingId,
    required this.code,
    required this.text,
  });

  final String projectId;
  final String buildingId;
  final String code;
  final String text;

  @override
  Widget build(BuildContext context) {
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
                          .snapshots();

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

    String? boqCode;
    return FilledButton.icon(
      icon: const Icon(Icons.add),
      label: Text(text),
      onPressed: () async {
        final boqRef = FirebaseFirestore.instance
            .collection('projects')
            .doc(projectId)
            .collection('buildings')
            .doc(buildingId)
            .collection('boq');

        final pick = await showBoqPickerDialog(
          context: context,
          boqRef: boqRef,
        );

        if (pick == null) return;

        boqCode = pick.code;
      },
    );
  }
}
