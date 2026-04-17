import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/calls_screen_cards_visibility.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/database/database_init_runner.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/init/app_init_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../calls/provider/remote_paths_provider.dart';
import '../../directory/providers/directory_provider.dart';
import '../widgets/create_new_database_dialog.dart';

/// Οθόνη ρυθμίσεων: διαδρομή βάσης δεδομένων και άλλες επιλογές.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.openCreateDatabaseOnStart = false,
    this.onAfterDatabaseChanged,
  });

  /// Μετά το πρώτο frame ανοίγει ο διάλογος δημιουργίας νέου αρχείου βάσης.
  final bool openCreateDatabaseOnStart;

  /// Μετά από νέα βάση / επανασύνδεση (ίδιο hook με `MainShell.onDatabaseReopened`).
  final Future<void> Function()? onAfterDatabaseChanged;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final SettingsService _settings = SettingsService();

  String _currentPath = '';
  List<String> _recentPaths = [];
  bool _currentPathExists = false;
  String? _selectedNewPath;
  bool _isLoadingPath = true;
  String? _errorMessage;
  bool _showImportExcelButton = false;
  bool _showActiveTimer = true;
  bool _showEmptyRemoteLaunchers = true;
  bool _enableSpellCheck = true;
  bool _showDatabaseNav = true;
  bool _showDictionaryNav = true;
  CallsScreenCardsVisibility _callsCardsVisibility =
      CallsScreenCardsVisibility.defaults;

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
    if (widget.openCreateDatabaseOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runCreateNewDatabaseFlow();
      });
    }
  }

  Future<void> _loadCurrentPath() async {
    setState(() {
      _isLoadingPath = true;
      _errorMessage = null;
    });
    try {
      final p = await _settings.getDatabasePath();
      final recent = await _settings.getRecentDatabasePaths();
      bool exists = false;
      if (p.trim().isNotEmpty) {
        try {
          exists = await File(p).exists();
        } catch (_) {
          exists = false;
        }
      }
      var paths = List<String>.from(recent);
      if (!paths.contains(p)) {
        paths.insert(0, p);
        paths = paths.take(3).toList();
      }
      final showImport = await _settings.getShowImportExcelButton();
      final showActiveTimer = await _settings.getShowActiveTimer();
      final showEmptyRemoteLaunchers = await _settings
          .getCallsShowEmptyRemoteLaunchers();
      final enableSpellCheck = await _settings.getEnableSpellCheck();
      final showDatabaseNav = await _settings.getShowDatabaseNav();
      final showDictionaryNav = await _settings.getShowDictionaryNav();
      final callsCardsVisibility = await _settings
          .getCallsScreenCardsVisibility();
      if (mounted) {
        setState(() {
          _currentPath = p;
          _recentPaths = paths;
          _currentPathExists = exists;
          _showImportExcelButton = showImport;
          _showActiveTimer = showActiveTimer;
          _showEmptyRemoteLaunchers = showEmptyRemoteLaunchers;
          _enableSpellCheck = enableSpellCheck;
          _showDatabaseNav = showDatabaseNav;
          _showDictionaryNav = showDictionaryNav;
          _callsCardsVisibility = callsCardsVisibility;
          _isLoadingPath = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Σφάλμα ανάγνωσης διαδρομής: $e';
          _isLoadingPath = false;
        });
      }
    }
  }

  String _callsCardsVisibilitySubtitle(CallsScreenCardsVisibility v) {
    final n = v.enabledCount;
    if (n == 5) return 'Όλες οι κάρτες εμφανίζονται';
    return '$n από 5 κάρτες εμφανίζονται';
  }

  Future<void> _openCallsCardsVisibilityEditor() async {
    final result = await showDialog<CallsScreenCardsVisibility>(
      context: context,
      builder: (ctx) =>
          _CallsScreenCardsEditorDialog(initial: _callsCardsVisibility),
    );
    if (result == null || !mounted) return;
    await _settings.setCallsScreenCardsVisibility(result);
    setState(() => _callsCardsVisibility = result);
    ref.invalidate(callsScreenCardsVisibilityProvider);
  }

  /// Επιλογή αρχείου .db (προτίμηση) ή φακέλου.
  Future<void> _pickDatabasePath() async {
    setState(() {
      _errorMessage = null;
      _selectedNewPath = null;
    });

    final picked = await pickDatabasePathWithSystemPicker();
    if (picked != null && picked.isNotEmpty) {
      await _validateApplyAndFinishPick(picked);
    } else {
      if (mounted) {
        setState(() => _errorMessage = 'Δεν επιλέχθηκε αρχείο ή φάκελος.');
      }
    }
  }

  /// Επαληθεύει το αρχείο βάσης (ίδια ροή με εκκίνηση), αποθηκεύει διαδρομή αν OK,
  /// επαναφέρει την προηγούμενη σε αποτυχία.
  Future<void> _validateApplyAndFinishPick(String newPath) async {
    final trimmed = newPath.trim();
    if (trimmed.isEmpty || !mounted) return;

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

    late ({bool ok, DatabaseInitRunnerResult runner}) outcome;
    try {
      outcome = await setAndVerifyDatabasePath(trimmed);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    if (!outcome.ok) {
      if (!mounted) return;
      final msg =
          outcome.runner.result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
      final det = outcome.runner.result.details?.trim();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Η βάση δεν είναι έγκυρη'),
          content: SingleChildScrollView(
            child: Text(det != null && det.isNotEmpty ? '$msg\n\n$det' : msg),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Βάση έτοιμη'),
        content: const Text(
          'Η διαδρομή αποθηκεύτηκε και η βάση επαληθεύτηκε.\n\n'
          'Για πλήρη εφαρμογή αλλαγών, κλείστε την εφαρμογή (π.χ. Alt+F4) και ανοίξτε την ξανά.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() {
      _currentPath = trimmed;
      _selectedNewPath = null;
      _errorMessage = null;
    });
    await _loadCurrentPath();

    if (!mounted) return;
    ref.invalidate(appInitProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η νέα βάση ορίστηκε και επαληθεύτηκε.')),
      );
    }
  }

  Future<void> _runCreateNewDatabaseFlow() async {
    setState(() => _errorMessage = null);
    await CreateNewDatabaseFlow.run(
      context,
      ref,
      onDatabaseReopened: widget.onAfterDatabaseChanged,
      onReloadSettingsState: () async {
        if (!mounted) return;
        await _loadCurrentPath();
        if (!mounted) return;
        setState(() {
          _selectedNewPath = null;
          _errorMessage = null;
        });
      },
    );
  }

  Future<void> _saveSettings() async {
    final newPath = _selectedNewPath?.trim();
    if (newPath == null || newPath.isEmpty) {
      setState(() => _errorMessage = 'Επιλέξτε πρώτα νέα διαδρομή.');
      return;
    }

    if (!newPath.toLowerCase().endsWith('.db')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Προειδοποίηση: η διαδρομή δεν τελειώνει σε .db. Βεβαιωθείτε ότι δείχνει σε αρχείο βάσης δεδομένων.',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }

    final newFile = File(newPath);
    try {
      final parentExists = await newFile.parent.exists();
      if (!parentExists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Προειδοποίηση: ο φάκελος δεν υπάρχει. Η διαδρομή θα αποθηκευτεί αλλά η βάση θα δημιουργηθεί στην πρώτη εκκίνηση.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}

    try {
      await _settings.setDatabasePath(newPath);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Σφάλμα αποθήκευσης: $e');
      }
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ρυθμίσεις αποθηκεύτηκαν'),
        content: const Text(
          'Η νέα διαδρομή θα ισχύσει στην επόμενη εκκίνηση της εφαρμογής.\n\n'
          'Παρακαλώ κλείστε την εφαρμογή χειροκίνητα (Alt+F4 ή κουμπί κλεισίματος) και ανοίξτε την ξανά.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() {
      _currentPath = newPath;
      _selectedNewPath = null;
      _errorMessage = null;
    });
    await _loadCurrentPath();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Η διαδρομή αποθηκεύτηκε επιτυχώς')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ρυθμίσεις')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Διαδρομή βάσης δεδομένων',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingPath)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _recentPaths.contains(_currentPath)
                              ? _currentPath
                              : _recentPaths.isNotEmpty
                              ? _recentPaths.first
                              : _currentPath,
                          isExpanded: true,
                          items: _recentPaths.map((path) {
                            final isDefault = path == AppConfig.defaultDbPath;
                            return DropdownMenuItem<String>(
                              value: path,
                              child: Text(
                                path.isEmpty
                                    ? '(προεπιλογή)'
                                    : isDefault
                                    ? '$path (προεπιλογή)'
                                    : path,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (String? value) async {
                            if (value == null || value == _currentPath) return;
                            await _settings.setDatabasePath(value);
                            await _loadCurrentPath();
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_currentPath.isNotEmpty && !_currentPathExists) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Δεν υπάρχει αυτή η βάση δεδομένων.',
                      child: Icon(
                        Icons.error,
                        color: theme.colorScheme.error,
                        size: 28,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Επιλέξτε τη διαδρομή που είναι η βάση δεδομένων.',
                    child: IconButton.filled(
                      onPressed: _pickDatabasePath,
                      icon: const Icon(Icons.storage),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            if (_selectedNewPath != null) ...[
              const SizedBox(height: 20),
              Text(
                'Νέα διαδρομή (προεπισκόπηση)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  _selectedNewPath!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Αποθήκευση ρύθμισης'),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Δημιουργία νέου αρχείου βάσης',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Η τρέχουσα βάση μετονομάζεται πάντα ως «όνομα_old_ημερομηνία» στον φάκελό της (χωρίς διαγραφή). '
              'Δημιουργείται νέο κενό αρχείο και ορίζεται ενεργό· επανασύνδεση χωρίς επανεκκίνηση.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _currentPath.trim().isEmpty
                  ? null
                  : _runCreateNewDatabaseFlow,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Δημιουργία νέου αρχείου βάσης'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Άλλες επιλογές',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              enabled: !_isLoadingPath,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.dashboard_customize_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Κάρτες οθόνης κλήσεων'),
              subtitle: Text(
                _callsCardsVisibilitySubtitle(_callsCardsVisibility),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCallsCardsVisibilityEditor(),
            ),
            SwitchListTile(
              value: _showImportExcelButton,
              onChanged: (value) async {
                await _settings.setShowImportExcelButton(value);
                if (mounted) setState(() => _showImportExcelButton = value);
              },
              title: const Text('Εμφάνιση κουμπιού Import Excel'),
              subtitle: const Text(
                'Ενεργοποίηση για να εμφανίζεται το κουμπί εισαγωγής Excel στην κύρια οθόνη.',
              ),
            ),
            SwitchListTile(
              value: _showActiveTimer,
              onChanged: (value) async {
                await _settings.setShowActiveTimer(value);
                if (mounted) setState(() => _showActiveTimer = value);
                ref.invalidate(showActiveTimerProvider);
              },
              title: const Text('Εμφάνιση ενεργού χρονομέτρου'),
              subtitle: const Text(
                'Ενεργοποίηση για να εμφανίζεται ο χρόνος (MM:SS) στη φόρμα καταγραφής κλήσεων.',
              ),
            ),
            SwitchListTile(
              value: _showEmptyRemoteLaunchers,
              onChanged: (value) async {
                await _settings.setCallsShowEmptyRemoteLaunchers(value);
                if (mounted) setState(() => _showEmptyRemoteLaunchers = value);
                ref.invalidate(callsRemoteUiConfigProvider);
              },
              title: const Text(
                'Εμφάνιση απομακρυσμένης σύνδεσης χωρίς παραμέτρους',
              ),
              subtitle: const Text(
                'Μικρά εικονίδια δίπλα στα εργαλεία απομακρυσμένης σύνδεσης για άνοιγμα της εφαρμογής χωρίς στόχο από την κλήση.',
              ),
            ),
            SwitchListTile(
              value: _enableSpellCheck,
              onChanged: (value) async {
                await _settings.setEnableSpellCheck(value);
                if (mounted) setState(() => _enableSpellCheck = value);
                ref.invalidate(enableSpellCheckProvider);
              },
              title: const Text('Ορθογραφικός έλεγχος σημειώσεων'),
              subtitle: const Text(
                'Ενσωματωμένο λεξικό (ελληνικά + IT)· σημαντικό σε Windows όπου δεν υπάρχει εγγενής έλεγχος.',
              ),
            ),
            SwitchListTile(
              value: !_showDatabaseNav,
              onChanged: (value) async {
                final show = !value;
                await _settings.setShowDatabaseNav(show);
                if (mounted) setState(() => _showDatabaseNav = show);
                ref.invalidate(showDatabaseNavProvider);
              },
              title: const Text('Απόκρυψη Βάσης Δεδομένων'),
              subtitle: const Text(
                'Κρύβει το στοιχείο πλοήγησης «Βάση Δεδομένων». Οι ρυθμίσεις λεξικού είναι στην οθόνη Λεξικό.',
              ),
            ),
            SwitchListTile(
              value: !_showDictionaryNav,
              onChanged: (value) async {
                final show = !value;
                await _settings.setShowDictionaryNav(show);
                if (mounted) setState(() => _showDictionaryNav = show);
                ref.invalidate(showDictionaryNavProvider);
              },
              title: const Text('Απόκρυψη Λεξικού'),
              subtitle: const Text('Κρύβει το στοιχείο πλοήγησης «Λεξικό».'),
            ),
            SwitchListTile(
              value: ref.watch(catalogContinuousScrollProvider).value ?? true,
              onChanged: (bool val) async {
                final db = await DatabaseHelper.instance.database;
                await DirectoryRepository(
                  db,
                ).setSetting('catalog_continuous_scroll', val.toString());
                ref.invalidate(catalogContinuousScrollProvider);
              },
              title: const Text('Συνεχής κύλιση πίνακα Καταλόγου'),
              subtitle: const Text(
                'Mouse wheel γραμμή-γραμμή αντί για αλλαγή σελίδας.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Διάλογος συμπαγών διακοπτών για τις κάρτες της οθόνης κλήσεων.
class _CallsScreenCardsEditorDialog extends StatefulWidget {
  const _CallsScreenCardsEditorDialog({required this.initial});

  final CallsScreenCardsVisibility initial;

  @override
  State<_CallsScreenCardsEditorDialog> createState() =>
      _CallsScreenCardsEditorDialogState();
}

class _CallsScreenCardsEditorDialogState
    extends State<_CallsScreenCardsEditorDialog> {
  late CallsScreenCardsVisibility _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row({
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Κάρτες οθόνης κλήσεων'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Επιλέξτε ποιες κάρτες εμφανίζονται στην οθόνη καταγραφής κλήσεων.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              row(
                title: 'Κάρτα υπαλλήλου',
                value: _v.showUserCard,
                onChanged: (b) =>
                    setState(() => _v = _v.copyWith(showUserCard: b)),
              ),
              row(
                title: 'Κάρτα εξοπλισμού',
                value: _v.showEquipmentCard,
                onChanged: (b) =>
                    setState(() => _v = _v.copyWith(showEquipmentCard: b)),
              ),
              row(
                title: 'Πρόσφατο ιστορικό υπαλλήλου',
                value: _v.showEmployeeRecentCard,
                onChanged: (b) =>
                    setState(() => _v = _v.copyWith(showEmployeeRecentCard: b)),
              ),
              row(
                title: 'Ιστορικό εξοπλισμού',
                value: _v.showEquipmentRecentPanel,
                onChanged: (b) => setState(
                  () => _v = _v.copyWith(showEquipmentRecentPanel: b),
                ),
              ),
              row(
                title: 'Τελευταίες 7 κλήσεις',
                value: _v.showGlobalRecentCard,
                onChanged: (b) =>
                    setState(() => _v = _v.copyWith(showGlobalRecentCard: b)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_v),
          child: const Text('Εντάξει'),
        ),
      ],
    );
  }
}
