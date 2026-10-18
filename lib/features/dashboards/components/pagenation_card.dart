import 'dart:math';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:flutter/material.dart';

class PaginationRow extends StatelessWidget {
  final int page;
  final int pageSize;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const PaginationRow({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final maxPage = max(1, (total / pageSize).ceil());
    final from = total == 0 ? 0 : ((page - 1) * pageSize + 1);
    final to = min(total, page * pageSize);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$from-$to of $total results',
          style: TextStyle(
            color: Colors.black.withOpacity(0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: page <= 1 ? null : onPrev,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AqsColors.border),
              ),
              child: Text(
                'Page $page / $maxPage',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: page >= maxPage ? null : onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}
