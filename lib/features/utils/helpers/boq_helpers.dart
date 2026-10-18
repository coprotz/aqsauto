String bestResolvedCode({required String billCode, required String rawCode}) {
  final c = rawCode.trim();
  // if already like 10.1.3(A) keep it
  if (c.contains('.')) return c;

  // if it's single letter/short code, make it unique per bill: "4.C"
  return '${billCode.trim()}.$c';
}

String civilResolvedBoqCode({
  required String minorCode,
  required String rawCode,
}) {
  String canonicalCode(String value) {
    var result = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    result = result.replaceAllMapped(
      RegExp(r'\s*\(\s*([^)]*?)\s*\)\s*'),
      (match) => '(${match.group(1)})',
    );
    result = result.replaceAllMapped(
      RegExp(r'\)([ivxlcdm]+)$', caseSensitive: false),
      (match) => ')(${match.group(1)})',
    );
    return result;
  }

  final minor = canonicalCode(minorCode);
  final raw = canonicalCode(rawCode);

  var leaf = raw;
  if (leaf.isEmpty) {
    leaf = minor;
  } else if (minor.isNotEmpty &&
      leaf != minor &&
      !leaf.startsWith('$minor.') &&
      !leaf.startsWith('$minor(')) {
    final bareLeaf = leaf.replaceAll(RegExp(r'^\(|\)$'), '');
    if (RegExp(r'^[A-Za-z]+$').hasMatch(bareLeaf)) {
      final isLowerRoman =
          bareLeaf == bareLeaf.toLowerCase() &&
          RegExp(r'^[ivxlcdm]+$').hasMatch(bareLeaf);
      final trailingLetter = RegExp(r'\(([A-Za-z])\)$').firstMatch(minor);
      if (bareLeaf.length == 1 && !isLowerRoman && trailingLetter != null) {
        leaf = '${minor.substring(0, trailingLetter.start)}($bareLeaf)';
      } else {
        leaf = '$minor($bareLeaf)';
      }
    }
  }

  return leaf;
}

String hierarchicalBoqCode(Map<String, dynamic> row) {
  String text(dynamic value) => (value ?? '').toString().trim();
  String first(Iterable<dynamic> values) {
    for (final value in values) {
      final candidate = text(value);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  final workType = text(row['boqWorkType']).toLowerCase();
  final sectionType = text(row['sectionType']).toLowerCase();
  if (workType == 'civil' || sectionType == 'series') {
    return civilResolvedBoqCode(
      minorCode: first([row['minorCode'], row['minorNo']]),
      rawCode: first([row['boqCode'], row['displayCode']]),
    );
  }

  String bareToken(String value) =>
      value.trim().replaceAll(RegExp(r'^\(+|\)+$'), '');

  final bill = first([row['billCode'], row['billNo']]);
  final subheading = first([row['subHeadingNo'], row['subheadingNo']]);
  final minor = bareToken(first([row['minorCode'], row['minorNo']]));
  var item = first([row['displayCode'], row['boqCode']]);

  // Building BOQs commonly number a minor heading as 2.00 and its items as
  // 2.01, 2.02, etc. The bill is a separate heading and must not be prefixed
  // to these item numbers.
  final cleanBill = bareToken(bill);
  final numericPath = RegExp(r'^\d+(?:\.\d+)+$');
  if (minor.isNotEmpty && numericPath.hasMatch(minor)) {
    final billToken = cleanBill.split('.').first;
    final minorToken = minor.split('.').first;

    // Prefer the raw imported item number. Older saved rows may have a
    // generated displayCode such as 1.2.00(2.01), while boqCode still holds
    // the useful leaf number 2.01.
    for (final candidate in [row['boqCode'], row['displayCode'], item]) {
      final value = text(candidate);
      if (value.isEmpty) continue;
      final trailingGroup = RegExp(
        r'\((\d+(?:\.\d+)*)\)\s*$',
      ).firstMatch(value);
      final cleanCandidate = trailingGroup?.group(1) ?? bareToken(value);
      if (RegExp(r'^\d+$').hasMatch(cleanCandidate)) {
        return '$minorToken.$cleanCandidate';
      }
      if (!numericPath.hasMatch(cleanCandidate)) continue;

      final parts = cleanCandidate.split('.');
      if (cleanBill.isNotEmpty &&
          parts.first == billToken &&
          parts.length > 2 &&
          parts[1] == minorToken) {
        return parts.skip(1).join('.');
      }
      if (parts.first == minorToken && parts.length > 1) {
        return parts.join('.');
      }
    }
  }

  var base = subheading;
  if (base.isEmpty) {
    base = bill;
  } else if (bill.isNotEmpty && base != bill && !base.startsWith('$bill.')) {
    base = '$bill.$base';
  }

  if (minor.isNotEmpty && !base.endsWith('($minor)')) {
    base = '$base($minor)';
  }

  final main = bareToken(first([row['mainNo']]));
  final sub = bareToken(first([row['subNo']]));
  if (main.isNotEmpty || sub.isNotEmpty) {
    if (main.isNotEmpty && !base.endsWith('($main)')) {
      base = base.isEmpty ? main : '$base($main)';
    }
    if (sub.isNotEmpty && !base.endsWith('($sub)')) {
      base = base.isEmpty ? sub : '$base($sub)';
    }
    return base;
  }

  // Keep a genuinely complete imported code, but do not mistake shortened
  // values such as "3.A" for the full subheading/minor hierarchy.
  if (base.isNotEmpty && (item == base || item.startsWith('$base('))) {
    return item;
  }
  if (bill.isNotEmpty && item.startsWith('$bill.')) {
    item = item.substring(bill.length + 1);
  } else if (base.isEmpty && item.contains('.')) {
    return item;
  }

  final itemToken = bareToken(item);
  if (itemToken.isNotEmpty) {
    base = base.isEmpty ? itemToken : '$base($itemToken)';
  }

  final resolved = text(row['resolvedBoqCode']);
  return base.isNotEmpty ? base : resolved;
}

String hierarchicalBoqCodeFromRows(
  Map<String, dynamic> row,
  Iterable<Map<String, dynamic>> allRows,
) {
  String text(dynamic value) => (value ?? '').toString().trim();
  double orderOf(Map<String, dynamic> value) =>
      value['order'] is num
          ? (value['order'] as num).toDouble()
          : double.tryParse('${value['order']}') ?? double.infinity;

  final enriched = Map<String, dynamic>.from(row);
  final targetOrder = orderOf(row);
  final targetStructure = text(row['structure']);
  final isCivil =
      text(row['boqWorkType']).toLowerCase() == 'civil' ||
      text(row['sectionType']).toLowerCase() == 'series';
  final sorted =
      allRows.map((value) => Map<String, dynamic>.from(value)).toList()
        ..sort((a, b) => orderOf(a).compareTo(orderOf(b)));

  String currentBill = '';
  String currentSubheadingCode = '';
  String currentMinorCode = '';
  final civilMinorPath = <String>[];
  for (final candidate in sorted) {
    if (orderOf(candidate) > targetOrder) break;
    final candidateStructure = text(candidate['structure']);
    if (targetStructure.isNotEmpty &&
        candidateStructure.isNotEmpty &&
        candidateStructure != targetStructure) {
      continue;
    }
    final type = text(candidate['rowType']).toLowerCase();
    if (type == 'bill') {
      currentBill =
          text(candidate['billCode']).isNotEmpty
              ? text(candidate['billCode'])
              : text(candidate['boqCode']);
      currentSubheadingCode = '';
      currentMinorCode = '';
      civilMinorPath.clear();
    } else if (type == 'subheading') {
      currentSubheadingCode =
          text(candidate['subHeadingNo']).isNotEmpty
              ? text(candidate['subHeadingNo'])
              : text(candidate['subheadingNo']).isNotEmpty
              ? text(candidate['subheadingNo'])
              : text(candidate['boqCode']);
      currentMinorCode = '';
      civilMinorPath.clear();
    } else if (type == 'minor') {
      currentMinorCode =
          text(candidate['minorCode']).isNotEmpty
              ? text(candidate['minorCode'])
              : text(candidate['minorNo']).isNotEmpty
              ? text(candidate['minorNo'])
              : text(candidate['boqCode']);
      if (isCivil && currentMinorCode.isNotEmpty) {
        final clean =
            currentMinorCode.replaceAll(RegExp(r'^\(|\)$'), '').trim();
        if (RegExp(r'^\d+(?:\.\d+)+').hasMatch(clean)) {
          civilMinorPath
            ..clear()
            ..add(clean);
        } else {
          civilMinorPath.add(clean);
        }
      }
    }
  }

  if (text(enriched['billCode']).isEmpty && currentBill.isNotEmpty) {
    enriched['billCode'] = currentBill;
  }
  if (text(enriched['subHeadingNo']).isEmpty &&
      text(enriched['subheadingNo']).isEmpty &&
      currentSubheadingCode.isNotEmpty) {
    enriched['subHeadingNo'] = currentSubheadingCode;
  }
  if (isCivil && civilMinorPath.isNotEmpty) {
    final nestedMinor = StringBuffer(civilMinorPath.first);
    for (final part in civilMinorPath.skip(1)) {
      nestedMinor.write('(${part.replaceAll(RegExp(r'^\(|\)$'), '')})');
    }
    enriched['minorCode'] = nestedMinor.toString();
  } else if (text(enriched['minorCode']).isEmpty &&
      text(enriched['minorNo']).isEmpty &&
      currentMinorCode.isNotEmpty) {
    enriched['minorCode'] = currentMinorCode;
  }
  return hierarchicalBoqCode(enriched);
}
