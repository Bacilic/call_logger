import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/schema_upgrade_station_guard.dart';
import '../../../core/services/crash_log_service.dart';
import '../../../core/services/session_liveness_mark.dart';
import '../../../core/services/station_name.dart';
import '../../../core/services/station_shutdown_request.dart';

/// Πού βρίσκεται το αίτημα προς έναν σταθμό — όπως φαίνεται **τώρα**.
enum ShutdownRequestStage {
  /// Δεν έχει σταλεί τίποτα σε αυτή την εκκίνηση του σταθμού.
  none,

  /// Γράφεται αυτή τη στιγμή στον κοινό φάκελο.
  sending,

  /// Περιμένει στον φάκελο· ο σταθμός θα το δει στον επόμενο παλμό του.
  pending,

  /// Περιμένει στον φάκελο, αλλά ο παλμός που περιμέναμε πέρασε χωρίς να το
  /// δει — ίσως η εφαρμογή του πάγωσε ή χάθηκε το δίκτυο.
  overdue,

  /// Ο σταθμός το μάζεψε: κλείνει (άμεσο) ή μετρά αντίστροφα (απλό).
  seen,

  /// Ο άνθρωπος μπροστά στην οθόνη είπε «όχι τώρα».
  denied,

  /// Ο φάκελος δεν δέχτηκε το σημείωμα.
  failed,
}

/// Πόσο νέα πρέπει να είναι μια εκκίνηση για να θεωρηθεί «ξεκινά ακόμη».
///
/// Η εφαρμογή γράφει το ίχνος της αμέσως στην εκκίνηση, αλλά αρχίζει να ακούει
/// αιτήματα μόνο όταν στηθεί η κύρια οθόνη της. Στο μεσοδιάστημα δεν ακούει —
/// και το «παλιά έκδοση» θα ήταν ψέμα.
const Duration _kStillStarting = Duration(minutes: 2);

/// Ένα αίτημα που στάλθηκε σε **συγκεκριμένη εκκίνηση** ενός σταθμού.
class _SentRequest {
  _SentRequest({required this.immediate, required this.holderStartedAt});

  final bool immediate;

  /// Η εκκίνηση του παραλήπτη στην οποία στάλθηκε. Η ταυτότητα της εφαρμογής
  /// μένει ίδια από άνοιγμα σε άνοιγμα· μόνο αυτό ξεχωρίζει το POPINIO που
  /// μάζεψε το αίτημα και έκλεισε από το POPINIO που ξανάνοιξε μετά.
  final DateTime holderStartedAt;

  bool denied = false;
}

/// Η ζωντανή λίστα των σταθμών που κρατούν τη βάση, με τα κουμπιά του αιτήματος.
///
/// **Ζωντανή, γιατί η αναμονή είναι η μόνη ενέργεια.** Η οθόνη υπάρχει για να
/// δει ο χρήστης το πεδίο να αδειάζει. Μια στατική λίστα θα τον ανάγκαζε να
/// πατά «Επαναδοκιμή» κάθε λίγο για να μάθει αν κάτι άλλαξε — και η
/// «Επαναδοκιμή» ξαναπροσπαθεί ολόκληρο το άνοιγμα της βάσης, που είναι πολύ
/// βαρύτερο από μια ματιά στον φάκελο.
///
/// **Τα κουμπιά ζουν ΜΟΝΟ εδώ.** Ένα γενικό «κλείσε την εφαρμογή του άλλου»,
/// διαθέσιμο κάθε στιγμή, θα ήταν εργαλείο ζημιάς. Εδώ έχει νόημα επειδή ο
/// φρουρός έχει ήδη αποδείξει ότι η αναβάθμιση δεν μπορεί να προχωρήσει.
class SchemaUpgradeWaitingPanel extends StatefulWidget {
  const SchemaUpgradeWaitingPanel({
    super.key,
    this.refreshInterval = const Duration(seconds: 5),
    this.loadHolders,
    this.sendRequest,
    this.pendingRequest,
    this.takeDenial,
    this.now,
    this.myStation,
  });

  /// Κάθε πότε ξαναρωτιέται ο φάκελος. Σύντομο: διαβάζει ήδη γραμμένα αρχεία,
  /// δεν αγγίζει τη βάση, και ο χρήστης κοιτά την οθόνη περιμένοντας αλλαγή.
  final Duration refreshInterval;

  /// Οι ενέσεις υπάρχουν ώστε ο έλεγχος να τρέχει χωρίς φάκελο και χωρίς δίκτυο.
  final Future<List<SessionLivenessMark>> Function()? loadHolders;

  /// Γράφει το σημείωμα· `null` όταν έφτασε, αλλιώς η αιτία της αποτυχίας.
  final Future<String?> Function(SessionLivenessMark holder, bool immediate)?
  sendRequest;

  /// Το σημείωμα που περιμένει ακόμη τον σταθμό στον φάκελο, αν περιμένει.
  final Future<StationShutdownRequest?> Function(SessionLivenessMark holder)?
  pendingRequest;
  final Future<StationShutdownReply?> Function(SessionLivenessMark holder)?
  takeDenial;
  final DateTime Function()? now;
  final String? myStation;

  @override
  State<SchemaUpgradeWaitingPanel> createState() =>
      _SchemaUpgradeWaitingPanelState();
}

/// **Η εικόνα βγαίνει από τον φάκελο, όχι από τη μνήμη της οθόνης.**
///
/// Ό,τι έστειλε η οθόνη το ξέρει ο κοινός φάκελος: το σημείωμα κάθεται εκεί
/// ώσπου να το μαζέψει ο παραλήπτης. Όσο ζούσε μόνο στη μνήμη, η εικόνα έλεγε
/// δύο ψέματα — χανόταν όταν ο αιτών ξανάνοιγε την εφαρμογή του (ενώ το
/// σημείωμα περίμενε ακόμη), και «θυμόταν» αίτημα προς έναν συνάδελφο που είχε
/// ήδη κλείσει και ξανανοίξει.
class _SchemaUpgradeWaitingPanelState extends State<SchemaUpgradeWaitingPanel> {
  List<SessionLivenessMark> _holders = const [];
  bool _loadedOnce = false;
  bool _refreshing = false;
  Timer? _timer;

  /// Τα αιτήματα που ξέρουμε, με κλειδί την ταυτότητα της εφαρμογής.
  ///
  /// Κλειδί η **εκτέλεση** και όχι ο σταθμός: δύο αντίγραφα στον ίδιο
  /// υπολογιστή είναι δύο ξεχωριστοί παραλήπτες, και το ένα δεν απαντά για το
  /// άλλο. Η εκκίνηση στην οποία στάλθηκε το αίτημα ζει μέσα στην εγγραφή.
  final Map<String, _SentRequest> _sent = {};

  /// Ό,τι περιμένει ακόμη στον φάκελο, όπως το βρήκε ο τελευταίος γύρος.
  final Map<String, StationShutdownRequest> _pending = {};

  /// Η αιτία της τελευταίας αποτυχημένης αποστολής ανά σταθμό.
  final Map<String, String> _failures = {};

  /// Οι σταθμοί που γράφονται αυτή τη στιγμή.
  final Set<String> _sending = {};

  DateTime get _now => (widget.now ?? DateTime.now)();

  String get _myStation => widget.myStation ?? StationName.current;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
      widget.refreshInterval,
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _keyOf(SessionLivenessMark mark) =>
      '${mark.station}|${mark.instance ?? ''}';

  /// Ξαναρωτά τον φάκελο: ποιοι κρατούν τη βάση, τι περιμένει ακόμη, ποιος
  /// αρνήθηκε.
  ///
  /// Ποτέ δύο μαζί: σε αργό δικτυακό φάκελο ένας γύρος μπορεί να κρατήσει
  /// περισσότερο από το διάστημα, και οι γύροι θα στοιβάζονταν.
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final holders =
          await (widget.loadHolders ?? otherStationsHoldingDatabase)();
      final pending = <String, StationShutdownRequest>{};
      for (final holder in holders) {
        final key = _keyOf(holder);
        // Νέα εκκίνηση του ίδιου σταθμού: ό,τι ξέραμε αφορούσε την
        // προηγούμενη, που έχει κλείσει.
        final known = _sent[key];
        if (known != null && known.holderStartedAt != holder.startedAt) {
          _sent.remove(key);
          _failures.remove(key);
        }

        final waiting = await _pendingFor(holder);
        if (waiting != null) {
          pending[key] = waiting;
          // Αίτημα στον φάκελο που η οθόνη δεν θυμάται: στάλθηκε πριν
          // ξανανοίξει η εφαρμογή μας. Ισχύει, και ο σταθμός θα το βρει.
          _sent.putIfAbsent(
            key,
            () => _SentRequest(
              immediate: waiting.immediate,
              holderStartedAt: holder.startedAt,
            ),
          );
          continue;
        }
        final sent = _sent[key];
        if (sent != null && !sent.denied) {
          final reply = await _takeDenialFor(holder);
          if (reply != null) sent.denied = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _holders = holders;
        _pending
          ..clear()
          ..addAll(pending);
        _loadedOnce = true;
      });
    } catch (_) {
      // Φάκελος που δεν απάντησε: κρατάμε την τελευταία εικόνα. Μια άδεια λίστα
      // εδώ θα έλεγε «έφυγαν όλοι», και ένα άδειο «περιμένει» θα έλεγε «το
      // είδε» — και τα δύο ακριβώς τα λάθος μηνύματα.
      if (mounted) setState(() => _loadedOnce = true);
    } finally {
      _refreshing = false;
    }
  }

  Future<StationShutdownRequest?> _pendingFor(SessionLivenessMark holder) {
    final injected = widget.pendingRequest;
    if (injected != null) return injected(holder);
    final log = CrashLogService.instanceOrNull;
    if (log == null) return Future.value(null);
    return pendingShutdownRequestFor(
      logsDirectory: log.logsDirectory,
      toStation: StationName.fileSafeOf(holder.station),
      toInstance: holder.instance ?? '',
      now: _now,
    );
  }

  Future<StationShutdownReply?> _takeDenialFor(SessionLivenessMark holder) {
    final injected = widget.takeDenial;
    if (injected != null) return injected(holder);
    final log = CrashLogService.instanceOrNull;
    if (log == null) return Future.value(null);
    return takeShutdownDenial(
      logsDirectory: log.logsDirectory,
      fromStation: StationName.fileSafeOf(holder.station),
      fromInstance: holder.instance ?? '',
      now: _now,
    );
  }

  /// Το στάδιο του αιτήματος προς τον [holder], όπως φαίνεται τώρα.
  ShutdownRequestStage _stageOf(SessionLivenessMark holder) {
    final key = _keyOf(holder);
    if (_sending.contains(key)) return ShutdownRequestStage.sending;
    if (_failures.containsKey(key)) return ShutdownRequestStage.failed;
    final sent = _sent[key];
    if (sent == null) return ShutdownRequestStage.none;
    if (sent.denied) return ShutdownRequestStage.denied;
    if (!_pending.containsKey(key)) return ShutdownRequestStage.seen;
    if (holder.listensForShutdownRequests &&
        shutdownRequestArrivalIn(holder, now: _now) == null) {
      return ShutdownRequestStage.overdue;
    }
    return ShutdownRequestStage.pending;
  }

  /// Το αίτημα προς τον [holder] είναι ζωντανό (περιμένει ή τιμάται).
  bool _isActive(SessionLivenessMark holder) => switch (_stageOf(holder)) {
    ShutdownRequestStage.sending ||
    ShutdownRequestStage.pending ||
    ShutdownRequestStage.overdue ||
    ShutdownRequestStage.seen => true,
    _ => false,
  };

  Future<void> _sendToAll({required bool immediate}) async {
    final targets = [
      for (final holder in _listeners)
        // Απλό αίτημα: όχι σε όποιον έχει ήδη ζωντανό αίτημα. Άμεσο: όχι σε
        // όποιον έχει ήδη άμεσο — ένα απλό που περιμένει κλιμακώνεται.
        if (immediate
            ? !(_isActive(holder) &&
                  (_sent[_keyOf(holder)]?.immediate ?? false))
            : !_isActive(holder))
          holder,
    ];
    if (targets.isEmpty) return;
    setState(() => _sending.addAll(targets.map(_keyOf)));
    for (final holder in targets) {
      final key = _keyOf(holder);
      final failure = await _sendTo(holder, immediate);
      if (failure == null) {
        _failures.remove(key);
        _sent[key] = _SentRequest(
          immediate: immediate,
          holderStartedAt: holder.startedAt,
        );
        _pending[key] = StationShutdownRequest(
          fromStation: _myStation,
          requestedAt: _now,
          immediate: immediate,
        );
      } else {
        _failures[key] = failure;
      }
      _sending.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _sendTo(SessionLivenessMark holder, bool immediate) {
    final injected = widget.sendRequest;
    if (injected != null) return injected(holder, immediate);
    final log = CrashLogService.instanceOrNull;
    if (log == null) {
      return Future.value('το ημερολόγιο της εφαρμογής δεν είναι διαθέσιμο');
    }
    return sendShutdownRequest(
      logsDirectory: log.logsDirectory,
      toStation: StationName.fileSafeOf(holder.station),
      toInstance: holder.instance ?? '',
      request: StationShutdownRequest(
        fromStation: _myStation,
        requestedAt: _now,
        immediate: immediate,
        database: log.databaseFileName,
      ),
    );
  }

  Iterable<SessionLivenessMark> get _listeners =>
      _holders.where((h) => h.listensForShutdownRequests);

  bool _isStillStarting(SessionLivenessMark holder) =>
      _now.difference(holder.startedAt) < _kStillStarting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.desktop_windows_outlined,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                'Ανοιχτές εφαρμογές αυτή τη στιγμή',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_loadedOnce)
            Text('Ρωτάω…', style: theme.textTheme.bodyMedium)
          else if (_holders.isEmpty)
            Text(
              'Κανείς άλλος δεν κρατά πια τη βάση. Πατήστε «Επαναδοκιμή».',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            for (final holder in _holders)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _StationLine(
                  holder: holder,
                  stage: _stageOf(holder),
                  immediate: _sent[_keyOf(holder)]?.immediate ?? false,
                  failure: _failures[_keyOf(holder)],
                  stillStarting: _isStillStarting(holder),
                  now: _now,
                  myStation: _myStation,
                ),
              ),
          if (_holders.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildActions(theme),
          ],
          const SizedBox(height: 10),
          Text(
            'Η ένδειξη είναι ίχνος, όχι βεβαιότητα: μετά από απότομο κλείσιμο '
            'ή πτώση δικτύου κάποιος μπορεί να φαίνεται εδώ ως τρία λεπτά.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    final listeners = _listeners.toList();
    if (listeners.isEmpty) {
      final starting = _holders.any(_isStillStarting);
      return Text(
        starting
            ? 'Περιμένετε λίγα δευτερόλεπτα: τα κουμπιά εμφανίζονται μόλις '
                  'κάποια εφαρμογή μπορεί να λάβει αίτημα κλεισίματος.'
            : 'Καμία από αυτές τις εφαρμογές δεν μπορεί να λάβει αίτημα '
                  'κλεισίματος — τρέχουν παλιά έκδοση. Χρειάζεται τηλέφωνο.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    // Γκρίζο όσο **κανείς** δεν έχει κάτι να λάβει: ένα δεύτερο πάτημα δεν θα
    // έστελνε τίποτα, και ένα κουμπί που μοιάζει πατήσιμο θα έλεγε το αντίθετο.
    final canRequest = _sending.isEmpty && listeners.any((h) => !_isActive(h));
    final canForce =
        _sending.isEmpty &&
        listeners.any(
          (h) => !(_isActive(h) && (_sent[_keyOf(h)]?.immediate ?? false)),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: canRequest ? () => _sendToAll(immediate: false) : null,
          icon: const Icon(Icons.schedule_send_outlined, size: 18),
          label: const Text('Αίτημα κλεισίματος'),
        ),
        OutlinedButton.icon(
          onPressed: canForce ? () => _sendToAll(immediate: true) : null,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Άμεσο κλείσιμο'),
        ),
      ],
    );
  }
}

/// Μία γραμμή: ποιος, πόσο πρόσφατα, και τι απέγινε το αίτημά μας.
class _StationLine extends StatelessWidget {
  const _StationLine({
    required this.holder,
    required this.stage,
    required this.immediate,
    required this.failure,
    required this.stillStarting,
    required this.now,
    required this.myStation,
  });

  final SessionLivenessMark holder;
  final ShutdownRequestStage stage;
  final bool immediate;
  final String? failure;
  final bool stillStarting;
  final DateTime now;
  final String myStation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ${describeStationsHoldingDatabase([holder], now: now, myStation: myStation).replaceFirst('• ', '')}',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            height: 1.4,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stage == ShutdownRequestStage.sending) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  _statusSentence(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _statusColor(theme),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusSentence() {
    final station = holder.station.trim().isEmpty
        ? 'Ο σταθμός'
        : holder.station.trim();
    final wait = shutdownRequestArrivalIn(holder, now: now);
    final when = wait == null ? '' : formatShutdownRequestArrival(wait);
    switch (stage) {
      case ShutdownRequestStage.sending:
        return 'Στέλνεται…';
      case ShutdownRequestStage.failed:
        return 'Το αίτημα δεν στάλθηκε: $failure.';
      case ShutdownRequestStage.denied:
        return '$station αρνήθηκε — χρειάζεται τηλέφωνο.';
      case ShutdownRequestStage.overdue:
        return 'Στάλθηκε, αλλά $station δεν το έχει δει ακόμη — ίσως η '
            'εφαρμογή του έχει παγώσει ή χάθηκε το δίκτυο.';
      case ShutdownRequestStage.pending:
        if (!holder.listensForShutdownRequests) {
          return 'Στάλθηκε — $station θα το δει μόλις ολοκληρώσει την '
              'εκκίνηση.';
        }
        // Στο άμεσο κλείσιμο ο συνάδελφος δεν βλέπει αίτημα να απαντήσει:
        // ένα δευτερόλεπτο ειδοποίηση και η εφαρμογή του κλείνει.
        return immediate
            ? 'Στάλθηκε άμεσο κλείσιμο — η εφαρμογή του $station θα '
                  'κλείσει $when.'
            : 'Στάλθηκε αίτημα — $station θα το δει $when.';
      case ShutdownRequestStage.seen:
        return immediate
            ? 'Η εφαρμογή του $station κλείνει.'
            : '$station είδε το αίτημα — αν δεν απαντήσει, η εφαρμογή του '
                  'κλείνει μόνη της σε ένα λεπτό.';
      case ShutdownRequestStage.none:
        if (!holder.listensForShutdownRequests) {
          return stillStarting
              ? '$station ξεκινά ακόμη — σε λίγα δευτερόλεπτα θα μπορεί να '
                    'λάβει αίτημα κλεισίματος.'
              : 'Δεν λαμβάνει αίτημα κλεισίματος — παλιά έκδοση.';
        }
        return 'Μπορεί να λάβει αίτημα κλεισίματος.';
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (stage) {
      case ShutdownRequestStage.denied:
      case ShutdownRequestStage.failed:
      case ShutdownRequestStage.overdue:
        return theme.colorScheme.error;
      case ShutdownRequestStage.sending:
      case ShutdownRequestStage.pending:
      case ShutdownRequestStage.seen:
        return theme.colorScheme.tertiary;
      case ShutdownRequestStage.none:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
