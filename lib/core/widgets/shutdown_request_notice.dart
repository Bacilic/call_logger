import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_close_controller.dart';
import '../services/station_shutdown_request.dart';

/// Πόσο χρόνο έχει ο άνθρωπος να αντιδράσει πριν κλείσει μόνη της η εφαρμογή.
///
/// Αρκετό για να γυρίσει κάποιος από το πληκτρολόγιο και να διαβάσει, αρκετά
/// σύντομο ώστε ο συνάδελφος που περιμένει να μην καθηλώνεται. Ίδιο μέγεθος με
/// τον παλμό του ίχνους ζωής, ώστε να υπάρχει **ένας** ρυθμός στην εφαρμογή.
const Duration kShutdownRequestCountdown = Duration(seconds: 60);

/// Η ειδοποίηση «σου ζητούν να κλείσεις», με αντίστροφη μέτρηση.
///
/// **Ο άδειος σταθμός είναι ο λόγος ύπαρξής της.** Ο υπολογιστής του συναδέλφου
/// μένει ανοιχτός με κλειδωμένη οθόνη και την εφαρμογή να κρατά τη βάση· κανείς
/// δεν πατά τίποτα, η μέτρηση τελειώνει μόνη της, και η αναβάθμιση περνά. Κάθε
/// σχεδιαστική επιλογή εδώ υπηρετεί αυτό: **τίποτα δεν περιμένει άνθρωπο**.
///
/// Το άμεσο αίτημα δεν προσφέρει άρνηση επίτηδες — ο αιτών **βλέπει** ότι η
/// θέση είναι άδεια και δεν έχει λόγο να περιμένει έναν λεπτό για κανέναν.
class ShutdownRequestNotice extends StatefulWidget {
  const ShutdownRequestNotice({
    super.key,
    required this.request,
    required this.onAccepted,
    required this.onDenied,
    this.countdown = kShutdownRequestCountdown,
  });

  final StationShutdownRequest request;

  /// Κλείσε την εφαρμογή. Καλείται μία φορά, από όποιο δρόμο κι αν έρθει.
  final VoidCallback onAccepted;

  /// Ο άνθρωπος αρνήθηκε — ο αιτών πρέπει να το μάθει.
  final VoidCallback onDenied;

  final Duration countdown;

  @override
  State<ShutdownRequestNotice> createState() => _ShutdownRequestNoticeState();
}

class _ShutdownRequestNoticeState extends State<ShutdownRequestNotice> {
  late int _secondsLeft;
  Timer? _ticker;

  /// Η απόφαση παίρνεται **μία** φορά.
  ///
  /// Το τελευταίο δευτερόλεπτο της μέτρησης και το δάχτυλο στο «Όχι τώρα»
  /// μπορούν να πέσουν στο ίδιο καρέ. Χωρίς αυτή τη σημαία ο χρήστης θα
  /// αρνιόταν και η εφαρμογή θα έκλεινε ούτως ή άλλως.
  bool _settled = false;

  bool get _allowsDenial => !widget.request.immediate;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.countdown.inSeconds;
    if (!_allowsDenial) {
      // Άμεσο αίτημα: η οθόνη υπάρχει για να προλάβει να διαβαστεί, όχι για να
      // απαντηθεί. Ένα δευτερόλεπτο, όσο να φανεί γιατί έκλεισε η εφαρμογή.
      _secondsLeft = 1;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _settled) return;
    if (_secondsLeft <= 1) {
      _accept();
      return;
    }
    setState(() => _secondsLeft -= 1);
  }

  void _accept() {
    if (_settled) return;
    _settled = true;
    _ticker?.cancel();
    widget.onAccepted();
  }

  void _deny() {
    if (_settled) return;
    _settled = true;
    _ticker?.cancel();
    widget.onDenied();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = widget.request.fromStation.trim();
    final who = from.isEmpty ? 'Ένας άλλος υπολογιστής' : from;

    return AlertDialog(
      icon: Icon(Icons.logout_rounded, color: theme.colorScheme.tertiary),
      title: Text(
        _allowsDenial
            ? 'Ζητείται το κλείσιμο της εφαρμογής'
            : 'Η εφαρμογή κλείνει',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$who χρειάζεται να αναβαθμίσει τη βάση, και η αναβάθμιση δεν '
            'μπορεί να γίνει όσο η εφαρμογή είναι ανοιχτή εδώ.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Text(
            _allowsDenial
                ? 'Η εφαρμογή θα κλείσει μόνη της σε $_secondsLeft '
                      'δευτερόλεπτα. Ό,τι δεν έχει αποθηκευτεί θα χαθεί.'
                : 'Η εφαρμογή κλείνει αμέσως. Ό,τι δεν έχει αποθηκευτεί '
                      'θα χαθεί.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        if (_allowsDenial)
          TextButton(onPressed: _deny, child: const Text('Όχι τώρα')),
        FilledButton(onPressed: _accept, child: const Text('Κλείσιμο τώρα')),
      ],
    );
  }
}

/// Δείχνει την ειδοποίηση και εκτελεί την απόφαση.
///
/// **Ένας διάλογος τη φορά.** Ένα δεύτερο σημείωμα που φτάνει όσο μετρά ο
/// πρώτος δεν ανοίγει δεύτερη ειδοποίηση: η εφαρμογή κλείνει ούτως ή άλλως, και
/// δύο στοιβαγμένοι διάλογοι θα σήμαιναν ότι το «Όχι τώρα» απαντά στον έναν
/// ενώ ο άλλος συνεχίζει να μετρά από κάτω.
bool _noticeOnScreen = false;

Future<void> showShutdownRequestNotice(
  BuildContext context, {
  required StationShutdownRequest request,
  required Future<void> Function() onDenied,
  VoidCallback? closeApp,
  Duration countdown = kShutdownRequestCountdown,
}) async {
  if (_noticeOnScreen) return;
  _noticeOnScreen = true;
  var accepted = false;
  try {
    await showDialog<void>(
      context: context,
      // Ένα κλικ εκτός του διαλόγου δεν είναι απάντηση: ο αιτών περιμένει
      // ξεκάθαρο ναι ή όχι, και η σιωπή σημαίνει «κλείσε» — όχι «ξέχασέ το».
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ShutdownRequestNotice(
          request: request,
          countdown: countdown,
          onAccepted: () {
            accepted = true;
            Navigator.of(ctx).pop();
          },
          onDenied: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  } finally {
    _noticeOnScreen = false;
  }

  if (accepted) {
    // Η ίδια πόρτα με το Χ και το Alt+F4: το ίχνος ζωής **σβήνεται** αντί να
    // παλιώσει, οπότε ο αιτών δεν περιμένει τα τρία λεπτά φρεσκάδας.
    (closeApp ?? appCloseController.handleCloseRequest)();
    return;
  }
  await onDenied();
}

/// Μόνο για τα τεστ: ξεχνά ότι υπάρχει ειδοποίηση στην οθόνη.
@visibleForTesting
void resetShutdownNoticeGuardForTest() => _noticeOnScreen = false;
