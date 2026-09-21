import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_init_runner.dart';
import '../services/database_path_switch_runner.dart';
import 'database_check_failed_dialog.dart';

/// Η εναλλαγή διαδρομής βάσης, για τις οθόνες που τρέχουν **πριν** το κέλυφος.
///
/// Δύο οθόνες υπάρχουν μόνο για να ξεμπλοκάρουν την εφαρμογή όταν η βάση δεν
/// άνοιξε: η οθόνη σφάλματος και η οθόνη του εκκρεμούς μηδενισμού. Και οι δύο
/// έκαναν την ίδια τετράδα βημάτων γραμμένη χωριστά — ένδειξη ότι δουλεύουμε,
/// επαλήθευση, διάλογος αποτυχίας, φινάλε — τέσσερις φορές συνολικά. Τέσσερα
/// αντίγραφα σημαίνουν ότι μια διόρθωση στη σειρά των βημάτων πρέπει να βρει
/// και τα τέσσερα, και το τελευταίο ξεχνιέται.
///
/// Η σειρά επιβάλλεται πλέον από τον [runDatabasePathSwitch], που έχει δικά
/// του τεστ για τον απαράβατο κανόνα: μετά από αποτυχία δεν εφαρμόζεται τίποτα,
/// μετά από επιτυχία εφαρμόζεται ακριβώς μία φορά.
///
/// **Γιατί όχι το ίδιο mixin με τις Ρυθμίσεις:** εκεί η επιτυχία ενημερώνει μια
/// ζωντανή συνεδρία — providers, ετικέτες, κύκλο ζωής. Εδώ δεν υπάρχει ακόμη
/// συνεδρία να ενημερωθεί: η εφαρμογή ξαναρχίζει την αρχικοποίησή της από την
/// αρχή. Ίδια βήματα, διαφορετικό φινάλε.
mixin DatabaseRecoverySwitchFlows<T extends ConsumerStatefulWidget>
    on ConsumerState<T>
    implements DatabasePathSwitchHooks {
  /// Τι κάνει η οθόνη μόλις η βάση ανοίξει επιτυχώς.
  ///
  /// Τυπικά: ξαναδοκιμάζει την αρχικοποίηση ή ειδοποιεί το κέλυφος. Καλείται
  /// **και** μετά από ανάκαμψη μέσα από τον διάλογο αποτυχίας, γιατί και εκεί
  /// το αποτέλεσμα είναι το ίδιο — βάση που πλέον ανοίγει.
  Future<void> onDatabaseRecovered();

  /// Η εναλλαγή, ολόκληρη. Επιστρέφει `true` μόνο όταν η βάση επαληθεύτηκε.
  ///
  /// Το μήνυμα επιτυχίας μένει στον καλούντα: διαφέρει ανά αφετηρία («η
  /// διαδρομή αποθηκεύτηκε» έναντι «η νέα βάση δημιουργήθηκε») και δεν έχει
  /// νόημα να το μαντεύει ο κοινός εκτελεστής.
  Future<bool> switchDatabasePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || !mounted) return false;
    return runDatabasePathSwitch(path: trimmed, hooks: this);
  }

  @override
  Future<void> showVerifyingIndicator() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              height: 48,
              width: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Text(
                'Έλεγχος βάσης δεδομένων…',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> hideVerifyingIndicator() async {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Future<void> reportVerificationFailure(
    DatabaseInitRunnerResult runner,
  ) async {
    if (!mounted) return;
    // Αποτυχία με πραγματική διέξοδο (συγκατάθεση αναβάθμισης, βάση νεότερης
    // έκδοσης) ΔΕΝ είναι αδιέξοδο — ο κοινός διάλογος δρομολογεί στη ροή
    // ανάκαμψης αντί για ένα σκέτο «Εντάξει».
    await showDatabaseCheckFailedDialog(
      context: context,
      result: runner.result,
      onSuccess: onDatabaseRecovered,
    );
  }

  /// **Επίτηδες κενό.** Πριν από το κέλυφος δεν υπάρχει συνεδρία να ενημερωθεί:
  /// το φινάλε είναι η [onDatabaseRecovered] που ξαναρχίζει την αρχικοποίηση,
  /// και την καλεί ο καλών αφού δείξει το δικό του μήνυμα επιτυχίας.
  @override
  Future<void> applySwitchToSession(String path) async {}

  /// **Επίτηδες κενά.** Το μητρώο κρίσιμων εργασιών υπάρχει για να εμποδίζει το
  /// κέλυφος να κάνει πράγματα στη μέση μιας εναλλαγής. Εδώ δεν υπάρχει κέλυφος.
  @override
  void declareSwitchBegin() {}

  @override
  void declareSwitchEnd() {}
}
