import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../../core/utils/safe_file_base_name.dart';
import '../../../../../core/utils/user_facing_error_messages.dart';
import '../floor_plan_output.dart';
import 'floor_plan_export.dart';

/// Αρκεί για 300 dpi σε A4. Παραπάνω το χαρτί δεν κερδίζει τίποτα, ενώ το
/// στιγμιότυπο μιας μεγάλης οθόνης θα έβγαινε έγγραφο εκατοντάδων MB.
const double _kPrintMaxLongSide = 3500;

/// Περιθώριο της σελίδας: ένα εκατοστό, περισσότερο από όσο αφήνει ακάλυπτο
/// ένας εκτυπωτής.
const double _kPageMargin = PdfPageFormat.cm;

/// Η σελίδα με την οποία ανοίγει το παράθυρο εκτύπωσης: A4, με τον
/// προσανατολισμό που ταιριάζει στον χάρτη.
PdfPageFormat floorPlanPrintFormat(int imageWidth, int imageHeight) =>
    imageWidth > imageHeight ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

/// Πόσο πρέπει να μεγαλώσει ο χάρτης για να αξίζει το γύρισμα: ένας σχεδόν
/// τετράγωνος όροφος μένει όρθιος, αντί να διαβάζεται στο πλάι για 5% παραπάνω.
const double _kRotateGain = 1.1;

/// Αν ο χάρτης πρέπει να γυρίσει κατά 90° πάνω στο χαρτί. Το παράθυρο των
/// Windows δεν ακολουθεί τον προσανατολισμό που του προτείνεται (μετρημένο στην
/// εφαρμογή, 04/11/2026): ανοίγει κατακόρυφο, και ένας πλατύς χάρτης θα έπιανε
/// μισή σελίδα.
bool floorPlanPrintShouldRotate({
  required double imageWidth,
  required double imageHeight,
  required double pageWidth,
  required double pageHeight,
}) {
  final straight = math.min(pageWidth / imageWidth, pageHeight / imageHeight);
  final turned = math.min(pageWidth / imageHeight, pageHeight / imageWidth);
  return turned > straight * _kRotateGain;
}

/// Το έγγραφο: μία σελίδα, όπου ο χάρτης χωρά ολόκληρος χωρίς να παραμορφωθεί.
/// Η [format] είναι το χαρτί που διάλεξε ο χρήστης στο παράθυρο εκτύπωσης.
Future<Uint8List> buildFloorPlanPdf({
  required Uint8List rgba,
  required int width,
  required int height,
  required PdfPageFormat format,
}) {
  final document = pw.Document();
  final image = pw.RawImage(bytes: rgba, width: width, height: height);
  final rotate = floorPlanPrintShouldRotate(
    imageWidth: width.toDouble(),
    imageHeight: height.toDouble(),
    pageWidth: format.width,
    pageHeight: format.height,
  );
  document.addPage(
    pw.Page(
      pageFormat: format,
      orientation: !rotate
          ? pw.PageOrientation.natural
          : format.width > format.height
          ? pw.PageOrientation.portrait
          : pw.PageOrientation.landscape,
      margin: const pw.EdgeInsets.all(_kPageMargin),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ),
  );
  return document.save();
}

/// Τυπώνει τον όροφο από το σύγχρονο παράθυρο των Windows. Η ακύρωση από τον
/// χρήστη δεν είναι σφάλμα και δεν ανακοινώνεται.
Future<void> printFloorPlan({
  required BuildContext context,
  required int floorId,
  required String floorLabel,
  required FloorPlanOutputScope scope,
  required GlobalKey snapshotKey,
  Set<String> hiddenLayers = const {},
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final render = await prepareFloorPlanOutput(
    context: context,
    floorId: floorId,
    floorLabel: floorLabel,
    scope: scope,
    snapshotKey: snapshotKey,
    hiddenLayers: hiddenLayers,
    snapshotMaxLongSide: _kPrintMaxLongSide,
  );
  if (render == null) return;
  try {
    final ui.Image raster = await render();
    final width = raster.width;
    final height = raster.height;
    final data = await raster.toByteData();
    raster.dispose();
    if (data == null) throw StateError('Η εικόνα του χάρτη δεν διαβάστηκε.');
    final rgba = data.buffer.asUint8List();
    await Printing.layoutPdf(
      onLayout: (format) => buildFloorPlanPdf(
        rgba: rgba,
        width: width,
        height: height,
        format: format,
      ),
      name: safeFileBaseName(floorPlanOutputFileName(floorLabel, scope)),
      format: floorPlanPrintFormat(width, height),
      // Το σύγχρονο παράθυρο: λίστα εκτυπωτών, αντίτυπα, κουμπί «Εκτύπωση».
      windowsModernDialog: true,
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Η εκτύπωση δεν ολοκληρώθηκε: ${humanizeUserFacingError(error)}',
        ),
      ),
    );
  }
}
