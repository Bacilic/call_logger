/// Πώς ονομάζεται το αρχείο ενός αντιγράφου.
///
/// Καθαρός υπολογισμός, χωρίς δίσκο και χωρίς βάση: δίνεις όνομα βάσης, ώρα
/// και προτίμηση μορφής, παίρνεις διαδρομές. Ζει έξω από τη ροή δημιουργίας
/// ώστε η ερώτηση «πώς θα λέγεται το αρχείο;» να μπορεί να απαντηθεί —και να
/// ελεγχθεί— χωρίς να τρέξει αντίγραφο.
library;

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/database_backup_settings.dart';

/// Οι διαδρομές ενός αντιγράφου, πριν γραφτεί οτιδήποτε.
///
/// Και οι δύο υπολογίζονται πάντα, ακόμη κι όταν το αντίγραφο θα μείνει
/// γρήγορο: η απόφαση «πλήρες ή γρήγορο» παίρνεται αργότερα, και δεν έχει
/// νόημα να ξαναμετρηθεί η ώρα τότε — δύο κλήσεις του ρολογιού θα μπορούσαν
/// να πέσουν σε διαφορετικό λεπτό και να δώσουν `.db` και `.zip` με ασύμφωνα
/// ονόματα.
class BackupArtifactPaths {
  const BackupArtifactPaths({
    required this.stem,
    required this.databasePath,
    required this.archivePath,
  });

  /// Το όνομα χωρίς επέκταση, κοινό και για τις δύο μορφές.
  final String stem;

  /// Το `.db` — το γρήγορο αντίγραφο, και το ενδιάμεσο κάθε πλήρους.
  final String databasePath;

  /// Το `.zip` — μόνο όταν το αντίγραφο βγει πλήρες.
  final String archivePath;
}

/// Η χρονοσφραγίδα του ονόματος: λεπτό ακριβείας, ταξινομήσιμη αλφαβητικά.
String formatBackupStamp(DateTime moment) =>
    DateFormat('yyyy-MM-dd_HH-mm').format(moment);

/// Χτίζει τις διαδρομές ενός αντιγράφου μέσα στον [destinationDirectory].
BackupArtifactPaths resolveBackupArtifactPaths({
  required String destinationDirectory,
  required String baseName,
  required DatabaseBackupNamingFormat namingFormat,
  required DateTime now,
}) {
  final stamp = formatBackupStamp(now);
  final stem = namingFormat == DatabaseBackupNamingFormat.dateTimeThenBase
      ? '${stamp}_$baseName'
      : '${baseName}_$stamp';

  return BackupArtifactPaths(
    stem: stem,
    databasePath: p.join(destinationDirectory, '$stem.db'),
    archivePath: p.join(destinationDirectory, '$stem.zip'),
  );
}
