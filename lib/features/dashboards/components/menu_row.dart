import 'package:flutter/material.dart';

class MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool danger;

  const MenuRow({required this.icon, required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = danger ? Colors.red : Colors.black.withOpacity(0.75);
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: c, fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
