import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BuildingMeasurementsTab extends StatefulWidget {
  const BuildingMeasurementsTab({
    super.key,
    required this.projectId,
    required this.buildingId,
    this.activeDrawingId,
    this.onDrawingSelected,
    this.onBackToDrawings,
  });

  final String projectId;
  final String buildingId;
  final String? activeDrawingId;
  final ValueChanged<String>? onDrawingSelected;
  final VoidCallback? onBackToDrawings;

  @override
  State<BuildingMeasurementsTab> createState() =>
      _BuildingMeasurementsTabState();
}

class _BuildingMeasurementsTabState extends State<BuildingMeasurementsTab> {
  late Future<_MeasurementCoverage> _coverageFuture;

  @override
  void initState() {
    super.initState();
    _coverageFuture = _loadCoverage();
  }

  DocumentReference<Map<String, dynamic>> get _buildingRef => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('buildings')
      .doc(widget.buildingId);

  Future<void> _refresh() async {
    setState(() => _coverageFuture = _loadCoverage());
    await _coverageFuture;
  }

  Future<_MeasurementCoverage> _loadCoverage() async {
    var boqSnap = await _buildingRef.collection('boq').get();
    if (boqSnap.docs.isEmpty) {
      boqSnap = await _buildingRef.collection('boqItems').get();
    }

    final measurementSnap = await _buildingRef.collection('measurements').get();

    final measuredKeys = <String>{};
    final measurementCountByKey = <String, int>{};

    for (final doc in measurementSnap.docs) {
      final data = doc.data();
      final keys = {
        _key(data['boqCode']),
        _key(data['resolvedBoqCode']),
        _key(data['boqCodeNorm']),
        _key(data['displayCode']),
      }..removeWhere((key) => key.isEmpty);

      for (final key in keys) {
        measuredKeys.add(key);
        measurementCountByKey[key] = (measurementCountByKey[key] ?? 0) + 1;
      }
    }

    final measuredItems = <_BoqCoverageItem>[];
    final unmeasuredItems = <_BoqCoverageItem>[];

    for (final doc in boqSnap.docs) {
      final data = doc.data();
      if (_rowType(data['rowType']) != 'item') continue;

      final item = _BoqCoverageItem.fromDoc(doc);
      final keys = item.matchKeys;
      final hasMeasurement = keys.any(measuredKeys.contains);
      final hasQtyOverride = _num(data['qtyOverride']) > 0;
      final count = keys
          .map((key) => measurementCountByKey[key] ?? 0)
          .fold<int>(0, (sum, value) => sum + value);

      final resolvedItem = item.copyWith(
        measured: hasMeasurement || hasQtyOverride,
        measurementCount: count,
      );

      if (resolvedItem.measured) {
        measuredItems.add(resolvedItem);
      } else {
        unmeasuredItems.add(resolvedItem);
      }
    }

    measuredItems.sort((a, b) => a.sortText.compareTo(b.sortText));
    unmeasuredItems.sort((a, b) => a.sortText.compareTo(b.sortText));

    return _MeasurementCoverage(
      measuredItems: measuredItems,
      unmeasuredItems: unmeasuredItems,
      measurementCount: measurementSnap.docs.length,
    );
  }

  String _key(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  String _rowType(dynamic value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    return text.isEmpty ? 'item' : text;
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MeasurementCoverage>(
      future: _coverageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _CoverageEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load measurement coverage',
            message: '${snapshot.error}',
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }

        final coverage = snapshot.data ?? _MeasurementCoverage.empty;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 44),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CoverageHeader(
                        coverage: coverage,
                        onRefresh: _refresh,
                        onBackToDrawings: widget.onBackToDrawings,
                      ),
                      const SizedBox(height: 18),
                      if (coverage.totalItems == 0)
                        _CoverageEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No BOQ items found',
                          message:
                              'Import or create BOQ items first. Coverage will appear here after take-off measurements are saved.',
                          actionLabel:
                              widget.onBackToDrawings == null
                                  ? null
                                  : 'Go to drawings',
                          onAction: widget.onBackToDrawings,
                        )
                      else ...[
                        _CoverageStats(coverage: coverage),
                        const SizedBox(height: 18),
                        _CoverageList(
                          title: 'Measured BOQ items',
                          subtitle: 'Items with saved measurements.',
                          emptyText: 'No BOQ items measured yet.',
                          items: coverage.measuredItems,
                          measured: true,
                        ),
                        const SizedBox(height: 18),
                        _CoverageList(
                          title: 'Not measured yet',
                          subtitle: 'Items still remaining for take-off.',
                          emptyText: 'All BOQ items are covered.',
                          items: coverage.unmeasuredItems,
                          measured: false,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CoverageHeader extends StatelessWidget {
  const _CoverageHeader({
    required this.coverage,
    required this.onRefresh,
    required this.onBackToDrawings,
  });

  final _MeasurementCoverage coverage;
  final Future<void> Function() onRefresh;
  final VoidCallback? onBackToDrawings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final title = Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AqsColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: AqsColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Measurement coverage',
                      style: TextStyle(
                        color: AqsColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${coverage.measuredItems.length} of ${coverage.totalItems} BOQ items covered',
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              if (onBackToDrawings != null)
                FilledButton.icon(
                  onPressed: onBackToDrawings,
                  icon: const Icon(Icons.architecture_outlined),
                  label: const Text('Take-off more'),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 16), actions],
            );
          }

          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _CoverageStats extends StatelessWidget {
  const _CoverageStats({required this.coverage});

  final _MeasurementCoverage coverage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Take-off coverage',
                  style: TextStyle(
                    color: AqsColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${coverage.percentCovered.round()}%',
                style: const TextStyle(
                  color: AqsColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: coverage.progress,
              minHeight: 10,
              backgroundColor: AqsColors.primarySoft,
              color: AqsColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatPill(
                icon: Icons.check_circle_outline_rounded,
                label: 'Measured',
                value: '${coverage.measuredItems.length}',
                color: AqsColors.success,
              ),
              _StatPill(
                icon: Icons.pending_actions_outlined,
                label: 'Not measured',
                value: '${coverage.unmeasuredItems.length}',
                color: const Color(0xFFB54708),
              ),
              _StatPill(
                icon: Icons.straighten_rounded,
                label: 'Measurements',
                value: '${coverage.measurementCount}',
                color: AqsColors.primary,
              ),
              _StatPill(
                icon: Icons.receipt_long_outlined,
                label: 'BOQ items',
                value: '${coverage.totalItems}',
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverageList extends StatelessWidget {
  const _CoverageList({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.items,
    required this.measured,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<_BoqCoverageItem> items;
  final bool measured;

  @override
  Widget build(BuildContext context) {
    final color = measured ? AqsColors.success : const Color(0xFFB54708);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    measured
                        ? Icons.check_circle_outline_rounded
                        : Icons.pending_actions_outlined,
                    color: color,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AqsColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AqsColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _CountBadge(count: items.length, color: color),
              ],
            ),
          ),
          Divider(height: 1, color: AqsColors.border),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AqsColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _CoverageItemTile(
                  item: items[index],
                  measured: measured,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CoverageItemTile extends StatelessWidget {
  const _CoverageItemTile({required this.item, required this.measured});

  final _BoqCoverageItem item;
  final bool measured;

  @override
  Widget build(BuildContext context) {
    final color = measured ? AqsColors.success : const Color(0xFFB54708);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            measured
                ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.code.isEmpty ? 'Uncoded item' : item.code,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description.isEmpty
                      ? 'No description'
                      : item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AqsColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (item.unit.isNotEmpty)
                      _MiniChip(
                        icon: Icons.square_foot_rounded,
                        label: item.unit,
                      ),
                    if (item.quantityText.isNotEmpty)
                      _MiniChip(
                        icon: Icons.format_list_numbered_rounded,
                        label: item.quantityText,
                      ),
                    if (measured)
                      _MiniChip(
                        icon: Icons.straighten_rounded,
                        label:
                            item.measurementCount <= 0
                                ? 'Qty override'
                                : '${item.measurementCount} measurement${item.measurementCount == 1 ? '' : 's'}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageEmptyState extends StatelessWidget {
  const _CoverageEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AqsColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AqsColors.muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AqsColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AqsColors.muted,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AqsColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AqsColors.muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AqsColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementCoverage {
  const _MeasurementCoverage({
    required this.measuredItems,
    required this.unmeasuredItems,
    required this.measurementCount,
  });

  static const empty = _MeasurementCoverage(
    measuredItems: [],
    unmeasuredItems: [],
    measurementCount: 0,
  );

  final List<_BoqCoverageItem> measuredItems;
  final List<_BoqCoverageItem> unmeasuredItems;
  final int measurementCount;

  int get totalItems => measuredItems.length + unmeasuredItems.length;
  double get progress =>
      totalItems == 0 ? 0 : measuredItems.length / totalItems;
  double get percentCovered => progress * 100;
}

class _BoqCoverageItem {
  const _BoqCoverageItem({
    required this.id,
    required this.code,
    required this.description,
    required this.unit,
    required this.quantityText,
    required this.matchKeys,
    required this.measured,
    required this.measurementCount,
  });

  final String id;
  final String code;
  final String description;
  final String unit;
  final String quantityText;
  final Set<String> matchKeys;
  final bool measured;
  final int measurementCount;

  String get sortText => '$code $description'.trim().toLowerCase();

  factory _BoqCoverageItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final code = _firstText(data, [
      'boqCode',
      'displayCode',
      'resolvedBoqCode',
      'code',
      'itemCode',
    ]);
    final description = _firstText(data, [
      'description',
      'itemDescription',
      'title',
      'name',
      'item',
    ]);
    final unit = _firstText(data, ['unit', 'uom']);
    final quantityText = _quantityText(data);
    final keys = {
      _normaliseKey(data['boqCode']),
      _normaliseKey(data['displayCode']),
      _normaliseKey(data['resolvedBoqCode']),
      _normaliseKey(data['code']),
      _normaliseKey(data['itemCode']),
    }..removeWhere((key) => key.isEmpty);

    return _BoqCoverageItem(
      id: doc.id,
      code: code,
      description: description,
      unit: unit,
      quantityText: quantityText,
      matchKeys: keys,
      measured: false,
      measurementCount: 0,
    );
  }

  _BoqCoverageItem copyWith({
    required bool measured,
    required int measurementCount,
  }) {
    return _BoqCoverageItem(
      id: id,
      code: code,
      description: description,
      unit: unit,
      quantityText: quantityText,
      matchKeys: matchKeys,
      measured: measured,
      measurementCount: measurementCount,
    );
  }

  static String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _quantityText(Map<String, dynamic> data) {
    final value =
        data['qtyOverride'] ?? data['quantity'] ?? data['qty'] ?? data['value'];
    if (value == null) return '';
    final text = value.toString().trim();
    return text.isEmpty ? '' : 'Qty $text';
  }

  static String _normaliseKey(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }
}
