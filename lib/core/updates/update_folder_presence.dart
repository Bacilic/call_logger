import 'dart:io';

/// Υπάρχει ο φάκελος ενημερώσεων που έχει οριστεί;
enum UpdateFolderPresence {
  /// Δεν έχει οριστεί διαδρομή — η εφαρμογή πέφτει στο `update_source.json`
  /// δίπλα στο εκτελέσιμο. Δεν είναι σφάλμα, είναι έγκυρη επιλογή.
  unset,

  /// Ορίστηκε διαδρομή αλλά ο φάκελος δεν βρίσκεται τώρα.
  missing,

  /// Ο φάκελος υπάρχει και είναι προσπελάσιμος.
  present,
}

/// Έλεγχος ύπαρξης φακέλου — αντικαθίσταται στα τεστ.
typedef DirectoryExistsProbe = Future<bool> Function(String path);

/// Υπάρχει ο φάκελος της [raw] διαδρομής;
///
/// Κενή διαδρομή δεν είναι σφάλμα: σημαίνει «χρησιμοποίησε το
/// `update_source.json` δίπλα στο εκτελέσιμο», και το πεδίο το λέει ήδη.
///
/// Σε άφταστη διαδρομή δικτύου (UNC εκτός δικτύου) το `exists()` των Windows
/// **πετάει** αντί να απαντήσει `false`. Για τον χρήστη η κατάσταση είναι μία:
/// ο φάκελος δεν είναι εκεί τώρα — γι' αυτό η εξαίρεση γίνεται [missing] και
/// όχι σιωπή.
Future<UpdateFolderPresence> probeUpdateFolderPresence(
  String raw, {
  DirectoryExistsProbe? exists,
}) async {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return UpdateFolderPresence.unset;

  final probe = exists ?? _systemDirectoryExists;
  try {
    return await probe(trimmed)
        ? UpdateFolderPresence.present
        : UpdateFolderPresence.missing;
  } on FileSystemException {
    return UpdateFolderPresence.missing;
  } catch (_) {
    return UpdateFolderPresence.missing;
  }
}

Future<bool> _systemDirectoryExists(String path) => Directory(path).exists();
