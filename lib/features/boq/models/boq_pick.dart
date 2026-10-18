class BoqPick {
  final String id;
  final String code;
  final String description;

  const BoqPick({
    required this.id,
    required this.code,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'description': description,
  };

  static BoqPick? fromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['boqItemId'] ?? m['id'] ?? '').toString();
    final code = (m['resolvedBoqCode'] ?? m['code'] ?? '').toString();
    final desc = (m['description'] ?? '').toString();
    if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
    return BoqPick(id: id, code: code, description: desc);
  }
}
