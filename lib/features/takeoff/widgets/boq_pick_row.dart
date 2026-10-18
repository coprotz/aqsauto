import 'package:flutter/material.dart';

Widget boqPickRow({
  required BuildContext context,
  required String title,
  required String code,
  required String desc,
  required VoidCallback onPick,
  VoidCallback? onClear,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              readOnly: true,
              controller: TextEditingController(text: code),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'BOQ code',
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Pick'),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Clear',
              onPressed: onClear,
              icon: const Icon(Icons.clear),
            ),
          ],
        ],
      ),
      if (desc.trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          desc,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ],
  );
}
