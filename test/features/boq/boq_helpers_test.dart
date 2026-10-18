import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hierarchicalBoqCode', () {
    test(
      'keeps numeric items under the minor heading without a bill prefix',
      () {
        expect(
          hierarchicalBoqCode({
            'billCode': '1',
            'minorCode': '2.00',
            'displayCode': '2.01',
          }),
          '2.01',
        );
        expect(
          hierarchicalBoqCode({
            'billCode': '1',
            'minorCode': '2.00',
            'displayCode': '2.06',
          }),
          '2.06',
        );
      },
    );

    test('restarts the numeric item path for another minor heading', () {
      expect(
        hierarchicalBoqCode({
          'billCode': '1',
          'minorCode': '3.00',
          'displayCode': '3.01',
        }),
        '3.01',
      );
    });

    test('removes a legacy bill prefix from an item code', () {
      expect(
        hierarchicalBoqCode({
          'billCode': '1',
          'minorCode': '2.00',
          'displayCode': '1.2.01',
        }),
        '2.01',
      );
    });

    test('repairs a legacy code that repeats the minor heading', () {
      expect(
        hierarchicalBoqCode({
          'billCode': '1',
          'minorCode': '2.00',
          'boqCode': '2.01',
          'displayCode': '1.2.00(2.01)',
        }),
        '2.01',
      );
    });

    test('combines a numeric leaf with its minor heading', () {
      expect(
        hierarchicalBoqCode({
          'billCode': '1',
          'minorCode': '1.00',
          'boqCode': '01',
          'displayCode': '1.00(01)',
        }),
        '1.01',
      );
    });

    test('resolves existing rows from the preceding hierarchy headings', () {
      final rows = <Map<String, dynamic>>[
        {'rowType': 'bill', 'order': 1, 'boqCode': '1'},
        {'rowType': 'minor', 'order': 2, 'minorNo': '2.00', 'boqCode': '2.00'},
        {
          'rowType': 'item',
          'order': 3,
          'boqCode': '2.01',
          'displayCode': '1.2.00(2.01)',
        },
      ];

      expect(hierarchicalBoqCodeFromRows(rows.last, rows), '2.01');
    });
  });
}
