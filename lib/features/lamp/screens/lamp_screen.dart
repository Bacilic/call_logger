import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers/lamp_open_settings_intent_provider.dart';
import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../../database/services/database_stats_service.dart';
import '../widgets/lamp_db_tables_tab.dart';
import '../widgets/lamp_issue_manual_review_dialog.dart';
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
  final _issueResolutionService = LampIssueResolutionService();

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
  bool _integrityChecking = false;
  LampIssueType? _resolvingIssueType;
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
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
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
    final path = (result != null && result.files.isNotEmpty)
        ? result.files.first.path
        : null;
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
    final path = (result != null && result.files.isNotEmpty)
        ? result.files.first.path
        : null;
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
        _message =
            'Χρειάζονται αρχείο Excel και αρχείο βάσης εξόδου .db (δημιουργίας).';
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
      _showSnack(
        'Ξεκίνησε η εισαγωγή Excel · περιμένετε…',
        duration: const Duration(seconds: 3),
      );
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
      await _applyPersistedReadAndValidate(
        announce: true,
        source: 'μετά import',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
      _lampSettingsDialogSetState?.call(() {});
      _showSnack(
        'Η εισαγωγή απέτυχε. Δείτε το μήνυμα στο παράθυρο.',
        isError: true,
      );
      final check = await _validator.validateReadPath(
        _readDbController.text.trim(),
      );
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
        _readPathCheck?.userMessageGreek ??
            'Η βάση προς ανάγνωση δεν είναι έτοιμη. Ανοίξτε τις ρυθμίσεις (γρανάζι).',
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
        _readPathCheck?.userMessageGreek ??
            'Η βάση προς ανάγνωση δεν είναι έτοιμη.',
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
    Future<OldEquipmentSearchResult> Function() action, {
    bool showProgressSnack = true,
  }) async {
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
      _showSnack(
        'Η αναζήτηση απέτυχε. Δοκιμάστε έλεγχο βάσης από το γρανάζι.',
        isError: true,
      );
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

  String _issueTypeLabel(Map<String, Object?> issue) {
    final raw = issue['issue_type']?.toString().trim();
    if (raw == null || raw.isEmpty) return 'Χωρίς κατηγορία';
    return raw;
  }

  String _issueField(Map<String, Object?> issue, String key) {
    final raw = issue[key];
    if (raw == null) return '-';
    final text = raw.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  Map<String, List<Map<String, Object?>>> _groupedIssuesByType() {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final issue in _issues) {
      final type = _issueTypeLabel(issue);
      grouped.putIfAbsent(type, () => <Map<String, Object?>>[]).add(issue);
    }
    return grouped;
  }

  int _issueCountFor(LampIssueType issueType) {
    return _issues
        .where(
          (issue) => issue['issue_type']?.toString() == issueType.issueType,
        )
        .length;
  }

  bool _canResolveIssueType(LampIssueType issueType) =>
      _readPathReadyForQuery &&
      _resolvingIssueType == null &&
      _issueCountFor(issueType) > 0;

  Future<void> _runIssueResolution(LampIssueType issueType) async {
    if (_resolvingIssueType != null) return;
    final path = _readDbController.text.trim();
    if (!_readPathReadyForQuery || path.isEmpty) {
      _showSnack('Η βάση προς ανάγνωση δεν είναι έτοιμη.', isError: true);
      return;
    }

    setState(() => _resolvingIssueType = issueType);
    try {
      _showSnack('Ανάλυση προτάσεων: ${issueType.label}…');
      final proposals = await _issueResolutionService.analyzeIssues(
        databasePath: path,
        issueType: issueType,
      );
      if (!mounted) return;
      if (proposals.isEmpty) {
        _showSnack(
          'Δεν υπάρχουν ανοικτές προτάσεις για ${issueType.issueType}.',
        );
        return;
      }

      final proceed = await _askResolutionPreview(issueType, proposals);
      if (proceed != true || !mounted) return;

      final autoDecisions = <LampIssueResolutionDecision>[
        for (final proposal in proposals)
          if (proposal.canApplyAutomatically)
            LampIssueResolutionDecision(proposal: proposal),
      ];
      final manualProposals = proposals
          .where(
            (proposal) =>
                proposal.proposedAction ==
                LampIssueResolutionAction.manualReview,
          )
          .toList(growable: false);

      final manualDecisions = manualProposals.isEmpty
          ? const <LampIssueResolutionDecision>[]
          : await showLampIssueManualReviewDialog(
              context: context,
              issueType: issueType,
              proposals: manualProposals,
            );
      if (manualDecisions == null || !mounted) return;

      final decisions = <LampIssueResolutionDecision>[
        ...autoDecisions,
        ...manualDecisions,
      ];
      if (decisions.isEmpty) {
        _showSnack('Δεν επιλέχθηκε καμία ενέργεια για εφαρμογή.');
        return;
      }
      if (_containsDestructiveResolution(decisions)) {
        final destructiveOk = await _askDestructiveResolutionConfirmation();
        if (destructiveOk != true || !mounted) return;
      }

      final apply = await _issueResolutionService.applyDecisions(
        databasePath: path,
        decisions: decisions,
      );
      await _loadIssues();
      if (!mounted) return;
      final errorSuffix = apply.errors.isEmpty
          ? ''
          : ' · Σφάλματα: ${apply.errors.length}';
      _showSnack(
        'Επίλυση ${issueType.issueType}: εφαρμόστηκαν ${apply.totalChanged} ενέργειες '
        '(auto: ${apply.resolved}, manual: ${apply.manualApplied}, νέες: ${apply.created})$errorSuffix.',
        isError: apply.errors.isNotEmpty,
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Η επίλυση απέτυχε: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _resolvingIssueType = null);
      }
    }
  }

  bool _containsDestructiveResolution(
    List<LampIssueResolutionDecision> decisions,
  ) {
    for (final decision in decisions) {
      final operation = decision.option?.metadata['operation']?.toString();
      if (operation != null && operation.startsWith('delete_duplicate')) {
        return true;
      }
    }
    return false;
  }

  Future<bool?> _askDestructiveResolutionConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Επιβεβαίωση διαγραφής διπλοεγγραφών'),
        content: const Text(
          'Έχετε επιλέξει ενέργεια που διαγράφει δευτερεύουσες εγγραφές equipment. '
          'Πριν τη διαγραφή θα μεταφερθούν τυχόν παιδιά set_master στην κύρια εγγραφή, '
          'αλλά η ενέργεια δεν έχει άμεση αναίρεση από την εφαρμογή. Θέλετε να συνεχίσετε;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Συνέχεια με διαγραφή'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _askResolutionPreview(
    LampIssueType issueType,
    List<LampIssueResolutionProposal> proposals,
  ) {
    final autoCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.autoFix)
        .length;
    final createCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.createNew)
        .length;
    final manualCount = proposals
        .where(
          (p) => p.proposedAction == LampIssueResolutionAction.manualReview,
        )
        .length;
    final unresolvedCount = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.unresolved)
        .length;
    final preview = proposals
        .take(8)
        .map(
          (p) =>
              '- row=${p.row ?? '-'} column=${p.column ?? '-'} · '
              '${p.proposedAction.jsonValue} · ${p.proposedMatch ?? p.notes}',
        )
        .join('\n');
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(issueType.label),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            child: SelectableText(
              'Βρέθηκαν ${proposals.length} προτάσεις.\n\n'
              '- auto_fix: $autoCount\n'
              '- create_new: $createCount\n'
              '- manual_review: $manualCount\n'
              '- unresolved: $unresolvedCount\n\n'
              'Δείγμα:\n$preview'
              '${proposals.length > 8 ? '\n...και ${proposals.length - 8} ακόμα.' : ''}\n\n'
              'Οι αυτόματες και create_new ενέργειες θα εφαρμοστούν μόνο μετά από αυτή την επιβεβαίωση. '
              'Οι manual_review περιπτώσεις θα ανοίξουν σε επόμενο παράθυρο επιλογών.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }

  String _buildIssuesClipboardText() {
    final grouped = _groupedIssuesByType();
    final lines = <String>[
      '# LAMP ETL Issues',
      'Σύνολο προβλημάτων: ${_issues.length}',
      '',
      'Οδηγία προς Πράκτορα ΤΝ: Ανάλυσε τα προβλήματα ανά κατηγορία, πρότεινε αιτίες, '
          'βήματα επιδιόρθωσης και προτεραιότητες.',
      '',
    ];
    for (final entry in grouped.entries) {
      lines.add('## ${entry.key} (${entry.value.length})');
      for (final issue in entry.value) {
        lines.add(
          '- Sheet: ${_issueField(issue, 'sheet')} | Row: ${_issueField(issue, 'row_number')} | '
          'Column: ${_issueField(issue, 'column_name')}',
        );
        lines.add('  Value: ${_issueField(issue, 'raw_value')}');
        lines.add('  Message: ${_issueField(issue, 'message')}');
      }
      lines.add('');
    }
    return lines.join('\n');
  }

  Future<void> _copyAllIssuesToClipboard() async {
    if (_issues.isEmpty) {
      _showSnack('Δεν υπάρχουν προβλήματα για αντιγραφή.');
      return;
    }
    final payload = _buildIssuesClipboardText();
    await Clipboard.setData(ClipboardData(text: payload));
    _showSnack('Αντιγράφηκαν ${_issues.length} προβλήματα στο πρόχειρο.');
  }

  Future<void> _runIntegrityCheck() async {
    if (_integrityChecking) return;
    final path = _readDbController.text.trim();
    if (path.isEmpty) {
      _showSnack('Δεν έχει οριστεί βάση για έλεγχο.', isError: true);
      return;
    }
    final cancellationToken = OldIntegrityCancellationToken();
    final progressNotifier = ValueNotifier<OldIntegrityScanProgress?>(null);
    setState(() => _integrityChecking = true);
    Future<void>? progressDialog;
    var progressDialogOpen = false;

    Future<void> closeProgressDialog() async {
      if (!progressDialogOpen || !mounted) return;
      progressDialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
      await progressDialog;
    }

    try {
      final historicalDurationsMs = await _settings
          .getIntegrityStepDurationsMs();
      if (!mounted) return;
      final historicalDurations = <String, Duration>{
        for (final entry in historicalDurationsMs.entries)
          entry.key: Duration(milliseconds: entry.value),
      };
      progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _IntegrityProgressDialog(
          progressListenable: progressNotifier,
          onCancel: cancellationToken.cancel,
        ),
      );
      progressDialogOpen = true;
      final scan = await _repository.scanIntegrityIssues(
        path,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
        onStepError: _askIntegrityStepErrorDecision,
        historicalStepDurations: historicalDurations,
      );
      if (!mounted) return;
      await closeProgressDialog();
      await _saveIntegrityStepDurations(scan);
      final persist = await _askPersistIntegrityIssues(scan);
      if (persist != true) {
        final suffix = scan.isPartial ? ' (μερική αναφορά)' : '';
        _showSnack(
          'Ο έλεγχος ολοκληρώθηκε χωρίς καταχώρηση στο data_issues$suffix.',
        );
        return;
      }
      final inserted = await _repository.insertDataIssues(path, scan.issues);
      await _loadIssues();
      if (!mounted) return;
      final suffix = scan.isPartial ? ' από μερικό έλεγχο' : '';
      _showSnack(
        'Καταχωρήθηκαν $inserted νέα προβλήματα$suffix στο data_issues.',
      );
    } catch (e) {
      if (!mounted) return;
      await closeProgressDialog();
      _showSnack('Ο έλεγχος ακεραιότητας απέτυχε: $e', isError: true);
    } finally {
      progressNotifier.dispose();
      if (mounted) {
        setState(() => _integrityChecking = false);
      }
    }
  }

  Future<OldIntegrityStepErrorDecision> _askIntegrityStepErrorDecision(
    OldIntegrityScanStepState step,
    Object error,
    List<Map<String, Object?>> partialIssues,
  ) async {
    if (!mounted) return OldIntegrityStepErrorDecision.stopWithPartialReport;
    final decision = await showDialog<OldIntegrityStepErrorDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Σφάλμα σε βήμα ελέγχου'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SelectableText(
            'Το βήμα «${step.label}» απέτυχε.\n\n'
            'Σφάλμα: $error\n\n'
            'Έχουν συλλεχθεί ${partialIssues.length} ευρήματα μέχρι τώρα. '
            'Μπορείτε να συνεχίσετε με τα επόμενα βήματα ή να δείτε μερική αναφορά.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(OldIntegrityStepErrorDecision.stopWithPartialReport),
            child: const Text('Προβολή αναφοράς'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(OldIntegrityStepErrorDecision.continueScan),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    return decision ?? OldIntegrityStepErrorDecision.stopWithPartialReport;
  }

  Future<void> _saveIntegrityStepDurations(OldIntegrityScanResult scan) async {
    final completedDurations = <String, int>{
      for (final step in scan.steps)
        if (step.status == OldIntegrityStepStatus.success &&
            step.elapsed.inMilliseconds > 0)
          step.id: step.elapsed.inMilliseconds,
    };
    await _settings.updateIntegrityStepDurationsMs(completedDurations);
  }

  Future<bool?> _askPersistIntegrityIssues(OldIntegrityScanResult scan) {
    final breakdown = scan.countByType.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    final stepReport = scan.steps.isEmpty
        ? ''
        : '\n\nΒήματα:\n${scan.steps.map(_integrityStepReportLine).join('\n')}';
    final partialPrefix = scan.cancelled
        ? 'Ο έλεγχος ακυρώθηκε από τον χρήστη. Εμφανίζονται ευρήματα από ${scan.completedSteps} από ${scan.totalSteps} βήματα.\n\n'
        : scan.stoppedAfterError
        ? 'Ο έλεγχος σταμάτησε μετά από σφάλμα. Εμφανίζονται τα ευρήματα που συλλέχθηκαν μέχρι εκείνο το σημείο.\n\n'
        : '';
    final reportText = scan.totalCount == 0
        ? '$partialPrefixΔεν εντοπίστηκαν προβληματικές εγγραφές με βάση τους κανόνες.'
        : '$partialPrefixΕντοπίστηκαν ${scan.totalCount} προβλήματα σε ${scan.countByType.length} κατηγορίες.\n\n$breakdown';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Αναφορά ελέγχου προβλημάτων'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SelectableText('$reportText$stepReport'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Μόνο αναφορά'),
          ),
          FilledButton(
            onPressed: scan.issues.isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Καταχώρηση στο data_issues'),
          ),
        ],
      ),
    );
  }

  String _integrityStepReportLine(OldIntegrityScanStepState step) {
    final status = switch (step.status) {
      OldIntegrityStepStatus.pending => 'Σε αναμονή',
      OldIntegrityStepStatus.running => 'Σε εξέλιξη',
      OldIntegrityStepStatus.success =>
        'Ολοκληρώθηκε (${step.issuesFound} ευρήματα)',
      OldIntegrityStepStatus.error =>
        'Σφάλμα (${step.errorMessage ?? 'άγνωστο σφάλμα'})',
      OldIntegrityStepStatus.cancelled => 'Ακυρώθηκε',
    };
    return '- ${step.index}/${step.total}: ${step.label} - $status';
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
    final effectiveFields = Map<String, Object?>.from(updatedFields);
    if (sectionType == InfoSectionType.owner &&
        effectiveFields.containsKey('owner_office')) {
      final ok = await _resolveOwnerOfficeChange(
        ownerId: id,
        newOffice: _toInt(effectiveFields['owner_office']),
        updatedFields: effectiveFields,
      );
      if (!ok) {
        return const EquipmentSectionSaveResult(
          success: false,
          message: 'Η αλλαγή γραφείου ακυρώθηκε.',
        );
      }
    }
    final result = await _repository.updateSection(
      databasePath: path,
      id: id,
      sectionType: sectionType.toRepositorySectionType(),
      updatedFields: effectiveFields,
    );
    if (result.success) {
      Future<void>.microtask(_runLiveSearch);
    }
    return EquipmentSectionSaveResult(
      success: result.success,
      message: result.message,
    );
  }

  Future<bool> _resolveOwnerOfficeChange({
    required int ownerId,
    required int? newOffice,
    required Map<String, Object?> updatedFields,
  }) async {
    final path = _readDbController.text.trim();
    final preview = await _repository.previewOwnerOfficeChange(
      databasePath: path,
      ownerId: ownerId,
      newOffice: newOffice,
    );
    if (!mounted) return false;

    if (!updatedFields.containsKey('owner_phones')) {
      final phoneChoice = await _askOwnerPhonePolicy(preview.newOfficePhones);
      if (phoneChoice == null) return false;
      updatedFields['owner_phones'] = phoneChoice;
    }

    if (preview.affectedEquipment.isEmpty) return true;
    final action = await _askOwnerOfficeEquipmentAction(
      preview.affectedEquipment,
    );
    if (action == null) return false;
    updatedFields[oldOwnerOfficeActionField] = action;
    return true;
  }

  Future<String?> _askOwnerPhonePolicy(String? newOfficePhones) async {
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Τηλέφωνο ιδιοκτήτη'),
        content: Text(
          newOfficePhones == null
              ? 'Το τηλέφωνο του ιδιοκτήτη θα μηδενιστεί μετά την αλλαγή γραφείου.'
              : 'Το τηλέφωνο του ιδιοκτήτη θα μηδενιστεί. Θέλετε να αντιγραφεί το τηλέφωνο του νέου γραφείου ($newOfficePhones);',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Μηδενισμός'),
          ),
          if (newOfficePhones != null)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(newOfficePhones),
              child: const Text('Αντιγραφή'),
            ),
        ],
      ),
    );
  }

  Future<String?> _askOwnerOfficeEquipmentAction(
    List<Map<String, Object?>> affectedEquipment,
  ) async {
    final count = affectedEquipment.length;
    final preview = affectedEquipment
        .take(8)
        .map((row) {
          final code = row['code']?.toString() ?? '—';
          final description = row['description']?.toString().trim();
          return description == null || description.isEmpty
              ? code
              : '$code · $description';
        })
        .join('\n');
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Εξοπλισμός κατόχου'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Η αλλαγή γραφείου επηρεάζει $count ${count == 1 ? 'τεμάχιο' : 'τεμάχια'} εξοπλισμού.',
              ),
              const SizedBox(height: 12),
              SelectableText(preview),
              if (affectedEquipment.length > 8)
                Text('...και ${affectedEquipment.length - 8} ακόμα.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(oldOwnerOfficeActionDetachEquipment),
            child: const Text('Αποσύνδεση κατόχου'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(oldOwnerOfficeActionTransferEquipment),
            child: const Text('Μεταφορά εξοπλισμού'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeLampSettingsDialog(void Function() pop) async {
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
                        label: const Text(
                          'Δημιουργία/ενημέρωση βάσης από Excel',
                        ),
                      ),
                    ),
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
    final grouped = _groupedIssuesByType();
    final groups = grouped.entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Σύνολο προβλημάτων: ${_issues.length} • Κατηγορίες: ${groups.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              FilledButton.tonalIcon(
                onPressed: _copyAllIssuesToClipboard,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Αντιγραφή όλων για ΤΝ'),
              ),
              FilledButton.icon(
                onPressed: _integrityChecking ? null : _runIntegrityCheck,
                icon: _integrityChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.rule_folder_outlined),
                label: const Text('Έλεγχος για προβλήματα'),
              ),
              _resolveIssueButton(
                LampIssueType.nonNumericFk,
                Icons.link_outlined,
              ),
              _resolveIssueButton(LampIssueType.unknownId, Icons.tag_outlined),
              _resolveIssueButton(
                LampIssueType.duplicateAssetNo,
                Icons.badge_outlined,
              ),
              _resolveIssueButton(
                LampIssueType.duplicateModelSerial,
                Icons.memory_outlined,
              ),
              _resolveIssueButton(
                LampIssueType.ownerOfficeMismatch,
                Icons.person_pin_circle_outlined,
              ),
              _resolveIssueButton(
                LampIssueType.setMasterSelfReference,
                Icons.link_off_outlined,
              ),
              _resolveIssueButton(
                LampIssueType.setMasterCycle,
                Icons.account_tree_outlined,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final group = groups[index];
              final type = group.key;
              final issues = group.value;
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: Text(type),
                      trailing: Text(
                        '${issues.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Divider(height: 1),
                    ...List<Widget>.generate(issues.length, (issueIndex) {
                      final issue = issues[issueIndex];
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.warning_amber),
                            title: Text(
                              'Φύλλο: ${_issueField(issue, 'sheet')} | '
                              'Γραμμή: ${_issueField(issue, 'row_number')}',
                            ),
                            subtitle: Text(
                              'Στήλη: ${_issueField(issue, 'column_name')}\n'
                              'Τιμή: ${_issueField(issue, 'raw_value')}\n'
                              '${_issueField(issue, 'message')}',
                            ),
                          ),
                          if (issueIndex < issues.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resolveIssueButton(LampIssueType issueType, IconData icon) {
    final count = _issueCountFor(issueType);
    final resolving = _resolvingIssueType == issueType;
    return OutlinedButton.icon(
      onPressed: _canResolveIssueType(issueType)
          ? () => _runIssueResolution(issueType)
          : null,
      icon: resolving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text('${issueType.label} ($count)'),
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
              hintText:
                  'Μπορείτε και επικόλληση (paste) — μετά: Έλεγχος & αποθήκευση',
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
        child: Text(
          'Δεν υπάρχουν αποτελέσματα. Εκτελέστε αναζήτηση με έγκυρη βάση.',
        ),
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

class _IntegrityProgressDialog extends StatefulWidget {
  const _IntegrityProgressDialog({
    required this.progressListenable,
    required this.onCancel,
  });

  final ValueListenable<OldIntegrityScanProgress?> progressListenable;
  final VoidCallback onCancel;

  @override
  State<_IntegrityProgressDialog> createState() =>
      _IntegrityProgressDialogState();
}

class _IntegrityProgressDialogState extends State<_IntegrityProgressDialog> {
  bool _cancelRequested = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Έλεγχος ακεραιότητας'),
      content: SizedBox(
        width: 640,
        child: ValueListenableBuilder<OldIntegrityScanProgress?>(
          valueListenable: widget.progressListenable,
          builder: (context, progress, _) {
            if (progress == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Προετοιμασία ελέγχου...'),
                  ],
                ),
              );
            }
            OldIntegrityScanStepState? current;
            for (final step in progress.steps) {
              if (step.status == OldIntegrityStepStatus.running) {
                current = step;
                break;
              }
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: progress.fraction),
                const SizedBox(height: 12),
                Text(
                  current == null
                      ? 'Ολοκληρωμένα βήματα: ${progress.completedSteps}/${progress.steps.length}'
                      : current.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Ευρήματα: ${progress.totalIssuesFound}'),
                    Text(
                      'Χρόνος: ${_formatIntegrityDuration(progress.elapsed)}',
                    ),
                    Text(
                      progress.estimatedRemaining == null
                          ? 'Υπόλοιπο: υπολογίζεται...'
                          : 'Υπόλοιπο: ~${_formatIntegrityDuration(progress.estimatedRemaining!)}',
                    ),
                  ],
                ),
                if (_cancelRequested || progress.cancelRequested) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ζητήθηκε ακύρωση. Ο έλεγχος θα σταματήσει στο πρώτο ασφαλές σημείο.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: progress.steps.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final step = progress.steps[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          _integrityStepIcon(step.status),
                          color: _integrityStepColor(context, step.status),
                        ),
                        title: Text(step.label),
                        subtitle: Text(_integrityStepSubtitle(step)),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _cancelRequested
              ? null
              : () {
                  setState(() => _cancelRequested = true);
                  widget.onCancel();
                },
          icon: const Icon(Icons.cancel_outlined),
          label: Text(_cancelRequested ? 'Ακύρωση ζητήθηκε' : 'Ακύρωση'),
        ),
      ],
    );
  }

  IconData _integrityStepIcon(OldIntegrityStepStatus status) {
    return switch (status) {
      OldIntegrityStepStatus.pending => Icons.schedule,
      OldIntegrityStepStatus.running => Icons.hourglass_top,
      OldIntegrityStepStatus.success => Icons.check_circle_outline,
      OldIntegrityStepStatus.error => Icons.error_outline,
      OldIntegrityStepStatus.cancelled => Icons.block,
    };
  }

  Color? _integrityStepColor(
    BuildContext context,
    OldIntegrityStepStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      OldIntegrityStepStatus.pending => scheme.outline,
      OldIntegrityStepStatus.running => scheme.primary,
      OldIntegrityStepStatus.success => Colors.green,
      OldIntegrityStepStatus.error => scheme.error,
      OldIntegrityStepStatus.cancelled => scheme.outline,
    };
  }

  String _integrityStepSubtitle(OldIntegrityScanStepState step) {
    return switch (step.status) {
      OldIntegrityStepStatus.pending => 'Σε αναμονή',
      OldIntegrityStepStatus.running => 'Σε εξέλιξη...',
      OldIntegrityStepStatus.success =>
        'Ολοκληρώθηκε (${step.issuesFound} ευρήματα, ${_formatIntegrityDuration(step.elapsed)})',
      OldIntegrityStepStatus.error =>
        'Σφάλμα: ${step.errorMessage ?? 'άγνωστο σφάλμα'}',
      OldIntegrityStepStatus.cancelled => 'Ακυρώθηκε',
    };
  }
}

String _formatIntegrityDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) return '${totalSeconds}s';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

int? _toInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
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
