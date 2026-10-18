import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BoqTemplatePage extends StatefulWidget {
  const BoqTemplatePage({
    super.key,
    required this.projectId,
    required this.facilityId,
    required this.templateId,
  });

  final String projectId;
  final String facilityId;
  final String templateId;

  @override
  State<BoqTemplatePage> createState() => _BoqTemplatePageState();
}

class _BoqTemplatePageState extends State<BoqTemplatePage> {
  String _search = '';

  final Set<String> _expandedBills = {};

  Stream<QuerySnapshot<Map<String, dynamic>>> _billsStream() {
    return FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('boqBills')
        .where('templateId', isEqualTo: widget.templateId)
        .orderBy('sortOrder')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _itemsStream() {
    return FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('boqItems')
        .where('templateId', isEqualTo: widget.templateId)
        .orderBy('sortOrder')
        .snapshots();
  }

  double _number(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatNumber(dynamic value, {int decimals = 2}) {
    if (value == null) {
      return '-';
    }

    final number = _number(value);

    final raw = number.toStringAsFixed(decimals);

    final parts = raw.split('.');

    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );

    if (decimals == 0) {
      return whole;
    }

    return '$whole.${parts.last}';
  }

  String _measurementTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'length':
        return 'Length';

      case 'area':
        return 'Area';

      case 'wall_area':
        return 'Wall';

      case 'volume':
        return 'Volume';

      case 'count':
        return 'Count';

      case 'weight':
        return 'Weight';

      case 'composite':
        return 'Composite';

      case 'manual':
        return 'Manual';

      case 'item':
        return 'Item';

      default:
        return 'Not Set';
    }
  }

  IconData _measurementIcon(String value) {
    switch (value.trim().toLowerCase()) {
      case 'length':
        return Icons.straighten_rounded;

      case 'area':
        return Icons.crop_square_rounded;

      case 'wall_area':
        return Icons.view_week_outlined;

      case 'volume':
        return Icons.view_in_ar_outlined;

      case 'count':
        return Icons.pin_outlined;

      case 'weight':
        return Icons.scale_outlined;

      case 'composite':
        return Icons.account_tree_outlined;

      default:
        return Icons.edit_note_rounded;
    }
  }

  Future<void> _updateMeasurementType({
    required String itemId,
    required String value,
  }) async {
    await FirebaseFirestore.instance
        .collection('projects')
        .doc(widget.projectId)
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('boqItems')
        .doc(itemId)
        .update({
          'measurementType': value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  void _startTakeoff({
    required String itemId,
    required Map<String, dynamic> item,
  }) {
    /*
     * STEP 5:
     *
     * We will navigate from here to:
     *
     * TakeoffWorkspacePage(
     *   projectId: widget.projectId,
     *   boqItemId: itemId,
     * )
     *
     * For now keep this visible so
     * we know the BOQ link is correct.
     */

    final description = (item['description'] ?? '').toString();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Take-off workspace for: $description')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,

      appBar: AppBar(
        title: const Text('BOQ Template'),
        actions: [
          TextButton.icon(
            onPressed: () {
              /*
               * Later:
               * export measured BOQ
               */
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export'),
          ),
          const SizedBox(width: 10),
        ],
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _billsStream(),
            builder: (context, billSnapshot) {
              if (billSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (billSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load BOQ bills: '
                    '${billSnapshot.error}',
                  ),
                );
              }

              final bills = billSnapshot.data?.docs ?? const [];

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _itemsStream(),
                builder: (context, itemSnapshot) {
                  if (itemSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (itemSnapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load BOQ items: '
                        '${itemSnapshot.error}',
                      ),
                    );
                  }

                  final items = itemSnapshot.data?.docs ?? const [];

                  return _buildContent(
                    context: context,
                    bills: bills,
                    items: items,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> bills,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  }) {
    final query = _search.trim().toLowerCase();

    var measuredItems = 0;
    var measurableItems = 0;

    for (final doc in items) {
      final data = doc.data();

      final isHeading = data['isHeading'] == true;

      if (isHeading) {
        continue;
      }

      measurableItems++;

      final measured = _number(data['measuredQuantity']);

      if (measured > 0) {
        measuredItems++;
      }
    }

    final progress =
        measurableItems == 0 ? 0.0 : measuredItems / measurableItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
      children: [
        const Text(
          'Project BOQ',
          style: TextStyle(
            color: AqsColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          'Review imported quantities and link each BOQ item directly to drawing take-off.',
          style: TextStyle(color: AqsColors.muted, height: 1.45),
        ),

        const SizedBox(height: 22),

        _BoqSummaryBar(
          billCount: bills.length,
          itemCount: measurableItems,
          measuredCount: measuredItems,
          progress: progress,
        ),

        const SizedBox(height: 20),

        _Toolbar(
          onSearchChanged: (value) {
            setState(() {
              _search = value;
            });
          },
          onExpandAll: () {
            setState(() {
              _expandedBills.addAll(bills.map((e) => e.id));
            });
          },
          onCollapseAll: () {
            setState(() {
              _expandedBills.clear();
            });
          },
        ),

        const SizedBox(height: 18),

        if (bills.isEmpty)
          const _EmptyBoq()
        else
          ...bills.map((bill) {
            final billData = bill.data();

            final billItems =
                items.where((doc) {
                  final data = doc.data();

                  if (data['billId']?.toString() != bill.id) {
                    return false;
                  }

                  if (query.isEmpty) {
                    return true;
                  }

                  final itemNo =
                      (data['itemNo'] ?? '').toString().toLowerCase();

                  final description =
                      (data['description'] ?? '').toString().toLowerCase();

                  return itemNo.contains(query) || description.contains(query);
                }).toList();

            if (query.isNotEmpty && billItems.isEmpty) {
              return const SizedBox.shrink();
            }

            final expanded =
                query.isNotEmpty || _expandedBills.contains(bill.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _BillCard(
                billId: bill.id,

                number: (billData['number'] ?? '').toString(),

                title: (billData['title'] ?? 'Bill').toString(),

                expanded: expanded,

                items: billItems,

                onToggle: () {
                  setState(() {
                    if (expanded) {
                      _expandedBills.remove(bill.id);
                    } else {
                      _expandedBills.add(bill.id);
                    }
                  });
                },

                numberReader: _number,

                numberFormatter: _formatNumber,

                measurementLabel: _measurementTypeLabel,

                measurementIcon: _measurementIcon,

                onMeasurementChanged: ({
                  required itemId,
                  required value,
                }) async {
                  await _updateMeasurementType(itemId: itemId, value: value);
                },

                onTakeoff: ({required itemId, required item}) {
                  _startTakeoff(itemId: itemId, item: item);
                },
              ),
            );
          }),
      ],
    );
  }
}

class _BoqSummaryBar extends StatelessWidget {
  const _BoqSummaryBar({
    required this.billCount,
    required this.itemCount,
    required this.measuredCount,
    required this.progress,
  });

  final int billCount;
  final int itemCount;
  final int measuredCount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percentage = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;

          final metrics = [
            _SummaryMetric(label: 'Bills', value: '$billCount'),
            _SummaryMetric(label: 'BOQ Items', value: '$itemCount'),
            _SummaryMetric(label: 'Measured', value: '$measuredCount'),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 18, children: metrics),
                const SizedBox(height: 20),
                _ProgressBlock(percentage: percentage, progress: progress),
              ],
            );
          }

          return Row(
            children: [
              ...metrics.expand(
                (metric) => [metric, const SizedBox(width: 34)],
              ),
              Expanded(
                child: _ProgressBlock(
                  percentage: percentage,
                  progress: progress,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.percentage, required this.progress});

  final int percentage;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Measurement progress',
                style: TextStyle(
                  color: Color(0xFFD0D5DD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percentage%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white.withOpacity(0.12),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onSearchChanged,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  final ValueChanged<String> onSearchChanged;

  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;

        final search = TextField(
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Search item or description...',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
          ),
        );

        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: onExpandAll,
              icon: const Icon(Icons.unfold_more_rounded),
              label: const Text('Expand'),
            ),
            TextButton.icon(
              onPressed: onCollapseAll,
              icon: const Icon(Icons.unfold_less_rounded),
              label: const Text('Collapse'),
            ),
          ],
        );

        if (compact) {
          return Column(
            children: [
              search,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: buttons),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 14),
            buttons,
          ],
        );
      },
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.billId,
    required this.number,
    required this.title,
    required this.expanded,
    required this.items,
    required this.onToggle,
    required this.numberReader,
    required this.numberFormatter,
    required this.measurementLabel,
    required this.measurementIcon,
    required this.onMeasurementChanged,
    required this.onTakeoff,
  });

  final String billId;
  final String number;
  final String title;
  final bool expanded;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;

  final VoidCallback onToggle;

  final double Function(dynamic) numberReader;

  final String Function(dynamic, {int decimals}) numberFormatter;

  final String Function(String) measurementLabel;

  final IconData Function(String) measurementIcon;

  final Future<void> Function({required String itemId, required String value})
  onMeasurementChanged;

  final void Function({
    required String itemId,
    required Map<String, dynamic> item,
  })
  onTakeoff;

  @override
  Widget build(BuildContext context) {
    final measuredCount =
        items.where((doc) {
          final data = doc.data();

          if (data['isHeading'] == true) {
            return false;
          }

          return numberReader(data['measuredQuantity']) > 0;
        }).length;

    final measurableCount =
        items.where((doc) => doc.data()['isHeading'] != true).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AqsColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.menu_book_outlined,
                      color: AqsColors.primary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          number.isEmpty ? title : 'Bill $number — $title',
                          style: const TextStyle(
                            color: AqsColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$measuredCount of $measurableCount items measured',
                          style: const TextStyle(
                            color: AqsColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),

          if (expanded)
            _BillItemsTable(
              items: items,
              numberFormatter: numberFormatter,
              measurementLabel: measurementLabel,
              measurementIcon: measurementIcon,
              onMeasurementChanged: onMeasurementChanged,
              onTakeoff: onTakeoff,
            ),
        ],
      ),
    );
  }
}

class _BillItemsTable extends StatelessWidget {
  const _BillItemsTable({
    required this.items,
    required this.numberFormatter,
    required this.measurementLabel,
    required this.measurementIcon,
    required this.onMeasurementChanged,
    required this.onTakeoff,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;

  final String Function(dynamic, {int decimals}) numberFormatter;

  final String Function(String) measurementLabel;

  final IconData Function(String) measurementIcon;

  final Future<void> Function({required String itemId, required String value})
  onMeasurementChanged;

  final void Function({
    required String itemId,
    required Map<String, dynamic> item,
  })
  onTakeoff;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('Description')),
            DataColumn(label: Text('Unit')),
            DataColumn(numeric: true, label: Text('Original Qty')),
            DataColumn(numeric: true, label: Text('Measured Qty')),
            DataColumn(numeric: true, label: Text('Approved Qty')),
            DataColumn(label: Text('Measurement')),
            DataColumn(label: Text('Action')),
          ],
          rows:
              items.map((doc) {
                final data = doc.data();

                final heading = data['isHeading'] == true;

                final itemNo = (data['itemNo'] ?? '').toString();

                final description = (data['description'] ?? '').toString();

                if (heading) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          itemNo,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 440,
                          child: Text(
                            description,
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('Heading')),
                      const DataCell(SizedBox.shrink()),
                    ],
                  );
                }

                final unit = (data['unit'] ?? '').toString();

                final measurementType =
                    (data['measurementType'] ?? 'manual')
                        .toString()
                        .toLowerCase();

                return DataRow(
                  cells: [
                    DataCell(Text(itemNo)),
                    DataCell(
                      SizedBox(
                        width: 440,
                        child: Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AqsColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(unit)),
                    DataCell(Text(numberFormatter(data['originalQuantity']))),
                    DataCell(
                      Text(
                        numberFormatter(data['measuredQuantity']),
                        style: const TextStyle(
                          color: AqsColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    DataCell(Text(numberFormatter(data['approvedQuantity']))),
                    DataCell(
                      _MeasurementSelector(
                        value: measurementType,
                        label: measurementLabel(measurementType),
                        icon: measurementIcon(measurementType),
                        onChanged: (value) async {
                          if (value == null) {
                            return;
                          }

                          await onMeasurementChanged(
                            itemId: doc.id,
                            value: value,
                          );
                        },
                      ),
                    ),
                    DataCell(
                      FilledButton.icon(
                        onPressed: () {
                          onTakeoff(itemId: doc.id, item: data);
                        },
                        icon: const Icon(Icons.architecture_rounded, size: 18),
                        label: const Text('Start Take-off'),
                      ),
                    ),
                  ],
                );
              }).toList(),
        ),
      ),
    );
  }
}

class _MeasurementSelector extends StatelessWidget {
  const _MeasurementSelector({
    required this.value,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final String value;
  final String label;
  final IconData icon;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      'length',
      'area',
      'wall_area',
      'volume',
      'count',
      'weight',
      'composite',
      'manual',
    ];

    final safeValue = options.contains(value) ? value : 'manual';

    return SizedBox(
      width: 165,
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isDense: true,
        isExpanded: true,
        onChanged: onChanged,
        items:
            options.map((option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      option == safeValue ? icon : Icons.straighten_outlined,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _label(option),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  String _label(String type) {
    switch (type) {
      case 'length':
        return 'Length';

      case 'area':
        return 'Area';

      case 'wall_area':
        return 'Wall';

      case 'volume':
        return 'Volume';

      case 'count':
        return 'Count';

      case 'weight':
        return 'Weight';

      case 'composite':
        return 'Composite';

      default:
        return 'Manual';
    }
  }
}

class _EmptyBoq extends StatelessWidget {
  const _EmptyBoq();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          Icon(Icons.table_rows_outlined, size: 42, color: AqsColors.muted),
          SizedBox(height: 14),
          Text(
            'No BOQ bills found',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
