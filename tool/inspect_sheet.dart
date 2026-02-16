import 'dart:io';
import 'package:excel/excel.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : r'd:\Downloads\Phone Link\Lap Top HP_Transfer Details from_2026-02-09 000000 to 2026-02-10 235959.XLSX';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  print('Sheets: ${excel.tables.keys.toList()}');
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    print('\n=== SHEET: $name ===');
    print('Rows: ${sheet.rows.length}');
    for (var r = 0; r < sheet.rows.length && r < 4; r++) {
      final row = sheet.rows[r]
          .map((c) => (c?.value ?? '').toString().replaceAll('\n', ' ').trim())
          .toList();
      print('R${r + 1}: ${row.join(' | ')}');
    }
  }
}
