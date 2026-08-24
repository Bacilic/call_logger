import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/active_database_generation.dart';
import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/init/database_switch_guard.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/new_database_suggested_file_name.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../settings/widgets/create_new_database_dialog.dart';
import '../services/create_new_database_texts.dart';
import '../utils/database_path_dropdown_options.dart';
import 'database_rename_notice_text.dart';
import 'database_settings_switch_flows.dart';

/// Καρτέλα «Βάση»: διαδρομή αρχείου βάσης και δημιουργία νέου `.db`.
class DatabaseSettingsFileTab extends ConsumerStatefulWidget {
  const DatabaseSettingsFileTab({super.key, this.onDatabaseLifecycleChanged});

  /// Μετά από επιτυχή αλλαγή διαδρομής (επαλήθευση) ή δημιουργία νέου αρχείου βάσης.
  final Future<void> Function()? onDatabaseLifecycleChanged;

  @override
  ConsumerState<DatabaseSettingsFileTab> createState() =>
      _DatabaseSettingsFileTabState();
}

class _DatabaseSettingsFileTabState
    extends ConsumerState<DatabaseSettingsFileTab>
    with
        AutomaticKeepAliveClientMixin,
        DatabaseSettingsSwitchFlows<DatabaseSettingsFileTab> {
  final SettingsService _settings = SettingsService();

  String _currentDbPath = '';
  List<String> _recentDbPaths = [];
  bool _currentDbPathExists = false;
  bool _isLoadingDbPath = true;
  String? _dbPathErrorMessage;

  // Η κατάσταση της καρτέλας ζει όσο ζει ο διάλογος — όπως όταν όλα τα
  // τμήματα κατοικούσαν σε ένα ενιαίο πάνελ.
  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> Function()? get onDatabaseLifecycleChanged =>
      widget.onDatabaseLifecycleChanged;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDatabasePathSection());
  }

  @override
  Future<void> refreshAfterDatabaseSwitch(String activePath) async {
    if (!mounted) return;
    setState(() {
      _currentDbPath = activePath;
      _dbPathErrorMessage = null;
    });
    await _loadDatabasePathSection();
  }

  Future<void> _loadDatabasePathSection() async {
    setState(() {
      _isLoadingDbPath = true;
      _dbPathErrorMessage = null;
    });
    try {
      final path = await _settings.getDatabasePath();
      final recent = await _settings.getRecentDatabasePaths();
      var exists = false;
      if (path.trim().isNotEmpty) {
        try {
          exists = await File(path).exists();
        } catch (_) {
          // Η αδυναμία ΕΛΕΓΧΟΥ είναι η απάντηση: σε νεκρή δικτυακή διαδρομή ή
          // άρνηση πρόσβασης δεν μπορούμε να επιβεβαιώσουμε το αρχείο, οπότε το
          // εικονίδιο «δεν υπάρχει αυτή η βάση» είναι η σωστή ένδειξη. Το
          // ονομαστικό σφάλμα το δίνει η επόμενη απόπειρα ανοίγματος.
          exists = false;
        }
      }
      final paths = List<String>.from(recent);
      if (mounted) {
        setState(() {
          _currentDbPath = path;
          _recentDbPaths = paths;
          _currentDbPathExists = exists;
          _isLoadingDbPath = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dbPathErrorMessage =
              'Σφάλμα ανάγνωσης διαδρομής: ${humanizeUserFacingError(e)}';
          _isLoadingDbPath = false;
        });
      }
    }
  }

  Future<void> _pickDatabasePath() async {
    if (!await ensureDatabaseSwitchAllowed(context, ref)) return;

    setState(() {
      _dbPathErrorMessage = null;
    });

    final picked = await pickDatabasePathWithSystemPicker();
    if (FilePickerSession.takeLastRefocusedExisting()) return;
    // Ακύρωση επιλογέα = έγκυρη πράξη· κανένα μήνυμα (η κενή διαδρομή
    // αποκλείεται πλέον κεντρικά στο SettingsService.setDatabasePath).
    if (picked == null || picked.path.isEmpty) return;
    if (picked.isBackupArchive) {
      await restoreFromBackupZip(preselectedZipPath: picked.path);
    } else {
      await switchToPickedDatabasePath(picked.path);
    }
  }

  Future<void> _runCreateNewDatabaseFlow() async {
    await runGuardedDatabaseSwitch(context, ref, () async {
      if (!mounted) return;
      setState(() => _dbPathErrorMessage = null);
      await CreateNewDatabaseFlow.run(
        context,
        ref,
        onDatabaseReopened: widget.onDatabaseLifecycleChanged,
        onReloadSettingsState: () async {
          if (!mounted) return;
          await _loadDatabasePathSection();
          if (!mounted) return;
          setState(() {
            _dbPathErrorMessage = null;
          });
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    // Η βάση μπορεί να αλλάξει και από άλλη καρτέλα (π.χ. επαναφορά) — το
    // σήμα γενιάς ξαναφορτώνει τη λίστα διαδρομών.
    ref.listen<int>(activeDatabaseGenerationProvider, (_, _) {
      unawaited(_loadDatabasePathSection());
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Διαδρομή βάσης δεδομένων',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoadingDbPath)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
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
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      // Η τιμή είναι ΠΑΝΤΑ η ενεργή διαδρομή: οι επιλογές την
                      // περιλαμβάνουν εξ ορισμού, οπότε δεν υπάρχει εφεδρική τιμή
                      // που θα εμφάνιζε ως ενεργή μια βάση που δεν είναι ανοιχτή.
                      value: _currentDbPath,
                      isExpanded: true,
                      items:
                          databasePathDropdownOptions(
                            currentPath: _currentDbPath,
                            recentPaths: _recentDbPaths,
                          ).map((path) {
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
                        if (value == null || value == _currentDbPath) return;
                        await switchToPickedDatabasePath(value);
                      },
                    ),
                  ),
                ),
              ),
              if (_currentDbPath.isNotEmpty && !_currentDbPathExists) ...[
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
        if (_dbPathErrorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
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
                    _dbPathErrorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Δημιουργία νέου αρχείου βάσης',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        DatabaseRenameNoticeText(
          // Το όνομα ξαναϋπολογίζεται σε κάθε χτίσιμο: μετά από αλλαγή βάσης η
          // οδηγία πρέπει να μιλά για τη ΝΕΑ ενεργή βάση, όχι για την παλιά.
          parts: currentDatabaseRenameNotice(
            renamedFileName: _currentDbPath.trim().isEmpty
                ? ''
                : resolveRenamedOldDatabaseFileName(
                    currentDatabasePath: _currentDbPath.trim(),
                  ),
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        CompactTooltip(
          message: createNewDatabaseButtonTooltip(
            suggestedFileName: suggestNewCallLoggerDatabaseFileName(
              directory: _currentDbPath.trim().isEmpty
                  ? ''
                  : p.dirname(_currentDbPath.trim()),
            ),
          ),
          child: FilledButton.tonalIcon(
            onPressed: _currentDbPath.trim().isEmpty
                ? null
                : _runCreateNewDatabaseFlow,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Δημιουργία νέου αρχείου βάσης'),
          ),
        ),
      ],
    );
  }
}
