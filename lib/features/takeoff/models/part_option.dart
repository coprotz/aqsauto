class PartOption {
  final String type;
  final String unit;
  final String label;
  const PartOption({
    required this.type,
    required this.unit,
    required this.label,
  });

  @override
  String toString() => '$label ($unit)';
}
