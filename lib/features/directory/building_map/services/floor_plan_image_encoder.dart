import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ποιότητα JPEG των κατόψεων (απόφαση Διευθυντή 17/10/2026).
///
/// Μετρημένο στις 7 κατόψεις του σπιτιού: 8,5 MB σε PNG → 0,85 MB, χωρίς ορατή
/// διαφορά σε διπλή μεγέθυνση. Η WebP ίδιας ποιότητας θα έβγαινε μικρότερη,
/// αλλά η βιβλιοθήκη εικόνων γράφει WebP μόνο χωρίς απώλειες (5,1 MB).
const int kFloorPlanJpegQuality = 85;

/// Η εικόνα που διάλεξε ο χρήστης δεν διαβάζεται ως εικόνα.
class FloorPlanImageUnreadable implements Exception {
  const FloorPlanImageUnreadable();

  @override
  String toString() => 'Το αρχείο δεν αναγνωρίστηκε ως εικόνα.';
}

/// Μετατρέπει την εικόνα που διάλεξε ο χρήστης στη μορφή που αποθηκεύεται.
///
/// **Οι διαστάσεις δεν αλλάζουν ποτέ.** Οι θέσεις των τμημάτων στον χάρτη
/// γράφονται ως ποσοστό του πλάτους/ύψους της εικόνας· μια σμίκρυνση θα ήταν
/// ακίνδυνη για τα ποσοστά, αλλά θα έκρυβε λεπτομέρεια που ο χρήστης διάλεξε.
///
/// **Η διαφάνεια γεμίζει λευκό.** Το JPEG δεν κρατά διαφάνεια· χωρίς το
/// γέμισμα τα διάφανα σημεία θα έβγαιναν μαύρα.
///
/// Καθαρή συνάρτηση, για να τρέχει σε δικό της νήμα (`Isolate.run`): η
/// μετατροπή μιας μεγάλης εικόνας κρατά δευτερόλεπτα.
Uint8List encodeFloorPlanImage(Uint8List source) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    // Η βιβλιοθήκη πετά ό,τι τύχει (π.χ. RangeError) σε κομμένο ή ξένο
    // αρχείο· ο χρήστης χρειάζεται ένα μήνυμα, όχι το εσωτερικό σφάλμα.
    throw const FloorPlanImageUnreadable();
  }
  if (decoded == null) throw const FloorPlanImageUnreadable();

  var opaque = decoded;
  if (decoded.hasAlpha) {
    opaque = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(opaque, decoded);
  }
  return img.encodeJpg(opaque, quality: kFloorPlanJpegQuality);
}
