import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../database/database_init_result.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Οθόνη σφάλματος βάσης / γενικού σφάλματος.
/// Λεπτομερή ελληνικά μηνύματα, επιλέξιμο κείμενο, αντιγραφή πλήρους αναφοράς.
class DatabaseErrorScreen extends StatefulWidget {
  const DatabaseErrorScreen({
    super.key,
    required this.result,
    required this.dbPath,
    required this.onRetry,
  });

  final DatabaseInitResult result;
  final String? dbPath;
  final Future<void> Function() onRetry;

  @override
  State<DatabaseErrorScreen> createState() => _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends State<DatabaseErrorScreen> {
  late final ScrollController _detailsScrollController;

  bool get _shouldOfferRestart {
    final original = widget.result.originalExceptionText?.toLowerCase() ?? '';
    final details = widget.result.details?.toLowerCase() ?? '';
    return original.contains('timed out') ||
        original.contains('timeoutexception') ||
        details.contains('δεν απάντησε έγκαιρα');
  }

  bool get _isFileNotFound =>
      widget.result.status == DatabaseStatus.fileNotFound;

  /// Μόνο τα σφάλματα με φιλικά κείμενα μετανάστευσης/SQLite από [DatabaseInitResult]
  /// (όχι γενικά applicationError όπως δίκτυο, timeout, «SQLite)» fallback κ.λπ.).
  bool get _isSchemaMigrationRecoveryMessage {
    if (_shouldOfferRestart) return false;
    if (widget.result.status != DatabaseStatus.applicationError) return false;
    final msg = widget.result.message ?? '';
    if (msg.contains('Προέκυψε πρόβλημα κατά την πρόσβαση ή την ενημέρωση') &&
        msg.contains('SQLite')) {
      return false;
    }
    if (msg.contains('Λείπει ο πίνακας') ||
        msg.contains('Λείπει αναμενόμενος πίνακας') ||
        msg.contains('Λείπει η στήλη') ||
        msg.contains('Λείπει αναμενόμενη στήλη')) {
      return true;
    }
    if (msg.contains('κατεστραμμένη ή βρίσκεται σε παλιά μορφή') ||
        msg.contains('κατεστραμμένη ή σε ασύμβατη μορφή')) {
      return true;
    }
    if (msg.contains('αναβάθμιση της βάσης δεδομένων') ||
        msg.contains('αναβάθμιση του σχήματος της βάσης δεδομένων')) {
      return true;
    }
    final det = widget.result.details ?? '';
    if (det.contains('Δοκιμάστε να διαγράψετε') &&
        det.contains('Data Base') &&
        det.contains('Εντολή SQL (Causing statement)')) {
      return true;
    }
    return false;
  }

  String? get _databaseFilePath =>
      (widget.result.path ?? widget.dbPath)?.trim();

  static const Color _solutionPhraseBlue = Color(0xFF1565C0);

  Future<void> _openSettingsForDatabaseIssue({
    required bool openFindDatabaseOnStart,
    required bool openCreateDatabaseOnStart,
  }) async {
    await Navigator.of(context).push<bool?>(
      MaterialPageRoute<bool?>(
        builder: (_) => SettingsScreen(
          openFindDatabaseOnStart: openFindDatabaseOnStart,
          openCreateDatabaseOnStart: openCreateDatabaseOnStart,
        ),
      ),
    );
    if (!context.mounted) return;
    await widget.onRetry();
  }

  Widget _buildMissingDatabaseGuidance(ThemeData theme) {
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );
    final boldLabel = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final bluePhrase = baseStyle?.copyWith(
      color: _solutionPhraseBlue,
      fontWeight: FontWeight.w600,
    );

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(
            text: 'Η βάση έχει αλλάξει τοποθεσία. Μπορείτε να ',
          ),
          TextSpan(text: 'αναζητήσετε τη βάση', style: bluePhrase),
          const TextSpan(text: ' σας με το κουμπί '),
          TextSpan(text: 'Εύρεση βάσης', style: boldLabel),
          const TextSpan(text: ' ή να '),
          TextSpan(text: 'δημιουργήσετε μία νέα βάση', style: bluePhrase),
          const TextSpan(
            text: ', ΧΩΡΙΣ δεδομένα με το κουμπί ',
          ),
          TextSpan(text: 'Δημιουργία νέας βάσης', style: boldLabel),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _detailsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _detailsScrollController.dispose();
    super.dispose();
  }

  String get _fallbackShortTitle {
    switch (widget.result.status) {
      case DatabaseStatus.fileNotFound:
        return 'Δεν βρέθηκε βάση δεδομένων.';
      case DatabaseStatus.accessDenied:
        return 'Πρόβλημα πρόσβασης στο αρχείο βάσης.';
      case DatabaseStatus.corruptedOrInvalid:
        return 'Μη έγκυρο ή κατεστραμμένο αρχείο βάσης.';
      case DatabaseStatus.applicationError:
        return 'Σφάλμα εφαρμογής ή υποσυστήματος.';
      case DatabaseStatus.success:
        return widget.result.message ?? 'Η σύνδεση πέτυχε.';
    }
  }

  String get _primaryMessage {
    final m = widget.result.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return _fallbackShortTitle;
  }

  Future<void> _copyFullReport(BuildContext context) async {
    final text = widget.result.buildClipboardReport(dbPathFallback: widget.dbPath);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκε πλήρης αναφορά σφάλματος στο πρόχειρο.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Άνοιγμα του Windows Explorer στο προβληματικό αρχείο .db (`/select,`).
  Future<void> _openFolderContainingDatabaseFile() async {
    final full = _databaseFilePath;
    if (full == null || full.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν υπάρχει γνωστή διαδρομή αρχείου βάσης για εντοπισμό.',
          ),
        ),
      );
      return;
    }
    if (!Platform.isWindows) {
      try {
        final dir = Directory(full).parent.path;
        await Process.run('explorer', [dir]);
      } catch (_) {}
      return;
    }
    try {
      final normalized = full.replaceAll('/', r'\');
      await Process.run('explorer.exe', ['/select,', normalized]);
    } catch (_) {
      try {
        await Process.run('explorer.exe', [Directory(full).parent.path]);
      } catch (_) {}
    }
  }

  Future<void> _restartApplication(BuildContext context) async {
    try {
      await Process.start(
        Platform.resolvedExecutable,
        Platform.executableArguments,
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Η αυτόματη επανεκκίνηση δεν ήταν δυνατή. Κλείστε και ανοίξτε ξανά την εφαρμογή.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = widget.result.path ?? widget.dbPath;
    final details = widget.result.details?.trim();
    final original = widget.result.originalExceptionText?.trim();
    final stack = widget.result.stackTraceText?.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Σφάλμα',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: _detailsScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _detailsScrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          _primaryMessage,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (_isFileNotFound && !_shouldOfferRestart) ...[
                          const SizedBox(height: 18),
                          _buildMissingDatabaseGuidance(theme),
                        ],
                        if (details != null && details.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SelectableText(
                            details,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (path != null && path.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Διαδρομή',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            path,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (widget.result.technicalCode != null &&
                            widget.result.technicalCode!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Κωδικός / αναγνωριστικό',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            widget.result.technicalCode!.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (original != null && original.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Αρχικό μήνυμα σφάλματος (runtime)',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            original,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (stack != null && stack.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Stack trace',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            stack,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _copyFullReport(context),
                icon: const Icon(Icons.copy),
                label: const Text('Αντιγραφή πλήρους σφάλματος'),
              ),
              const SizedBox(height: 12),
              if (!_isSchemaMigrationRecoveryMessage) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Ρυθμίσεις'),
                ),
                const SizedBox(height: 12),
              ],
              if (_isFileNotFound && !_shouldOfferRestart)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openSettingsForDatabaseIssue(
                          openFindDatabaseOnStart: true,
                          openCreateDatabaseOnStart: false,
                        ),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Εύρεση βάσης'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openSettingsForDatabaseIssue(
                          openFindDatabaseOnStart: false,
                          openCreateDatabaseOnStart: true,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Δημιουργία νέας βάσης'),
                      ),
                    ),
                  ],
                )
              else if (_isSchemaMigrationRecoveryMessage && !_shouldOfferRestart)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openFolderContainingDatabaseFile,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('Εντοπισμός βάσης'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openSettingsForDatabaseIssue(
                              openFindDatabaseOnStart: false,
                              openCreateDatabaseOnStart: true,
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Δημιουργία νέας βάσης'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await widget.onRetry();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Επαναδοκιμή'),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    if (_shouldOfferRestart) {
                      await _restartApplication(context);
                      return;
                    }
                    await widget.onRetry();
                  },
                  icon: Icon(_shouldOfferRestart ? Icons.restart_alt : Icons.refresh),
                  label: Text(_shouldOfferRestart ? 'Επανεκκίνηση εφαρμογής' : 'Επαναδοκιμή'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
