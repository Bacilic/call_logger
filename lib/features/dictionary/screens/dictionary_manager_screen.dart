import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/database/dictionary_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/errors/dictionary_export_exception.dart';
import '../../../core/models/dictionary_import_mode.dart';
import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/providers/lexicon_categories_provider.dart';
import '../../../core/providers/lexicon_full_mode_provider.dart';
import '../../../core/providers/lexicon_language_recalc_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/providers/shell_navigation_intent_provider.dart';
import '../../../core/providers/spell_check_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/services/core_lexicon_service.dart';
import '../../../core/services/dictionary_service.dart';
import '../../../core/services/master_dictionary_service.dart';
import '../../../core/utils/lexicon_word_metrics.dart';
import '../dictionary_table_layout.dart';
import '../providers/dictionary_layout_provider.dart';
import '../models/lexicon_list_filters_model.dart';
import '../providers/lexicon_list_filters_provider.dart';
import '../providers/lexicon_scroll_provider.dart';
import '../providers/lexicon_spelling_panel_provider.dart';
import '../widgets/dictionary_grid_row.dart';
import '../widgets/dictionary_settings_dialog.dart';
import '../widgets/lexicon_spelling_panel.dart';

const _kLexiconLangAssetAll = 'assets/greek_english.png';
const _kLexiconLangAssetMix = 'assets/greek_english_mix.png';
const _kLexiconLangAssetEl = 'assets/greece_flag.png';
const _kLexiconLangAssetEn = 'assets/united_kingdom_flag.png';
const _kPunctuationMarksIcon = 'assets/punctuation_marks.png';
const _kNumberOfColumnsIcon = 'assets/number_of_columns.png';
const _kLexiconLangDdWidth = 64.0;

Widget _lexiconLangFlagImage(String asset, {required double height}) {
  return Image.asset(
    asset,
    height: height,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Icon(Icons.flag_outlined, size: height * 0.92),
  );
}

Widget _lexiconLangFilterSelectedIcon(int index) {
  switch (index) {
    case 0:
      return Image.asset(
        _kLexiconLangAssetAll,
        height: 30,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.translate, size: 28),
      );
    case 1:
      return _lexiconLangFlagImage(_kLexiconLangAssetEl, height: 30);
    case 2:
      return _lexiconLangFlagImage(_kLexiconLangAssetEn, height: 30);
    case 3:
      return Image.asset(
        _kLexiconLangAssetMix,
        height: 30,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.text_fields, size: 28),
      );
    default:
      return const SizedBox.shrink();
  }
}

Widget _lexiconLangFilterMenuItem({
  required String tooltip,
  required Widget icon,
}) {
  return Tooltip(
    message: tooltip,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Center(child: icon),
    ),
  );
}

/// Οπτικός διαχωρισμός ομάδων στηλών: παχιά κάθετη γραμμή αριστερά στις ομάδες 2+.
Widget _lexiconColumnGroupShell({
  required BuildContext context,
  required int groupIndex,
  required Widget child,
}) {
  if (groupIndex == 0) {
    return child;
  }
  final color = Theme.of(context).colorScheme.outline;
  return Container(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: color, width: 3),
      ),
    ),
    child: child,
  );
}

class _AddCustomWordsDialog extends StatefulWidget {
  const _AddCustomWordsDialog({
    required this.categories,
    required this.master,
    required this.addCustomWordErrorMessage,
  });

  final List<String> categories;
  final MasterDictionaryService master;
  final String Function(Object e) addCustomWordErrorMessage;

  @override
  State<_AddCustomWordsDialog> createState() => _AddCustomWordsDialogState();
}

class _AddCustomWordsDialogState extends State<_AddCustomWordsDialog> {
  late final TextEditingController _wordCtrl;
  late String _selectedCategory;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _wordCtrl = TextEditingController();
    _selectedCategory = widget.categories.first;
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _wordCtrl.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Νέες λέξεις στο λεξικό'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_dialogError != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _dialogError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _wordCtrl,
                autofocus: true,
                minLines: 4,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Λέξεις',
                  hintText: 'Χωρισμός με κενά ή κόμμα (ή επικόλληση λίστας)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Κατηγορία',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    borderRadius: BorderRadius.circular(12),
                    value: widget.categories.contains(_selectedCategory)
                        ? _selectedCategory
                        : widget.categories.first,
                    isExpanded: true,
                    items: widget.categories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(
                              c,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedCategory = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () async {
                  setState(() => _dialogError = null);
                  try {
                    await widget.master.addCustomWords(
                      input: _wordCtrl.text,
                      category: _selectedCategory,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    setState(
                      () => _dialogError =
                          widget.addCustomWordErrorMessage(e),
                    );
                  }
                }
              : null,
          child: const Text('Προσθήκη'),
        ),
      ],
    );
  }
}

/// Διαχείριση master λεξικού (`full_dictionary` + `user_dictionary`).
class DictionaryManagerScreen extends ConsumerStatefulWidget {
  const DictionaryManagerScreen({
    super.key,
    required this.databaseResult,
  });

  final DatabaseInitResult databaseResult;

  @override
  ConsumerState<DictionaryManagerScreen> createState() =>
      _DictionaryManagerScreenState();
}

class _DictionaryManagerScreenState extends ConsumerState<DictionaryManagerScreen> {
  /// Γιατί η λίστα μπορεί να έχει λίγες γραμμές ενώ η ορθογραφία «ξέρει» πολλές λέξεις.
  String _lexiconScopeInfoTooltip(CoreLexiconState core) {
    final coreSummary = core.loaded && (core.path?.trim().isNotEmpty ?? false)
        ? '${p.basename(core.path!.trim())} - ${core.wordCount} λέξεις'
        : 'δεν φορτώθηκε';
    return 'Εδώ φαίνονται μόνο οι εγγραφές στη βάση '
        '(Πλήρες Λεξικό μαζί με το πρόχειρο Λεξικό Χρήστη), όχι το Λεξικό-Πυρήνας '
        '($coreSummary).\n\n'
        'Η ορθογραφία φορτώνει στη μνήμη το Λεξικό-Πυρήνας και το Λεξικό Χρήστη· '
        'Το Πλήρες Λεξικό δεν επηρεάζει τον έλεγχο. Είναι μόνο για επεξεργασία των λέξεων.\n\n'
        'Για προβολή ΟΛΩΝ των λέξεων πηγήνε: Ρυθμίσεις → Εισαγωγή από αρχείο (TXT).';
  }

  final _master = MasterDictionaryService();
  final _searchCtrl = TextEditingController();
  final _horizontalTableScroll = ScrollController();
  final _verticalTableScroll = ScrollController();

  int _totalCount = 0;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;
  /// null = αυτόματο πλάτος από περιεχόμενο ομάδας· αλλιώς πλάτος από λαβή resize.
  List<double?> _lexiconWordColumnWidthUser =
      List<double?>.filled(kLexiconMaxColumnGroups, null);
  /// Ζωντανό πλάτος κατά το σύρσιμο λαβής (χωρίς rebuild ολόκληρης οθόνης).
  final List<ValueNotifier<double?>> _lexiconWordWidthDuringDrag = List.generate(
    kLexiconMaxColumnGroups,
    (_) => ValueNotifier<double?>(null),
  );
  final List<double?> _lexiconResizeDragBaseWidth =
      List<double?>.filled(kLexiconMaxColumnGroups, null);

  final _lettersCountField = TextEditingController();
  Timer? _lettersFilterDebounce;
  bool _initialFiltersRefreshDone = false;
  bool _bootstrapScheduled = false;

  Timer? _searchDebounce;

  double _tableViewportWidth = 0;
  double _tableViewportHeight = 0;

  void _syncDictionaryLayout(
    BuildContext context, {
    required int? columnGroups,
  }) {
    if (_tableViewportWidth <= 0 || _tableViewportHeight <= 0) return;
    ref.read(dictionaryLayoutProvider.notifier).calculateLayout(
          rows: _loading ? const [] : _rows,
          viewportWidth: _tableViewportWidth,
          viewportHeight: _tableViewportHeight,
          columnGroups: columnGroups,
          userWordColumnWidths: _lexiconWordColumnWidthUser,
          metrics: DictionaryLayoutMetrics.fromContext(context),
        );
  }

  void _scheduleDictionaryLayoutSync(
    BuildContext context, {
    required double viewportWidth,
    required double viewportHeight,
    required int? columnGroups,
  }) {
    _tableViewportWidth = viewportWidth;
    _tableViewportHeight = viewportHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncDictionaryLayout(context, columnGroups: columnGroups);
    });
  }

  @override
  void initState() {
    super.initState();
    if (!widget.databaseResult.isSuccess) {
      setState(() => _loading = false);
    }
    _searchCtrl.addListener(_onSearchChanged);
    _verticalTableScroll.addListener(_onVerticalLexiconScroll);
  }

  bool _isAtScrollEnd(ScrollPosition pos) {
    const threshold = 400.0;
    return pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - threshold;
  }

  void _onVerticalLexiconScroll() {
    if (!mounted) return;
    final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
    if (!continuous || _loadingMore || _loading) return;
    if (_rows.isEmpty || _rows.length >= _totalCount) return;
    final c = _verticalTableScroll;
    if (!c.hasClients) return;
    final pos = c.position;
    final atEnd = _isAtScrollEnd(pos);
    if (atEnd) {
      _refreshList(append: true);
    }
  }

  void _scheduleContinuousViewportFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fillContinuousViewportIfNeeded());
    });
  }

  /// Συνεχής κύλιση: αν το περιεχόμενο χωράει στην οθόνη, φόρτωσε κι άλλες γραμμές
  /// μέχρι να ενεργοποιηθεί scrollbar ή να εξαντληθούν τα αποτελέσματα.
  Future<void> _fillContinuousViewportIfNeeded() async {
    if (!mounted) return;
    final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
    if (!continuous || _loadingMore || _loading) return;
    if (_rows.isEmpty || _rows.length >= _totalCount) return;
    final c = _verticalTableScroll;
    if (!c.hasClients) {
      _scheduleContinuousViewportFill();
      return;
    }
    final maxExt = c.position.maxScrollExtent;
    if (maxExt > 0) return;
    await _refreshList(append: true);
    if (!mounted) return;
    _scheduleContinuousViewportFill();
  }

  void _scheduleContinuousViewportFillAfterLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
      if (continuous && _rows.length < _totalCount) {
        _scheduleContinuousViewportFill();
      }
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      await ref.read(lexiconListFiltersProvider.notifier).resetPage();
      if (mounted) _refreshList();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _lettersFilterDebounce?.cancel();
    _searchCtrl.dispose();
    _lettersCountField.dispose();
    _verticalTableScroll.removeListener(_onVerticalLexiconScroll);
    _verticalTableScroll.dispose();
    _horizontalTableScroll.dispose();
    for (final n in _lexiconWordWidthDuringDrag) {
      n.dispose();
    }
    super.dispose();
  }

  void _onLexiconWordColumnResizeStart(int groupIndex, double currentWidth) {
    _lexiconResizeDragBaseWidth[groupIndex] = currentWidth;
  }

  void _onLexiconWordColumnResizeUpdate(int groupIndex, double delta) {
    final base = _lexiconResizeDragBaseWidth[groupIndex];
    if (base == null) return;
    _lexiconWordWidthDuringDrag[groupIndex].value = (base + delta).clamp(
      kLexiconWordColumnMin,
      kLexiconWordColumnMax,
    );
  }

  void _onLexiconWordColumnResizeEnd(int groupIndex, double delta) {
    final base = _lexiconResizeDragBaseWidth[groupIndex];
    if (base != null) {
      final w = (base + delta).clamp(
        kLexiconWordColumnMin,
        kLexiconWordColumnMax,
      );
      setState(() {
        _lexiconWordColumnWidthUser =
            List<double?>.from(_lexiconWordColumnWidthUser)
              ..[groupIndex] = w;
        _lexiconResizeDragBaseWidth[groupIndex] = null;
      });
    }
    _lexiconWordWidthDuringDrag[groupIndex].value = null;
  }

  void _onLexiconWordColumnResizeCancel(int groupIndex) {
    _lexiconResizeDragBaseWidth[groupIndex] = null;
    _lexiconWordWidthDuringDrag[groupIndex].value = null;
  }

  Future<void> _refreshList({bool append = false}) async {
    if (!widget.databaseResult.isSuccess) return;
    final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
    final pageSize = ref.read(lexiconPageSizeProvider).value ?? 40;
    final filters = ref.read(lexiconListFiltersProvider);

    if (append) {
      if (!continuous || _loadingMore || _loading) return;
      if (_rows.isEmpty || _rows.length >= _totalCount) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final search = _searchCtrl.text.trim();
      String? lettersOp;
      int? lettersVal;
      final lettersText = _lettersCountField.text.trim();
      if (lettersText.isNotEmpty) {
        final p = int.tryParse(lettersText);
        if (p != null && p >= 1 && p <= 100) {
          lettersOp = filters.lettersCompareOp;
          lettersVal = p;
        }
      }

      final dbLex = await DatabaseHelper.instance.database;
      final dictLex = DictionaryRepository(dbLex);
      List<Map<String, dynamic>> mutableRows(List<Map<String, dynamic>> src) =>
          src.map((r) => Map<String, dynamic>.from(r)).toList(growable: true);

      if (append) {
        final rows = await dictLex.queryCombinedLexiconPage(
          language: filters.langFilter,
          source: filters.sourceFilter,
          category: filters.categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly:
              filters.sourceFilter == DictionaryRepository.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: filters.diacriticMarksFilter,
          limit: pageSize,
          offset: _rows.length,
        );
        if (mounted) {
          setState(() {
            if (rows.isEmpty) {
              _totalCount = _rows.length;
            } else {
              _rows = [..._rows, ...mutableRows(rows)];
            }
            _loadingMore = false;
          });
          _scheduleContinuousViewportFillAfterLoad();
        }
      } else {
        final count = await dictLex.countCombinedLexiconRows(
          language: filters.langFilter,
          source: filters.sourceFilter,
          category: filters.categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly:
              filters.sourceFilter == DictionaryRepository.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: filters.diacriticMarksFilter,
        );
        var page = filters.page;
        if (!continuous) {
          final maxPage = count == 0 ? 0 : ((count - 1) ~/ pageSize);
          if (page > maxPage) {
            page = maxPage;
            await ref.read(lexiconListFiltersProvider.notifier).setPage(maxPage);
          }
        }
        final offset = continuous ? 0 : page * pageSize;
        final rows = await dictLex.queryCombinedLexiconPage(
          language: filters.langFilter,
          source: filters.sourceFilter,
          category: filters.categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly:
              filters.sourceFilter == DictionaryRepository.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: filters.diacriticMarksFilter,
          limit: pageSize,
          offset: offset,
        );
        if (mounted) {
          setState(() {
            _totalCount = count;
            _rows = mutableRows(rows);
            _loading = false;
            _loadingMore = false;
          });
          _scheduleContinuousViewportFillAfterLoad();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _openDictionarySettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => DictionarySettingsDialog(
        onImportTxt: _importTxtFile,
        onCompile: _compileExport,
      ),
    );
  }

  String _addCustomWordErrorMessage(Object e) {
    final s = e.toString();
    const p = 'Exception: ';
    return s.startsWith(p) ? s.substring(p.length) : s;
  }

  Future<void> _openAddCustomWordDialog() async {
    List<String> categories;
    try {
      categories = await ref.read(lexiconCategoriesProvider.future);
    } catch (_) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    if (categories.isEmpty) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    categories = categories
        .where((c) => c != AppConfig.lexiconCategoryUnspecified)
        .toList();
    if (categories.isEmpty) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    if (!mounted) return;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddCustomWordsDialog(
        categories: categories,
        master: _master,
        addCustomWordErrorMessage: _addCustomWordErrorMessage,
      ),
    );

    if (added == true && mounted) {
      ref.invalidate(coreLexiconProvider);
      ref.invalidate(spellCheckServiceProvider);
      ref.read(lexiconMasterDataRevisionProvider.notifier).bump();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Οι λέξεις προστέθηκαν στο λεξικό'),
          duration: Duration(seconds: 3),
        ),
      );
      await _refreshList();
    }
  }

  Future<void> _importTxtFile() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final mode = await showDialog<DictionaryImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Εισαγωγή αρχείου'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, DictionaryImportMode.enrich),
            child: const Text('Εμπλουτισμός'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, DictionaryImportMode.replace),
            child: const Text('Αντικατάσταση'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == DictionaryImportMode.replace) {
      final existing =
          await DictionaryRepository(await DatabaseHelper.instance.database)
              .countFullDictionaryTotal();
      final lines = await File(path).readAsLines();
      var newCount = 0;
      for (final line in lines) {
        final t = line.trim();
        if (t.isNotEmpty && !t.startsWith('#')) newCount++;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Αντικατάσταση'),
          content: Text(
            'Πρόκειται να αντικαταστήσετε $existing λέξεις με $newCount νέες. Να γίνει η αντικατάσταση;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _master.importFromTxtFile(path, mode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Εισαγωγή αρχείου ολοκληρώθηκε')),
        );
        await _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    }
  }

  Future<void> _compileExport() async {
    try {
      await _master.compileExportToTxt();
      ref.invalidate(coreLexiconProvider);
      ref.invalidate(spellCheckServiceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compile ολοκληρώθηκε. Αν χρησιμοποιείτε custom πηγή, βεβαιωθείτε ότι η διαδρομή πηγής δείχνει στο νέο αρχείο.',
            ),
          ),
        );
        await _refreshList();
      }
    } on DictionaryExportPathMissingException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ορίστε διαδρομή εξαγωγής (Compile).'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα Compile: $e')),
        );
      }
    }
  }

  String _lexiconRowWidgetKey(Map<String, dynamic> row) {
    final entryId = row['entry_id'] as int?;
    if (entryId != null) return 'lex_e_$entryId';
    final normKey = row['norm_key'] as String? ?? '';
    return 'lex_d_$normKey';
  }

  int _indexOfLexiconRow({
    required int? entryId,
    required String normKey,
  }) {
    return _rows.indexWhere((r) {
      final id = r['entry_id'] as int?;
      if (entryId != null && id == entryId) return true;
      return (r['norm_key'] as String? ?? '') == normKey;
    });
  }

  bool _rowPassesLettersFilter(
    Map<String, dynamic> row,
    LexiconListFiltersModel filters,
  ) {
    final lettersText = _lettersCountField.text.trim();
    if (lettersText.isEmpty) return true;
    final parsed = int.tryParse(lettersText);
    if (parsed == null || parsed < 1 || parsed > 100) return true;
    final lettersCount = row['letters_count'] as int? ?? 0;
    return switch (filters.lettersCompareOp) {
      '>=' => lettersCount >= parsed,
      '<=' => lettersCount <= parsed,
      '=' => lettersCount == parsed,
      _ => true,
    };
  }

  bool _rowPassesDiacriticFilter(
    Map<String, dynamic> row,
    LexiconListFiltersModel filters,
  ) {
    final filter = filters.diacriticMarksFilter;
    if (filter == null || filter.isEmpty) return true;
    final count = row['diacritic_mark_count'] as int? ?? 0;
    return switch (filter) {
      'none' => count == 0,
      '1' => count == 1,
      '2' => count == 2,
      '3' => count == 3,
      'gt3' => count > 3,
      _ => true,
    };
  }

  bool _localRowMatchesFilters(Map<String, dynamic> row) {
    final filters = ref.read(lexiconListFiltersProvider);
    final search = _searchCtrl.text.trim();
    if (search.isNotEmpty) {
      final normKey = (row['norm_key'] as String? ?? '').toLowerCase();
      final display = (row['display_word'] as String? ?? '').toLowerCase();
      final needle = search.toLowerCase();
      if (!normKey.contains(needle) && !display.contains(needle)) {
        return false;
      }
    }

    final category = filters.categoryFilter;
    if (category != null && category.isNotEmpty) {
      if ((row['cat'] as String? ?? '') != category) return false;
    }

    final src = row['src'] as String? ?? '';
    final pending = (row['pending_user'] as int? ?? 0) == 1;
    final sourceFilter = filters.sourceFilter;
    if (sourceFilter == DictionaryRepository.kLexiconSourceDraft) {
      if (src != DictionaryRepository.kLexiconSourceDraft) return false;
    } else if (sourceFilter == DictionaryRepository.kLexiconPendingFilter) {
      if (!pending) return false;
    } else if (sourceFilter != null && sourceFilter.isNotEmpty) {
      if (src != sourceFilter) return false;
    }

    final langFilter = filters.langFilter;
    if (langFilter != null &&
        langFilter.isNotEmpty &&
        langFilter != DictionaryRepository.kLexiconMixedScriptsFilter) {
      if ((row['lang'] as String? ?? '') != langFilter) return false;
    }

    if (!_rowPassesLettersFilter(row, filters) ||
        !_rowPassesDiacriticFilter(row, filters)) {
      return false;
    }
    return true;
  }

  void _patchLexiconRowLocally({
    required int? entryId,
    required String oldNormKey,
    required String displayWord,
    required String category,
    bool promoteFromDraft = false,
    int? promotedEntryId,
    String? promotedSrc,
    String? promotedLang,
  }) {
    final index = _indexOfLexiconRow(entryId: entryId, normKey: oldNormKey);
    if (index < 0) return;

    final trimmedWord = displayWord.trim();
    final newKey = DictionaryService.canonicalLexiconKey(trimmedWord);
    final metrics = LexiconWordMetrics.compute(trimmedWord);
    final updated = Map<String, dynamic>.from(_rows[index]);
    updated['display_word'] = trimmedWord;
    updated['norm_key'] = newKey;
    updated['cat'] = category;
    updated['letters_count'] = metrics.lettersCount;
    updated['diacritic_mark_count'] = metrics.diacriticMarkCount;
    if (promoteFromDraft && promotedEntryId != null) {
      updated['entry_id'] = promotedEntryId;
      updated['src'] = promotedSrc ?? 'user';
      if (promotedLang != null && promotedLang.isNotEmpty) {
        updated['lang'] = promotedLang;
      }
    }

    setState(() {
      if (!_localRowMatchesFilters(updated)) {
        _rows = [..._rows]..removeAt(index);
        if (_totalCount > 0) _totalCount--;
        return;
      }
      _rows = [..._rows]..[index] = updated;
    });
  }

  void _removeLexiconRowLocally({
    required int? entryId,
    required String normKey,
  }) {
    final index = _indexOfLexiconRow(entryId: entryId, normKey: normKey);
    if (index < 0) return;

    setState(() {
      _rows = [..._rows]..removeAt(index);
      if (_totalCount > 0) _totalCount--;
    });
  }

  Future<void> _updateLexiconRow(
    Map<String, dynamic> row,
    String displayWord,
    String category,
  ) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';
    final display = row['display_word'] as String? ?? '';
    final src = row['src'] as String? ?? '';
    final isDraft = entryId == null || src == DictionaryRepository.kLexiconSourceDraft;
    final lang = row['lang'] as String? ?? 'el';
    final prevCat = row['cat'] as String? ?? 'Γενική';

    if (displayWord == display && category == prevCat) return;

    try {
      if (isDraft) {
        await _master.microMergeUserDraft(
          normalizedKey: normKey,
          displayWord: displayWord,
          category: category,
          language: lang,
        );
      } else {
        final newWord = displayWord;
        final dictUp =
            DictionaryRepository(await DatabaseHelper.instance.database);
        await dictUp.upsertFullDictionaryCategory(
          id: entryId,
          category: category,
          newDisplayWord: newWord != display ? newWord : null,
        );
        if ((row['pending_user'] as int? ?? 0) == 1 && newWord != display) {
          final newKey = DictionaryService.canonicalLexiconKey(newWord);
          if (newKey != normKey) {
            await dictUp.updateUserDictionaryWordKey(
              normKey,
              newKey,
              displayWord: newWord,
            );
          }
        }
      }

      final newKey = DictionaryService.canonicalLexiconKey(displayWord);
      int? promotedEntryId;
      String? promotedSrc;
      String? promotedLang;
      if (isDraft) {
        final db = await DatabaseHelper.instance.database;
        final promoted = await db.query(
          AppConfig.fullDictionaryTable,
          columns: ['id', 'source', 'language'],
          where: 'normalized_word = ?',
          whereArgs: [newKey],
          limit: 1,
        );
        if (promoted.isNotEmpty) {
          promotedEntryId = promoted.first['id'] as int?;
          promotedSrc = promoted.first['source'] as String? ?? 'user';
          promotedLang = promoted.first['language'] as String?;
        }
      }

      if (!mounted) return;
      _patchLexiconRowLocally(
        entryId: entryId,
        oldNormKey: normKey,
        displayWord: displayWord,
        category: category,
        promoteFromDraft: isDraft,
        promotedEntryId: promotedEntryId,
        promotedSrc: promotedSrc,
        promotedLang: promotedLang,
      );
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        const exPrefix = 'Exception: ';
        const statePrefix = 'Bad state: ';
        final msg = raw.startsWith(exPrefix)
            ? raw.substring(exPrefix.length)
            : raw.startsWith(statePrefix)
                ? raw.substring(statePrefix.length)
                : raw;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      // Propagate so [DictionaryGridRow] can revert the word field and category UI.
      rethrow;
    }
  }

  Future<void> _applySpellingSuggestion(String suggestion) async {
    final target = ref.read(lexiconSpellingPanelProvider).target;
    if (target == null) return;
    final index = _indexOfLexiconRow(
      entryId: target.entryId,
      normKey: target.normKey,
    );
    if (index < 0) return;
    final row = _rows[index];
    final cat = (row['cat'] as String?)?.trim().isNotEmpty == true
        ? (row['cat'] as String).trim()
        : 'Γενική';
    await _updateLexiconRow(row, suggestion.trim(), cat);
  }

  void _onSpellingContextFromRow(Map<String, dynamic> row, String word) {
    ref.read(lexiconSpellingPanelProvider.notifier).updateFromRow(
          word: word,
          normKey: row['norm_key'] as String? ?? '',
          entryId: row['entry_id'] as int?,
        );
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';
    final src = row['src'] as String? ?? '';
    final isDraft = entryId == null || src == DictionaryRepository.kLexiconSourceDraft;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή'),
        content: Text('Διαγραφή «${row['display_word']}»;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final dictDel =
          DictionaryRepository(await DatabaseHelper.instance.database);
      if (isDraft) {
        await dictDel.deleteUserDictionaryWord(normKey);
      } else {
        await dictDel.hardDeleteFullDictionaryById(entryId);
        await dictDel.deleteUserDictionaryWord(normKey);
      }
      if (!mounted) return;
      _removeLexiconRowLocally(entryId: entryId, normKey: normKey);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    }
  }

  void _navigateFromImmersiveLexicon(MainNavDestination destination) {
    ref.read(shellNavigationIntentProvider.notifier).setPending(destination);
    ref.read(lexiconFullModeProvider.notifier).setFalse();
  }

  static Widget _navMenuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  /// Μενού πλοήγησης (ίδια βήματα με το NavigationRail, χωρίς Λεξικό).
  Widget _immersiveNavigationMenuButton() {
    final showDb = ref.watch(showDatabaseNavProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );
    return PopupMenuButton<MainNavDestination>(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tooltip: 'Μετάβαση σε άλλη οθόνη',
      icon: const Icon(Icons.menu),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 40,
      ),
      onSelected: _navigateFromImmersiveLexicon,
      itemBuilder: (context) {
        return <PopupMenuEntry<MainNavDestination>>[
          PopupMenuItem(
            value: MainNavDestination.calls,
            child: _navMenuRow(Icons.phone_in_talk, 'Κλήσεις'),
          ),
          PopupMenuItem(
            value: MainNavDestination.tasks,
            child: _navMenuRow(Icons.task_alt, 'Εκκρεμότητες'),
          ),
          PopupMenuItem(
            value: MainNavDestination.directory,
            child: _navMenuRow(Icons.contacts, 'Κατάλογος'),
          ),
          PopupMenuItem(
            value: MainNavDestination.history,
            child: _navMenuRow(Icons.history, 'Ιστορικό'),
          ),
          if (showDb)
            PopupMenuItem(
              value: MainNavDestination.database,
              child: _navMenuRow(Icons.storage, 'Βάση Δεδομένων'),
            ),
        ];
      },
    );
  }

  Future<void> _bootstrapLexiconList() async {
    if (_initialFiltersRefreshDone) return;
    await ref.read(lexiconListFiltersProvider.notifier).hydrationFuture;
    if (!mounted || _initialFiltersRefreshDone) return;
    _initialFiltersRefreshDone = true;
    final filters = ref.read(lexiconListFiltersProvider);
    if (_lettersCountField.text != filters.lettersCount) {
      _lettersCountField.text = filters.lettersCount;
    }
    if (widget.databaseResult.isSuccess) {
      await _refreshList();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapScheduled) {
      _bootstrapScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_bootstrapLexiconList());
      });
    }

    ref.listen<int>(lexiconMasterDataRevisionProvider, (prev, next) {
      _refreshList();
    });

    final listFilters = ref.watch(lexiconListFiltersProvider);

    final immersive = ref.watch(lexiconFullModeProvider);
    final outerPadding = immersive
        ? const EdgeInsets.fromLTRB(8, 4, 8, 8)
        : const EdgeInsets.all(16);

    if (!widget.databaseResult.isSuccess) {
      final msg = widget.databaseResult.message ??
          'Η βάση δεδομένων δεν είναι διαθέσιμη.';
      if (immersive) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _immersiveNavigationMenuButton(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(msg, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(msg, textAlign: TextAlign.center),
        ),
      );
    }

    final theme = Theme.of(context);
    final coreLexicon = ref.watch(coreLexiconProvider);
    final lexiconScopeInfo = _lexiconScopeInfoTooltip(coreLexicon);
    final lexiconCategoriesAsync = ref.watch(lexiconCategoriesProvider);
    final lexiconCategoryOptions = switch (lexiconCategoriesAsync) {
      AsyncData(:final value) => value,
      _ => SettingsService.defaultLexiconCategoriesList,
    };
    final lexiconContinuousAsync = ref.watch(lexiconContinuousScrollProvider);
    final lexiconContinuousScroll = lexiconContinuousAsync.value ?? true;
    final lexiconPageSizeAsync = ref.watch(lexiconPageSizeProvider);
    final lexiconPageSize = lexiconPageSizeAsync.value ?? 40;
    final maxPage =
        _totalCount == 0 ? 0 : ((_totalCount - 1) ~/ lexiconPageSize);
    final listPage = listFilters.page;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

    const langDdWidth = _kLexiconLangDdWidth;
    final sourceDdWidth = computeDropdownMenuWidth(
      context,
      const [
        'Πηγή: Όλες',
        'Πηγή: Εισαγωγή',
        'Πηγή: Χρήστης',
        'Πηγή: Πρόχειρο',
        'Πηγή: Διπλές',
      ],
    );
    final columnGroupsDdWidth = computeDropdownMenuWidth(
      context,
      const [
        'Αυτόματα',
        '1',
        '2',
        '3',
        '4',
      ],
    );
    final diacriticFilterDdWidth = computeDropdownMenuWidth(
      context,
      const [
        'Όλα',
        'Κανένα',
        '1',
        '2',
        '3',
        'Περισσότερα (>3)',
      ],
    );
    return Padding(
      padding: outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (immersive) _immersiveNavigationMenuButton(),
              Expanded(
                child: Text(
                  'Διαχείριση λεξικού',
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: lexiconScopeInfo,
                icon: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Τι εμφανίζεται εδώ;'),
                      content: SingleChildScrollView(
                        child: Text(lexiconScopeInfo),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Κλείσιμο'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Προσθήκη λέξεων στο λεξικό (πολλές, με κενά ή κόμμα)',
                icon: const Text(
                  '✍️',
                  style: TextStyle(fontSize: 36, height: 1),
                ),
                onPressed: _openAddCustomWordDialog,
              ),
              IconButton(
                tooltip: ref.watch(lexiconSpellingPanelProvider).visible
                    ? 'Απόκρυψη πάνελ ορθογραφίας'
                    : 'Εμφάνιση πάνελ ορθογραφίας',
                icon: Icon(
                  ref.watch(lexiconSpellingPanelProvider).visible
                      ? Icons.spellcheck
                      : Icons.spellcheck_outlined,
                  color: ref.watch(lexiconSpellingPanelProvider).visible
                      ? theme.colorScheme.primary
                      : null,
                ),
                onPressed: () => ref
                    .read(lexiconSpellingPanelProvider.notifier)
                    .toggleVisible(),
              ),
              IconButton(
                tooltip: 'Ρυθμίσεις λεξικού (διαδρομές, import, compile)',
                icon: const Icon(Icons.settings),
                onPressed: _openDictionarySettings,
              ),
            ],
          ),
          SizedBox(height: immersive ? 6 : 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final categoryDdLabels = <String>[
                'Κατηγορία: Όλες',
                ...lexiconCategoryOptions.map((c) => 'Κατηγορία: $c'),
                'Κατηγορία: ${AppConfig.lexiconCategoryUnspecified}',
              ];
              final categoryFilterWidth = computeDropdownMenuWidth(
                context,
                categoryDdLabels,
              ).clamp(140.0, 240.0);
              const gaps = 12.0 + 8.0 + 8.0;
              final tailFixed = gaps +
                  langDdWidth +
                  sourceDdWidth +
                  categoryFilterWidth;
              /// Runtime evidence:
              /// H8 measured `searchWidth` ~385.48px στο πρώτο layout,
              /// άρα το 200px υποεκτιμούσε έντονα το πραγματικό απαιτούμενο πλάτος.
              const minSearchWhenScroll = 400.0;
              /// Μικρό περιθώριο ώστε να μην «σπάει» το Row στα όρια (padding Theme).
              const layoutSafetyPx = 24.0;
              final useHorizontalScroll = constraints.maxWidth <
                  tailFixed + minSearchWhenScroll + layoutSafetyPx;

              final searchField = TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Αναζήτηση (normalized)',
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Καθαρισμός',
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              );

              final langDropdown = SizedBox(
                width: langDdWidth,
                height: 40,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      value: listFilters.langFilter,
                      isExpanded: true,
                  hint: const Text('Γλώσσα'),
                  selectedItemBuilder: (context) {
                    return List<Widget>.generate(4, (i) {
                      return Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _lexiconLangFilterSelectedIcon(i),
                      );
                    });
                  },
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: _lexiconLangFilterMenuItem(
                        tooltip: 'Όλες οι γλώσσες',
                        icon: Image.asset(
                          _kLexiconLangAssetAll,
                          height: 30,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.translate, size: 28),
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'el',
                      child: _lexiconLangFilterMenuItem(
                        tooltip: 'Ελληνικά',
                        icon: _lexiconLangFlagImage(_kLexiconLangAssetEl, height: 30),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'en',
                      child: _lexiconLangFilterMenuItem(
                        tooltip: 'English',
                        icon: _lexiconLangFlagImage(_kLexiconLangAssetEn, height: 30),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: DictionaryRepository.kLexiconMixedScriptsFilter,
                      child: _lexiconLangFilterMenuItem(
                        tooltip: 'Λέξεις με ελληνικά και λατινικά γράμματα',
                        icon: Image.asset(
                          _kLexiconLangAssetMix,
                          height: 30,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.text_fields, size: 28),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) async {
                    await ref
                        .read(lexiconListFiltersProvider.notifier)
                        .setLangFilter(v);
                    if (!mounted) return;
                    _refreshList();
                  },
                    ),
                  ),
                ),
              );

              final sourceDropdown = SizedBox(
                width: sourceDdWidth,
                height: 40,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      value: listFilters.sourceFilter,
                      isExpanded: true,
                  hint: const Text('Πηγή'),
                  selectedItemBuilder: (context) {
                    return const [
                      Text('Πηγή: Όλες', overflow: TextOverflow.ellipsis),
                      Text('Πηγή: Εισαγωγή', overflow: TextOverflow.ellipsis),
                      Text('Πηγή: Χρήστης', overflow: TextOverflow.ellipsis),
                      Text('Πηγή: Πρόχειρο', overflow: TextOverflow.ellipsis),
                      Text('Πηγή: Διπλές', overflow: TextOverflow.ellipsis),
                    ];
                  },
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Όλες')),
                    DropdownMenuItem(value: 'imported', child: Text('Εισαγωγή')),
                    DropdownMenuItem(value: 'user', child: Text('Χρήστης')),
                    DropdownMenuItem(
                      value: DictionaryRepository.kLexiconSourceDraft,
                      child: Text('Πρόχειρο'),
                    ),
                    DropdownMenuItem(
                      value: DictionaryRepository.kLexiconPendingFilter,
                      child: Text('Διπλές'),
                    ),
                  ],
                  onChanged: (v) async {
                    await ref
                        .read(lexiconListFiltersProvider.notifier)
                        .setSourceFilter(v);
                    if (!mounted) return;
                    _refreshList();
                  },
                    ),
                  ),
                ),
              );

              final orphanCategory = listFilters.categoryFilter != null &&
                  listFilters.categoryFilter!.isNotEmpty &&
                  !lexiconCategoryOptions.contains(listFilters.categoryFilter) &&
                  listFilters.categoryFilter != AppConfig.lexiconCategoryUnspecified;
              final categoryDropdown = SizedBox(
                width: categoryFilterWidth,
                height: 40,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      value: listFilters.categoryFilter,
                      isExpanded: true,
                  hint: const Text('Κατηγορία'),
                  selectedItemBuilder: (context) {
                    return [
                      const Text('Κατηγορία: Όλες',
                          overflow: TextOverflow.ellipsis),
                      ...lexiconCategoryOptions.map(
                        (c) => Text(
                          'Κατηγορία: $c',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'Κατηγορία: ${AppConfig.lexiconCategoryUnspecified}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (orphanCategory)
                        Text(
                          'Κατηγορία: ${listFilters.categoryFilter}',
                          overflow: TextOverflow.ellipsis,
                        ),
                    ];
                  },
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Όλες'),
                    ),
                    ...lexiconCategoryOptions.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c,
                        child: Text(
                          c,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: AppConfig.lexiconCategoryUnspecified,
                      child: Text(
                        AppConfig.lexiconCategoryUnspecified,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (orphanCategory)
                      DropdownMenuItem<String?>(
                        value: listFilters.categoryFilter,
                        child: Text(
                          listFilters.categoryFilter!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) async {
                    await ref
                        .read(lexiconListFiltersProvider.notifier)
                        .setCategoryFilter(v);
                    if (!mounted) return;
                    _refreshList();
                  },
                    ),
                  ),
                ),
              );

              final rowChildren = <Widget>[
                if (useHorizontalScroll)
                  SizedBox(
                    width: minSearchWhenScroll,
                    child: searchField,
                  )
                else
                  Expanded(
                    child: searchField,
                  ),
                const SizedBox(width: 12),
                langDropdown,
                const SizedBox(width: 8),
                sourceDropdown,
                const SizedBox(width: 8),
                categoryDropdown,
              ];

              if (useHorizontalScroll) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: rowChildren,
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: rowChildren,
              );
            },
          ),
          const SizedBox(height: 8),
          if (_loadError != null)
            Text(_loadError!, style: TextStyle(color: theme.colorScheme.error)),
          if (!_loading)
            LayoutBuilder(
              builder: (context, constraints) {
                const filterBarStripHeight = 40.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: filterBarStripHeight,
                      child: Center(
                        child: Text('Σύνολο: $_totalCount'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: filterBarStripHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                        Tooltip(
                          message: 'Ομάδα στηλών',
                          child: Image.asset(
                            _kNumberOfColumnsIcon,
                            height: 22,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.view_column_outlined,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: columnGroupsDdWidth,
                          height: filterBarStripHeight,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                borderRadius: BorderRadius.circular(12),
                                isDense: true,
                                value: listFilters.columnGroups,
                                isExpanded: true,
                            selectedItemBuilder: (context) {
                              return const [
                                Text(
                                  'Αυτόματα',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '1',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '2',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '3',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '4',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ];
                            },
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Αυτόματα'),
                              ),
                              DropdownMenuItem(value: 1, child: Text('1')),
                              DropdownMenuItem(value: 2, child: Text('2')),
                              DropdownMenuItem(value: 3, child: Text('3')),
                              DropdownMenuItem(value: 4, child: Text('4')),
                            ],
                            onChanged: (v) async {
                              await ref
                                  .read(lexiconListFiltersProvider.notifier)
                                  .setColumnGroups(v);
                              _scheduleContinuousViewportFillAfterLoad();
                            },
                              ),
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            height: filterBarStripHeight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                            Text(
                              'Γράμματα',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 64,
                              height: filterBarStripHeight,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    borderRadius: BorderRadius.circular(12),
                                    isDense: true,
                                    value: listFilters.lettersCompareOp,
                                    isExpanded: true,
                                selectedItemBuilder: (context) => const [
                                  Text('≥'),
                                  Text('≤'),
                                  Text('='),
                                ],
                                items: const [
                                  DropdownMenuItem(
                                    value: '>=',
                                    child: Text('≥'),
                                  ),
                                  DropdownMenuItem(
                                    value: '<=',
                                    child: Text('≤'),
                                  ),
                                  DropdownMenuItem(
                                    value: '=',
                                    child: Text('='),
                                  ),
                                ],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await ref
                                      .read(lexiconListFiltersProvider.notifier)
                                      .setLettersCompareOp(v);
                                  if (!mounted) return;
                                  _refreshList();
                                },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              height: filterBarStripHeight,
                              child: TextField(
                                controller: _lettersCountField,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                maxLength: 3,
                                style: theme.textTheme.bodyMedium,
                                decoration: const InputDecoration(
                                  labelText: 'Αριθμός',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  counterText: '',
                                ),
                                onChanged: (_) {
                                  _lettersFilterDebounce?.cancel();
                                  _lettersFilterDebounce = Timer(
                                    const Duration(milliseconds: 350),
                                    () async {
                                      if (!mounted) return;
                                      await ref
                                          .read(lexiconListFiltersProvider.notifier)
                                          .setLettersCount(
                                            _lettersCountField.text,
                                          );
                                      if (!mounted) return;
                                      _refreshList();
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Tooltip(
                                  message: 'Σημεία Στήξης',
                                  child: Image.asset(
                                    _kPunctuationMarksIcon,
                                    height: 22,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.format_overline,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: diacriticFilterDdWidth,
                                  height: filterBarStripHeight,
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String?>(
                                        borderRadius: BorderRadius.circular(12),
                                        isDense: true,
                                        value: listFilters.diacriticMarksFilter,
                                        isExpanded: true,
                                    selectedItemBuilder: (context) {
                                      return const [
                                        Text(
                                          'Όλα',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Κανένα',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '1',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '2',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '3',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Περισσότερα (>3)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ];
                                    },
                                    items: const [
                                      DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Όλα'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: 'none',
                                        child: Text('Κανένα'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: '1',
                                        child: Text('1'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: '2',
                                        child: Text('2'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: '3',
                                        child: Text('3'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: 'gt3',
                                        child: Text('Περισσότερα (>3)'),
                                      ),
                                    ],
                                    onChanged: (v) async {
                                      await ref
                                          .read(lexiconListFiltersProvider.notifier)
                                          .setDiacriticMarksFilter(v);
                                      if (!mounted) return;
                                      _refreshList();
                                    },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            height: filterBarStripHeight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                            IconButton(
                              tooltip: lexiconContinuousScroll
                                  ? 'Συνεχής κύλιση — πάτημα για σελίδες'
                                  : 'Σελίδες — πάτημα για συνεχή κύλιση',
                              style: IconButton.styleFrom(
                                minimumSize:
                                    const Size(filterBarStripHeight, filterBarStripHeight),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: Icon(
                                lexiconContinuousScroll
                                    ? Icons.swap_vert
                                    : Icons.view_agenda,
                              ),
                              onPressed: () async {
                                final cur = ref
                                        .read(lexiconContinuousScrollProvider)
                                        .value ??
                                    true;
                                final newVal = !cur;
                                final dbSet = await DatabaseHelper.instance.database;
                                await SettingsRepository(dbSet).saveSetting(
                                  'lexicon_continuous_scroll',
                                  newVal.toString(),
                                );
                                ref.invalidate(lexiconContinuousScrollProvider);
                                await ref.read(
                                    lexiconContinuousScrollProvider.future);
                                if (!mounted) return;
                                await ref
                                    .read(lexiconListFiltersProvider.notifier)
                                    .resetPage();
                                if (_verticalTableScroll.hasClients) {
                                  _verticalTableScroll.jumpTo(0);
                                }
                                await _refreshList();
                              },
                            ),
                            if (!lexiconContinuousScroll) ...[
                              IconButton(
                                tooltip: 'Προηγούμενη',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(
                                      filterBarStripHeight, filterBarStripHeight),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: listPage > 0
                                    ? () async {
                                        await ref
                                            .read(lexiconListFiltersProvider.notifier)
                                            .setPage(listPage - 1);
                                        if (!mounted) return;
                                        _refreshList();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Tooltip(
                                message:
                                    'Αλλαγή σελίδας κάθε $lexiconPageSize λέξεις',
                                child: SizedBox(
                                  height: filterBarStripHeight,
                                  child: Center(
                                    child: Text('${listPage + 1} / ${maxPage + 1}'),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Επόμενη',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(
                                      filterBarStripHeight, filterBarStripHeight),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: listPage < maxPage
                                    ? () async {
                                        await ref
                                            .read(lexiconListFiltersProvider.notifier)
                                            .setPage(listPage + 1);
                                        if (!mounted) return;
                                        _refreshList();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                              SizedBox(
                                width: filterBarStripHeight,
                                height: filterBarStripHeight,
                                child: PopupMenuButton<int>(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                style: IconButton.styleFrom(
                                  minimumSize: Size.square(filterBarStripHeight),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                tooltip: 'Λέξεις ανά σελίδα',
                                icon: const Icon(Icons.numbers),
                                onSelected: (v) async {
                                  final dbPs =
                                      await DatabaseHelper.instance.database;
                                  await SettingsRepository(dbPs).saveSetting(
                                    'lexicon_page_size',
                                    '$v',
                                  );
                                  ref.invalidate(lexiconPageSizeProvider);
                                  await ref.read(lexiconPageSizeProvider.future);
                                  if (!mounted) return;
                                  await ref
                                      .read(lexiconListFiltersProvider.notifier)
                                      .resetPage();
                                  await _refreshList();
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 20, child: Text('20 λέξεις')),
                                  PopupMenuItem(
                                      value: 30, child: Text('30 λέξεις')),
                                  PopupMenuItem(
                                      value: 40, child: Text('40 λέξεις')),
                                  PopupMenuItem(
                                      value: 50, child: Text('50 λέξεις')),
                                  PopupMenuItem(
                                      value: 75, child: Text('75 λέξεις')),
                                  PopupMenuItem(
                                      value: 100, child: Text('100 λέξεις')),
                                  PopupMenuItem(
                                      value: 150, child: Text('150 λέξεις')),
                                  PopupMenuItem(
                                      value: 200, child: Text('200 λέξεις')),
                                ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  ],
                );
              },
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _scheduleDictionaryLayoutSync(
                        context,
                        viewportWidth: constraints.maxWidth,
                        viewportHeight: constraints.maxHeight,
                        columnGroups: listFilters.columnGroups,
                      );
                      final tableLayout = ref.watch(dictionaryLayoutProvider);
                      final columnsCount = tableLayout.columnsCount;
                      final gridRowCount = tableLayout.gridRowCount;
                      final footerRows =
                          lexiconContinuousScroll && _loadingMore ? 1 : 0;
                      final listItemCount = gridRowCount + footerRows;

                      return AnimatedBuilder(
                        animation: Listenable.merge(_lexiconWordWidthDuringDrag),
                        builder: (context, _) {
                          final liveDragWidths = _lexiconWordWidthDuringDrag
                              .map((n) => n.value)
                              .toList(growable: false);
                          final groupLayouts =
                              tableLayout.groupLayoutsWithLiveDrag(liveDragWidths);
                          final scrollW =
                              tableLayout.effectiveScrollWidth(groupLayouts);

                          return Scrollbar(
                            controller: _horizontalTableScroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _horizontalTableScroll,
                              scrollDirection: Axis.horizontal,
                              primary: false,
                              child: SizedBox(
                                width: scrollW,
                                height: constraints.maxHeight,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        columnsCount,
                                        (groupIndex) {
                                          final groupLayout =
                                              groupLayouts[groupIndex];
                                          return _lexiconColumnGroupShell(
                                            context: context,
                                            groupIndex: groupIndex,
                                            child: SizedBox(
                                              width: groupLayout.baseTotal,
                                              child: DictionaryLexiconHeaderRow(
                                                wordWidth: groupLayout.wordWidth,
                                                sourceWidth:
                                                    groupLayout.sourceWidth,
                                                categoryWidth:
                                                    groupLayout.categoryWidth,
                                                onWordColumnResizeStart: () =>
                                                    _onLexiconWordColumnResizeStart(
                                                  groupIndex,
                                                  groupLayout.wordWidth,
                                                ),
                                                onWordColumnResizeUpdate: (delta) =>
                                                    _onLexiconWordColumnResizeUpdate(
                                                  groupIndex,
                                                  delta,
                                                ),
                                                onWordColumnResizeEnd: (delta) =>
                                                    _onLexiconWordColumnResizeEnd(
                                                  groupIndex,
                                                  delta,
                                                ),
                                                onWordColumnResizeCancel: () =>
                                                    _onLexiconWordColumnResizeCancel(
                                                  groupIndex,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: _loading
                                          ? const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(24),
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            )
                                          : Scrollbar(
                                              controller: _verticalTableScroll,
                                              thumbVisibility: true,
                                              child: ListView.builder(
                                                controller: _verticalTableScroll,
                                                primary: false,
                                                padding: EdgeInsets.zero,
                                                itemExtent: kDictionaryGridRowExtent,
                                                itemCount: listItemCount,
                                                itemBuilder: (context, i) {
                                                  if (i >= gridRowCount) {
                                                    return SizedBox(
                                                      width: scrollW,
                                                      child: const Center(
                                                        child: SizedBox(
                                                          width: 28,
                                                          height: 28,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: List.generate(
                                                        columnsCount, (colIndex) {
                                                      final groupLayout =
                                                          groupLayouts[colIndex];
                                                      final rowIndex =
                                                          i * columnsCount +
                                                              colIndex;
                                                      if (rowIndex >= _rows.length) {
                                                        return _lexiconColumnGroupShell(
                                                          context: context,
                                                          groupIndex: colIndex,
                                                          child: SizedBox(
                                                            width: groupLayout
                                                                .baseTotal,
                                                          ),
                                                        );
                                                      }
                                                      final r = _rows[rowIndex];
                                                      return _lexiconColumnGroupShell(
                                                        context: context,
                                                        groupIndex: colIndex,
                                                        child: SizedBox(
                                                          width:
                                                              groupLayout.baseTotal,
                                                          child: RepaintBoundary(
                                                            child: DictionaryGridRow(
                                                              key: ValueKey(
                                                                _lexiconRowWidgetKey(
                                                                    r),
                                                              ),
                                                              row: r,
                                                              layout: groupLayout,
                                                              categoryOptions:
                                                                  lexiconCategoryOptions,
                                                              onUpdate: (word, cat) =>
                                                                  _updateLexiconRow(
                                                                    _rows[rowIndex],
                                                                    word,
                                                                    cat,
                                                                  ),
                                                              onDelete: () =>
                                                                  _deleteRow(
                                                                      _rows[rowIndex]),
                                                              onSpellingContextChanged:
                                                                  (word) =>
                                                                      _onSpellingContextFromRow(
                                                                        _rows[
                                                                            rowIndex],
                                                                        word,
                                                                      ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  );
                                                },
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (ref.watch(lexiconSpellingPanelProvider).visible) ...[
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  SizedBox(
                    width: kLexiconSpellingPanelWidth,
                    child: LexiconSpellingPanel(
                      onApplySuggestion: _applySpellingSuggestion,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
