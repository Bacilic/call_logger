/// Οι δύο έξοδοι του φύλλου μιας εκκρεμότητας: ο εκτυπωτής και το αρχείο.
///
/// Και οι δύο περνούν από το **ίδιο** έγγραφο και τα ίδια bytes — αλλιώς το
/// χαρτί και το PDF θα άρχιζαν να λένε διαφορετικά πράγματα, και η απόκλιση θα
/// φαινόταν μόνο όταν κάποιος τα έβαζε δίπλα-δίπλα.
///
/// Ζουν έξω από την οθόνη ώστε η κάρτα να δηλώνει «θέλω εκτύπωση» και τίποτε
/// άλλο.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../../history/services/dashboard_export_launcher.dart';
import '../models/task.dart';
import 'task_pdf_export.dart';
import 'task_print_document.dart';

/// Η γραμματοσειρά που ενσωματώνεται στο PDF.
///
/// Το Inter συνοδεύει ήδη την εφαρμογή και καλύπτει το ελληνικό αλφάβητο· οι
/// ενσωματωμένες γραμματοσειρές του PDF δεν το καλύπτουν.
const String kTaskPdfFontAsset = 'assets/fonts/Inter-Regular.ttf';

/// Τα bytes του φύλλου — το ένα σημείο απ' όπου περνούν και οι δύο έξοδοι.
Future<Uint8List> buildTaskSheetBytes(Task task, {AssetBundle? bundle}) async {
  final fontData = (await (bundle ?? rootBundle).load(
    kTaskPdfFontAsset,
  )).buffer.asUint8List();
  return buildTaskPdf(buildTaskPrintDocument(task), fontData: fontData);
}

/// Στέλνει τα [bytes] στο παράθυρο εκτύπωσης των Windows.
///
/// **Υπάρχει επειδή το έτοιμο κουμπί του πακέτου δεν φτάνει:** εκείνο καλεί τη
/// ροή με τις προεπιλογές, και τα Windows ανοίγουν τότε το παλιό «Παράμετροι
/// εκτύπωσης» — ένα κουτί ρυθμίσεων χαρτιού με κουμπί «OK», όπου δεν είναι καν
/// προφανές ότι κάτι θα τυπωθεί. Μετρημένο στην εφαρμογή, 20/09/2026.
///
/// Η ακύρωση από τον χρήστη δεν είναι σφάλμα και δεν ανακοινώνεται: πάτησε
/// «Άκυρο» και ξέρει τι έκανε.
Future<bool> sendSheetToPrinter({
  required ScaffoldMessengerState messenger,
  required Task task,
  required Uint8List bytes,
}) async {
  try {
    return await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: taskPrintFileName(task),
      // Το σύγχρονο παράθυρο: λίστα εκτυπωτών, αντίτυπα, κουμπί «Εκτύπωση».
      windowsModernDialog: true,
    );
  } on Exception catch (error) {
    _show(
      messenger,
      'Η εκτύπωση δεν ολοκληρώθηκε: ${humanizeUserFacingError(error)}',
    );
    return false;
  }
}

/// Ρωτά πού να σωθεί το φύλλο και το γράφει.
///
/// Επιστρέφει τη διαδρομή του αρχείου, ή `null` όταν ο χρήστης ακύρωσε.
Future<String?> saveTaskSheetAsPdf({
  required ScaffoldMessengerState messenger,
  required Task task,
  AssetBundle? bundle,
}) async {
  final Uri? destination;
  try {
    destination = await FilePicker.saveFile(
      dialogTitle: 'Αποθήκευση εκκρεμότητας ως PDF',
      fileName: taskPrintFileName(task),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: Uint8List(0),
    );
  } on Exception catch (error) {
    _show(
      messenger,
      'Δεν άνοιξε ο διάλογος αποθήκευσης: '
      '${humanizeUserFacingError(error)}',
    );
    return null;
  }
  if (destination == null) return null;

  final path = destination.toFilePath();
  try {
    final bytes = await buildTaskSheetBytes(task, bundle: bundle);
    await File(path).writeAsBytes(bytes, flush: true);
  } on Exception catch (error) {
    _show(
      messenger,
      'Η αποθήκευση δεν ολοκληρώθηκε: ${humanizeUserFacingError(error)}',
    );
    return null;
  }

  _show(
    messenger,
    'Η εκκρεμότητα αποθηκεύτηκε ως PDF.',
    action: SnackBarAction(
      label: 'Άνοιγμα φακέλου',
      // Το ίδιο εργαλείο με την εξαγωγή των Στατιστικών: ο χρήστης έχει μάθει
      // ότι μετά από κάθε αποθήκευση ένα κλικ τον πάει στο αρχείο.
      onPressed: () => revealFileInExplorer(path),
    ),
  );
  return path;
}

void _show(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
}) {
  messenger.showSnackBar(SnackBar(content: Text(message), action: action));
}
