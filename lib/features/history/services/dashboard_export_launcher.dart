/// Η μία πόρτα για την εξαγωγή των Στατιστικών Κλήσεων.
///
/// Ρωτά πού να σωθεί, φτιάχνει τα bytes της μορφής που ζητήθηκε, γράφει, και
/// λέει στον χρήστη τι έγινε. Ζει έξω από την οθόνη ώστε το widget να δηλώνει
/// «θέλω εξαγωγή σε Excel» και τίποτε άλλο.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../screens/dashboard_top_bar.dart';
import 'dashboard_excel_export.dart';
import 'dashboard_export_document.dart';
import 'dashboard_pdf_export.dart';

/// Η γραμματοσειρά που ενσωματώνεται στο PDF.
///
/// Το Inter συνοδεύει ήδη την εφαρμογή και καλύπτει το ελληνικό αλφάβητο· οι
/// ενσωματωμένες γραμματοσειρές του PDF δεν το καλύπτουν.
const String kDashboardPdfFontAsset = 'assets/fonts/Inter-Regular.ttf';

/// Εξάγει ό,τι δείχνει αυτή τη στιγμή η οθόνη.
///
/// Επιστρέφει τη διαδρομή του αρχείου, ή `null` όταν ο χρήστης ακύρωσε.
/// Τα μηνύματα προς τον χρήστη τα βγάζει η ίδια, μέσω του [messenger] που της
/// δίνει ο καλών: ο διάλογος αποθήκευσης κρατά αρκετή ώρα ώστε η οθόνη να έχει
/// φύγει όταν τελειώσει, και ένας `context` που δεν ζει πια δεν εμφανίζει
/// τίποτα.
Future<String?> exportDashboardStatistics({
  required ScaffoldMessengerState messenger,
  required DashboardExportFormat format,
  required DashboardSummaryModel data,
  required DashboardFilterModel filter,
  AssetBundle? bundle,
  DateTime? now,
}) async {
  final document = buildDashboardExportDocument(
    data: data,
    filter: filter,
    now: now,
  );

  final extension = switch (format) {
    DashboardExportFormat.excel => 'xlsx',
    DashboardExportFormat.pdf => 'pdf',
  };
  final suggestedName = '${dashboardExportFileBaseName(now: now)}.$extension';

  final Uri? destination;
  try {
    destination = await FilePicker.saveFile(
      dialogTitle: 'Εξαγωγή στατιστικών κλήσεων',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List(0),
    );
  } on Exception catch (error) {
    _show(messenger, 'Δεν άνοιξε ο διάλογος αποθήκευσης: '
        '${humanizeUserFacingError(error)}');
    return null;
  }
  if (destination == null) return null;

  final path = destination.toFilePath();

  try {
    final bytes = switch (format) {
      DashboardExportFormat.excel => buildDashboardExcel(document),
      DashboardExportFormat.pdf => await buildDashboardPdf(
        document,
        fontData: (await (bundle ?? rootBundle).load(kDashboardPdfFontAsset))
            .buffer
            .asUint8List(),
      ),
    };
    await File(path).writeAsBytes(bytes, flush: true);
  } on Exception catch (error) {
    _show(
      messenger,
      'Η εξαγωγή δεν ολοκληρώθηκε: ${humanizeUserFacingError(error)}',
    );
    return null;
  }

  _show(
    messenger,
    'Η εξαγωγή αποθηκεύτηκε.',
    action: SnackBarAction(
      label: 'Άνοιγμα φακέλου',
      onPressed: () => revealFileInExplorer(path),
    ),
  );
  return path;
}

/// Ανοίγει τον Explorer με το αρχείο επιλεγμένο.
///
/// Η αποτυχία δεν ενοχλεί τον χρήστη: το αρχείο έχει ήδη γραφτεί και η
/// διαδρομή του ειπώθηκε — το άνοιγμα του φακέλου είναι διευκόλυνση, όχι μέρος
/// της εξαγωγής.
Future<void> revealFileInExplorer(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path.replaceAll('/', r'\')]);
      return;
    }
    await Process.run('open', [File(path).parent.path]);
  } on Exception {
    // Σιωπηλά: δες την τεκμηρίωση παραπάνω.
  }
}

void _show(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      // Με ενέργεια, το μήνυμα δεν κλείνει μόνο του — ο χρήστης πρέπει να
      // προλάβει να την πατήσει.
      duration: action == null
          ? const Duration(seconds: 4)
          : const Duration(seconds: 10),
    ),
  );
}
