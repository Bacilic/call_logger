import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';

/// Απόφαση υιοθέτησης επιλεγμένου `.db` στον φορητό φάκελο της Λάμπας.
class LampDbAdoptionDecision {
  const LampDbAdoptionDecision({
    required this.allowed,
    required this.requiresOverwriteConfirmation,
    this.rejectionMessage,
  });

  final bool allowed;
  final bool requiresOverwriteConfirmation;
  final String? rejectionMessage;
}

bool _isCallLoggerFamily(DatabaseFileKind kind) =>
    kind == DatabaseFileKind.callLogger || kind == DatabaseFileKind.hybrid;

/// Κρίνει αν επιτρέπεται η αντιγραφή του [pickedPath] στον [destinationPath].
///
/// Οι [classify] και [fileExists] είναι injectable για τεστ χωρίς πραγματικά αρχεία.
Future<LampDbAdoptionDecision> decideLampDbAdoption({
  required String pickedPath,
  required String destinationPath,
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
      requiresOverwriteConfirmation: false,
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
      requiresOverwriteConfirmation: false,
    );
  }

  final destName = p.basename(destinationPath.trim());
  final destKind = await classifyFn(destinationPath);
  if (_isCallLoggerFamily(destKind)) {
    return LampDbAdoptionDecision(
      allowed: false,
      requiresOverwriteConfirmation: false,
      rejectionMessage:
          'Στον φάκελο της Λάμπας υπάρχει ήδη αρχείο «$destName» που είναι '
          'η βάση της Καταγραφής Κλήσεων — η αντιγραφή θα την κατέστρεφε.',
    );
  }

  return const LampDbAdoptionDecision(
    allowed: true,
    requiresOverwriteConfirmation: true,
  );
}
