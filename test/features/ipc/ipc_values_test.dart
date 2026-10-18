import 'package:aqs/features/ipc/ipc_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IPC values handle Excel comma-formatted amounts', () {
    expect(ipcNumber('1,009,928,800.00'), 1009928800);
    expect(ipcNumber(12.5), 12.5);
    expect(ipcNumber(null), 0);
  });

  test('IPC amounts display full values and two decimal places', () {
    expect(ipcMoney(1009928800), 'TZS 1,009,928,800.00');
    expect(ipcMoney(0), 'TZS 0.00');
    expect(ipcMoney(12.345), 'TZS 12.35');
  });
}
