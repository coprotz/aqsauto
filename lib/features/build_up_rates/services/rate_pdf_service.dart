import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class RatePdfService {
  const RatePdfService();

  static const website = 'https://aqsautoboq.com';

  Future<Uint8List> build(BuildUpRate rate) async {
    final document = PdfDocument();
    document.pageSettings.margins.all = 36;
    final page = document.pages.add();
    final bounds = page.getClientSize();
    final money = NumberFormat('#,##0.00');
    final quantity = NumberFormat('#,##0.####');
    final dark = PdfColor(16, 24, 40);
    final blue = PdfColor(21, 94, 239);
    final muted = PdfColor(102, 112, 133);
    final border = PdfColor(234, 236, 240);

    final logoData = await rootBundle.load('assets/images/logo.png');
    page.graphics.drawImage(
      PdfBitmap(logoData.buffer.asUint8List()),
      const Rect.fromLTWH(0, 0, 48, 48),
    );
    page.graphics.drawString(
      'AQS AUTOboq',
      PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: const Rect.fromLTWH(60, 5, 260, 24),
    );
    page.graphics.drawString(
      'Professional Build-Up Rate Analysis',
      PdfStandardFont(PdfFontFamily.helvetica, 9),
      brush: PdfSolidBrush(muted),
      bounds: const Rect.fromLTWH(60, 31, 260, 16),
    );
    page.graphics.drawLine(
      PdfPen(blue, width: 2),
      Offset.zero.translate(0, 62),
      Offset(bounds.width, 62),
    );

    page.graphics.drawString(
      rate.name,
      PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(dark),
      bounds: Rect.fromLTWH(0, 82, bounds.width, 30),
    );
    page.graphics.drawString(
      '${rate.category.label}  |  Unit: ${rate.unit}  |  Currency: ${rate.currency}',
      PdfStandardFont(PdfFontFamily.helvetica, 10),
      brush: PdfSolidBrush(muted),
      bounds: Rect.fromLTWH(0, 116, bounds.width, 18),
    );
    if (rate.description.isNotEmpty) {
      page.graphics.drawString(
        rate.description,
        PdfStandardFont(PdfFontFamily.helvetica, 10),
        brush: PdfSolidBrush(dark),
        bounds: Rect.fromLTWH(0, 140, bounds.width, 36),
      );
    }

    final grid = PdfGrid();
    grid.columns.add(count: 6);
    grid.headers.add(1);
    final header = grid.headers[0];
    const headings = [
      'Resource',
      'Qty',
      'Unit',
      'Unit price',
      'Waste',
      'Amount',
    ];
    for (var index = 0; index < headings.length; index++) {
      header.cells[index].value = headings[index];
    }
    for (final component in rate.components) {
      final row = grid.rows.add();
      row.cells[0].value = component.name;
      row.cells[1].value = quantity.format(component.quantity);
      row.cells[2].value = component.unit;
      row.cells[3].value =
          '${rate.currency} ${money.format(component.unitRate)}';
      row.cells[4].value = '${quantity.format(component.wastePercent)}%';
      row.cells[5].value = '${rate.currency} ${money.format(component.amount)}';
    }
    grid.columns[0].width = 145;
    grid.columns[1].width = 48;
    grid.columns[2].width = 42;
    grid.columns[3].width = 90;
    grid.columns[4].width = 48;
    grid.columns[5].width = 92;
    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 6, right: 6, top: 7, bottom: 7),
      font: PdfStandardFont(PdfFontFamily.helvetica, 8.5),
    );
    header.style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(blue),
      textBrush: PdfBrushes.white,
      font: PdfStandardFont(
        PdfFontFamily.helvetica,
        9,
        style: PdfFontStyle.bold,
      ),
    );
    for (var rowIndex = 0; rowIndex < grid.rows.count; rowIndex++) {
      final row = grid.rows[rowIndex];
      for (var cellIndex = 0; cellIndex < row.cells.count; cellIndex++) {
        final cell = row.cells[cellIndex];
        cell.style.borders.all = PdfPen(border);
      }
    }
    final gridResult =
        grid.draw(
          page: page,
          bounds: Rect.fromLTWH(
            0,
            rate.description.isEmpty ? 150 : 184,
            bounds.width,
            0,
          ),
        )!;

    var totalsPage = gridResult.page;
    var top = gridResult.bounds.bottom + 20;
    if (top > totalsPage.getClientSize().height - 170) {
      totalsPage = document.pages.add();
      top = 36;
    }
    void totalLine(String label, double value, {bool strong = false}) {
      totalsPage.graphics.drawString(
        label,
        PdfStandardFont(
          PdfFontFamily.helvetica,
          strong ? 12 : 10,
          style: strong ? PdfFontStyle.bold : PdfFontStyle.regular,
        ),
        brush: PdfSolidBrush(dark),
        bounds: Rect.fromLTWH(260, top, 130, 20),
      );
      totalsPage.graphics.drawString(
        '${rate.currency} ${money.format(value)}',
        PdfStandardFont(
          PdfFontFamily.helvetica,
          strong ? 13 : 10,
          style: PdfFontStyle.bold,
        ),
        brush: PdfSolidBrush(strong ? blue : dark),
        bounds: Rect.fromLTWH(390, top, 140, 20),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
      top += strong ? 28 : 22;
    }

    totalLine('Direct cost', rate.directCost);
    totalLine(
      'Overheads (${quantity.format(rate.overheadsPercent)}%)',
      rate.overheadsAmount,
    );
    totalLine(
      'Profit (${quantity.format(rate.profitPercent)}%)',
      rate.profitAmount,
    );
    totalsPage.graphics.drawLine(
      PdfPen(border),
      Offset(260, top),
      Offset(530, top),
    );
    top += 10;
    totalLine('FINAL RATE / ${rate.unit}', rate.finalRate, strong: true);

    final footerY = totalsPage.getClientSize().height - 28;
    PdfTextWebLink(
      url: website,
      text: 'Create professional BOQs and rate analyses at $website',
      font: PdfStandardFont(PdfFontFamily.helvetica, 8),
      brush: PdfSolidBrush(blue),
    ).draw(totalsPage, Offset(0, footerY));

    final bytes = Uint8List.fromList(await document.save());
    document.dispose();
    return bytes;
  }
}
