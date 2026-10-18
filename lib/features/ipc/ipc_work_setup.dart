import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<Map<String, dynamic>?> showWorkIpcSetup(
  BuildContext context, {
  int nextNumber = 2,
  Set<int> usedNumbers = const {},
}) async {
  String ipcNumber = '$nextNumber';
  final form = GlobalKey<FormState>();
  final dates = <String, DateTime?>{
    'periodFrom': null,
    'periodTo': null,
    'submissionDate': null,
  };
  String amount = '';
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, refresh) => AlertDialog(
                title: const Text('Prepare new IPC'),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            initialValue: ipcNumber,
                            decoration: const InputDecoration(
                              labelText: 'IPC No.',
                              prefixIcon: Icon(Icons.numbers),
                              suffixIcon: Icon(Icons.edit_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => ipcNumber = value,
                            validator: (value) {
                              final number = int.tryParse((value ?? '').trim());
                              if (number == null || number < 1)
                                return 'Enter a positive whole number';
                              if (usedNumbers.contains(number))
                                return 'This IPC number is already in use';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Enter the application details, then add project BOQs or import an external Excel BOQ.',
                          ),
                          const SizedBox(height: 20),
                          for (final key in dates.keys)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: FormField<DateTime>(
                                validator: (_) {
                                  if (dates[key] == null)
                                    return 'Select a date';
                                  if (key == 'periodTo' &&
                                      dates['periodFrom'] != null &&
                                      dates[key]!.isBefore(
                                        dates['periodFrom']!,
                                      ))
                                    return 'End date must not precede start date';
                                  return null;
                                },
                                builder:
                                    (field) => InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              dates[key] ?? DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null && context.mounted)
                                          refresh(() {
                                            dates[key] = picked;
                                            field.didChange(picked);
                                          });
                                      },
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText:
                                              key == 'periodFrom'
                                                  ? 'Period From'
                                                  : key == 'periodTo'
                                                  ? 'Period To'
                                                  : 'Submission Date',
                                          errorText: field.errorText,
                                          prefixIcon: const Icon(
                                            Icons.calendar_month_outlined,
                                          ),
                                          border: const OutlineInputBorder(),
                                        ),
                                        child: Text(
                                          dates[key] == null
                                              ? 'Select date'
                                              : DateFormat(
                                                'dd MMM yyyy',
                                              ).format(dates[key]!),
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          TextFormField(
                            onChanged: (value) => amount = value,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount applied (TZS)',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final n = double.tryParse(
                                (value ?? '').replaceAll(',', ''),
                              );
                              return n == null || !n.isFinite || n < 0
                                  ? 'Enter a valid amount'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'This is the QS-entered application amount. The BOQ-calculated amount and deductions are retained separately for comparison.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      final value = double.parse(amount.replaceAll(',', ''));
                      Navigator.pop(context, {
                        'number': int.parse(ipcNumber.trim()),
                        for (final entry in dates.entries)
                          entry.key: Timestamp.fromDate(entry.value!),
                        'period':
                            '${DateFormat('dd MMM yyyy').format(dates['periodFrom']!)} – ${DateFormat('dd MMM yyyy').format(dates['periodTo']!)}',
                        'amountApplied': value,
                        'enteredAmountApplied': value,
                      });
                    },
                    child: const Text('Continue to BOQs'),
                  ),
                ],
              ),
        ),
  );
}
