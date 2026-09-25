import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';
import '../../../core/services/profile_availability.dart';
import '../screens/operator_picker_screen.dart';
import '../services/selectable_profiles.dart';
import 'admin_override_dialog.dart';
import 'change_operator_dialog.dart';

/// Η οθόνη «Ποιος είστε;» που **ξαναδιαβάζει** όσο μένει ανοιχτή.
///
/// **Γιατί δεν αρκεί μία φόρτωση.** Ένα προφίλ κλειδώνεται όσο το κρατά άλλος
/// υπολογιστής, και το κλείδωμα λύνεται μόνο του — είτε όταν ο συνάδελφος
/// κλείσει την εφαρμογή του, είτε όταν παλιώσει το ίχνος. Με μία μόνιμη
/// φόρτωση στη μνήμη, η οθόνη θα έλεγε «κλειδωμένο» για πάντα και ο άνθρωπος
/// θα έπρεπε να κλείσει και να ξανανοίξει ολόκληρη την εφαρμογή.
///
/// Το [refreshEvery] γίνεται `null` στα τεστ: ένας περιοδικός χρονιστής που
/// επιζεί του ελέγχου τον κάνει να αποτύχει.
class RefreshingOperatorPicker extends StatefulWidget {
  const RefreshingOperatorPicker({
    super.key,
    required this.loadProfiles,
    required this.onPick,
    required this.onCreate,
    required this.loading,
    this.refreshEvery = kProfileLockRefreshInterval,
  });

  final Future<SelectableProfiles> Function() loadProfiles;
  final Future<void> Function(Operator operator) onPick;
  final Future<void> Function(String displayName, bool bindCurrentAccount)
  onCreate;

  /// Τι δείχνεται ώσπου να απαντήσει η πρώτη ανάγνωση.
  final Widget loading;

  final Duration? refreshEvery;

  @override
  State<RefreshingOperatorPicker> createState() =>
      _RefreshingOperatorPickerState();
}

class _RefreshingOperatorPickerState extends State<RefreshingOperatorPicker> {
  SelectableProfiles? _selectable;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  /// Ο χρονιστής ζει **μόνο όσο υπάρχει κάτι κλειδωμένο**.
  ///
  /// Η ανανέωση υπάρχει για να ξεκλειδώνει· χωρίς κλείδωμα δεν έχει τι να
  /// ανακοινώσει, και σε βάση πάνω από κοινόχρηστο φάκελο κάθε ανάγνωση κάθε
  /// δεκαπέντε δευτερόλεπτα είναι κίνηση που πληρώνουν όλοι οι σταθμοί.
  void _syncRefreshTimer() {
    final locked =
        _selectable?.availability.values.any(
          (state) => state.kind != ProfileLockKind.free,
        ) ??
        false;
    if (!locked) {
      _refresh?.cancel();
      _refresh = null;
      return;
    }
    if (_refresh != null) return;
    final every = widget.refreshEvery;
    if (every == null) return;
    _refresh = Timer.periodic(every, (_) => unawaited(_reload()));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// **Ποτέ μοιραίο:** μια αποτυχία της ανανέωσης δεν ρίχνει την εκκίνηση —
  /// η προηγούμενη εικόνα μένει και η επόμενη προσπάθεια ξαναδοκιμάζει.
  Future<void> _reload() async {
    try {
      final fresh = await widget.loadProfiles();
      if (!mounted) return;
      setState(() => _selectable = fresh);
      _syncRefreshTimer();
    } catch (_) {
      if (!mounted) return;
      // Χωρίς καμία απάντηση δεν υπάρχει οθόνη να δείξουμε: κρατάμε άδεια
      // λίστα, ώστε ο άνθρωπος να μπορεί τουλάχιστον να συστηθεί.
      setState(() => _selectable ??= SelectableProfiles.empty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectable = _selectable;
    if (selectable == null) return widget.loading;

    return OperatorPickerScreen(
      profiles: selectable.profiles,
      presence: selectable.presence,
      availability: selectable.availability,
      presenceUnavailable: selectable.presenceUnavailable,
      confirmAdminOverride: (operator, station) =>
          confirmAdminProfileOpenElsewhere(
            context,
            operator: operator,
            station: station,
          ),
      suggestedName: OperatorIdentity.suggestedDisplayName(),
      hasWindowsAccount: OperatorIdentity.suggestedDisplayName().isNotEmpty,
      onPick: widget.onPick,
      onCreate: widget.onCreate,
    );
  }
}
