import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/schema_upgrade_station_guard.dart';
import '../../../core/services/crash_log_service.dart';
import '../../../core/services/session_liveness_mark.dart';
import '../../../core/services/station_name.dart';
import '../../../core/services/station_shutdown_request.dart';

/// Τι απέγινε το σημείωμα προς έναν σταθμό.
enum ShutdownRequestOutcome {
  /// Δεν έχει σταλεί τίποτα ακόμη.
  none,

  /// Στάλθηκε και περιμένουμε.
  sent,

  /// Ο φάκελος δεν δέχτηκε το σημείωμα.
  failed,

  /// Ο άνθρωπος μπροστά στην οθόνη είπε «όχι τώρα».
  denied,
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
    this.takeDenial,
    this.now,
    this.myStation,
  });

  /// Κάθε πότε ξαναρωτιέται ο φάκελος. Σύντομο: διαβάζει ήδη γραμμένα αρχεία,
  /// δεν αγγίζει τη βάση, και ο χρήστης κοιτά την οθόνη περιμένοντας αλλαγή.
  final Duration refreshInterval;

  /// Οι ενέσεις υπάρχουν ώστε ο έλεγχος να τρέχει χωρίς φάκελο και χωρίς δίκτυο.
  final Future<List<SessionLivenessMark>> Function()? loadHolders;
  final Future<bool> Function(SessionLivenessMark holder, bool immediate)?
  sendRequest;
  final Future<StationShutdownReply?> Function(SessionLivenessMark holder)?
  takeDenial;
  final DateTime Function()? now;
  final String? myStation;

  @override
  State<SchemaUpgradeWaitingPanel> createState() =>
      _SchemaUpgradeWaitingPanelState();
}

class _SchemaUpgradeWaitingPanelState extends State<SchemaUpgradeWaitingPanel> {
  List<SessionLivenessMark> _holders = const [];
  bool _loadedOnce = false;
  bool _refreshing = false;
  bool _sending = false;
  Timer? _timer;

  /// Τι απέγινε το σημείωμα κάθε σταθμού, με κλειδί την ταυτότητα εκτέλεσης.
  ///
  /// Κλειδί η **εκτέλεση** και όχι ο σταθμός: δύο αντίγραφα στον ίδιο
  /// υπολογιστή είναι δύο ξεχωριστοί παραλήπτες, και το ένα δεν απαντά για το
  /// άλλο.
  final Map<String, ShutdownRequestOutcome> _outcomes = {};

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

  /// Ξαναρωτά τον φάκελο και μαζεύει τυχόν αρνήσεις.
  ///
  /// Ποτέ δύο μαζί: σε αργό δικτυακό φάκελο ένας γύρος μπορεί να κρατήσει
  /// περισσότερο από το διάστημα, και οι γύροι θα στοιβάζονταν.
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final holders =
          await (widget.loadHolders ?? otherStationsHoldingDatabase)();
      for (final holder in holders) {
        final key = _keyOf(holder);
        if (_outcomes[key] != ShutdownRequestOutcome.sent) continue;
        final reply = await _takeDenialFor(holder);
        if (reply != null) _outcomes[key] = ShutdownRequestOutcome.denied;
      }
      if (!mounted) return;
      setState(() {
        _holders = holders;
        _loadedOnce = true;
      });
    } catch (_) {
      // Φάκελος που δεν απάντησε: κρατάμε την τελευταία εικόνα. Μια άδεια λίστα
      // εδώ θα έλεγε «έφυγαν όλοι», που είναι το ακριβώς λάθος μήνυμα.
      if (mounted) setState(() => _loadedOnce = true);
    } finally {
      _refreshing = false;
    }
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

  Future<void> _sendToAll({required bool immediate}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      for (final holder in _holders) {
        if (!holder.listensForShutdownRequests) continue;
        final ok = await _sendTo(holder, immediate);
        _outcomes[_keyOf(holder)] = ok
            ? ShutdownRequestOutcome.sent
            : ShutdownRequestOutcome.failed;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _sendTo(SessionLivenessMark holder, bool immediate) {
    final injected = widget.sendRequest;
    if (injected != null) return injected(holder, immediate);
    final log = CrashLogService.instanceOrNull;
    if (log == null) return Future.value(false);
    return writeShutdownRequest(
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

  bool get _anyoneListens => _holders.any((h) => h.listensForShutdownRequests);

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
                  outcome:
                      _outcomes[_keyOf(holder)] ?? ShutdownRequestOutcome.none,
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
    if (!_anyoneListens) {
      return Text(
        'Καμία από αυτές τις εφαρμογές δεν μπορεί να λάβει αίτημα κλεισίματος '
        '— τρέχουν έκδοση παλαιότερη από τη λειτουργία. Χρειάζεται τηλέφωνο.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: _sending ? null : () => _sendToAll(immediate: false),
          icon: const Icon(Icons.schedule_send_outlined, size: 18),
          label: const Text('Αίτημα κλεισίματος'),
        ),
        OutlinedButton.icon(
          onPressed: _sending ? null : () => _sendToAll(immediate: true),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Άμεσο κλείσιμο'),
        ),
      ],
    );
  }
}

/// Μία γραμμή: ποιος, πόσο πρόσφατα, και τι απέγινε το σημείωμά μας.
class _StationLine extends StatelessWidget {
  const _StationLine({
    required this.holder,
    required this.outcome,
    required this.now,
    required this.myStation,
  });

  final SessionLivenessMark holder;
  final ShutdownRequestOutcome outcome;
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
          child: Text(
            _statusSentence(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _statusColor(theme),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _statusSentence() {
    final station = holder.station.trim().isEmpty
        ? 'Ο σταθμός'
        : holder.station.trim();
    switch (outcome) {
      case ShutdownRequestOutcome.denied:
        return '$station αρνήθηκε — χρειάζεται τηλέφωνο.';
      case ShutdownRequestOutcome.failed:
        return 'Το αίτημα δεν στάλθηκε: ο κοινός φάκελος δεν απάντησε.';
      case ShutdownRequestOutcome.sent:
        final wait = shutdownRequestArrivalIn(holder, now: now);
        if (wait == null) return 'Στάλθηκε αίτημα.';
        return '$station θα δει το αίτημα '
            '${formatShutdownRequestArrival(wait)}.';
      case ShutdownRequestOutcome.none:
        if (!holder.listensForShutdownRequests) {
          return 'Παλιά έκδοση — δεν λαμβάνει αίτημα κλεισίματος.';
        }
        return 'Μπορεί να λάβει αίτημα κλεισίματος.';
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (outcome) {
      case ShutdownRequestOutcome.denied:
      case ShutdownRequestOutcome.failed:
        return theme.colorScheme.error;
      case ShutdownRequestOutcome.sent:
        return theme.colorScheme.tertiary;
      case ShutdownRequestOutcome.none:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
