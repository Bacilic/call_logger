import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/printer_rpc_policy.dart';
import '../../../../core/services/server_sessions/printer_station_matching.dart';
import '../../../../core/services/server_sessions/server_printer_models.dart';
import '../../../../core/services/server_sessions/server_session_models.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import 'server_action_banner.dart';

/// Οι ενέργειες συντήρησης πάνω σε έναν διακομιστή.
///
/// Ζουν χωριστά από την οθόνη γιατί καθεμιά έχει δικό της βάρος: η μία αγγίζει
/// τις εκτυπώσεις όλων, η άλλη ρίχνει ολόκληρο τον διακομιστή.

/// Επανεκκίνηση της ουράς εκτυπώσεων, αφού μετρηθεί τι θα χαθεί.
Future<void> showRestartSpoolerDialog(
  BuildContext context,
  WidgetRef ref,
  ManagedServer server,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _RestartSpoolerDialog(server: server),
  );
}

/// Καθαρισμός των ορφανών εκτυπωτών — η πραγματική συντήρηση.
Future<void> showOrphanCleanupDialog(
  BuildContext context,
  WidgetRef ref,
  ManagedServer server,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _OrphanCleanupDialog(server: server),
  );
}

/// Επανεκκίνηση του διακομιστή, με προειδοποίηση προς όσους είναι μέσα.
Future<void> showServerRestartDialog(
  BuildContext context,
  WidgetRef ref,
  ManagedServer server,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ServerRestartDialog(server: server),
  );
}

// --- Επανεκκίνηση ουράς εκτυπώσεων -----------------------------------------

class _RestartSpoolerDialog extends ConsumerStatefulWidget {
  const _RestartSpoolerDialog({required this.server});

  final ManagedServer server;

  @override
  ConsumerState<_RestartSpoolerDialog> createState() =>
      _RestartSpoolerDialogState();
}

class _RestartSpoolerDialogState extends ConsumerState<_RestartSpoolerDialog> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _done;

  int _pendingJobs = 0;
  int _printersWithJobs = 0;
  int _printerCount = 0;

  /// Η λίστα ήρθε από το μητρώο: το πλήθος εργασιών ΔΕΝ είναι γνωστό.
  bool _limited = false;

  /// Ο κωδικός των Windows πίσω από την περιορισμένη προβολή.
  int _limitedCode = 0;

  /// Η κοινή εξήγηση της περιορισμένης προβολής — ίδια συνάρτηση με τους
  /// διαλόγους εκτυπωτών και εκκαθάρισης ουρών, ώστε τα κείμενα να μην
  /// αποκλίνουν. Χωρίς την προτροπή για επανεκκίνηση: είμαστε ήδη μέσα της.
  String get _limitedViewText {
    final policy =
        ref.watch(printerRpcPolicyProvider).value ??
        const PrinterRpcPolicyState.unreadable();
    return policy.limitedPrinterViewMessage(
      host: widget.server.host,
      showHint: ref.watch(printersLimitedViewHintProvider).value ?? false,
      errorCode: _limitedCode,
      suggestRestart: false,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Μετράει τι περιμένει στις ουρές **πριν** πειραχτεί οτιδήποτε.
  ///
  /// Το πλήθος έρχεται από την ίδια λίστα εκτυπωτών, χωρίς να ανοίξει καμία
  /// ουρά ξεχωριστά: σε διακομιστή με σαράντα εκτυπωτές αυτό θα ήταν σαράντα
  /// ερωτήσεις για μια πληροφορία που ήδη έχουμε.
  Future<void> _measure() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ref
        .read(serverPrinterServiceProvider)
        .listPrinters(
          host: widget.server.host,
          adminUser: widget.server.adminUser,
          adminPassword: widget.server.adminPassword,
        );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = result.error;
      });
      return;
    }

    var jobs = 0;
    var withJobs = 0;
    for (final p in result.printers) {
      if (p.jobCount > 0) {
        jobs += p.jobCount;
        withJobs++;
      }
    }
    setState(() {
      _loading = false;
      _printerCount = result.printers.length;
      _pendingJobs = jobs;
      _printersWithJobs = withJobs;
      _limited = result.isLimited;
      _limitedCode = result.fallbackCode;
    });
  }

  Future<void> _restart() async {
    setState(() {
      _working = true;
      _error = null;
    });

    final result = await ref
        .read(serverPrinterServiceProvider)
        .restartSpooler(
          host: widget.server.host,
          adminUser: widget.server.adminUser,
          adminPassword: widget.server.adminPassword,
        );
    if (!mounted) return;

    setState(() {
      _working = false;
      if (result.ok) {
        _done =
            'Η ουρά εκτυπώσεων του ${widget.server.host} επανεκκινήθηκε και '
            'λειτουργεί. Αν κάποιος χρήστης δεν βλέπει ακόμη τον εκτυπωτή του, '
            'ας αποσυνδεθεί και ας ξανασυνδεθεί.';
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableDialogShell(
      title: const Text('Επανεκκίνηση ουράς εκτυπώσεων'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.server.displayLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Μετράμε τι υπάρχει στις ουρές…'),
                  ],
                )
              else if (_done != null)
                ServerActionBanner(
                  icon: Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  text: _done!,
                )
              else ...[
                const Text(
                  'Κανείς δεν πέφτει έξω από τον διακομιστή και καμία συνεδρία '
                  'δεν κλείνει. Σταματά και ξαναρχίζει μόνο η υπηρεσία που '
                  'διαχειρίζεται τις εκτυπώσεις.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Ο διακομιστής έχει $_printerCount εκτυπωτές.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (_limited)
                  ServerActionBanner(
                    icon: Icons.info_outline,
                    color: theme.colorScheme.tertiary,
                    // Η κοινή εξήγηση της περιορισμένης προβολής, χωρίς την
                    // προτροπή για επανεκκίνηση — είμαστε ήδη μέσα σε αυτήν.
                    // Από πίσω μπαίνει ο κίνδυνος που αφορά μόνο εδώ.
                    text:
                        '$_limitedViewText Η επανεκκίνηση θα ζητηθεί κανονικά, '
                        'αλλά χωρίς να ξέρουμε αν κόβεται εκτύπωση.',
                  )
                else if (_pendingJobs > 0)
                  ServerActionBanner(
                    icon: Icons.warning_amber_outlined,
                    color: theme.colorScheme.error,
                    text:
                        'Αυτή τη στιγμή περιμένουν $_pendingJobs εκτυπώσεις σε '
                        '$_printersWithJobs εκτυπωτές. Όποια τυπώνεται τώρα θα '
                        'κοπεί και θα ξεκινήσει από την αρχή.',
                  )
                else
                  ServerActionBanner(
                    icon: Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                    text: 'Καμία εκτύπωση σε αναμονή — η στιγμή είναι καλή.',
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ServerActionBanner(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  text: _error!,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: Text(_done == null ? 'Ακύρωση' : 'Κλείσιμο'),
          ),
          if (_done == null)
            FilledButton.icon(
              onPressed: _loading || _working ? null : _restart,
              icon: _working
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt, size: 18),
              label: Text(_working ? 'Γίνεται…' : 'Επανεκκίνηση ουράς'),
            ),
        ],
      ),
    );
  }
}

// --- Καθαρισμός ορφανών ----------------------------------------------------

class _OrphanCleanupDialog extends ConsumerStatefulWidget {
  const _OrphanCleanupDialog({required this.server});

  final ManagedServer server;

  @override
  ConsumerState<_OrphanCleanupDialog> createState() =>
      _OrphanCleanupDialogState();
}

class _OrphanCleanupDialogState extends ConsumerState<_OrphanCleanupDialog> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _done;

  List<ServerPrinter> _orphans = const [];
  int _printerCount = 0;

  /// Η λίστα ήρθε από τις ρυθμίσεις του διακομιστή, όχι από την υπηρεσία.
  ///
  /// Τα ονόματα αρκούν για να **βρεθούν** οι ορφανοί — η αντιστοίχιση γίνεται
  /// με το όνομα και τη συνεδρία, όχι με την ουρά. Η **αφαίρεση** όμως περνά
  /// από την ίδια υπηρεσία που δεν απαντά, οπότε δεν προσφέρεται.
  bool _limited = false;

  /// Ο κωδικός των Windows πίσω από την περιορισμένη προβολή.
  int _limitedCode = 0;

  /// Η κοινή εξήγηση της περιορισμένης προβολής — ίδια συνάρτηση με τους
  /// υπόλοιπους διαλόγους εκτυπωτών, ώστε τα κείμενα να μην αποκλίνουν.
  String get _limitedViewText {
    final policy =
        ref.watch(printerRpcPolicyProvider).value ??
        const PrinterRpcPolicyState.unreadable();
    return policy.limitedPrinterViewMessage(
      host: widget.server.host,
      showHint: ref.watch(printersLimitedViewHintProvider).value ?? false,
      errorCode: _limitedCode,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _done = null;
    });

    final s = widget.server;

    // Πρώτα οι συνεδρίες: χωρίς αυτές δεν υπάρχει τρόπος να ξέρουμε ποιος
    // εκτυπωτής είναι ορφανός, και μια εικασία εδώ σβήνει εκτυπωτές που
    // δουλεύουν.
    final sessions = await ref
        .read(serverSessionServiceProvider)
        .listSessions(
          host: s.host,
          adminUser: s.adminUser,
          adminPassword: s.adminPassword,
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
          host: s.host,
          adminUser: s.adminUser,
          adminPassword: s.adminPassword,
        );
    if (!mounted) return;
    if (!printers.ok) {
      setState(() {
        _loading = false;
        _error = printers.error;
      });
      return;
    }

    setState(() {
      _loading = false;
      _printerCount = printers.printers.length;
      _limited = printers.isLimited;
      _limitedCode = printers.fallbackCode;
      _orphans = PrinterStationMatching.orphans(
        printers: printers.printers,
        liveSessionIds: PrinterStationMatching.liveSessionIds(
          sessions.sessions,
        ),
      );
    });
  }

  Future<void> _cleanup() async {
    setState(() {
      _working = true;
      _error = null;
    });

    final s = widget.server;
    final service = ref.read(serverPrinterServiceProvider);
    var removed = 0;
    String? lastError;

    for (final p in _orphans) {
      final result = await service.removePrinter(
        host: s.host,
        adminUser: s.adminUser,
        adminPassword: s.adminPassword,
        printerFullName: p.fullName,
      );
      if (result.ok) {
        removed++;
      } else {
        lastError = result.error;
      }
    }
    if (!mounted) return;

    setState(() {
      _working = false;
      _done = 'Αφαιρέθηκαν $removed από ${_orphans.length} ορφανούς εκτυπωτές.';
      // Μερική αποτυχία λέγεται, δεν κρύβεται: κάποιοι μπορεί να ήταν
      // κλειδωμένοι από τη διεργασία εκτύπωσης.
      _error = removed == _orphans.length ? null : lastError;
    });
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableDialogShell(
      title: const Text('Καθαρισμός ορφανών εκτυπωτών'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.server.displayLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Σάρωση εκτυπωτών και συνεδριών…'),
                  ],
                )
              else ...[
                const Text(
                  'Ορφανός είναι ο εκτυπωτής που ανήκει σε συνεδρία η οποία δεν '
                  'υπάρχει πια. Δεν εξυπηρετεί κανέναν και φορτώνει την ουρά '
                  'εκτυπώσεων για πάντα.',
                ),
                const SizedBox(height: 12),
                Text(
                  '$_printerCount εκτυπωτές συνολικά · '
                  '${_orphans.length} ορφανοί',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_limited) ...[
                  const SizedBox(height: 8),
                  ServerActionBanner(
                    icon: Icons.info_outline,
                    color: theme.colorScheme.tertiary,
                    // Οι ορφανοί εντοπίζονται κανονικά — η αντιστοίχιση θέλει
                    // ονόματα, όχι ουρές. Η αφαίρεση όμως περνά από την
                    // υπηρεσία που δεν απαντά, γι' αυτό και το κουμπί σβήνει.
                    text:
                        '$_limitedViewText Η αφαίρεση περνά από την ίδια '
                        'υπηρεσία, οπότε δεν είναι διαθέσιμη τώρα — ο '
                        'εντοπισμός των ορφανών παραμένει έγκυρος.',
                  ),
                ],
                if (_orphans.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _orphans.length,
                        itemBuilder: (ctx, i) {
                          final p = _orphans[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link_off, size: 18),
                            title: Text(
                              p.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'συνεδρία ${p.sessionId}'
                              '${p.stationName.isEmpty ? '' : ' · από ${p.stationName}'}',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
              if (_done != null) ...[
                const SizedBox(height: 12),
                ServerActionBanner(
                  icon: Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  text: _done!,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ServerActionBanner(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  text: _error!,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
          FilledButton.icon(
            onPressed: _loading || _working || _limited || _orphans.isEmpty
                ? null
                : _cleanup,
            icon: _working
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined, size: 18),
            label: Text(
              _working ? 'Γίνεται…' : 'Αφαίρεση ${_orphans.length} ορφανών',
            ),
          ),
        ],
      ),
    );
  }
}

// --- Επανεκκίνηση διακομιστή -----------------------------------------------

class _ServerRestartDialog extends ConsumerStatefulWidget {
  const _ServerRestartDialog({required this.server});

  final ManagedServer server;

  @override
  ConsumerState<_ServerRestartDialog> createState() =>
      _ServerRestartDialogState();
}

class _ServerRestartDialogState extends ConsumerState<_ServerRestartDialog> {
  static const int _graceSeconds = 90;

  final TextEditingController _confirmController = TextEditingController();

  bool _loading = true;
  bool _working = false;
  String? _error;

  List<ServerSession> _sessions = const [];

  /// Όσο τρέχει, η επανεκκίνηση έχει ήδη ξεκινήσει και μπορεί να ακυρωθεί.
  Timer? _countdown;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmController.text.trim().toLowerCase() ==
      widget.server.host.trim().toLowerCase();

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ref
        .read(serverSessionServiceProvider)
        .listSessions(
          host: widget.server.host,
          adminUser: widget.server.adminUser,
          adminPassword: widget.server.adminPassword,
        );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.ok) {
        _sessions = result.sessions.where((s) => s.isLogoffCandidate).toList();
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      _working = true;
      _error = null;
    });

    final result = await ref
        .read(serverPrinterServiceProvider)
        .initiateRestart(
          host: widget.server.host,
          adminUser: widget.server.adminUser,
          adminPassword: widget.server.adminPassword,
          message:
              'Ο διακομιστής επανεκκινείται. Αποθηκεύστε τη δουλειά σας και '
              'αποσυνδεθείτε.',
          graceSeconds: _graceSeconds,
        );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _working = false;
        _error = result.error;
      });
      return;
    }

    // Μία πηγή χρόνου: ο μετρητής μειώνεται από το χρονόμετρο και από πουθενά
    // αλλού, ώστε να μη δείχνει άλλα η οθόνη και άλλα ο διακομιστής.
    setState(() {
      _working = false;
      _secondsLeft = _graceSeconds;
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  Future<void> _abort() async {
    setState(() => _working = true);
    final result = await ref
        .read(serverPrinterServiceProvider)
        .abortRestart(
          host: widget.server.host,
          adminUser: widget.server.adminUser,
          adminPassword: widget.server.adminPassword,
        );
    if (!mounted) return;

    setState(() {
      _working = false;
      if (result.ok) {
        _countdown?.cancel();
        _secondsLeft = 0;
        _error = null;
      } else {
        _error = result.error;
      }
    });
    if (result.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η επανεκκίνηση ακυρώθηκε.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counting = _secondsLeft > 0;

    return DraggableDialogShell(
      title: const Text('Επανεκκίνηση διακομιστή'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        icon: Icon(Icons.dangerous_outlined, color: theme.colorScheme.error),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.server.displayLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (counting) ...[
                ServerActionBanner(
                  icon: Icons.timer_outlined,
                  color: theme.colorScheme.error,
                  text:
                      'Η επανεκκίνηση ξεκίνησε. Απομένουν $_secondsLeft '
                      'δευτερόλεπτα — όσο μετράει, μπορεί να ακυρωθεί.',
                ),
              ] else ...[
                if (_loading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Μετράμε ποιοι δουλεύουν αυτή τη στιγμή…'),
                    ],
                  )
                else ...[
                  ServerActionBanner(
                    icon: Icons.groups_outlined,
                    color: theme.colorScheme.error,
                    text: _sessions.isEmpty
                        ? 'Δεν βρέθηκε καμία ανοιχτή συνεδρία.'
                        : 'Θα πεταχτούν έξω ${_sessions.length} χρήστες: '
                              '${_sessionNames()}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Θα τους σταλεί προειδοποίηση και θα έχουν $_graceSeconds '
                    'δευτερόλεπτα να αποθηκεύσουν. Ό,τι δεν σωθεί, χάνεται.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Για επιβεβαίωση, γράψε τη διεύθυνση του διακομιστή:',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _confirmController,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: widget.server.host,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ServerActionBanner(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  text: _error!,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
          if (counting)
            FilledButton.icon(
              onPressed: _working ? null : _abort,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('ΑΚΥΡΩΣΗ επανεκκίνησης'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: _loading || _working || !_confirmed ? null : _start,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(_working ? 'Γίνεται…' : 'Επανεκκίνηση'),
            ),
        ],
      ),
    );
  }

  String _sessionNames() {
    final names = _sessions.map((s) => s.username).toList()..sort();
    if (names.length <= 6) return names.join(', ');
    return '${names.take(6).join(', ')} και ${names.length - 6} ακόμη';
  }
}
