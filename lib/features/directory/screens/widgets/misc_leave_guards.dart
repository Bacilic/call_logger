import 'package:flutter/widgets.dart';

/// Ό,τι οφείλει να ολοκληρωθεί πριν φύγει μια υπο-οθόνη των «Διαφόρων».
///
/// Επιστρέφει `false` όταν η έξοδος πρέπει να ακυρωθεί (π.χ. ο χρήστης
/// διάλεξε να μείνει για να μη χάσει αλλαγές).
typedef MiscLeaveGuard = Future<bool> Function();

/// Οι φρουροί εξόδου της ανοιχτής υπο-οθόνης.
///
/// **Μοναδικός δρόμος:** κάθε έξοδος προς τις κάρτες των «Διαφόρων» —
/// «Επιστροφή», νέο πάτημα της καρτέλας, επιστροφή από τα Απομακρυσμένα
/// Εργαλεία — ρωτά πρώτα εδώ. Μια νέα υπο-οθόνη με εκκρεμή δουλειά απλώς
/// γράφεται στο μητρώο ([MiscLeaveScope.maybeOf]) και καλύπτεται από όλες τις
/// εξόδους μαζί, χωρίς να χρειάζεται να τις ξέρει.
class MiscLeaveGuards {
  final List<MiscLeaveGuard> _guards = <MiscLeaveGuard>[];

  void add(MiscLeaveGuard guard) => _guards.add(guard);

  void remove(MiscLeaveGuard guard) => _guards.remove(guard);

  /// Ρωτά τους φρουρούς με τη σειρά· ο πρώτος που αρνείται σταματά την έξοδο.
  Future<bool> canLeave() async {
    for (final guard in List<MiscLeaveGuard>.of(_guards)) {
      if (!await guard()) return false;
    }
    return true;
  }
}

/// Δίνει στις υπο-οθόνες των «Διαφόρων» το μητρώο των φρουρών εξόδου.
class MiscLeaveScope extends InheritedWidget {
  const MiscLeaveScope({super.key, required this.guards, required super.child});

  final MiscLeaveGuards guards;

  /// `null` όταν η οθόνη ζει εκτός «Διαφόρων» (π.χ. σε τεστ).
  static MiscLeaveGuards? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MiscLeaveScope>()?.guards;

  @override
  bool updateShouldNotify(MiscLeaveScope oldWidget) =>
      guards != oldWidget.guards;
}
