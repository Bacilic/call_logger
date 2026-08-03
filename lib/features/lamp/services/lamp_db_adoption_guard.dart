import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_file_classifier.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';

/// Απόφαση υιοθέτησης επιλεγμένου `.db` στον φορητό φάκελο της Λάμπας.
class LampDbAdoptionDecision {
  const LampDbAdoptionDecision({
    required this.allowed,
    required this.destinationExists,
    this.destinationIsConfiguredOutput = false,
    this.rejectionMessage,
  });

  final bool allowed;

  /// True όταν στον προορισμό υπάρχει ήδη **άλλο** αρχείο με το ίδιο όνομα.
  final bool destinationExists;

  /// True όταν το αρχείο στον προορισμό είναι η ρυθμισμένη βάση εξόδου —
  /// η αντικατάσταση θα κατέστρεφε αρχείο που χρησιμοποιεί η ίδια η εφαρμογή.
  final bool destinationIsConfiguredOutput;

  final String? rejectionMessage;
}

bool _isCallLoggerFamily(DatabaseFileKind kind) =>
    kind == DatabaseFileKind.callLogger || kind == DatabaseFileKind.hybrid;

/// Κρίνει αν επιτρέπεται η αντιγραφή του [pickedPath] στον [destinationPath].
///
/// Το [configuredOutputPath] (βάση που δημιουργεί το Excel) δηλώνεται ώστε η
/// σύγκρουση ονόματος να μπορεί να ονομάσει τι ακριβώς κινδυνεύει.
///
/// Οι [classify] και [fileExists] είναι injectable για τεστ χωρίς πραγματικά αρχεία.
Future<LampDbAdoptionDecision> decideLampDbAdoption({
  required String pickedPath,
  required String destinationPath,
  String? configuredOutputPath,
  Future<DatabaseFileKind> Function(String path)? classify,
  Future<bool> Function(String path)? fileExists,
}) async {
  final classifyFn = classify ?? classifyDatabaseFile;
  final existsFn = fileExists ?? ((String path) => File(path).exists());

  final pickedName = p.basename(pickedPath.trim());
  final pickedKind = await classifyFn(pickedPath);
  if (_isCallLoggerFamily(pickedKind)) {
    return LampDbAdoptionDecision(
      allowed: false,
      destinationExists: false,
      rejectionMessage:
          'Το αρχείο «$pickedName» είναι η βάση της Καταγραφής Κλήσεων, '
          'όχι της Λάμπας.',
    );
  }

  final destExists = await existsFn(destinationPath);
  final samePhysicalFile = LampOldDbValidator.pathsReferToSameFile(
    pickedPath,
    destinationPath,
  );
  if (!destExists || samePhysicalFile) {
    return const LampDbAdoptionDecision(
      allowed: true,
      destinationExists: false,
    );
  }

  final destName = p.basename(destinationPath.trim());
  final destKind = await classifyFn(destinationPath);
  if (_isCallLoggerFamily(destKind)) {
    return LampDbAdoptionDecision(
      allowed: false,
      destinationExists: true,
      rejectionMessage:
          'Στον φάκελο της Λάμπας υπάρχει ήδη αρχείο «$destName» που είναι '
          'η βάση της Καταγραφής Κλήσεων — η αντιγραφή θα την κατέστρεφε.',
    );
  }

  final outputPath = configuredOutputPath?.trim() ?? '';
  final destinationIsOutput =
      outputPath.isNotEmpty &&
      LampOldDbValidator.pathsReferToSameFile(destinationPath, outputPath);

  return LampDbAdoptionDecision(
    allowed: true,
    destinationExists: true,
    destinationIsConfiguredOutput: destinationIsOutput,
  );
}

/// Όνομα αρχείου για «διατήρηση και των δύο»: το αντίγραφο παίρνει μοναδικό
/// χρονοσφραγισμένο όνομα και το υπάρχον αρχείο δεν πειράζεται.
///
/// Ίδιος μηχανισμός ονοματοδοσίας με τα αντίγραφα της Καταγραφής Κλήσεων:
/// ημερομηνία → `HH-mm` → `HH-mm-ss` → αριθμητικό επίθημα.
String lampAdoptionKeepBothFileName({
  required String directory,
  required String pickedPath,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
}) {
  final stem = p.basenameWithoutExtension(pickedPath.trim());
  final ext = p.extension(pickedPath.trim());
  return resolveUniqueTimestampedFileName(
    directory: directory,
    baseName: stem.isEmpty ? 'lamp' : stem,
    suffix: '_',
    extension: ext.isEmpty ? '.db' : ext,
    now: now,
    fileExists: fileExists,
  );
}
