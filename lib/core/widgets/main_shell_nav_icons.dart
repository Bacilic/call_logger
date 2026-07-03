part of 'main_shell.dart';

/// Εικονίδιο πλοήγησης «Κλήσεις» — ίδιο στυλ μπάλωματος με τις εκκρεμότητες.
class _CallsNavigationIcon extends ConsumerWidget {
  const _CallsNavigationIcon({required this.isOnCallsScreen});

  final bool isOnCallsScreen;

  static bool _hasActiveCallSession(CallEntryState s) =>
      s.durationSeconds > 0 ||
      s.isCallTimerRunning ||
      s.retainPlayPauseAfterManualZero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasActiveCall = ref.watch(
      callEntryProvider.select(_hasActiveCallSession),
    );
    final showBadge = hasActiveCall && !isOnCallsScreen;

    final core = Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message:
          'Καταγραφή νέας κλήσης τεχνικής υποστήριξης\nΚύρια οθόνη – πατήστε εδώ όταν χτυπά τηλέφωνο',
      child: const Icon(
        Icons.phone_in_talk,
        key: ValueKey('nav_rail_calls'),
      ),
    );
    return Badge(
      isLabelVisible: showBadge,
      label: const Icon(Icons.phone, size: 10, color: Colors.white),
      child: core,
    );
  }
}

class _TasksNavigationIcon extends StatelessWidget {
  const _TasksNavigationIcon({
    required this.showBadge,
    required this.pendingCount,
  });

  final bool showBadge;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final core = Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message:
          'Προβλήματα που χρήζουν παρακολούθησης\nΑνοιχτές εργασίες & υπενθυμίσεις',
      child: const Icon(Icons.task_alt, key: ValueKey('nav_rail_tasks')),
    );
    return Badge(
      isLabelVisible: showBadge && pendingCount > 0,
      label: Text(pendingCount.toString()),
      child: core,
    );
  }
}

class _DictionaryNavigationIcon extends StatelessWidget {
  const _DictionaryNavigationIcon({required this.showWarning});

  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    const book = Icon(
      Icons.menu_book,
      key: ValueKey('nav_rail_dictionary'),
    );
    final child = showWarning
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              book,
              const Positioned(
                right: -4,
                top: -4,
                child: NavRailAttentionBadge(),
              ),
            ],
          )
        : book;
    return Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message: showWarning
          ? 'Δεν έχει φορτωθεί λεξικό-πυρήνας — πατήστε για ρύθμιση'
          : 'Διαχείριση λεξικού ορθογραφίας\nΕισαγωγές, συγχώνευση και εξαγωγή (compile) σε αρχείο',
      child: child,
    );
  }
}

class _LampNavigationIcon extends StatelessWidget {
  const _LampNavigationIcon({required this.showWarning});

  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    const lamp = Icon(
      Icons.lightbulb_outline,
      key: ValueKey('nav_rail_lamp'),
    );
    final child = showWarning
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              lamp,
              const Positioned(
                right: -4,
                top: -4,
                child: NavRailAttentionBadge(),
              ),
            ],
          )
        : lamp;
    return Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message: showWarning
          ? 'Η παλιά βάση δεν είναι προσπελάσιμη — ανοίξτε τη Λάμπα για διόρθωση διαδρομών'
          : 'Παλιά βάση εξοπλισμού\nΜετατροπή Excel, αναζήτηση και προβλήματα ETL',
      child: child,
    );
  }
}
