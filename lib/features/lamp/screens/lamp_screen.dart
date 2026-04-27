import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers/lamp_open_settings_intent_provider.dart';
import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../../database/services/database_stats_service.dart';
import '../widgets/lamp_db_tables_tab.dart';
import '../widgets/lamp_result_card.dart';

class LampScreen extends ConsumerStatefulWidget {
  const LampScreen({super.key});

  @override
  ConsumerState<LampScreen> createState() => _LampScreenState();
}

class _LampScreenState extends ConsumerState<LampScreen> {
  final _settings = LampSettingsStore();
  final _importer = OldExcelImporter();
  final _repository = OldEquipmentRepository();
  final _validator = LampOldDbValidator();

  final _excelController = TextEditingController();
  final _readDbController = TextEditingController();
  final _outputDbController = TextEditingController();
  final _globalController = TextEditingController();
  final _codeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _serialController = TextEditingController();
  final _assetController = TextEditingController();
  final _ownerController = TextEditingController();
  final _officeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _maxSearchResultsController = TextEditingController();
  int _maxSearchResults = LampSettingsStore.defaultMaxSearchResults;
  Timer? _liveSearchDebounce;
  bool _suppressLiveSearch = false;

  bool _loading = true;
  bool _importing = false;
  String? _message;
  LampOldDbCheckResult? _readPathCheck;
  bool _lampSettingsDialogOpen = false;
  void Function(void Function())? _lampSettingsDialogSetState;
  bool _capturedLampRequestBaseline = false;
  int _lampRequestBaseline = 0;
  List<Map<String, Object?>> _results = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _issues = const <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    _attachSearchListeners();
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
    _detachSearchListeners();
    _liveSearchDebounce?.cancel();
    _excelController.dispose();
    _readDbController.dispose();
    _outputDbController.dispose();
    _globalController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _serialController.dispose();
    _assetController.dispose();
    _ownerController.dispose();
    _officeController.dispose();
    _phoneController.dispose();
    _maxSearchResultsController.dispose();
    super.dispose();
  }

  List<TextEditingController> get _fieldSearchControllers =>
      <TextEditingController>[
        _codeController,
        _descriptionController,
        _serialController,
        _assetController,
        _ownerController,
        _officeController,
        _phoneController,
      ];

  void _attachSearchListeners() {
    _globalController.addListener(_onGlobalSearchInputChanged);
    for (final c in _fieldSearchControllers) {
      c.addListener(_onFieldSearchInputChanged);
    }
  }

  void _detachSearchListeners() {
    _globalController.removeListener(_onGlobalSearchInputChanged);
    for (final c in _fieldSearchControllers) {
      c.removeListener(_onFieldSearchInputChanged);
    }
  }

  bool get _hasAnyFieldSearchInput =>
      _fieldSearchControllers.any((c) => c.text.trim().isNotEmpty);

  void _onGlobalSearchInputChanged() {
    if (_suppressLiveSearch) return;
    if (_globalController.text.trim().isNotEmpty && _hasAnyFieldSearchInput) {
      _suppressLiveSearch = true;
      for (final c in _fieldSearchControllers) {
        if (c.text.isNotEmpty) c.clear();
      }
      _suppressLiveSearch = false;
    }
    _scheduleLiveSearch();
  }

  void _onFieldSearchInputChanged() {
    if (_suppressLiveSearch) return;
    if (_hasAnyFieldSearchInput && _globalController.text.trim().isNotEmpty) {
      _suppressLiveSearch = true;
      _globalController.clear();
      _suppressLiveSearch = false;
    }
    _scheduleLiveSearch();
  }

  void _scheduleLiveSearch() {
    _liveSearchDebounce?.cancel();
    _liveSearchDebounce = Timer(const Duration(milliseconds: 320), () async {
      await _runLiveSearch();
    });
  }

  Future<void> _runLiveSearch() async {
    if (!mounted) return;
    final hasGlobal = _globalController.text.trim().isNotEmpty;
    final hasFields = _hasAnyFieldSearchInput;
    if (!hasGlobal && !hasFields) {
      setState(() {
        _results = const <Map<String, Object?>>[];
        _message = null;
      });
      return;
    }
    if (hasGlobal) {
      await _globalSearch(showProgressSnack: false);
      return;
    }
    await _fieldSearch(showProgressSnack: false);
  }

  void _clearAllSearchInputs() {
    _suppressLiveSearch = true;
    _globalController.clear();
    for (final c in _fieldSearchControllers) {
      c.clear();
    }
    _suppressLiveSearch = false;
    _liveSearchDebounce?.cancel();
    setState(() {
      _results = const <Map<String, Object?>>[];
      _message = null;
    });
  }

  Widget? _clearFieldSuffix({
    required TextEditingController controller,
    required String tooltip,
  }) {
    if (controller.text.isEmpty) return null;
    return IconButton(
      tooltip: tooltip,
      onPressed: controller.clear,
      icon: const Icon(Icons.close),
    );
  }

  void _showSnack(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : null,
        duration: duration,
      ),
    );
  }

  Future<void> _loadSettings() async {
    final excelPath = await _settings.getExcelPath();
    final readRaw = await _settings.getReadPathRaw();
    final outRaw = await _settings.getOutputPathRaw();
    if (!mounted) return;
    _excelController.text = excelPath ?? '';
    if (readRaw != null && readRaw.isNotEmpty) {
      _readDbController.text = readRaw;
    } else {
      _readDbController.text = outRaw ?? '';
    }
    _outputDbController.text = outRaw ?? '';
    _maxSearchResults = await _settings.getMaxSearchResults();
    _maxSearchResultsController.text = _maxSearchResults.toString();
    await _applyPersistedReadAndValidate(announce: true, source: 'έναρξη');
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Αποθήκευση διαβασμένου path από πεδία και πλήρης έλεγχος πρόσβασης/σχήματος.
  Future<void> _applyPersistedReadAndValidate({
    bool announce = true,
    String source = 'αλλαγή',
  }) async {
    var read = _readDbController.text.trim();
    final output = _outputDbController.text.trim();
    if (read.isEmpty && output.isNotEmpty) {
      read = output;
      _readDbController.text = output;
    }
    await _settings.setReadPath(read);
    await _settings.setOutputPath(output);
    final result = await _validator.validateReadPath(read);
    if (!mounted) return;
    setState(() => _readPathCheck = result);
    if (result.status == LampOldDbStatus.ok) {
      await _loadIssues();
      await _repository.preloadSearchCache(read);
    } else {
      setState(() => _issues = const <Map<String, Object?>>[]);
    }
    if (announce) {
      _announceCheck(result, source: source);
    }
  }

  void _announceCheck(LampOldDbCheckResult result, {required String source}) {
    final String prefix = source == 'έναρξη'
        ? 'Λάμπα: '
        : 'Έλεγχος βάσης ($source): ';
    if (result.status == LampOldDbStatus.ok) {
      // Η επιτυχία εμφανίζεται στο banner· όχι SnackBar (αποφυγή τριπλότητας).
      return;
    } else if (result.status == LampOldDbStatus.pathEmpty) {
      _showSnack(
        '$prefix${result.userMessageGreek}',
        isError: false,
        duration: const Duration(seconds: 7),
      );
    } else {
      _showSnack(
        '$prefix${result.userMessageGreek}',
        isError: true,
        duration: const Duration(seconds: 8),
      );
    }
  }

  /// Ανανέωση αναζητήσεων μετά αλλαγή read path: κλείσιμο σύνδεσης, επανεπαλήθευση, μηνύματα.
  Future<void> _refreshDataAfterReadPathChange({required String source}) async {
    await LampDatabaseProvider.instance.close();
    await _applyPersistedReadAndValidate(announce: true, source: source);
  }

  Future<void> _pickExcel() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'xls'],
    );
    final path =
        (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
    if (path == null) {
      if (mounted) {
        _showSnack('Η επιλογή αρχείου Excel ακυρώθηκε.');
      }
      return;
    }
    _excelController.text = path;
    await _settings.setExcelPath(path);
    if (mounted) {
      _lampSettingsDialogSetState?.call(() {});
      _showSnack('Ορίστηκε αρχείο Excel: ${p.basename(path)}');
    }
  }

  Future<void> _pickReadDatabase() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['db'],
    );
    final path =
        (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
    if (path == null) {
      if (mounted) {
        _showSnack('Η επιλογή αρχείου .db (ανάγνωση) ακυρώθηκε.');
      }
      return;
    }
    _readDbController.text = path;
    await _settings.setReadPath(path);
    if (!mounted) return;
    _lampSettingsDialogSetState?.call(() {});
    _showSnack('Θα γίνει έλεγχος της βάσης προς ανάγνωση…');
    await _refreshDataAfterReadPathChange(source: 'επιλογή αρχείου ανάγνωσης');
  }

  Future<void> _pickDatabaseOutput() async {
    final oldOut = _outputDbController.text.trim();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Θέση και όνομα βάσης εξόδου (.db) για import Excel',
      fileName: 'old_equipment.db',
      type: FileType.custom,
      allowedExtensions: const <String>['db'],
    );
    if (path == null) {
      if (mounted) {
        _showSnack('Η αποθήκευση/προορισμός αρχείου εξόδου ακυρώθηκε.');
      }
      return;
    }
    _outputDbController.text = path;
    await _settings.setOutputPath(path);
    final readT = _readDbController.text.trim();
    if (readT.isEmpty || (oldOut.isNotEmpty && readT == oldOut)) {
      _readDbController.text = path;
      await _settings.setReadPath(path);
      if (mounted) {
        _showSnack(
          'Η διαδρομή εξόδου ενημερώθηκε. Η «ανάγνωση» συγχρονίστηκε (ίδιο αρχείο).',
        );
        _lampSettingsDialogSetState?.call(() {});
      }
      await _refreshDataAfterReadPathChange(source: 'αλλαγή αρχείου εξόδου');
    } else {
      if (mounted) {
        _showSnack(
          'Η διαδρομή εξόδου (δημιουργίας) ενημερώθηκε. Η βάση προς «ανάγνωση» παρέμεινε ξεχωριστή.',
        );
        _lampSettingsDialogSetState?.call(() {});
      }
    }
  }

  void _matchReadToOutput() {
    _readDbController.text = _outputDbController.text;
    if (mounted) {
      _lampSettingsDialogSetState?.call(() {});
      _showSnack(
        'Η «ανάγνωση» ευθυγραμμίστηκε με τη διαδρομή εξόδου. Πατήστε αποθήκευση στο τέλος ή κάντε έλεγχο.',
      );
    }
  }

  Future<void> _runImport() async {
    final excelPath = _excelController.text.trim();
    final outPath = _outputDbController.text.trim();
    if (excelPath.isEmpty || outPath.isEmpty) {
      setState(() {
        _message = 'Χρειάζονται αρχείο Excel και αρχείο βάσης εξόδου .db (δημιουργίας).';
      });
      _lampSettingsDialogSetState?.call(() {});
      _showSnack(
        'Λείπει Excel ή/c η διαδρομή αρχείου εξόδου .db.',
        isError: true,
      );
      return;
    }

    await _settings.setExcelPath(excelPath);
    await _settings.setOutputPath(outPath);
    await LampDatabaseProvider.instance.close();
    setState(() {
      _importing = true;
      _message = null;
      _results = const <Map<String, Object?>>[];
      _issues = const <Map<String, Object?>>[];
    });
    _lampSettingsDialogSetState?.call(() {});

    try {
      _showSnack('Ξεκίνησε η εισαγωγή Excel · περιμένετε…', duration: const Duration(seconds: 3));
      final result = await _importer.importExcel(
        excelPath: excelPath,
        databasePath: outPath,
        onProgress: (_) {
          if (!mounted) return;
        },
      );
      if (!mounted) return;
      await _settings.setOutputAndReadFromImportResult(result.databasePath);
      _readDbController.text = result.databasePath;
      _outputDbController.text = result.databasePath;
      setState(() {
        _message =
            'Ολοκληρώθηκε η βάση ${p.basename(result.databasePath)}. Προβλήματα ETL: ${result.issueCount}. '
            'Η αποθηκευμένη διαδρομή «ανάγνωση» ευθυγραμμίστηκε με το .db εξόδου (ίδιο αρχείο).';
      });
      _lampSettingsDialogSetState?.call(() {});
      _showSnack(
        'Η εισαγωγή τελείωσε. Έγινε επανασύνδεση· γίνεται έλεγχος αρχείου…',
        duration: const Duration(seconds: 4),
      );
      await _applyPersistedReadAndValidate(announce: true, source: 'μετά import');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
      _lampSettingsDialogSetState?.call(() {});
      _showSnack('Η εισαγωγή απέτυχε. Δείτε το μήνυμα στο παράθυρο.', isError: true);
      final check = await _validator.validateReadPath(_readDbController.text.trim());
      if (mounted) {
        setState(() => _readPathCheck = check);
        await _loadIssues();
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
        _lampSettingsDialogSetState?.call(() {});
      }
    }
  }

  bool get _readPathReadyForQuery =>
      _readPathCheck?.status == LampOldDbStatus.ok;

  Future<void> _fieldSearch({bool showProgressSnack = true}) async {
    if (!_readPathReadyForQuery) {
      _showSnack(
        _readPathCheck?.userMessageGreek ?? 'Η βάση προς ανάγνωση δεν είναι έτοιμη. Ανοίξτε τις ρυθμίσεις (γρανάζι).',
        isError: true,
      );
      return;
    }
    await _runSearch(
      () => _repository.searchByFields(
        _readDbController.text.trim(),
        OldEquipmentSearchFilters(
          code: _codeController.text,
          description: _descriptionController.text,
          serialNo: _serialController.text,
          assetNo: _assetController.text,
          owner: _ownerController.text,
          office: _officeController.text,
          phone: _phoneController.text,
        ),
        maxDisplay: _maxSearchResults,
      ),
      showProgressSnack: showProgressSnack,
    );
  }

  Future<void> _globalSearch({bool showProgressSnack = true}) async {
    if (!_readPathReadyForQuery) {
      _showSnack(
        _readPathCheck?.userMessageGreek ?? 'Η βάση προς ανάγνωση δεν είναι έτοιμη.',
        isError: true,
      );
      return;
    }
    await _runSearch(
      () => _repository.globalSearch(
        _readDbController.text.trim(),
        _globalController.text,
        maxDisplay: _maxSearchResults,
      ),
      showProgressSnack: showProgressSnack,
    );
  }

  String _searchOutcomeMessage(int totalCount) {
    final xStr = DatabaseStatsService.formatIntegerEl(totalCount);
    final n = _maxSearchResults;
    if (totalCount > 0 && n < totalCount) {
      final nStr = DatabaseStatsService.formatIntegerEl(n);
      return 'Εμφάνιση των πρώτων $nStr αποτελεσμάτων από $xStr.';
    }
    return 'Βρέθηκαν $xStr αποτελέσματα.';
  }

  Future<void> _runSearch(
    Future<OldEquipmentSearchResult> Function() action,
    {bool showProgressSnack = true,}
  ) async {
    final pth = _readDbController.text.trim();
    if (pth.isEmpty) {
      setState(() {
        // handled by status, still clear results
        _message = 'Κενή διαδρομή βάσης προς ανάγνωση.';
      });
      return;
    }
    setState(() => _message = null);
    if (showProgressSnack) {
      _showSnack('Εκτέλεση αναζήτησης…', duration: const Duration(seconds: 2));
    }
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _results = result.rows;
        _message = _searchOutcomeMessage(result.totalCount);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
      _showSnack('Η αναζήτηση απέτυχε. Δοκιμάστε έλεγχο βάσης από το γρανάζι.', isError: true);
    }
  }

  Future<void> _loadIssues() async {
    final path = _readDbController.text.trim();
    if (path.isEmpty) return;
    if (_readPathCheck?.status != LampOldDbStatus.ok) {
      if (mounted) {
        setState(() => _issues = const <Map<String, Object?>>[]);
      }
      return;
    }
    try {
      final issues = await _repository.dataIssues(path);
      if (!mounted) return;
      setState(() => _issues = issues);
    } catch (e) {
      if (!mounted) return;
      setState(() => _issues = const <Map<String, Object?>>[]);
      _showSnack('Δεν φορτώθηκαν τα προβλήματα ETL: $e', isError: true);
    }
  }

  Future<EquipmentSectionSaveResult> _saveEquipmentSection({
    required int id,
    required InfoSectionType sectionType,
    required Map<String, Object?> updatedFields,
  }) async {
    final path = _readDbController.text.trim();
    if (path.isEmpty) {
      return const EquipmentSectionSaveResult(
        success: false,
        message: 'Δεν έχει οριστεί βάση προς ενημέρωση.',
      );
    }
    final result = await _repository.updateSection(
      databasePath: path,
      id: id,
      sectionType: sectionType.toRepositorySectionType(),
      updatedFields: updatedFields,
    );
    return EquipmentSectionSaveResult(
      success: result.success,
      message: result.message,
    );
  }

  Future<void> _closeLampSettingsDialog(
    void Function() pop,
  ) async {
    if (_importing) return;
    final parsedMax = int.tryParse(_maxSearchResultsController.text.trim());
    if (parsedMax != null) {
      await _settings.setMaxSearchResults(parsedMax);
    }
    if (mounted) {
      final max = await _settings.getMaxSearchResults();
      setState(() {
        _maxSearchResults = max;
        _maxSearchResultsController.text = max.toString();
      });
    }
    _showSnack('Αποθήκευση διαδρομών και έλεγχος βάσης…');
    await _refreshDataAfterReadPathChange(source: 'αποθήκευση ρυθμίσεων');
    if (!mounted) return;
    pop();
    Future<void>.microtask(() async {
      if (!mounted) return;
      await _runLiveSearch();
    });
  }

  void _openLampSettingsDialog() {
    if (_lampSettingsDialogOpen) return;
    _lampSettingsDialogOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _lampSettingsDialogSetState = setDialogState;
            return AlertDialog(
              title: const Text('Ρυθμίσεις Λάμπας'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ξεχωριστά: αρχείο εξόδου (import Excel) και αρχείο ανάγνωσης (αναζήτηση). '
                      'Με το πρώτο import ευθυγραμμίζονται. Μπορείτε μετά να φορτώσετε άλλο .db μόνο για ανάγνωση (δοκιμές).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    _pathRow(
                      controller: _excelController,
                      label: 'Αρχείο Excel (πηγή import)',
                      onPick: _pickExcel,
                    ),
                    const SizedBox(height: 12),
                    _pathRow(
                      controller: _outputDbController,
                      label: 'Βάση εξόδου .db (δημιουργία / ενημέρωση)',
                      onPick: _pickDatabaseOutput,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Όπου αποθηκεύεται/φτιάχνεται το .db από το κουμπί import.',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 12),
                    _pathRow(
                      controller: _readDbController,
                      label: 'Βάση .db προς ανάγνωση (αναζήτηση, ETL issues)',
                      onPick: _pickReadDatabase,
                    ),
                    const SizedBox(height: 6),
                    _lampReadPathCheckPanel(context),
                    const SizedBox(height: 4),
                    Text(
                      'Μπορεί να δείχνει και σε άλλο αντίγραφο .db (δοκιμές).',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _maxSearchResultsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'Μέγιστος αριθμός εμφανιζόμενων αποτελεσμάτων αναζήτησης (Ν)',
                        border: const OutlineInputBorder(),
                        helperText:
                            'Εύρος ${LampSettingsStore.minMaxSearchResults}–'
                            '${LampSettingsStore.maxMaxSearchResults} · προεπιλογή '
                            '${LampSettingsStore.defaultMaxSearchResults}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _importing
                            ? null
                            : () {
                                _matchReadToOutput();
                              },
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Ίδιο με τη διαδρομή εξόδου'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _importing
                            ? null
                            : () async {
                                await _applyPersistedReadAndValidate(
                                  announce: true,
                                  source: 'επαλήθευση',
                                );
                                if (!context.mounted) return;
                                _lampSettingsDialogSetState?.call(() {});
                              },
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Έλεγχος & αποθήκευση διαδρομών'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _importing ? null : _runImport,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Δημιουργία/ενημέρωση βάσης από Excel'),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_message!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _importing
                      ? null
                      : () async {
                          await _closeLampSettingsDialog(
                            () => Navigator.of(dialogContext).pop(),
                          );
                        },
                  child: const Text('Κλείσιμο'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _lampSettingsDialogOpen = false;
      _lampSettingsDialogSetState = null;
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
    final dbOk = _readPathCheck?.status == LampOldDbStatus.ok;
    final showEtlTab = dbOk && _issues.isNotEmpty;
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
              if (showEtlTab) const Tab(text: 'Προβλήματα ETL'),
              if (showTablesTab) const Tab(text: 'Πίνακες'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _searchTab(context),
                if (showEtlTab) _issuesTab(context),
                if (showTablesTab)
                  LampDbTablesTab(
                    key: ValueKey(
                      'lamp-tables-${_readDbController.text.trim()}',
                    ),
                    databasePath: _readDbController.text.trim(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Έλεγχος/κατάσταση της διαδρομής ανάγνωσης· εμφανίζεται κάτω από το αντίστοιχο
  /// [TextField] στις ρυθμίσεις (γρανάζι).
  Widget _lampReadPathCheckPanel(BuildContext context) {
    final r = _readPathCheck;
    if (r == null) {
      return Text(
        'Δεν έχει τρέξει ακόμη έλεγχος. Μετά την επικόλληση/επιλογή πατήστε «Έλεγχος & αποθήκευση διαδρομών».',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final Color? bg;
    final IconData icon;
    if (r.status == LampOldDbStatus.ok) {
      bg = scheme.primaryContainer.withValues(alpha: 0.45);
      icon = Icons.check_circle_outline;
    } else if (r.status == LampOldDbStatus.pathEmpty) {
      bg = scheme.surfaceContainerHighest;
      icon = Icons.info_outline;
    } else {
      bg = scheme.errorContainer.withValues(alpha: 0.55);
      icon = Icons.error_outline;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurface),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_readDbController.text.isNotEmpty)
                    Text(
                      p.basename(_readDbController.text),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (r.status != LampOldDbStatus.ok) ...[
                    if (_readDbController.text.isNotEmpty)
                      const SizedBox(height: 4),
                    Text(
                      r.userMessageGreek,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Καθολική αναζήτηση πάνω, αναζήτηση ανά πεδίο κάτω, κοινά αποτελέσματα.
  Widget _searchTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _globalController,
                  decoration: InputDecoration(
                    labelText: 'Αναζήτηση σαν Google',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _clearFieldSuffix(
                      controller: _globalController,
                      tooltip: 'Καθαρισμός καθολικής αναζήτησης',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _globalSearch(),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _smallField(_codeController, 'Κωδικός'),
              _smallField(_descriptionController, 'Περιγραφή'),
              _smallField(_serialController, 'Serial No'),
              _smallField(_assetController, 'Asset No'),
              _smallField(_ownerController, 'Ιδιοκτήτης'),
              _smallField(_officeController, 'Τμήμα/Γραφείο'),
              _smallField(_phoneController, 'Τηλέφωνο'),
              OutlinedButton.icon(
                onPressed: _clearAllSearchInputs,
                icon: const Icon(Icons.clear_all),
                label: const Text('Καθαρισμός όλων'),
              ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        Expanded(child: _resultsList(context)),
      ],
    );
  }

  Widget _issuesTab(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _issues.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = _issues[index];
        return ListTile(
          leading: const Icon(Icons.warning_amber),
          title: Text('${issue['issue_type'] ?? ''}'),
          subtitle: Text(
            'Φύλλο: ${issue['sheet'] ?? '-'} | Γραμμή: ${issue['row_number'] ?? '-'} | '
            'Στήλη: ${issue['column_name'] ?? '-'}\n'
            'Τιμή: ${issue['raw_value'] ?? '-'}\n'
            '${issue['message'] ?? ''}',
          ),
        );
      },
    );
  }

  Widget _pathRow({
    required TextEditingController controller,
    required String label,
    required VoidCallback onPick,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              hintText: 'Μπορείτε και επικόλληση (paste) — μετά: Έλεγχος & αποθήκευση',
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Επιλογή'),
        ),
      ],
    );
  }

  Widget _smallField(TextEditingController controller, String label) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _clearFieldSuffix(
            controller: controller,
            tooltip: 'Καθαρισμός πεδίου',
          ),
        ),
        onSubmitted: (_) => _fieldSearch(),
      ),
    );
  }

  Widget _resultsList(BuildContext context) {
    if (_results.isEmpty) {
      return const Center(
        child: Text('Δεν υπάρχουν αποτελέσματα. Εκτελέστε αναζήτηση με έγκυρη βάση.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) => EquipmentResultCard(
        viewModel: EquipmentViewModel.fromRow(_results[index]),
        onSaveSection: _saveEquipmentSection,
      ),
    );
  }
}

extension on InfoSectionType {
  OldEquipmentSectionType toRepositorySectionType() {
    return switch (this) {
      InfoSectionType.equipment => OldEquipmentSectionType.equipment,
      InfoSectionType.model => OldEquipmentSectionType.model,
      InfoSectionType.contract => OldEquipmentSectionType.contract,
      InfoSectionType.owner => OldEquipmentSectionType.owner,
      InfoSectionType.department => OldEquipmentSectionType.department,
    };
  }
}