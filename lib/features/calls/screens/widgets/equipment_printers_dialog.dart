import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/printer_rpc_policy.dart';
import '../../../../core/services/server_sessions/printer_station_matching.dart';
import '../../../../core/services/server_sessions/server_printer_models.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../utils/equipment_server_context.dart';
import 'user_logoff_dialog.dart';

/// Ανοίγει τους εκτυπωτές που ο διακομιστής έχει σηκώσει για έναν εξοπλισμό.
Future<void> showEquipmentPrintersDialog(
  BuildContext context, {
  required String equipmentCode,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _EquipmentPrintersDialog(equipmentCode: equipmentCode),
  );
}

class _EquipmentPrintersDialog extends ConsumerStatefulWidget {
  const _EquipmentPrintersDialog({required this.equipmentCode});

  final String equipmentCode;

  @override
  ConsumerState<_EquipmentPrintersDialog> createState() =>
      _EquipmentPrintersDialogState();
}

class _EquipmentPrintersDialogState
    extends ConsumerState<_EquipmentPrintersDialog> {
  ManagedServer? _server;
  List<ManagedServer> _servers = const [];
  String _stationName = '';

  List<StationPrinter> _printers = const [];

  /// Οι ουρές που έχει ανοίξει ο χειριστής, ανά πλήρες όνομα εκτυπωτή.
  final Map<String, List<PrintJob>> _queues = {};
  final Set<String> _loadingQueues = {};

  bool _loading = true;
  bool _working = false;
  String? _error;

  /// Πόσες συνεδρίες βρέθηκαν για αυτόν τον σταθμό — μπαίνει στην επικεφαλίδα.
  int _stationSessionCount = 0;

  /// Τι επέστρεψε συνολικά ο διακομιστής, πριν από κάθε φιλτράρισμα.
  ///
  /// Χωρίς αυτό, το «κανένας εκτυπωτής για αυτόν τον υπολογιστή» είναι
  /// αδιάγνωστο: δεν ξεχωρίζει το «ο διακομιστής δεν έδωσε τίποτα» από το
  /// «έδωσε πολλά, αλλά κανένα δεν ανήκει εδώ».
  int _totalPrinters = 0;
  int _redirectedTotal = 0;
  List<String> _sampleNames = const [];

  /// Η λίστα ήρθε από το μητρώο, επειδή η υπηρεσία ουράς δεν απάντησε.
  /// Τότε ξέρουμε ΠΟΙΟΙ εκτυπωτές υπάρχουν, αλλά όχι τι κάνουν.
  bool _limited = false;

  /// Ο κωδικός των Windows πίσω από την περιορισμένη προβολή.
  int _limitedCode = 0;

  /// Λέει η περιορισμένη προβολή πού ενεργοποιείται η πλήρης;
  ///
  /// Προσωπική ρύθμιση: για όποιον θέλει απλώς να δει τους εκτυπωτές, η
  /// υπόδειξη είναι θόρυβος. Όσο δεν έχει διαβαστεί, δεν εμφανίζεται —
  /// καλύτερα να έρθει μια στιγμή αργότερα παρά να αναβοσβήσει.
  bool get _showHint =>
      ref.watch(printersLimitedViewHintProvider).value ?? false;

  /// Η εξήγηση της περιορισμένης προβολής — ίδια συνάρτηση με τον διάλογο
  /// εκκαθάρισης ουρών, ώστε τα δύο κείμενα να μην αποκλίνουν.
  String get _limitedViewText {
    final policy =
        ref.watch(printerRpcPolicyProvider).value ??
        const PrinterRpcPolicyState.unreadable();
    return policy.limitedPrinterViewMessage(
      host: _server?.host ?? '',
      showHint: _showHint,
      errorCode: _limitedCode,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final ctx = await resolveEquipmentServerContext(ref, widget.equipmentCode);
    if (!mounted) return;

    _stationName = ctx.stationName;
    setState(() {
      _servers = ctx.servers;
      _server = ctx.choice.server;
    });

    if (ctx.choice.server == null) {
      setState(() {
        _loading = false;
        _error =
            'Δεν υπάρχει καταχωρημένος διακομιστής. Πρόσθεσε έναν από τον '
            'Κατάλογο → Διάφορα → Διακομιστές.';
      });
      return;
    }
    await _refresh();
  }

  /// Ρωτάει **πρώτα** τις συνεδρίες και μετά τους εκτυπωτές.
  ///
  /// Η σειρά έχει σημασία: χωρίς τη ζωντανή λίστα συνεδριών δεν μπορούμε να
  /// πούμε ποιος εκτυπωτής είναι ορφανός — και μια λάθος απάντηση εκεί θα
  /// πρότεινε διαγραφή εκτυπωτών που δουλεύουν.
  Future<void> _refresh() async {
    final server = _server;
    if (server == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _queues.clear();
    });

    final sessions = await ref
        .read(serverSessionServiceProvider)
        .listSessions(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
        );
    if (!mounted) return;
    if (!sessions.ok) {
      setState(() {
        _loading = false;
        _error = sessions.error;
      });
      return;
    }

    final printers = await ref
        .read(serverPrinterServiceProvider)
        .listPrinters(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
        );
    if (!mounted) return;
    if (!printers.ok) {
      setState(() {
        _loading = false;
        _error = printers.error;
      });
      return;
    }

    final stationSessions = PrinterStationMatching.sessionIdsForStation(
      sessions: sessions.sessions,
      stationName: _stationName,
    );
    final matched = PrinterStationMatching.printersForStation(
      printers: printers.printers,
      stationName: _stationName,
      stationSessionIds: stationSessions,
      liveSessionIds: PrinterStationMatching.liveSessionIds(sessions.sessions),
    );

    setState(() {
      _loading = false;
      _printers = matched;
      _stationSessionCount = stationSessions.length;
      _totalPrinters = printers.printers.length;
      _redirectedTotal = printers.printers.where((p) => p.isRedirected).length;
      _sampleNames = printers.printers.take(3).map((p) => p.fullName).toList();
      _limited = printers.isLimited;
      _limitedCode = printers.fallbackCode;
    });
  }

  Future<void> _toggleQueue(StationPrinter sp) async {
    final key = sp.printer.fullName;
    if (_queues.containsKey(key)) {
      setState(() => _queues.remove(key));
      return;
    }

    final server = _server;
    if (server == null) return;
    setState(() => _loadingQueues.add(key));

    final result = await ref
        .read(serverPrinterServiceProvider)
        .listQueue(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          printerFullName: key,
        );
    if (!mounted) return;

    setState(() {
      _loadingQueues.remove(key);
      if (result.ok) {
        _queues[key] = result.jobs;
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _purge(StationPrinter sp) async {
    final server = _server;
    if (server == null) return;

    final confirmed = await _confirmPurge(sp);
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final result = await ref
        .read(serverPrinterServiceProvider)
        .purgeQueue(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          printerFullName: sp.printer.fullName,
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }
    _notify(
      result.affected == 0
          ? 'Η ουρά ήταν ήδη άδεια.'
          : 'Σβήστηκαν ${result.affected} εκτυπώσεις.',
    );
    await _refresh();
  }

  Future<void> _removeOrphan(StationPrinter sp) async {
    final server = _server;
    if (server == null) return;

    final confirmed = await _confirmRemove(sp);
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final result = await ref
        .read(serverPrinterServiceProvider)
        .removePrinter(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          printerFullName: sp.printer.fullName,
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }
    _notify('Αφαιρέθηκε ο εκτυπωτής «${sp.printer.displayName}».');
    await _refresh();
  }

  Future<void> _resume(StationPrinter sp) async {
    final server = _server;
    if (server == null) return;

    setState(() => _working = true);
    final result = await ref
        .read(serverPrinterServiceProvider)
        .resumePrinter(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          printerFullName: sp.printer.fullName,
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }
    _notify('Ο «${sp.printer.displayName}» ξεπάγωσε.');
    await _refresh();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmPurge(StationPrinter sp) {
    final theme = Theme.of(context);
    final jobs = _queues[sp.printer.fullName];
    final active =
        jobs?.where((j) => j.isActive).toList() ?? const <PrintJob>[];

    return showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Άδειασμα ουράς'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          icon: Icon(
            Icons.warning_amber_outlined,
            color: theme.colorScheme.error,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Να σβηστούν όλες οι εκτυπώσεις του «${sp.printer.displayName}»;',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Οι εκτυπώσεις χάνονται οριστικά και πρέπει να σταλούν ξανά. '
                'Αφορά μόνο αυτόν τον εκτυπωτή.',
              ),
              if (active.isNotEmpty) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'ΠΡΟΣΟΧΗ: αυτή τη στιγμή τυπώνεται '
                      '«${active.first.document}». Θα κοπεί στη μέση.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Όχι'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ναι, άδειασμα'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmRemove(StationPrinter sp) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Αφαίρεση ορφανού εκτυπωτή'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: Text(
            'Να αφαιρεθεί ο «${sp.printer.displayName}» από τον διακομιστή;\n\n'
            'Ανήκει σε συνεδρία ${sp.printer.sessionId} που δεν υπάρχει πια. '
            'Αν ο χρήστης ξανασυνδεθεί, ο εκτυπωτής του θα δημιουργηθεί από '
            'την αρχή.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αφαίρεση'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: Text('Εκτυπωτές · ${widget.equipmentCode}'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme),
              const Divider(height: 18),
              // ΕΝΑ ΣΗΜΕΙΟ ΚΥΛΙΣΗΣ: το σώμα κυλά ό,τι κι αν δείχνει.
              //
              // Το `Flexible` από μόνο του απαιτεί παιδί που ξέρει να
              // συρρικνωθεί — και μόνο η λίστα εκτυπωτών το ήξερε. Οι
              // υπόλοιπες καταστάσεις (φόρτωση, σφάλμα, κενό αποτέλεσμα)
              // είναι στήλες σταθερού ύψους και ξεχείλιζαν μόλις το κείμενο
              // μεγάλωνε. Τυλίγοντας εδώ, καμία μελλοντική κατάσταση δεν
              // μπορεί να ξεχάσει την κύλισή της.
              Flexible(
                child: SingleChildScrollView(child: _buildBody(theme)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _working ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Ανανέωση'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final server = _server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Διακομιστής'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: server?.id,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  for (final s in _servers)
                    DropdownMenuItem(value: s.id, child: Text(s.displayLabel)),
                ],
                onChanged: _loading || _working
                    ? null
                    : (id) {
                        if (id == null) return;
                        setState(() {
                          _server = _servers.firstWhere((s) => s.id == id);
                        });
                        _refresh();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _stationName.isEmpty
              ? 'Ο εξοπλισμός δεν αντιστοιχεί σε γνωστό όνομα υπολογιστή.'
              : 'Σταθμός $_stationName · '
                    '${_stationSessionCount == 0 ? 'καμία ανοιχτή συνεδρία' : '$_stationSessionCount ανοιχτές συνεδρίες'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_limited) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _limitedViewText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Ερώτηση διακομιστή…'),
            ],
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(error)),
          ],
        ),
      );
    }

    if (_printers.isEmpty) return _buildEmpty(theme);

    return ListView.builder(
      shrinkWrap: true,
      // Την κύλιση την κάνει ο γονιός (βλ. build): δύο περιοχές κύλισης η μία
      // μέσα στην άλλη παλεύουν για το ίδιο δάχτυλο.
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _printers.length,
      itemBuilder: (ctx, i) {
        final sp = _printers[i];
        return _PrinterTile(
          stationPrinter: sp,
          jobs: _queues[sp.printer.fullName],
          loadingQueue: _loadingQueues.contains(sp.printer.fullName),
          busy: _working,
          limited: _limited,
          onToggleQueue: () => _toggleQueue(sp),
          onPurge: () => _purge(sp),
          onResume: !_limited && _canResume(sp) ? () => _resume(sp) : null,
          onRemove: sp.isOrphan && !_limited ? () => _removeOrphan(sp) : null,
        );
      },
    );
  }

  /// Το ξεπάγωμα έχει νόημα μόνο όταν ο εκτυπωτής είναι σταματημένος.
  ///
  /// Σε εκτυπωτή εκτός σύνδεσης δεν αλλάζει τίποτα — και ένα κουμπί που δεν
  /// κάνει τίποτα είναι χειρότερο από κουμπί που λείπει.
  bool _canResume(StationPrinter sp) =>
      sp.printer.health == PrinterHealth.paused ||
      sp.printer.health == PrinterHealth.error;

  /// Το κενό αποτέλεσμα λέει ΚΑΙ τι είδε ο διακομιστής.
  ///
  /// Δύο εντελώς διαφορετικά προβλήματα καταλήγουν σε άδεια λίστα: ο
  /// διακομιστής να μη δίνει καθόλου εκτυπωτές (ορατότητα ή δικαιώματα), ή να
  /// δίνει πολλούς που κανένας δεν ανήκει σε αυτόν τον σταθμό (ταίριασμα).
  /// Χωρίς τους αριθμούς, το μήνυμα δεν οδηγεί πουθενά.
  Widget _buildEmpty(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ο διακομιστής δεν έχει σηκώσει κανέναν εκτυπωτή για αυτόν τον '
            'υπολογιστή.',
          ),
          const SizedBox(height: 10),
          Text(
            _totalPrinters == 0
                ? 'Ο διακομιστής δεν επέστρεψε κανέναν εκτυπωτή — ούτε δικό '
                      'του. Συνήθως σημαίνει ότι ο λογαριασμός διαχειριστή δεν '
                      'βλέπει τους εκτυπωτές του, όχι ότι δεν υπάρχουν.'
                : 'Ο διακομιστής επέστρεψε $_totalPrinters εκτυπωτές, από τους '
                      'οποίους $_redirectedTotal ανήκουν σε συνεδρίες χρηστών. '
                      'Κανένας δεν αντιστοιχεί στον σταθμό '
                      '${_stationName.isEmpty ? '(άγνωστο)' : _stationName}.',
            style: muted,
          ),
          const SizedBox(height: 12),
          // Το επόμενο σκαλί προτείνεται εδώ, τη στιγμή που χρειάζεται: όταν ο
          // εκτυπωτής λείπει εντελώς, μόνο μια επανασύνδεση τον ξαναφέρνει.
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _working
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      showUserLogoffDialog(
                        context,
                        equipmentCode: widget.equipmentCode,
                      );
                    },
              icon: const Icon(Icons.cast_connected_outlined, size: 18),
              label: const Text('Δοκίμασε αποσύνδεση οθόνης'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Η συνεδρία δεν κλείνει. Μόλις ο χρήστης ξανασυνδεθεί, ο '
            'υπολογιστής του ξαναστέλνει τους εκτυπωτές του.',
            style: muted,
          ),
          if (_sampleNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Δείγμα ονομάτων από τον διακομιστή:', style: muted),
            for (final n in _sampleNames)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  n,
                  style: muted?.copyWith(fontFamily: 'monospace'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.stationPrinter,
    required this.jobs,
    required this.loadingQueue,
    required this.busy,
    required this.limited,
    required this.onToggleQueue,
    required this.onPurge,
    required this.onRemove,
    required this.onResume,
  });

  final StationPrinter stationPrinter;
  final List<PrintJob>? jobs;
  final bool loadingQueue;
  final bool busy;

  /// Χωρίς την υπηρεσία ουράς, δεν υπάρχει ουρά να δείξουμε ούτε να αδειάσουμε.
  final bool limited;
  final VoidCallback onToggleQueue;
  final VoidCallback onPurge;
  final VoidCallback? onRemove;

  /// Διαθέσιμο μόνο σε σταματημένο εκτυπωτή — το φθηνότερο σκαλί επαναφοράς.
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = stationPrinter.printer;
    final orphan = stationPrinter.isOrphan;
    final health = p.health;

    final accent = orphan
        ? theme.colorScheme.tertiary
        : health.needsAttention
        ? theme.colorScheme.error
        : theme.colorScheme.outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: accent.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  orphan
                      ? Icons.link_off
                      : health.needsAttention
                      ? Icons.print_disabled_outlined
                      : Icons.print_outlined,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _subtitle(orphan, p),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: orphan || health.needsAttention
                              ? accent
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  TextButton.icon(
                    onPressed: busy ? null : onRemove,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 16,
                    ),
                    label: const Text('Αφαίρεση'),
                  ),
                if (!limited)
                  TextButton.icon(
                    onPressed: busy ? null : onToggleQueue,
                    icon: Icon(
                      jobs == null ? Icons.expand_more : Icons.expand_less,
                      size: 16,
                    ),
                    label: Text(jobs == null ? 'Ουρά' : 'Κλείσιμο'),
                  ),
              ],
            ),
            if (loadingQueue)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (jobs != null) _buildQueue(theme, jobs!),
          ],
        ),
      ),
    );
  }

  String _subtitle(bool orphan, ServerPrinter p) {
    final session = p.sessionId == null ? '' : 'συνεδρία ${p.sessionId}';
    if (orphan) return '$session — δεν υπάρχει πια · ορφανός';
    // Σε περιορισμένη προβολή το μηδέν ΔΕΝ σημαίνει άδεια ουρά· σημαίνει ότι
    // δεν τη ρωτήσαμε. Λέγεται ρητά, αλλιώς διαβάζεται ως γεγονός.
    if (limited) {
      final driver = p.driverName.isEmpty ? '' : ' · ${p.driverName}';
      return '$session · ουρά άγνωστη$driver';
    }
    final queue = p.jobCount == 0 ? 'ουρά άδεια' : '${p.jobCount} στην ουρά';
    return '$session · ${p.health.label.toLowerCase()} · $queue';
  }

  Widget _buildQueue(ThemeData theme, List<PrintJob> jobs) {
    if (jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Η ουρά είναι άδεια.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        for (final j in jobs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${j.document} · ${j.user}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${j.totalPages} σελ. · ${j.statusLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: j.isStuck
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: busy ? null : onPurge,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('Άδειασμα ουράς'),
          ),
        ),
      ],
    );
  }
}
