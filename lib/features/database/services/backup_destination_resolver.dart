import 'dart:io';

import '../../../core/utils/user_facing_error_messages.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_location_hints.dart';

/// Πώς τελείωσε η προσπάθεια να οριστεί φάκελος προορισμού.
enum BackupDestinationOutcome {
  /// Ο φάκελος είναι έγκυρος και η διαδρομή πρέπει να αποθηκευτεί.
  valid,

  /// Ο χρήστης ακύρωσε τη δημιουργία — ισχύει το μήνυμα της επικύρωσης.
  cancelled,

  /// Δεν έγινε· το [BackupDestinationResolution.errorMessage] λέει γιατί.
  invalid,
}

/// Το αποτέλεσμα της επικύρωσης, με το μήνυμα που θα δει ο χρήστης.
class BackupDestinationResolution {
  const BackupDestinationResolution(this.outcome, {this.errorMessage});

  final BackupDestinationOutcome outcome;
  final String? errorMessage;

  bool get isValid => outcome == BackupDestinationOutcome.valid;
}

/// Ζητά από τον χρήστη άδεια να δημιουργηθεί ο φάκελος.
typedef CreateFolderConfirmation = Future<bool> Function(String folderPath);

/// Επικυρώνει τη διαδρομή προορισμού και, αν λείπει ο φάκελος, τον φτιάχνει.
///
/// Η λογική ζει εδώ και όχι μέσα στην καρτέλα, ώστε να μπορεί να ελεγχθεί
/// χωρίς οθόνη: η μόνη εξάρτηση από διεπαφή είναι η [confirmCreate], που ο
/// καλών υλοποιεί με διάλογο.
///
/// **Ο δίσκος ελέγχεται ΠΡΙΝ προσφερθεί δημιουργία:** σε αποσυνδεδεμένο ή
/// ανύπαρκτο τόμο η δημιουργία είναι αδύνατη, και η ερώτηση «να τον φτιάξω;»
/// δίνει ελπίδα που δεν υπάρχει.
Future<BackupDestinationResolution> resolveBackupDestination(
  String rawPath, {
  required CreateFolderConfirmation confirmCreate,
}) async {
  var result = await BackupDestinationFolderValidator.validate(rawPath);
  if (result.kind != BackupDestinationValidationKind.missingDirectory) {
    return _fromValidation(result);
  }

  final trimmed = rawPath.trim();
  if (!BackupLocationHints.volumeOfPathExists(trimmed)) {
    return BackupDestinationResolution(
      BackupDestinationOutcome.invalid,
      errorMessage: missingVolumeMessage(trimmed),
    );
  }

  if (!await confirmCreate(trimmed)) {
    return BackupDestinationResolution(
      BackupDestinationOutcome.cancelled,
      errorMessage: result.errorMessage,
    );
  }

  try {
    await Directory(trimmed).create(recursive: true);
  } catch (e) {
    return BackupDestinationResolution(
      BackupDestinationOutcome.invalid,
      errorMessage:
          'Δεν ήταν δυνατή η δημιουργία του φακέλου: '
          '${humanizeUserFacingError(e)}',
    );
  }

  result = await BackupDestinationFolderValidator.validate(rawPath);
  return _fromValidation(result);
}

BackupDestinationResolution _fromValidation(
  BackupDestinationValidationResult result,
) {
  if (result.kind == BackupDestinationValidationKind.ok) {
    return const BackupDestinationResolution(BackupDestinationOutcome.valid);
  }
  return BackupDestinationResolution(
    BackupDestinationOutcome.invalid,
    errorMessage: result.errorMessage,
  );
}

/// Το μήνυμα για δίσκο που δεν υπάρχει — με τους δίσκους που υπάρχουν.
///
/// Η εφαρμογή ήδη ξέρει ποιοι τόμοι είναι συνδεδεμένοι· το να τους πει είναι
/// η διαφορά ανάμεσα σε «κάτι πήγε στραβά» και «ορίστε τι μπορείτε να
/// διαλέξετε».
String missingVolumeMessage(String folderPath) {
  final letter = BackupLocationHints.windowsDriveLetterFromPath(folderPath);
  final drives = BackupLocationHints.eligibleWindowsBackupDriveLabels();
  final head = letter == null
      ? 'Ο δίσκος της διαδρομής δεν είναι διαθέσιμος'
      : 'Ο δίσκος $letter: δεν υπάρχει ή δεν είναι συνδεδεμένος';
  if (drives.isEmpty) {
    return '$head — ο φάκελος δεν μπορεί να δημιουργηθεί εκεί.';
  }
  return '$head — ο φάκελος δεν μπορεί να δημιουργηθεί εκεί. '
      'Διαθέσιμοι δίσκοι: ${drives.join(', ')}.';
}
