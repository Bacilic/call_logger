// Η εκτύπωση του χάρτη: ο προσανατολισμός ακολουθεί τον χάρτη, και το έγγραφο
// γράφεται με το χαρτί που διάλεξε ο χρήστης.
//
//   flutter test test/features/directory/building_map/plan/services/floor_plan_print_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_print.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  test('πλατύς χάρτης ανοίγει οριζόντια, ψηλός κατακόρυφα', () {
    final wide = floorPlanPrintFormat(3000, 1000);
    expect(wide.width, greaterThan(wide.height));
    final tall = floorPlanPrintFormat(1000, 3000);
    expect(tall.height, greaterThan(tall.width));
  });

  group('Γύρισμα πάνω στο χαρτί', () {
    bool rotate(double w, double h, PdfPageFormat page) =>
        floorPlanPrintShouldRotate(
          imageWidth: w,
          imageHeight: h,
          pageWidth: page.width,
          pageHeight: page.height,
        );

    test('πλατύς χάρτης σε κατακόρυφο χαρτί γυρίζει', () {
      expect(rotate(3000, 1500, PdfPageFormat.a4), isTrue);
    });

    test('πλατύς χάρτης σε οριζόντιο χαρτί μένει όρθιος', () {
      expect(rotate(3000, 1500, PdfPageFormat.a4.landscape), isFalse);
    });

    test('ψηλός χάρτης σε οριζόντιο χαρτί γυρίζει', () {
      expect(rotate(1500, 3000, PdfPageFormat.a4.landscape), isTrue);
    });

    test('σχεδόν τετράγωνος όροφος μένει όρθιος', () {
      expect(rotate(3160, 3004, PdfPageFormat.a4), isFalse);
    });
  });

  test(
    'το έγγραφο βγαίνει έγκυρο PDF και με άλλο χαρτί από το αρχικό',
    () async {
      final bytes = await buildFloorPlanPdf(
        rgba: Uint8List(4 * 40 * 20),
        width: 40,
        height: 20,
        format: PdfPageFormat.a3,
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    },
  );
}
