import 'package:flutter/material.dart';

class BoqRowTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const BoqRowTile({super.key, required this.data});

  String _s(dynamic v) => (v ?? '').toString().trim();
  num _n(dynamic v) => (v is num) ? v : num.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = _s(data['rowType']).isEmpty ? 'item' : _s(data['rowType']);

    final billNo = _s(data['billNo']);
    final billName = _s(data['billName']);
    final shNo = _s(data['subheadingNo']);
    final sh = _s(data['subheading']);

    final code = _s(data['boqCode']);
    final desc = _s(data['description']);
    final unit = _s(data['unit']);

    final rate = _n(data['rate']);
    final amount = _n(data['amount']);

    if (type == 'bill') {
      return Container(
        margin: const EdgeInsets.only(top: 12, bottom: 6),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              offset: const Offset(0, 3),
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cs.onPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.onPrimary.withOpacity(0.25)),
                ),
                child: Text(
                  billNo.isEmpty ? 'BILL' : 'BILL $billNo',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  billName.isNotEmpty
                      ? billName.toUpperCase()
                      : desc.toUpperCase(),
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (type == 'subheading') {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            // Accent bar
            Container(
              width: 6,
              height: 54,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (shNo.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.primary.withOpacity(0.25),
                          ),
                        ),
                        child: Text(
                          shNo,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    if (shNo.isNotEmpty) const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sh.isNotEmpty ? sh : desc,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Normal item row (table style)
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                code,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 60,
              child: Text(
                unit,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text(
                rate == 0 ? '' : rate.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: Text(
                amount == 0 ? '' : amount.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
