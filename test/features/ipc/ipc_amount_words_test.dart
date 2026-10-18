import 'package:aqs/features/ipc/ipc_amount_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference amount uses correct million grouping and cents', () {
    expect(ipcAmountInWords(2773578597.33), 'Tanzanian Shillings Two Billion, Seven Hundred Seventy Three Million, Five Hundred Seventy Eight Thousand, Five Hundred Ninety Seven and Thirty Three Cents');
  });
  test('zero, whole values, rounding, negatives and unavailable', () {
    expect(ipcAmountInWords(0), 'Tanzanian Shillings Zero Only');
    expect(ipcAmountInWords(1000), 'Tanzanian Shillings One Thousand Only');
    expect(ipcAmountInWords(999.999), 'Tanzanian Shillings One Thousand Only');
    expect(ipcAmountInWords(-0.01), 'Minus Tanzanian Shillings Zero and One Cent');
    expect(ipcAmountInWords(null), 'Amount in words unavailable');
    expect(ipcAmountInWords(double.nan), 'Amount in words unavailable');
  });
}
