// Οθόνη Λάμπας: συντονισμός καρτελών, controllers και dialogs.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_network_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../../../core/providers/lamp_open_settings_intent_provider.dart';
import '../../../core/providers/lamp_read_path_health_provider.dart';
import '../../calls/provider/lookup_provider.dart';
import '../controllers/lamp_import_controller.dart';
import '../controllers/lamp_integrity_controller.dart';
import '../controllers/lamp_issue_resolution_controller.dart';
import '../controllers/lamp_path_management.dart';
import '../controllers/lamp_screen_host.dart';
import '../controllers/lamp_search_controller.dart';
import '../services/lamp_migration_service.dart';
import '../widgets/lamp_db_tables_tab.dart';
import '../widgets/lamp_issue_widgets.dart';
import '../widgets/lamp_result_card.dart';
import '../widgets/lamp_settings_dialog.dart';
import '../widgets/lamp_transfer_wizard_dialog.dart';

class LampScreen extends ConsumerStatefulWidget {
  const LampScreen({super.key});

  @override
  ConsumerState<LampScreen> createState() => _LampScreenState();
}

class _LampScreenState extends ConsumerState<LampScreen> implements LampScreenHost {
  late final LampScreenShared _shared;
  late final LampPathController _path;
  late final LampSearchController _search;
  late final LampImportController _import;
  late final LampIntegrityController _integrity;
  late final LampIssuesController _issues;
  late final LampIssueResolutionController _resolution;

  final _lampErrorDialogScroll = ScrollController();

  bool _loading = true;
  bool _lampSettingsDialogOpen = false;
  String? _lampDialogFeedback;
  bool _lampDialogFeedbackIsError = false;
  StateSetter? _lampSettingsDialogSetState;
  bool _capturedLampRequestBaseline = false;
  int _lampRequestBaseline = 0;

  @override
  LampScreenShared get shared => _shared;

  @override
  LampOldDbCheckResult? get readPathCheck =>
      ref.watch(lampReadPathHealthProvider).value;

  @override
  bool get lampSettingsDialogOpen => _lampSettingsDialogOpen;

  @override
  set lampSettingsDialogOpen(bool value) => _lampSettingsDialogOpen = value;

  @override
  StateSetter? get lampSettingsDialogSetState => _lampSettingsDialogSetState;

  @override
  set lampSettingsDialogSetState(StateSetter? value) =>
      _lampSettingsDialogSetState = value;

  @override
  String? get lampDialogFeedback => _lampDialogFeedback;

  @override
  set lampDialogFeedback(String? value) => _lampDialogFeedback = value;

  @override
  bool get lampDialogFeedbackIsError => _lampDialogFeedbackIsError;

  @override
  set lampDialogFeedbackIsError(bool value) =>
      _lampDialogFeedbackIsError = value;

  @override
  void notifyState() => setState(() {});

  @override
  void clearLampDialogFeedback() {
    if (_lampDialogFeedback == null && !_lampDialogFeedbackIsError) return;
    if (!mounted) return;
    setState(() {
      _lampDialogFeedback = null;
      _lampDialogFeedbackIsError = false;
    });
    _lampSettingsDialogSetState?.call(() {});
  }

  @override
  void setLampDialogFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _lampDialogFeedback = message;
      _lampDialogFeedbackIsError = isError;
    });
    _lampSettingsDialogSetState?.call(() {});
  }

  @override
  Future<void> runLiveSearch() => _search.runLiveSearch();

  @override
  Future<void> loadIssues() => _issues.loadIssues();

  @override
  void initState() {
    super.initState();
    _shared = LampScreenShared(
      settings: LampSettingsStore(),
      repository: OldEquipmentRepository(),
      issueResolutionService: LampIssueResolutionService(),
      networkIssueResolutionService: LampNetworkIssueResolutionService(),
      migrationService: LampMigrationService(),
      importer: OldExcelImporter(),
    );
    _path = LampPathController(host: this);
    _search = LampSearchController(host: this, path: _path);
    _import = LampImportController(host: this, path: _path);
    _integrity = LampIntegrityController(host: this, path: _path);
    _issues = LampIssuesController(host: this, path: _path, search: _search);
    _resolution = LampIssueResolutionController(
      host: this,
      path: _path,
      search: _search,
      issuesList: () => _issues.issues,
      issueCountFor: _issues.issueCountFor,
    );
    _search.attachListeners();
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_capturedLampRequestBaseline) {
      _capturedLampRequestBaseline = true;
      _lampRequestBaseline = ref.read(lampOpenSettingsRequestProvider);
    }
  }

  @override
  void dispose() {
    _search.detachListeners();
    _search.dispose();
    _path.dispose();
    _lampErrorDialogScroll.dispose();
    super.dispose();
  }

  @override
  void showSnack(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (!mounted) return;
    if (_lampSettingsDialogOpen) {
      if (isError) {
        unawaited(showLampErrorDialog(message));
      } else {
        setLampDialogFeedback(message, isError: false);
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        duration: duration,
      ),
    );
  }

  @override
  Future<void> showLampErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          icon: const Icon(Icons.error_outline),
          title: const Text('Σφάλμα'),
          content: SizedBox(
            width: 560,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
              ),
              child: Scrollbar(
                controller: _lampErrorDialogScroll,
                child: SingleChildScrollView(
                  controller: _lampErrorDialogScroll,
                  child: SelectableText(
                    message,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Αντιγραφή'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Κλείσιμο'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSettings() async {
    await _path.loadPathsFromSettings();
    _search.maxSearchResults = await _shared.settings.getMaxSearchResults();
    _search.maxSearchResultsController.text =
        _search.maxSearchResults.toString();
    await _path.applyPersistedReadAndValidate(
      announce: true,
      source: 'έναρξη',
      onDbOk: _onReadPathOk,
      onDbNotOk: _onReadPathNotOk,
    );
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _onReadPathOk() async {
    await _issues.loadIssues();
    await _shared.repository.preloadSearchCache(
      _path.readDbController.text.trim(),
    );
  }

  void _onReadPathNotOk() {
    _issues.clearIssues();
    notifyState();
  }

  Future<void> _refreshDataAfterReadPathChange({
    required String source,
    bool announce = true,
  }) async {
    await _path.refreshDataAfterReadPathChange(
      source: source,
      announce: announce,
      onDbOk: _onReadPathOk,
      onDbNotOk: _onReadPathNotOk,
    );
  }

  Future<void> _runImport() async {
    final failureMessage = await _import.runImport(
      onImportStart: () {
        _search.results = const <Map<String, Object?>>[];
        _search.message = null;
        _issues.clearIssues();
        notifyState();
      },
      onImportSuccess: (message) {
        _search.message = message;
        notifyState();
      },
      afterImportValidate: () => _path.applyPersistedReadAndValidate(
        announce: true,
        source: 'μετά import',
        onDbOk: _onReadPathOk,
        onDbNotOk: _onReadPathNotOk,
      ),
      onImportFailureReload: () async {
        await ref.read(lampReadPathHealthProvider.notifier).refresh(
          pathOverride: _path.readDbController.text.trim(),
          outputPathOverride: _path.outputDbController.text.trim(),
          excelPathOverride: _path.excelController.text.trim(),
        );
        await _issues.loadIssues();
      },
    );
    if (failureMessage != null && mounted) {
      setState(() => _search.message = failureMessage);
    }
  }

  Future<EquipmentSectionSaveResult> _saveEquipmentSection({
    required int id,
    required InfoSectionType sectionType,
    required Map<String, Object?> updatedFields,
  }) async {
    final dbPath = _path.readDbController.text.trim();
    if (dbPath.isEmpty) {
      return const EquipmentSectionSaveResult(
        success: false,
        message: 'Δεν έχει οριστεί βάση προς ενημέρωση.',
      );
    }
    final result = await _shared.repository.updateSection(
      databasePath: dbPath,
      id: id,
      sectionType: sectionType.toRepositorySectionType(),
      updatedFields: Map<String, Object?>.from(updatedFields),
    );
    if (result.success) {
      Future<void>.microtask(_search.runLiveSearch);
    }
    return EquipmentSectionSaveResult(
      success: result.success,
      message: result.message,
    );
  }

  LampTransferTarget? _transferTargetForSection(InfoSectionType sectionType) {
    return switch (sectionType) {
      InfoSectionType.equipment => LampTransferTarget.equipment,
      InfoSectionType.owner => LampTransferTarget.owner,
      InfoSectionType.department => LampTransferTarget.department,
      _ => null,
    };
  }

  Future<void> _openTransferWizard({
    required InfoSectionType sectionType,
    required Map<String, Object?> sourceRow,
  }) async {
    final target = _transferTargetForSection(sectionType);
    if (target == null) {
      showSnack('Η μεταφορά υποστηρίζεται μόνο για εξοπλισμό/κάτοχο/τμήμα.');
      return;
    }
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LampTransferWizardDialog(
        target: target,
        sourceRow: sourceRow,
        service: _shared.migrationService,
      ),
    );
    if (!mounted || message == null) return;
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!mounted) return;
    showSnack(message);
    await _search.runLiveSearch();
  }

  Future<void> _closeLampSettingsDialog(void Function() pop) async {
    if (_import.importing) return;
    pop();
    _lampSettingsDialogOpen = false;
    _lampSettingsDialogSetState = null;

    final parsedMax = int.tryParse(
      _search.maxSearchResultsController.text.trim(),
    );
    if (parsedMax != null) {
      await _shared.settings.setMaxSearchResults(parsedMax);
    }
    if (mounted) {
      final max = await _shared.settings.getMaxSearchResults();
      setState(() {
        _search.maxSearchResults = max;
        _search.maxSearchResultsController.text = max.toString();
      });
    }
    await _refreshDataAfterReadPathChange(
      source: 'αποθήκευση ρυθμίσεων',
      announce: false,
    );
    if (!mounted) return;
    Future<void>.microtask(_search.runLiveSearch);
  }

  void _openLampSettingsDialog() {
    if (_lampSettingsDialogOpen) return;
    _lampSettingsDialogOpen = true;
    clearLampDialogFeedback();
    final settingsController = LampSettingsDialogController(
      path: _path,
      search: _search,
      importController: _import,
      integrityController: _integrity,
      getReadPathCheck: () => readPathCheck,
      getDialogFeedback: () => _lampDialogFeedback,
      getDialogFeedbackIsError: () => _lampDialogFeedbackIsError,
      onClearDialogFeedback: clearLampDialogFeedback,
      onCopyDialogFeedback: (message) =>
          Clipboard.setData(ClipboardData(text: message)),
      onPickExcel: _path.pickExcel,
      onPickReadDatabase: () => _path.pickReadDatabase(
        onPathChanged: ({required source}) =>
            _refreshDataAfterReadPathChange(source: source),
      ),
      onPickDatabaseOutput: () => _path.pickDatabaseOutput(
        onReadSynced: ({required source}) =>
            _refreshDataAfterReadPathChange(source: source),
      ),
      onMatchReadToOutput: _path.matchReadToOutput,
      onRunIntegrityCheck: () => _integrity.runIntegrityCheck(
        reloadIssues: _issues.loadIssues,
      ),
      onApplyPersistedReadAndValidate: () => _path.applyPersistedReadAndValidate(
        announce: true,
        source: 'επαλήθευση',
        onDbOk: _onReadPathOk,
        onDbNotOk: _onReadPathNotOk,
      ),
      onRunImport: _runImport,
      onClose: _closeLampSettingsDialog,
      isImporting: () => _import.importing,
      isIntegrityChecking: () => _integrity.integrityChecking,
    );
    openLampSettingsDialog(
      context: context,
      controller: settingsController,
      registerDialogSetState: (setDialogState) {
        _lampSettingsDialogSetState = setDialogState;
      },
      onDialogClosed: () {
        if (mounted) {
          setState(() {
            _lampSettingsDialogOpen = false;
            _lampDialogFeedback = null;
            _lampDialogFeedbackIsError = false;
          });
        } else {
          _lampSettingsDialogOpen = false;
          _lampDialogFeedback = null;
          _lampDialogFeedbackIsError = false;
        }
        _lampSettingsDialogSetState = null;
      },
    );
  }

  void _toggleIssueGroup(String rawIssueType, bool expanded) {
    setState(() {
      if (expanded) {
        _issues.expandedIssueGroupKeys.remove(rawIssueType);
      } else {
        _issues.expandedIssueGroupKeys.add(rawIssueType);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(lampOpenSettingsRequestProvider, (previous, next) {
      if (next > _lampRequestBaseline) {
        _lampRequestBaseline = next;
        Future<void>.microtask(() {
          if (!mounted) return;
          _openLampSettingsDialog();
        });
      }
    });
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final dbOk = readPathCheck?.status == LampOldDbStatus.ok;
    final showEtlTab = dbOk && _issues.issues.isNotEmpty;
    final showTablesTab = dbOk;
    final tabCount = 1 + (showEtlTab ? 1 : 0) + (showTablesTab ? 1 : 0);
    return DefaultTabController(
      key: ValueKey('lamp-$tabCount'),
      length: tabCount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            tabs: [
              const Tab(text: 'Αναζήτηση'),
              if (showEtlTab) const Tab(text: 'Προβλήματα Εξαγωγής, Μετασχηματισμού και Φόρτωσης (ETL)'),
              if (showTablesTab) const Tab(text: 'Πίνακες'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _searchTab(context),
                if (showEtlTab)
                  LampIssuesTab(
                    issuesController: _issues,
                    resolutionController: _resolution,
                    integrityChecking: _integrity.integrityChecking,
                    onRunIntegrityCheck: () => _integrity.runIntegrityCheck(
                      reloadIssues: _issues.loadIssues,
                    ),
                    showSnack: showSnack,
                    onToggleGroup: _toggleIssueGroup,
                  ),
                if (showTablesTab)
                  LampDbTablesTab(
                    key: ValueKey(
                      'lamp-tables-${_path.readDbController.text.trim()}',
                    ),
                    databasePath: _path.readDbController.text.trim(),
                    repository: _shared.repository,
                    onAfterDataIssuesPurge: _issues.loadIssues,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LampSearchTabReadPathBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final blockWidth = LampSearchController.searchFieldsBlockWidth(
                constraints.maxWidth,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: blockWidth,
                    child: TextField(
                      controller: _search.globalController,
                      decoration: InputDecoration(
                        labelText: 'Καθολική Αναζήτηση',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.clearFieldSuffix(
                          controller: _search.globalController,
                          tooltip: 'Καθαρισμός καθολικής αναζήτησης',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search.globalSearch(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: LampSearchController.searchFieldSpacing,
                    runSpacing: LampSearchController.searchFieldSpacing,
                    children: [
                      _smallField(_search.phoneController, 'Τηλέφωνο'),
                      _smallField(
                        _search.codeController,
                        'Κωδικός Εξοπλισμού',
                      ),
                      _smallField(_search.ownerController, 'Υπάλληλος'),
                      _smallField(_search.officeController, 'Τμήμα'),
                      _smallField(
                        _search.serialController,
                        'Σειριακός Αριθμός',
                      ),
                      OutlinedButton.icon(
                        onPressed: _search.clearAllSearchInputs,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Καθαρισμός όλων'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        if (_search.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _search.message!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        Expanded(child: _resultsList(context)),
      ],
    );
  }

  Widget _smallField(TextEditingController controller, String label) {
    return SizedBox(
      width: LampSearchController.searchFieldWidth,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _search.clearFieldSuffix(
            controller: controller,
            tooltip: 'Καθαρισμός πεδίου',
          ),
        ),
        onSubmitted: (_) => _search.fieldSearch(),
      ),
    );
  }

  Widget _resultsList(BuildContext context) {
    if (_search.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _search.emptyResultsCenterMessage(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _search.results.length,
      itemBuilder: (context, index) => EquipmentResultCard(
        viewModel: EquipmentViewModel.fromRow(_search.results[index]),
        onSaveSection: _saveEquipmentSection,
        onTransferSection: _openTransferWizard,
      ),
    );
  }
}
