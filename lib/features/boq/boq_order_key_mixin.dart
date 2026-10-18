mixin BoqOrderKeyMixin {
  /// Builds a stable sortable key from boqCode.
  /// Handles patterns like:
  /// - 3.1(B)(i)
  /// - 3.7(i)(A)(ii)
  /// - 3.7(A)(ii)
  String makeOrderKey(String boqCode) {
    final c = boqCode.trim();
    if (c.isEmpty) return '99|999.999.999|999|ZZZ|999|';

    String extractSection(String code) {
      final idx = code.indexOf('(');
      final head = (idx == -1) ? code : code.substring(0, idx);
      final m = RegExp(r'^\d+(?:\.\d+)*').firstMatch(head.trim());
      return (m?.group(0) ?? head.trim());
    }

    List<String> parenTokens(String code) {
      return RegExp(r'\(([^)]+)\)')
          .allMatches(code)
          .map((m) => (m.group(1) ?? '').trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }

    bool isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

    int romanToInt(String roman) {
      final s = roman.trim().toUpperCase();
      if (s.isEmpty) return 999;
      const map = <String, int>{
        'I': 1,
        'V': 5,
        'X': 10,
        'L': 50,
        'C': 100,
        'D': 500,
        'M': 1000,
      };
      int total = 0;
      int prev = 0;
      for (int i = s.length - 1; i >= 0; i--) {
        final v = map[s[i]] ?? 0;
        if (v < prev)
          total -= v;
        else
          total += v;
        prev = v;
      }
      return total == 0 ? 999 : total;
    }

    String padSection(String section) {
      final parts = section.split('.').map((e) => e.trim()).toList();
      return parts
          .map((e) => (int.tryParse(e) ?? 0).toString().padLeft(3, '0'))
          .join('.');
    }

    String padRoman(String r) {
      final t = r.trim();
      if (t.isEmpty) return '999';
      return romanToInt(t).toString().padLeft(3, '0');
    }

    String padLetter(String s) {
      final t = s.trim();
      if (t.isEmpty) return 'ZZZ';
      return t.toUpperCase();
    }

    String padSub(String s) {
      final t = s.trim().toLowerCase();
      if (t.isEmpty) return '999';
      if (_isRoman(t)) return romanToInt(t).toString().padLeft(3, '0');
      final n = int.tryParse(t);
      if (n != null) return n.toString().padLeft(3, '0');
      return '998';
    }

    final section = extractSection(c); // 3.7
    final toks = parenTokens(c);

    String minor = '';
    String main = '';
    String sub = '';

    // 3.7(i)(A)(ii)
    if (toks.length >= 2 && _isRoman(toks[0]) && isLetter(toks[1])) {
      minor = toks[0].toLowerCase();
      main = toks[1].toUpperCase();
      if (toks.length >= 3) sub = toks[2].toLowerCase();
    }
    // 3.7(A)(ii)
    else if (toks.isNotEmpty && isLetter(toks[0])) {
      main = toks[0].toUpperCase();
      if (toks.length >= 2) sub = toks[1].toLowerCase();
    }

    final bill = section.split('.').first.trim();
    return '${bill.padLeft(2, '0')}|${padSection(section)}|'
        '${padRoman(minor)}|${padLetter(main)}|${padSub(sub)}|$c';
  }

  String _extractSection(String code) {
    final idx = code.indexOf('(');
    final head = (idx == -1) ? code : code.substring(0, idx);
    final m = RegExp(r'^\d+(?:\.\d+)*').firstMatch(head.trim());
    return (m?.group(0) ?? head.trim());
  }

  String _extractBill(String section) {
    final p = section.split('.').first.trim();
    return p.isEmpty ? '99' : p;
  }

  String _padSection(String section) {
    final parts = section.split('.').map((e) => e.trim()).toList();
    return parts
        .map((e) => (int.tryParse(e) ?? 0).toString().padLeft(3, '0'))
        .join('.');
  }

  String _padLetter(String s) =>
      s.trim().isEmpty ? 'ZZZ' : s.trim().toUpperCase();

  String _padRoman(String r) {
    final t = r.trim();
    if (t.isEmpty) return '999';
    return _romanToInt(t).toString().padLeft(3, '0');
  }

  String _padSub(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return '999';
    if (_isRoman(t)) return _romanToInt(t).toString().padLeft(3, '0');
    final n = int.tryParse(t);
    if (n != null) return n.toString().padLeft(3, '0');
    return '998';
  }

  List<String> _parenTokens(String code) {
    return RegExp(r'\(([^)]+)\)')
        .allMatches(code)
        .map((m) => (m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // bool _isRoman(String x) =>
  //     RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());

  bool _isLetter(String x) => RegExp(r'^[A-Za-z]$').hasMatch(x.trim());

  bool _isRoman(String x) =>
      RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(x.trim());

  bool _isLetterButNotRoman(String x) {
    final t = x.trim();
    if (!RegExp(r'^[A-Za-z]$').hasMatch(t)) return false;
    return !_isRoman(t); // ✅ excludes I,V,X,L,C,D,M (roman letters)
  }

  int _romanToInt(String roman) {
    final s = roman.trim().toUpperCase();
    if (s.isEmpty) return 999;

    const map = <String, int>{
      'I': 1,
      'V': 5,
      'X': 10,
      'L': 50,
      'C': 100,
      'D': 500,
      'M': 1000,
    };

    int total = 0;
    int prev = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      final v = map[s[i]] ?? 0;
      if (v < prev)
        total -= v;
      else
        total += v;
      prev = v;
    }
    return total == 0 ? 999 : total;
  }
}
