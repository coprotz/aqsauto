import 'package:flutter/material.dart';

Widget boqPickField({
  required String label,
  required TextEditingController codeCtrl,
  required TextEditingController descCtrl,
  required VoidCallback onPick,
}) {
  final code = codeCtrl.text.trim();
  final desc = descCtrl.text.trim();

  return InkWell(
    onTap: onPick,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: const Icon(Icons.search),
      ),
      child: Text(
        code.isEmpty ? 'Click to pick' : '$code — $desc',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    ),
  );
}
