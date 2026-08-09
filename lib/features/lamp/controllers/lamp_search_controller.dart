// Αναζήτηση εξοπλισμού: debounce, φίλτρα πεδίων, αποτελέσματα.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_search_filter_selection.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/lamp_unlinked_entities.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../widgets/lamp_result_card.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';
import 'lamp_search_outcome_message.dart';
import 'lamp_search_query_parser.dart';

class LampSearchController {
  LampSearchController({required this.host, required this.path});

  final LampScreenHost host;
  final LampPathController path;

  static const double searchFieldWidth = 180;
  static const double searchFieldSpacing = 12;
  static const int searchFieldCount = 5;

  final globalController = TextEditingController();
  final codeController = TextEditingController();
  final serialController = TextEditingController();
  final ownerController = TextEditingController();
  final officeController = TextEditingController();
  final phoneController = TextEditingController();
  final maxSearchResultsController = TextEditingController();

  Timer? liveSearchDebounce;
  bool suppressLiveSearch = false;

  final Map<String, String?> _mirroredFieldValues = <String, String?>{
    'phone': null,
    'code': null,
    'owner': null,
    'office': null,
    'serial': null,
  };

  int maxSearchResults = LampSettingsStore.defaultMaxSearchResults;
  List<Map<String, Object?>> results = const <Map<String, Object?>>[];
  List<EquipmentViewModel> resultViewModels = const <EquipmentViewModel>[];

  /// Ταιριάσματα χωρίς συνδεδεμένο εξοπλισμό — δική τους ενότητα κάτω από τις
  /// κάρτες εξοπλισμού, ώστε να μη χάνονται μέσα σε εκατοντάδες αποτελέσματα.
  List<LampUnlinkedEntity> unlinkedResults = const <LampUnlinkedEntity>[];

  /// Συνολικό πλήθος ασύνδετων ταιριασμάτων (πριν το όριο εμφάνισης).
  int unlinkedTotalCount = 0;

  /// Πλήθη ανά είδος από την τελευταία αναζήτηση — για το μενού φίλτρων.
  Map<LampUnlinkedEntityKind, int> unlinkedCountsByKind =
      const <LampUnlinkedEntityKind, int>{};

  /// Η επιλογή του μενού «Φίλτρα».
  ///
  /// Δεν κόβει αποτελέσματα — ορίζει τι ψάχνουμε, γι' αυτό και λειτουργεί
  /// ακόμη και με εντελώς κενή αναζήτηση.
  LampSearchFilterSelection filterSelection = LampSearchFilterSelection.none;

  bool get unlinkedFilterActive => filterSelection.isActive;

  /// Πόσες από τις ταιριασμένες ασύνδετες είναι «κενές εγγραφές».
  int unlinkedEmptyCount = 0;

  /// Συνολικά πλήθη ανά είδος (χωρίς κριτήρια) — φορτώνονται μία φορά για το
  /// μενού, όταν δεν έχει τρέξει ακόμη αναζήτηση. Δεμένα με τη διαδρομή της
  /// βάσης: σε αλλαγή βάσης δεν ισχύουν και ξαναφορτώνονται.
  LampFilterMenuCounts? _totalUnlinkedCounts;
  String? _totalUnlinkedCountsPath;

  /// Τα κενά εξοπλισμού δεν εξαρτώνται από την αναζήτηση — μένουν σταθερά
  /// μέσα στην ίδια βάση, οπότε κρατιούνται και όταν τα υπόλοιπα φρεσκάρουν.
  Map<LampEquipmentGapKind, int>? _equipmentGapTotals;

  /// True όταν τα [unlinkedCountsByKind] προέρχονται από πραγματική αναζήτηση.
  bool _hasFreshCounts = false;
  String? message;

  /// Υπάρχει οτιδήποτε να δείξουμε — εξοπλισμός ή ασύνδετη οντότητα;
  bool get hasAnyResult => results.isNotEmpty || unlinkedResults.isNotEmpty;

  static List<EquipmentViewModel> buildResultViewModels(
    List<Map<String, Object?>> rows,
  ) {
    return rows.map(EquipmentViewModel.fromRow).toList(growable: false);
  }

  void _assignResults(
    List<Map<String, Object?>> rows, {
    List<LampUnlinkedEntity> unlinked = const <LampUnlinkedEntity>[],
    int unlinkedTotal = 0,
    Map<LampUnlinkedEntityKind, int> countsByKind =
        const <LampUnlinkedEntityKind, int>{},
    int emptyCount = 0,
    bool freshCounts = false,
  }) {
    results = rows;
    resultViewModels = buildResultViewModels(rows);
    unlinkedResults = unlinked;
    unlinkedTotalCount = unlinkedTotal;
    unlinkedCountsByKind = countsByKind;
    unlinkedEmptyCount = emptyCount;
    _hasFreshCounts = freshCounts;
  }

  void clearResults() {
    _assignResults(_emptyResults);
  }

  static const List<Map<String, Object?>> _emptyResults =
      <Map<String, Object?>>[];

  List<TextEditingController> get fieldSearchControllers =>
      <TextEditingController>[
        phoneController,
        codeController,
        ownerController,
        officeController,
        serialController,
      ];

  bool get readPathReadyForQuery =>
      host.readPathCheck?.status == LampOldDbStatus.ok;

  void attachListeners() {
    globalController.addListener(onGlobalSearchInputChanged);
    for (final c in fieldSearchControllers) {
      c.addListener(onFieldSearchInputChanged);
    }
  }

  void detachListeners() {
    globalController.removeListener(onGlobalSearchInputChanged);
    for (final c in fieldSearchControllers) {
      c.removeListener(onFieldSearchInputChanged);
    }
  }

  void dispose() {
    liveSearchDebounce?.cancel();
    globalController.dispose();
    codeController.dispose();
    serialController.dispose();
    ownerController.dispose();
    officeController.dispose();
    phoneController.dispose();
    maxSearchResultsController.dispose();
  }

  static double searchFieldsBlockWidth(double maxWidth) {
    if (maxWidth <= 0) return searchFieldWidth;
    var rowWidth = 0.0;
    var maxRowWidth = 0.0;
    for (var i = 0; i < searchFieldCount; i++) {
      if (rowWidth == 0) {
        rowWidth = searchFieldWidth;
      } else if (rowWidth + searchFieldSpacing + searchFieldWidth > maxWidth) {
        if (rowWidth > maxRowWidth) maxRowWidth = rowWidth;
        rowWidth = searchFieldWidth;
      } else {
        rowWidth += searchFieldSpacing + searchFieldWidth;
      }
    }
    if (rowWidth > maxRowWidth) maxRowWidth = rowWidth;
    return maxRowWidth;
  }

  bool get hasAnyFieldSearchInput =>
      fieldSearchControllers.any((c) => c.text.trim().isNotEmpty);

  bool get hasAnySearchInput =>
      globalController.text.trim().isNotEmpty ||
      hasAnyFieldSearchInput ||
      unlinkedFilterActive;

  List<String> get activeFieldSearchTerms => fieldSearchControllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  String emptyResultsCenterMessage() {
    if (!readPathReadyForQuery) {
      final detail = host.readPathCheck?.userMessageGreek.trim();
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
      return 'Υπάρχει πρόβλημα με τη βάση δεδομένων της Λάμπας';
    }
    if (!hasAnySearchInput) {
      return 'Ξεκινήστε την αναζήτηση: είτε καθολικά είτε σε συγκεκριμένο πεδίο';
    }
    final globalTerm = globalController.text.trim();
    // Σκέτο φίλτρο, χωρίς κείμενο: το γενικό «η αναζήτηση του "..."» δεν έχει
    // όρο να δείξει — το κενό εδώ σημαίνει «κανένα τέτοιο είδος δεν ταίριαξε».
    if (unlinkedFilterActive && globalTerm.isEmpty && !hasAnyFieldSearchInput) {
      return 'Καμία οντότητα χωρίς εξοπλισμό δεν ταιριάζει στο ενεργό φίλτρο';
    }
    if (globalTerm.isNotEmpty) {
      return 'Η αναζήτηση του «$globalTerm» δεν αντιστοιχεί σε καμία εγγραφή στη βάση της Λάμπας';
    }
    final terms = activeFieldSearchTerms;
    if (terms.length == 1) {
      return 'Η αναζήτηση του «${terms.first}» δεν αντιστοιχεί σε καμία εγγραφή στη βάση της Λάμπας';
    }
    final combined = terms.map((t) => '«$t»').join(' + ');
    return 'Η αναζήτηση του $combined δεν αντιστοιχεί σε καμία εγγραφή στη βάση της Λάμπας';
  }

  void onGlobalSearchInputChanged() {
    if (suppressLiveSearch) return;
    final parsed = LampSearchQueryParser.parse(globalController.text);
    if (parsed.hasScopedTerms) {
      applyMirrorFromParsed(parsed);
    } else if (globalController.text.trim().isNotEmpty &&
        hasAnyFieldSearchInput) {
      suppressLiveSearch = true;
      for (final c in fieldSearchControllers) {
        if (c.text.isNotEmpty) c.clear();
      }
      _mirroredFieldValues.updateAll((_, _) => null);
      suppressLiveSearch = false;
    } else {
      clearMirroredFieldsIfNeeded(parsed);
    }
    scheduleLiveSearch();
  }

  void onFieldSearchInputChanged() {
    if (suppressLiveSearch) return;
    final parsed = LampSearchQueryParser.parse(globalController.text);
    if (hasAnyFieldSearchInput &&
        globalController.text.trim().isNotEmpty &&
        !parsed.hasScopedTerms) {
      suppressLiveSearch = true;
      globalController.clear();
      _mirroredFieldValues.updateAll((_, _) => null);
      suppressLiveSearch = false;
    }
    scheduleLiveSearch();
  }

  TextEditingController? controllerForMirrorFieldId(String fieldId) {
    switch (fieldId) {
      case 'phone':
        return phoneController;
      case 'code':
        return codeController;
      case 'owner':
        return ownerController;
      case 'office':
        return officeController;
      case 'serial':
        return serialController;
      default:
        return null;
    }
  }

  void applyMirrorFromParsed(LampSearchParseResult parsed) {
    suppressLiveSearch = true;
    try {
      final activeMirrorFields = <String>{};
      for (final term in parsed.scopedTerms) {
        final fieldId = LampSearchQueryParser.mirrorFieldIdForNormalizedKey(
          term.normalizedKey,
        );
        if (fieldId == null) continue;
        final controller = controllerForMirrorFieldId(fieldId);
        if (controller == null) continue;
        activeMirrorFields.add(fieldId);
        final mirrored = _mirroredFieldValues[fieldId];
        if (mirrored != null || controller.text.isEmpty) {
          controller.text = term.value;
          _mirroredFieldValues[fieldId] = term.value;
        }
      }
      for (final entry in _mirroredFieldValues.entries) {
        if (activeMirrorFields.contains(entry.key)) continue;
        final mirrored = entry.value;
        if (mirrored == null) continue;
        final controller = controllerForMirrorFieldId(entry.key);
        if (controller != null && controller.text == mirrored) {
          controller.clear();
        }
        _mirroredFieldValues[entry.key] = null;
      }
    } finally {
      suppressLiveSearch = false;
    }
  }

  void clearMirroredFieldsIfNeeded(LampSearchParseResult parsed) {
    if (parsed.hasScopedTerms) return;
    suppressLiveSearch = true;
    try {
      for (final entry in _mirroredFieldValues.entries.toList()) {
        final mirrored = entry.value;
        if (mirrored == null) continue;
        final controller = controllerForMirrorFieldId(entry.key);
        if (controller != null && controller.text == mirrored) {
          controller.clear();
        }
        _mirroredFieldValues[entry.key] = null;
      }
    } finally {
      suppressLiveSearch = false;
    }
  }

  LampSearchParseResult parseGlobalQuery() {
    return LampSearchQueryParser.parse(globalController.text);
  }

  void scheduleLiveSearch() {
    liveSearchDebounce?.cancel();
    liveSearchDebounce = Timer(const Duration(milliseconds: 320), () async {
      await runLiveSearch();
    });
  }

  Future<void> runLiveSearch() async {
    if (!host.mounted) return;
    final hasGlobal = globalController.text.trim().isNotEmpty;
    final hasFields = hasAnyFieldSearchInput;
    if (!hasGlobal && !hasFields && !unlinkedFilterActive) {
      _assignResults(_emptyResults);
      message = null;
      host.notifyState();
      return;
    }
    if (hasGlobal || (!hasFields && unlinkedFilterActive)) {
      // Σκέτο φίλτρο περνά από το καθολικό μονοπάτι με κενό κείμενο:
      // «όλες οι ασύνδετες οντότητες των επιλεγμένων ειδών».
      final parsed = parseGlobalQuery();
      applyMirrorFromParsed(parsed);
      await globalSearch(showProgressSnack: false);
      return;
    }
    await fieldSearch(showProgressSnack: false);
  }

  /// Αλλαγή φίλτρου: νέα επιλογή και άμεση επανεκτέλεση της τρέχουσας
  /// αναζήτησης (χωρίς debounce — είναι κλικ, όχι πληκτρολόγηση).
  Future<void> setFilterSelection(LampSearchFilterSelection selection) async {
    filterSelection = selection;
    host.notifyState();
    liveSearchDebounce?.cancel();
    await runLiveSearch();
  }

  /// Πλήθη για το μενού φίλτρων.
  ///
  /// Με πρόσφατη αναζήτηση: τα ταιριάσματα ανά είδος (πριν την επιλογή ειδών,
  /// ώστε τα ανεπίλεκτα να μη δείχνουν μηδέν). Χωρίς αναζήτηση: τα συνολικά
  /// της βάσης — φορτώνονται μία φορά και ξεχνιούνται σε αλλαγή διαδρομής.
  Future<LampFilterMenuCounts> unlinkedMenuCounts() async {
    if (_hasFreshCounts) {
      return LampFilterMenuCounts(
        byKind: unlinkedCountsByKind,
        emptyRecords: unlinkedEmptyCount,
        equipmentGaps: _equipmentGapTotals ?? const <LampEquipmentGapKind, int>{},
      );
    }
    final currentPath = path.readDbController.text.trim();
    final cached = _totalUnlinkedCounts;
    if (cached != null && _totalUnlinkedCountsPath == currentPath) {
      return cached;
    }
    if (!readPathReadyForQuery) return const LampFilterMenuCounts();
    try {
      final totals = await host.shared.repository.countFilterCandidates(
        currentPath,
      );
      _totalUnlinkedCounts = totals;
      _equipmentGapTotals = totals.equipmentGaps;
      _totalUnlinkedCountsPath = currentPath;
      return totals;
    } catch (_) {
      // Χωρίς πλήθη το μενού παραμένει χρήσιμο — απλώς δεν δείχνει αριθμούς.
      return const LampFilterMenuCounts();
    }
  }

  void clearAllSearchInputs() {
    suppressLiveSearch = true;
    globalController.clear();
    for (final c in fieldSearchControllers) {
      c.clear();
    }
    _mirroredFieldValues.updateAll((_, _) => null);
    suppressLiveSearch = false;
    filterSelection = LampSearchFilterSelection.none;
    liveSearchDebounce?.cancel();
    _assignResults(_emptyResults);
    message = null;
    host.notifyState();
  }

  Widget? clearFieldSuffix({
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

  bool readPathCheckIsErrorForSnack(LampOldDbStatus? status) {
    return status != LampOldDbStatus.pathEmpty &&
        status != LampOldDbStatus.pendingCreation;
  }

  Future<void> fieldSearch({bool showProgressSnack = true}) async {
    if (!readPathReadyForQuery) {
      host.showSnack(
        host.readPathCheck?.userMessageGreek ??
            'Η βάση προς ανάγνωση δεν είναι έτοιμη. Ανοίξτε «Ρυθμίσεις διαδρομών».',
        isError: readPathCheckIsErrorForSnack(host.readPathCheck?.status),
      );
      return;
    }
    await runSearch(
      () => host.shared.repository.searchByFields(
        path.readDbController.text.trim(),
        OldEquipmentSearchFilters(
          phone: phoneController.text,
          code: codeController.text,
          owner: ownerController.text,
          office: officeController.text,
          serialNo: serialController.text,
        ),
        maxDisplay: maxSearchResults,
        filters: filterSelection,
      ),
      showProgressSnack: showProgressSnack,
    );
  }

  Future<void> globalSearch({bool showProgressSnack = true}) async {
    if (!readPathReadyForQuery) {
      host.showSnack(
        host.readPathCheck?.userMessageGreek ??
            'Η βάση προς ανάγνωση δεν είναι έτοιμη.',
        isError: readPathCheckIsErrorForSnack(host.readPathCheck?.status),
      );
      return;
    }
    final parsed = parseGlobalQuery();
    applyMirrorFromParsed(parsed);
    await runSearch(() {
      if (!parsed.hasScopedTerms) {
        return host.shared.repository.globalSearch(
          path.readDbController.text.trim(),
          globalController.text,
          maxDisplay: maxSearchResults,
          filters: filterSelection,
        );
      }
      return host.shared.repository.globalSearch(
        path.readDbController.text.trim(),
        globalController.text,
        maxDisplay: maxSearchResults,
        scopedTerms: parsed.scopedTerms,
        freeText: parsed.freeText,
        filters: filterSelection,
      );
    }, showProgressSnack: showProgressSnack);
  }

  /// Η γραμμή σύνοψης πάνω από τα αποτελέσματα.
  ///
  Future<void> runSearch(
    Future<OldEquipmentSearchResult> Function() action, {
    bool showProgressSnack = true,
  }) async {
    final pth = path.readDbController.text.trim();
    if (pth.isEmpty) {
      message = 'Κενή διαδρομή βάσης προς ανάγνωση.';
      host.notifyState();
      return;
    }
    message = null;
    host.notifyState();
    if (showProgressSnack) {
      host.showSnack(
        'Εκτέλεση αναζήτησης…',
        duration: const Duration(seconds: 2),
      );
    }
    try {
      final result = await action();
      if (!host.mounted) return;
      _assignResults(
        result.rows,
        unlinked: result.unlinked,
        unlinkedTotal: result.unlinkedTotalCount,
        countsByKind: result.unlinkedCountsByKind,
        emptyCount: result.unlinkedEmptyCount,
        freshCounts: true,
      );
      message = lampSearchOutcomeMessage(
        equipmentTotal: result.totalCount,
        equipmentShown: result.rows.length,
        unlinkedTotal: result.unlinkedTotalCount,
        unlinkedShown: result.unlinked.length,
      );
      host.notifyState();
    } catch (e) {
      if (!host.mounted) return;
      message = e.toString();
      host.notifyState();
      host.showSnack(
        'Η αναζήτηση απέτυχε. Ελέγξτε τη διαδρομή από «Ρυθμίσεις διαδρομών».',
        isError: true,
      );
    }
  }
}
