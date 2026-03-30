import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup_location_hints.dart';

/// Προειδοποιήσεις τοποθεσίας προορισμού backup σε σχέση με τη βάση.
class BackupDestinationLocationWarnings {
  BackupDestinationLocationWarnings._();

  /// True αν ο φάκελος προορισμού είναι ο ίδιος με το φάκελο του αρχείου βάσης
  /// ή βρίσκεται **μέσα** σε αυτόν (υποφάκελος).
  static bool colocatedWithDatabase({
    required String databaseFilePath,
    required String destinationDirectory,
  }) {
    final dbRaw = databaseFilePath.trim();
    final destRaw = destinationDirectory.trim();
    if (dbRaw.isEmpty || destRaw.isEmpty) return false;

    final dbNorm = p.normalize(dbRaw);
    final destNorm = p.normalize(destRaw);

    final dbFolder = p.dirname(dbNorm);
    if (p.equals(dbFolder, destNorm)) return true;
    if (p.isWithin(dbFolder, destNorm)) return true;
    return false;
  }

  /// True αν και οι δύο διαδρομές έχουν γράμμα τόμου Windows και είναι ίδιο.
  /// Σε UNC ή μη Windows / χωρίς γράμμα επιστρέφει false.
  static bool sameWindowsVolume({
    required String databasePath,
    required String destinationDirectory,
  }) {
    if (!Platform.isWindows) return false;
    final a = BackupLocationHints.windowsDriveLetterFromPath(databasePath);
    final b = BackupLocationHints.windowsDriveLetterFromPath(destinationDirectory);
    if (a == null || b == null) return false;
    return a == b;
  }
}
