// Αναζήτηση εξοπλισμού: debounce, φίλτρα πεδίων, αποτελέσματα.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../database/services/database_stats_service.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';

class LampSearchController {
  LampSearchController({
    required this.host,
    required this.path,
  });

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

  int maxSearchResults = LampSettingsStore.defaultMaxSearchResults;
  List<Map<String, Object?>> results = const <Map<String, Object?>>[];
  String? message;

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
      globalController.text.trim().isNotEmpty || hasAnyFieldSearchInput;

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
    if (globalController.text.trim().isNotEmpty && hasAnyFieldSearchInput) {
      suppressLiveSearch = true;
      for (final c in fieldSearchControllers) {
        if (c.text.isNotEmpty) c.clear();
      }
      suppressLiveSearch = false;
    }
    scheduleLiveSearch();
  }

  void onFieldSearchInputChanged() {
    if (suppressLiveSearch) return;
    if (hasAnyFieldSearchInput && globalController.text.trim().isNotEmpty) {
      suppressLiveSearch = true;
      globalController.clear();
      suppressLiveSearch = false;
    }
    scheduleLiveSearch();
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
    if (!hasGlobal && !hasFields) {
      results = const <Map<String, Object?>>[];
      message = null;
      host.notifyState();
      return;
    }
    if (hasGlobal) {
      await globalSearch(showProgressSnack: false);
      return;
    }
    await fieldSearch(showProgressSnack: false);
  }

  void clearAllSearchInputs() {
    suppressLiveSearch = true;
    globalController.clear();
    for (final c in fieldSearchControllers) {
      c.clear();
    }
    suppressLiveSearch = false;
    liveSearchDebounce?.cancel();
    results = const <Map<String, Object?>>[];
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
    await runSearch(
      () => host.shared.repository.globalSearch(
        path.readDbController.text.trim(),
        globalController.text,
        maxDisplay: maxSearchResults,
      ),
      showProgressSnack: showProgressSnack,
    );
  }

  String? searchOutcomeMessage(int totalCount) {
    if (totalCount == 0) return null;
    final xStr = DatabaseStatsService.formatIntegerEl(totalCount);
    final n = maxSearchResults;
    if (totalCount > 0 && n < totalCount) {
      final nStr = DatabaseStatsService.formatIntegerEl(n);
      return 'Εμφάνιση των πρώτων $nStr αποτελεσμάτων από $xStr.';
    }
    return 'Βρέθηκαν $xStr αποτελέσματα.';
  }

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
      results = result.rows;
      message = searchOutcomeMessage(result.totalCount);
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
