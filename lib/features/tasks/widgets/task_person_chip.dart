import 'package:flutter/material.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../../operators/avatars/operator_avatar_image.dart';

/// Ποιον ρόλο παίζει το πρόσωπο πάνω στην κάρτα.
///
/// Ρητός ρόλος και όχι ναι/όχι: με τρεις περιπτώσεις, ένα «είναι ο δημιουργός;»
/// θα έστελνε σιωπηλά τον κλείσαντα στη μορφή του υπευθύνου — δηλαδή θα του
/// έδινε κουμπί που δεν οδηγεί πουθενά.
enum TaskPersonRole {
  /// Ο υπεύθυνος — αλλάζει, άρα το σήμα του είναι κουμπί.
  assignee,

  /// Ο δημιουργός — γεγονός του παρελθόντος, ένδειξη που δεν πατιέται.
  creator,

  /// Ο άνθρωπος που ολοκλήρωσε την εκκρεμότητα — επίσης γεγονός.
  closer,
}

/// Τα πρόσωπα μιας εκκρεμότητας, με μορφή που δηλώνει τον ρόλο τους.
///
/// Ο **υπεύθυνος** αλλάζει: το σήμα του είναι κουμπί και ανοίγει τον επιλογέα
/// ανάθεσης. Ο **δημιουργός** και ο **κλείσας** είναι γεγονότα του παρελθόντος
/// και δεν αλλάζουν ποτέ: τα σήματά τους είναι ενδείξεις που δεν πατιούνται. Αν
/// έμοιαζαν ίδια, ο χρήστης θα δοκίμαζε να αλλάξει κάτι που δεν αλλάζει.
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
  }) : _role = TaskPersonRole.assignee;

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
       _role = TaskPersonRole.creator;

  /// Ο άνθρωπος που ολοκλήρωσε την εκκρεμότητα — ένδειξη που δεν πατιέται.
  ///
  /// Μπαίνει μόνο όταν **δεν** είναι αυτός που τη χρωστούσε: αλλιώς η κάρτα θα
  /// έλεγε δύο φορές το ίδιο όνομα. Είναι η αναγνώριση της δουλειάς που έγινε
  /// σε ξένη βάρδια — ως τώρα φαινόταν μόνο σε όποιον άνοιγε το Ιστορικό.
  const TaskPersonChip.closer({
    required this.name,
    this.avatarKey,
    this.isDisabledProfile = false,
    super.key,
  }) : onAssign = null,
       _role = TaskPersonRole.closer;

  final String name;
  final VoidCallback? onAssign;

  /// Το εικονίδιο του προσώπου· `null` δίνει το κλασικό ανθρωπάκι.
  final String? avatarKey;

  /// Το προφίλ έχει απενεργοποιηθεί: το όνομα γράφεται πλάγια και η υπόδειξη
  /// το λέει. Ολόκληρη η λέξη δεν χωρά — το σήμα είναι στενό και θα έσπρωχνε
  /// τα κουμπιά δίπλα· στις λίστες επιλογής, όπου ο χώρος φτάνει και η
  /// απόφαση είναι ενεργή, γράφεται κανονικά «(απενεργοποιημένος)».
  final bool isDisabledProfile;

  final TaskPersonRole _role;

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

  /// Το ρήμα μπροστά από το όνομα ξεχωρίζει τους δύο παθητικούς ρόλους: χωρίς
  /// αυτό, δύο ίδια σήματα δίπλα-δίπλα δεν θα έλεγαν ποιος έκανε τι.
  String get _label => switch (_role) {
    TaskPersonRole.assignee => name,
    TaskPersonRole.creator => 'Άνοιξε: $name',
    TaskPersonRole.closer => 'Έκλεισε: $name',
  };

  String get _tooltip => switch (_role) {
    TaskPersonRole.assignee =>
      onAssign == null
          ? 'Υπεύθυνος$_disabledNote'
          : 'Υπεύθυνος$_disabledNote — κλικ για αλλαγή ανάθεσης',
    TaskPersonRole.creator => 'Δημιουργός της εκκρεμότητας$_disabledNote',
    TaskPersonRole.closer => 'Ολοκλήρωσε την εκκρεμότητα$_disabledNote',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = OperatorAvatarImage(
      avatarKey: avatarKey,
      size: 18,
      muted: isDisabledProfile,
    );
    final label = Text(_label, style: _labelStyle(theme));

    if (_role != TaskPersonRole.assignee) {
      return CompactTooltip(
        message: _tooltip,
        child: Chip(
          avatar: avatar,
          label: label,
          padding: _padding,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return CompactTooltip(
      message: _tooltip,
      child: ActionChip(
        avatar: avatar,
        label: label,
        onPressed: onAssign,
        padding: _padding,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
