import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/call_entry_provider.dart';
import 'nav_rail_attention_badge.dart';
import 'compact_tooltip.dart';

/// Εικονίδιο πλοήγησης «Κλήσεις» — ίδιο στυλ μπάλωματος με τις εκκρεμότητες.
class CallsNavigationIcon extends ConsumerWidget {
  const CallsNavigationIcon({super.key, required this.isOnCallsScreen});

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

    final core = CompactTooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message:
          'Καταγραφή νέας κλήσης τεχνικής υποστήριξης\nΚύρια οθόνη – πατήστε εδώ όταν χτυπά τηλέφωνο',
      child: const Icon(Icons.phone_in_talk, key: ValueKey('nav_rail_calls')),
    );
    return Badge(
      isLabelVisible: showBadge,
      label: const Icon(Icons.phone, size: 10, color: Colors.white),
      child: core,
    );
  }
}

/// Εικονίδιο πλοήγησης «Εκκρεμότητες» με μετρητή ανοιχτών εργασιών.
class TasksNavigationIcon extends StatelessWidget {
  const TasksNavigationIcon({
    super.key,
    required this.showBadge,
    required this.pendingCount,
  });

  final bool showBadge;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final core = CompactTooltip(
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

/// Εικονίδιο πλοήγησης «Λεξικό» με προειδοποίηση όταν λείπει λεξικό-πυρήνας.
class DictionaryNavigationIcon extends StatelessWidget {
  const DictionaryNavigationIcon({super.key, required this.showWarning});

  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    const book = Icon(Icons.menu_book, key: ValueKey('nav_rail_dictionary'));
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
    return CompactTooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message: showWarning
          ? 'Δεν έχει φορτωθεί λεξικό-πυρήνας — πατήστε για ρύθμιση'
          : 'Διαχείριση λεξικού ορθογραφίας\nΕισαγωγές, συγχώνευση και εξαγωγή (compile) σε αρχείο',
      child: child,
    );
  }
}

/// Εικονίδιο πλοήγησης «Λάμπα» με προειδοποίηση μη προσπελάσιμης παλιάς βάσης.
class LampNavigationIcon extends StatelessWidget {
  const LampNavigationIcon({super.key, required this.showWarning});

  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    const lamp = Icon(Icons.lightbulb_outline, key: ValueKey('nav_rail_lamp'));
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
    return CompactTooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message: showWarning
          ? 'Η παλιά βάση δεν είναι προσπελάσιμη — ανοίξτε τη Λάμπα για διόρθωση διαδρομών'
          : 'Παλιά βάση εξοπλισμού\nΜετατροπή Excel, αναζήτηση και προβλήματα ETL',
      child: child,
    );
  }
}
