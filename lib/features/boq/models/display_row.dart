import 'package:aqs/features/utils/enum.dart';

class DisplayRow {
  final RowType type;
  final Map<String, dynamic>? data; // only for item rows
  final String? textLeft; // e.g. billCode or ""
  final String? text; // heading label
  final String? billCode; // for footer totals
  DisplayRow({
    required this.type,
    this.data,
    this.textLeft,
    this.text,
    this.billCode,
  });
}
