import 'package:flutter/material.dart';

import 'operator_avatar_catalog.dart';

/// Το εικονίδιο ενός χρήστη, όπου κι αν εμφανίζεται.
///
/// **Μία πηγή για όλες τις θέσεις** — τη λίστα «Χρήστες», τον επιλογέα
/// ταυτότητας, την μπάρα πλοήγησης και τα σήματα των εκκρεμοτήτων. Τέσσερα
/// αντίγραφα του ίδιου κώδικα θα απέκλιναν στην πρώτη αλλαγή: το ένα θα
/// έδειχνε το κλασικό ανθρωπάκι όταν λείπει εικονίδιο, το άλλο κενό.
///
/// **Τι γίνεται όταν δεν υπάρχει εικονίδιο.** Δείχνεται το κλασικό ανθρωπάκι.
/// Συμβαίνει σε τρεις περιπτώσεις, και καμία δεν είναι σφάλμα: το προφίλ
/// γεννήθηκε όταν τα εικονίδια είχαν τελειώσει, η βάση γράφτηκε από νεότερη
/// έκδοση με εικονίδιο που δεν γνωρίζουμε, ή το αρχείο λείπει από το πακέτο.
class OperatorAvatarImage extends StatelessWidget {
  const OperatorAvatarImage({
    super.key,
    required this.avatarKey,
    this.size = 40,
    this.muted = false,
  });

  /// Το κλειδί του καταλόγου· `null` ή άγνωστο δίνει το κλασικό ανθρωπάκι.
  final String? avatarKey;

  /// Η πλευρά του τετραγώνου μέσα στο οποίο ζωγραφίζεται.
  final double size;

  /// Απενεργοποιημένο προφίλ: το εικονίδιο ξεθωριάζει.
  ///
  /// Ίδια γλώσσα με τα πλάγια γράμματα του ονόματος — «υπάρχει, αλλά δεν
  /// δουλεύει πια εδώ».
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final avatar = findAvatar(avatarKey);
    if (avatar == null) return _fallback(context);

    Widget image = Image.asset(
      avatar.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // Το εικονίδιο δεν είναι πληροφορία που λείπει αν χαθεί το αρχείο: το
      // όνομα του χρήστη γράφεται πάντα δίπλα. Γι' αυτό η αποτυχία φόρτωσης
      // πέφτει σιωπηλά στο ανθρωπάκι αντί να δείξει σπασμένη εικόνα.
      errorBuilder: (context, _, _) => _fallback(context),
    );

    if (muted) {
      image = Opacity(opacity: 0.45, child: image);
    }
    return SizedBox(width: size, height: size, child: image);
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      Icons.person,
      size: size * 0.82,
      color: muted ? scheme.onSurfaceVariant : scheme.primary,
    );
  }
}
