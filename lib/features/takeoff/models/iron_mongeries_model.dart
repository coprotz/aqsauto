import 'package:flutter/material.dart';

class IronItem {
  final String key; // stable id (e.g. 'lockset')
  final String title; // UI label
  final String unit; // usually 'item' or 'set'
  bool include;

  final TextEditingController qtyCtrl = TextEditingController(text: '1');
  final TextEditingController boqCodeCtrl = TextEditingController();
  final TextEditingController boqDescCtrl = TextEditingController();

  IronItem({
    required this.key,
    required this.title,
    required this.unit,
    this.include = false,
  });

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0.0;

  void dispose() {
    qtyCtrl.dispose();
    boqCodeCtrl.dispose();
    boqDescCtrl.dispose();
  }
}
