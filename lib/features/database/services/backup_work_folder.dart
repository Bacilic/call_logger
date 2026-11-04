import 'dart:io';

import 'package:path/path.dart' as p;

/// Προσωρινός φάκελος μέσα στον προορισμό, όπου χτίζεται ένα αντίγραφο πριν
/// πάρει το κανονικό του όνομα.
///
/// Έτσι ισχύουν δύο κανόνες:
/// - **μισό αρχείο δεν μοιάζει ποτέ έγκυρο** — οι λίστες αντιγράφων και η
///   εκκαθάριση δεν κοιτούν μέσα σε υποφακέλους,
/// - **αποτυχία δεν σβήνει το προηγούμενο αντίγραφο** με το ίδιο όνομα, ούτε
///   αυτό άλλου υπολογιστή που γράφει το ίδιο λεπτό στον ίδιο φάκελο.
///
/// Βρίσκεται μέσα στον προορισμό επίτηδες: η μετακίνηση στον ίδιο δίσκο είναι
/// ατομική, ενώ από τον δίσκο του συστήματος θα ήταν ξανά αντιγραφή.
class BackupWorkFolder {
  BackupWorkFolder._(this._directory);

  static const String _namePrefix = '.call_logger_backup_in_progress_';

  /// Πόσο περιμένουμε πριν θεωρήσουμε εγκαταλειμμένο έναν φάκελο που άφησε
  /// απότομος τερματισμός. Πολύ πάνω από κάθε αντίγραφο σε εξέλιξη, ώστε να μην
  /// αγγίξουμε φάκελο άλλου υπολογιστή που γράφει τώρα.
  static const Duration abandonedAfter = Duration(days: 2);

  final Directory _directory;

  /// Δημιουργεί φάκελο με όνομα που δεν συμπίπτει με κανενός άλλου.
  static Future<BackupWorkFolder> create(String destination) async {
    final name =
        '$_namePrefix${DateTime.now().microsecondsSinceEpoch}_${pid}_'
        '${Platform.localHostname}';
    final directory = Directory(p.join(destination, name));
    await directory.create();
    return BackupWorkFolder._(directory);
  }

  /// Πού γράφεται προσωρινά το αρχείο που θα καταλήξει στο [finalPath].
  ///
  /// Το όνομα μένει ίδιο, οπότε ο έλεγχος του αντιγράφου κρίνει το είδος του
  /// από την κατάληξη όπως πάντα.
  String pathFor(String finalPath) =>
      p.join(_directory.path, p.basename(finalPath));

  /// Δίνει στο αρχείο το κανονικό του όνομα, αντικαθιστώντας ό,τι υπάρχει ήδη.
  Future<void> publish(String finalPath) async {
    await File(pathFor(finalPath)).rename(finalPath);
  }

  /// Βρίσκεται η [path] μέσα σε αυτόν τον φάκελο;
  bool holds(String? path) => path != null && p.isWithin(_directory.path, path);

  /// Σβήνει τον φάκελο και ό,τι έμεινε μέσα του.
  ///
  /// Δεν ρίχνει το αντίγραφο αν αποτύχει: ένας φάκελος που έμεινε πίσω είναι
  /// ακαταστασία, και τον μαζεύει το [removeAbandoned] στο επόμενο αντίγραφο.
  Future<void> dispose() async {
    try {
      await _directory.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  /// Μαζεύει φακέλους που έμειναν από εκτέλεση που διακόπηκε απότομα.
  static Future<void> removeAbandoned(
    String destination, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    try {
      await for (final entity in Directory(
        destination,
      ).list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!p.basename(entity.path).startsWith(_namePrefix)) continue;
        final age = current.difference((await entity.stat()).modified);
        if (age > abandonedAfter) await entity.delete(recursive: true);
      }
    } on FileSystemException {
      return;
    }
  }
}
