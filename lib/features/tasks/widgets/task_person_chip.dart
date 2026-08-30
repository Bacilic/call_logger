import 'package:flutter/material.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../../operators/avatars/operator_avatar_image.dart';

/// Τα δύο πρόσωπα μιας εκκρεμότητας, με μορφή που δηλώνει τον ρόλο τους.
///
/// Ο **υπεύθυνος** αλλάζει: το σήμα του είναι κουμπί και ανοίγει τον επιλογέα
/// ανάθεσης. Ο **δημιουργός** είναι γεγονός του παρελθόντος και δεν αλλάζει
/// ποτέ: το σήμα του είναι ένδειξη που δεν πατιέται. Αν τα δύο έμοιαζαν ίδια,
/// ο χρήστης θα δοκίμαζε να αλλάξει κάτι που δεν αλλάζει.
class TaskPersonChip extends StatelessWidget {
  /// Ο υπεύθυνος — κουμπί προς τον επιλογέα ανάθεσης.
  ///
  /// Με [onAssign] `null` μένει ένδειξη: κουμπί που δεν οδηγεί πουθενά είναι
  /// χειρότερο από απλή ένδειξη.
  const TaskPersonChip.assignee({
    required this.name,
    required this.onAssign,
    this.avatarKey,
    this.isDisabledProfile = false,
    super.key,
  }) : _isCreator = false;

  /// Ο δημιουργός — ένδειξη που δεν πατιέται.
  ///
  /// Κουβαλά κι αυτός το πρόσωπο του χρήστη. Παλιότερα έμενε χωρίς εικονίδιο,
  /// γιατί το γενικό `person_outline` ήταν ήδη πιασμένο δύο φορές στην ίδια
  /// κάρτα και ένα τρίτο ίδιο θα μπέρδευε. Το προσωπικό εικονίδιο **ξεχωρίζει
  /// από μόνο του** — και εδώ ακριβώς κερδίζει: με μια ματιά φαίνεται ποιος
  /// άνοιξε την εκκρεμότητα και ποιος τη χρωστά.
  const TaskPersonChip.creator({
    required this.name,
    this.avatarKey,
    this.isDisabledProfile = false,
    super.key,
  }) : onAssign = null,
       _isCreator = true;

  final String name;
  final VoidCallback? onAssign;

  /// Το εικονίδιο του προσώπου· `null` δίνει το κλασικό ανθρωπάκι.
  final String? avatarKey;

  /// Το προφίλ έχει απενεργοποιηθεί: το όνομα γράφεται πλάγια και η υπόδειξη
  /// το λέει. Ολόκληρη η λέξη δεν χωρά — το σήμα είναι στενό και θα έσπρωχνε
  /// τα κουμπιά δίπλα· στις λίστες επιλογής, όπου ο χώρος φτάνει και η
  /// απόφαση είναι ενεργή, γράφεται κανονικά «(απενεργοποιημένος)».
  final bool isDisabledProfile;

  final bool _isCreator;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 0,
  );

  /// Πλάγια για το απενεργοποιημένο προφίλ — ίδιο σήμα με το «(διαγραμμένο)»
  /// των οντοτήτων καταλόγου, που κάθεται λίγα εικονοστοιχεία παραδίπλα.
  TextStyle? _labelStyle(ThemeData theme) {
    final base = theme.textTheme.labelSmall;
    if (!isDisabledProfile) return base;
    return (base ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
  }

  String get _disabledNote =>
      isDisabledProfile ? ' (απενεργοποιημένο προφίλ)' : '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isCreator) {
      return CompactTooltip(
        message: 'Δημιουργός της εκκρεμότητας$_disabledNote',
        child: Chip(
          avatar: OperatorAvatarImage(
            avatarKey: avatarKey,
            size: 18,
            muted: isDisabledProfile,
          ),
          label: Text('Άνοιξε: $name', style: _labelStyle(theme)),
          padding: _padding,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return CompactTooltip(
      message: onAssign == null
          ? 'Υπεύθυνος$_disabledNote'
          : 'Υπεύθυνος$_disabledNote — κλικ για αλλαγή ανάθεσης',
      child: ActionChip(
        avatar: OperatorAvatarImage(
          avatarKey: avatarKey,
          size: 18,
          muted: isDisabledProfile,
        ),
        label: Text(name, style: _labelStyle(theme)),
        onPressed: onAssign,
        padding: _padding,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
