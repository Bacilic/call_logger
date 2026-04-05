import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/errors/dictionary_export_exception.dart';
import '../../../core/models/dictionary_import_mode.dart';
import '../../../core/providers/greek_dictionary_provider.dart';
import '../../../core/providers/lexicon_categories_provider.dart';
import '../../../core/providers/lexicon_full_mode_provider.dart';
import '../../../core/providers/lexicon_language_recalc_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/providers/shell_navigation_intent_provider.dart';
import '../../../core/providers/spell_check_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/services/dictionary_service.dart';
import '../../../core/services/master_dictionary_service.dart';
import '../dictionary_table_layout.dart';
import '../providers/lexicon_scroll_provider.dart';
import '../widgets/dictionary_grid_row.dart';
import '../widgets/dictionary_settings_dialog.dart';

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
  static const double _lexiconWordColumnMin = 88.0;
  static const double _lexiconWordColumnMax = 2000.0;

  final _master = MasterDictionaryService();
  final _searchCtrl = TextEditingController();
  final _horizontalTableScroll = ScrollController();
  final _verticalTableScroll = ScrollController();

  String? _langFilter;
  String? _sourceFilter;
  String? _categoryFilter;

  int _page = 0;
  int _totalCount = 0;
  /// null = αριθμός στηλών από πλάτος· 1–4 = σταθερός αριθμός ομάδων στηλών.
  int? _lexiconColumnGroups;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;
  /// null = αυτόματο πλάτος από περιεχόμενο· αλλιώς πλάτος που όρισε ο χρήστης (λαβή).
  double? _lexiconWordColumnWidthUser;

  String _lettersCompareOp = '>=';
  final _lettersCountField = TextEditingController();
  Timer? _lettersFilterDebounce;
  /// null = όλα· `none` | `1` | `2` | `3` | `gt3`
  String? _diacriticMarksFilter;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.databaseResult.isSuccess) {
      _refreshList();
    } else {
      setState(() => _loading = false);
    }
    _searchCtrl.addListener(_onSearchChanged);
    _verticalTableScroll.addListener(_onVerticalLexiconScroll);
  }

  void _onVerticalLexiconScroll() {
    if (!mounted) return;
    final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
    if (!continuous || _loadingMore || _loading) return;
    if (_rows.isEmpty || _rows.length >= _totalCount) return;
    final c = _verticalTableScroll;
    if (!c.hasClients) return;
    const threshold = 400.0;
    final pos = c.position;
    final atEnd = pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - threshold;
    if (atEnd) {
      _refreshList(append: true);
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _page = 0);
        _refreshList();
      }
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
    super.dispose();
  }

  Future<void> _refreshList({bool append = false}) async {
    if (!widget.databaseResult.isSuccess) return;
    final continuous = ref.read(lexiconContinuousScrollProvider).value ?? true;
    final pageSize = ref.read(lexiconPageSizeProvider).value ?? 40;

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
          lettersOp = _lettersCompareOp;
          lettersVal = p;
        }
      }

      if (append) {
        final rows = await DatabaseHelper.instance.queryCombinedLexiconPage(
          language: _langFilter,
          source: _sourceFilter,
          category: _categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly: _sourceFilter == DatabaseHelper.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: _diacriticMarksFilter,
          limit: pageSize,
          offset: _rows.length,
        );
        if (mounted) {
          setState(() {
            if (rows.isEmpty) {
              _totalCount = _rows.length;
            } else {
              _rows = [..._rows, ...rows];
            }
            _loadingMore = false;
          });
        }
      } else {
        final count = await DatabaseHelper.instance.countCombinedLexiconRows(
          language: _langFilter,
          source: _sourceFilter,
          category: _categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly: _sourceFilter == DatabaseHelper.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: _diacriticMarksFilter,
        );
        final offset = continuous ? 0 : _page * pageSize;
        final rows = await DatabaseHelper.instance.queryCombinedLexiconPage(
          language: _langFilter,
          source: _sourceFilter,
          category: _categoryFilter,
          normalizedSearch: search.isEmpty ? null : search,
          pendingOnly: _sourceFilter == DatabaseHelper.kLexiconPendingFilter,
          lettersCountOp: lettersOp,
          lettersCountValue: lettersVal,
          diacriticMarksFilter: _diacriticMarksFilter,
          limit: pageSize,
          offset: offset,
        );
        if (mounted) {
          setState(() {
            _totalCount = count;
            _rows = rows;
            _loading = false;
            _loadingMore = false;
          });
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
      ref.invalidate(greekDictionaryServiceProvider);
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
    final r = await FilePicker.platform.pickFiles(
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
      final existing = await DatabaseHelper.instance.countFullDictionaryTotal();
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
      ref.invalidate(greekDictionaryServiceProvider);
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

  Future<void> _updateLexiconRow(
    Map<String, dynamic> row,
    String displayWord,
    String category,
  ) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';
    final display = row['display_word'] as String? ?? '';
    final src = row['src'] as String? ?? '';
    final isDraft = entryId == null || src == DatabaseHelper.kLexiconSourceDraft;
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
        await DatabaseHelper.instance.upsertFullDictionaryCategory(
          id: entryId,
          category: category,
          newDisplayWord: newWord != display ? newWord : null,
        );
        if ((row['pending_user'] as int? ?? 0) == 1 && newWord != display) {
          final newKey = DictionaryService.canonicalLexiconKey(newWord);
          if (newKey != normKey) {
            await DatabaseHelper.instance.updateUserDictionaryWordKey(normKey, newKey);
          }
        }
      }
      await _refreshList();
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

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';
    final src = row['src'] as String? ?? '';
    final isDraft = entryId == null || src == DatabaseHelper.kLexiconSourceDraft;

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
      if (isDraft) {
        await DatabaseHelper.instance.deleteUserDictionaryWord(normKey);
      } else {
        await DatabaseHelper.instance.hardDeleteFullDictionaryById(entryId);
        await DatabaseHelper.instance.deleteUserDictionaryWord(normKey);
      }
      await _refreshList();
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

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(lexiconMasterDataRevisionProvider, (prev, next) {
      _refreshList();
    });

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
                tooltip: 'Προσθήκη λέξεων στο λεξικό (πολλές, με κενά ή κόμμα)',
                icon: const Text(
                  '✍️',
                  style: TextStyle(fontSize: 36, height: 1),
                ),
                onPressed: _openAddCustomWordDialog,
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
                      value: _langFilter,
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
                      value: DatabaseHelper.kLexiconMixedScriptsFilter,
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
                  onChanged: (v) {
                    setState(() {
                      _langFilter = v;
                      _page = 0;
                    });
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
                      value: _sourceFilter,
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
                      value: DatabaseHelper.kLexiconSourceDraft,
                      child: Text('Πρόχειρο'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseHelper.kLexiconPendingFilter,
                      child: Text('Διπλές'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _sourceFilter = v;
                      _page = 0;
                    });
                    _refreshList();
                  },
                    ),
                  ),
                ),
              );

              final orphanCategory = _categoryFilter != null &&
                  _categoryFilter!.isNotEmpty &&
                  !lexiconCategoryOptions.contains(_categoryFilter) &&
                  _categoryFilter != AppConfig.lexiconCategoryUnspecified;
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
                      value: _categoryFilter,
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
                          'Κατηγορία: $_categoryFilter',
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
                        value: _categoryFilter,
                        child: Text(
                          _categoryFilter!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _categoryFilter = v;
                      _page = 0;
                    });
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
                                value: _lexiconColumnGroups,
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
                            onChanged: (v) {
                              setState(() => _lexiconColumnGroups = v);
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
                                    value: _lettersCompareOp,
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
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    _lettersCompareOp = v;
                                    _page = 0;
                                  });
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
                                    () {
                                      if (!mounted) return;
                                      setState(() => _page = 0);
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
                                        value: _diacriticMarksFilter,
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
                                    onChanged: (v) {
                                      setState(() {
                                        _diacriticMarksFilter = v;
                                        _page = 0;
                                      });
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
                                await DatabaseHelper.instance.setSetting(
                                  'lexicon_continuous_scroll',
                                  newVal.toString(),
                                );
                                ref.invalidate(lexiconContinuousScrollProvider);
                                await ref.read(
                                    lexiconContinuousScrollProvider.future);
                                if (!mounted) return;
                                setState(() => _page = 0);
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
                                onPressed: _page > 0
                                    ? () {
                                        setState(() => _page--);
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
                                    child: Text('${_page + 1} / ${maxPage + 1}'),
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
                                onPressed: _page < maxPage
                                    ? () {
                                        setState(() => _page++);
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
                                  await DatabaseHelper.instance.setSetting(
                                    'lexicon_page_size',
                                    '$v',
                                  );
                                  ref.invalidate(lexiconPageSizeProvider);
                                  await ref.read(lexiconPageSizeProvider.future);
                                  if (!mounted) return;
                                  setState(() => _page = 0);
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rowsForLayout =
                    _loading ? <Map<String, dynamic>>[] : _rows;
                final baseLayout = computeDictionaryTableLayout(
                  context: context,
                  rows: rowsForLayout,
                  viewportWidth: constraints.maxWidth,
                );
                final wordWidth = (_lexiconWordColumnWidthUser ??
                        baseLayout.wordWidth)
                    .clamp(_lexiconWordColumnMin, _lexiconWordColumnMax);
                final layout = DictionaryTableLayout(
                  wordWidth: wordWidth,
                  sourceWidth: baseLayout.sourceWidth,
                  categoryWidth: baseLayout.categoryWidth,
                );
                const groupSeparatorWidth = 3.0;
                final autoColumns = math.max(
                  1,
                  (constraints.maxWidth + groupSeparatorWidth) ~/
                      (layout.baseTotal + groupSeparatorWidth),
                );
                final int columnsCount = _lexiconColumnGroups == null
                    ? autoColumns
                    : math.min(4, math.max(1, _lexiconColumnGroups!));
                final totalWidthNeeded = layout.baseTotal * columnsCount +
                    (columnsCount > 0 ? (columnsCount - 1) * groupSeparatorWidth : 0);
                final scrollW = math.max(constraints.maxWidth, totalWidthNeeded);
                final gridRowCount =
                    columnsCount == 0 ? 0 : (_rows.length / columnsCount).ceil();
                final footerRows =
                    lexiconContinuousScroll && _loadingMore ? 1 : 0;
                final listItemCount = gridRowCount + footerRows;

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
                              (groupIndex) => _lexiconColumnGroupShell(
                                context: context,
                                groupIndex: groupIndex,
                                child: SizedBox(
                                  width: layout.baseTotal,
                                  child: DictionaryLexiconHeaderRow(
                                    wordWidth: layout.wordWidth,
                                    sourceWidth: layout.sourceWidth,
                                    categoryWidth: layout.categoryWidth,
                                    onWordColumnResize: (delta) {
                                      setState(() {
                                        final cur = _lexiconWordColumnWidthUser ??
                                            baseLayout.wordWidth;
                                        _lexiconWordColumnWidthUser =
                                            (cur + delta).clamp(
                                          _lexiconWordColumnMin,
                                          _lexiconWordColumnMax,
                                        );
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : Scrollbar(
                                    controller: _verticalTableScroll,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller: _verticalTableScroll,
                                      primary: false,
                                      padding: EdgeInsets.zero,
                                      itemCount: listItemCount,
                                      itemBuilder: (context, i) {
                                        if (i >= gridRowCount) {
                                          return SizedBox(
                                            width: scrollW,
                                            height: 48,
                                            child: const Center(
                                              child: SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: CircularProgressIndicator(
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
                                            final rowIndex =
                                                i * columnsCount + colIndex;
                                            if (rowIndex >= _rows.length) {
                                              return _lexiconColumnGroupShell(
                                                context: context,
                                                groupIndex: colIndex,
                                                child: SizedBox(
                                                    width: layout.baseTotal),
                                              );
                                            }
                                            final r = _rows[rowIndex];
                                            final normKey =
                                                r['norm_key'] as String? ?? '';
                                            final entryId = r['entry_id'];
                                            return _lexiconColumnGroupShell(
                                              context: context,
                                              groupIndex: colIndex,
                                              child: SizedBox(
                                                width: layout.baseTotal,
                                                child: DictionaryGridRow(
                                                  key: ValueKey(
                                                      'lex_${normKey}_$entryId'),
                                                  row: r,
                                                  wordWidth: layout.wordWidth,
                                                  sourceWidth: layout.sourceWidth,
                                                  categoryWidth:
                                                      layout.categoryWidth,
                                                  categoryOptions:
                                                      lexiconCategoryOptions,
                                                  onUpdate: (word, cat) =>
                                                      _updateLexiconRow(
                                                          r, word, cat),
                                                  onDelete: () => _deleteRow(r),
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
            ),
          ),
        ],
      ),
    );
  }
}
