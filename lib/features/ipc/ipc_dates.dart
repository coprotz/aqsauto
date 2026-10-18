import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<bool> editIpcDates(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> ref,
) async {
  final data = (await ref.get()).data() ?? {};
  if (!context.mounted) return false;
  DateTime? read(String key) =>
      data[key] is Timestamp ? (data[key] as Timestamp).toDate() : null;
  DateTime? from = read('periodFrom'),
      to = read('periodTo'),
      submitted = read('submissionDate') ?? read('submittedAt');
  String? error;
  bool saving = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder:
        (context) => StatefulBuilder(
          builder: (context, refresh) {
            Widget picker(
              String label,
              DateTime? value,
              void Function(DateTime) set,
            ) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  '$label: ${value == null ? 'Select date' : DateFormat('dd MMM yyyy').format(value)}',
                ),
                onPressed:
                    saving
                        ? null
                        : () async {
                          final chosen = await showDatePicker(
                            context: context,
                            initialDate: value ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (chosen != null && context.mounted)
                            refresh(() {
                              set(chosen);
                              error = null;
                            });
                        },
              ),
            );
            return AlertDialog(
              title: const Text('IPC period & submission date'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    picker('Period from', from, (d) => from = d),
                    picker('Period to', to, (d) => to = d),
                    picker('Submitted date', submitted, (d) => submitted = d),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      saving
                          ? null
                          : () async {
                            if (from == null ||
                                to == null ||
                                submitted == null) {
                              refresh(() => error = 'Select all three dates.');
                              return;
                            }
                            if (to!.isBefore(from!)) {
                              refresh(
                                () =>
                                    error =
                                        'Period end must be on or after the start.',
                              );
                              return;
                            }
                            refresh(() => saving = true);
                            try {
                              final problem = await FirebaseFirestore.instance
                                  .runTransaction<String?>((transaction) async {
                                    final current =
                                        (await transaction.get(ref)).data();
                                    if (current == null ||
                                        current['isDeleted'] == true)
                                      return 'IPC is no longer available.';
                                    for (final key in [
                                      'reviewedAt',
                                      'certifiedAt',
                                      'sentToEmployerAt',
                                      'paidAt',
                                    ]) {
                                      final later = current[key];
                                      if (later is Timestamp &&
                                          submitted!.isAfter(later.toDate()))
                                        return 'Submission cannot be after a completed status date.';
                                    }
                                    transaction.update(ref, {
                                      'periodFrom': Timestamp.fromDate(from!),
                                      'periodTo': Timestamp.fromDate(to!),
                                      'period':
                                          '${DateFormat('dd MMM yyyy').format(from!)} – ${DateFormat('dd MMM yyyy').format(to!)}',
                                      'submissionDate': Timestamp.fromDate(
                                        submitted!,
                                      ),
                                      if (current['submittedAt'] is Timestamp)
                                        'submittedAt': Timestamp.fromDate(
                                          submitted!,
                                        ),
                                      'datesUpdatedAt':
                                          FieldValue.serverTimestamp(),
                                    });
                                    return null;
                                  });
                              if (!context.mounted) return;
                              if (problem == null) {
                                Navigator.pop(context, true);
                              } else {
                                refresh(() {
                                  error = problem;
                                  saving = false;
                                });
                              }
                            } catch (_) {
                              if (context.mounted)
                                refresh(() {
                                  error = 'Could not save dates. Please retry.';
                                  saving = false;
                                });
                            }
                          },
                  child: Text(saving ? 'Saving…' : 'Save dates'),
                ),
              ],
            );
          },
        ),
  );
  return result == true;
}
