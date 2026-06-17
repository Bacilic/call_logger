import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/dictionary_repository.dart';
import '../../../core/services/settings_service.dart';
import '../dictionary_table_layout.dart';

const double kDictionaryGridActionsWidth = 108;

/// Σταθερό ύψος γραμμής πίνακα λεξικού (για [ListView.itemExtent]).
const double kDictionaryGridRowExtent = 48.0;

/// Ζώνη ανάμεσα σε «Λέξη» και «Πηγή»· ίδιο πλάτος στην επικεφαλίδα (λαβή) και στις γραμμές (κενό).
const double kDictionaryWordColumnResizeHandleWidth = 12.0;

const _kLexiconTooltipAssetEl = 'assets/greece_flag.png';
const _kLexiconTooltipAssetEn = 'assets/united_kingdom_flag.png';
const _kLexiconTooltipAssetMix = 'assets/greek_english_mix.png';
const _kLexiconTooltipAssetFallback = 'assets/greek_english.png';

/// Κείμενο δίπλα στη σημαία στο tooltip· κενό για el/en (μόνο εικόνα).
String _lexiconLangTooltipLabel(String lang) {
  switch (lang) {
    case 'el':
    case 'en':
      return '';
    case DictionaryRepository.kLexiconLanguageMix:
      return 'Μικτή γραφή';
    default:
      return lang.isEmpty ? '' : lang;
  }
}

String _lexiconLangTooltipAsset(String lang) {
  switch (lang) {
    case 'el':
      return _kLexiconTooltipAssetEl;
    case 'en':
      return _kLexiconTooltipAssetEn;
    case DictionaryRepository.kLexiconLanguageMix:
      return _kLexiconTooltipAssetMix;
    default:
      return _kLexiconTooltipAssetFallback;
  }
}

/// Γραμμή επικεφαλίδας πίνακα λεξικού (Λέξη, Πηγή, Κατηγορία, Ενέργειες).
class DictionaryLexiconHeaderRow extends StatelessWidget {
  const DictionaryLexiconHeaderRow({
    super.key,
    required this.wordWidth,
    required this.sourceWidth,
    required this.categoryWidth,
    this.onWordColumnResizeStart,
    this.onWordColumnResizeUpdate,
    this.onWordColumnResizeEnd,
    this.onWordColumnResizeCancel,
  });

  final double wordWidth;
  final double sourceWidth;
  final double categoryWidth;
  /// Έναρξη σύρσιμου λαβής (αποθήκευση βάσης πλάτους).
  final VoidCallback? onWordColumnResizeStart;
  /// Συσσωρευμένη μεταβολή πλάτους κατά το σύρσιμο (throttled).
  final ValueChanged<double>? onWordColumnResizeUpdate;
  /// Οριστική μεταβολή στο τέλος του σύρσιμου.
  final ValueChanged<double>? onWordColumnResizeEnd;
  /// Ακύρωση σύρσιμου — επαναφορά χωρίς αποθήκευση.
  final VoidCallback? onWordColumnResizeCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: wordWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Λέξη',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _LexiconWordColumnResizeHandle(
              onResizeStart: onWordColumnResizeStart,
              onResizeUpdate: onWordColumnResizeUpdate,
              onResizeEnd: onWordColumnResizeEnd,
              onResizeCancel: onWordColumnResizeCancel,
            ),
            SizedBox(
              width: sourceWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Πηγή',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: categoryWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Κατηγορία',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: kDictionaryGridActionsWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Ενέργειες', style: style, textAlign: TextAlign.end),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LexiconWordColumnResizeHandle extends StatefulWidget {
  const _LexiconWordColumnResizeHandle({
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
    this.onResizeCancel,
  });

  final VoidCallback? onResizeStart;
  final ValueChanged<double>? onResizeUpdate;
  final ValueChanged<double>? onResizeEnd;
  final VoidCallback? onResizeCancel;

  @override
  State<_LexiconWordColumnResizeHandle> createState() =>
      _LexiconWordColumnResizeHandleState();
}

class _LexiconWordColumnResizeHandleState extends State<_LexiconWordColumnResizeHandle> {
  static const _previewThrottle = Duration(milliseconds: 16);

  bool _isHovered = false;
  bool _isDragging = false;
  double _accumulatedDelta = 0;
  DateTime? _lastPreviewEmit;
  OverlayEntry? _dragCursorOverlay;

  void _showDragCursorOverlay() {
    _removeDragCursorOverlay();
    final overlay = Overlay.of(context, rootOverlay: true);
    _dragCursorOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.transparent,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_dragCursorOverlay!);
  }

  void _removeDragCursorOverlay() {
    _dragCursorOverlay?.remove();
    _dragCursorOverlay = null;
  }

  void _emitPreview({bool force = false}) {
    final cb = widget.onResizeUpdate;
    if (cb == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastPreviewEmit != null &&
        now.difference(_lastPreviewEmit!) < _previewThrottle) {
      return;
    }
    _lastPreviewEmit = now;
    cb(_accumulatedDelta);
  }

  void _onHorizontalDragStart(DragStartDetails _) {
    _showDragCursorOverlay();
    widget.onResizeStart?.call();
    setState(() {
      _isDragging = true;
      _accumulatedDelta = 0;
      _lastPreviewEmit = null;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _accumulatedDelta += details.delta.dx;
    setState(() {});
    _emitPreview();
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    final total = _accumulatedDelta;
    _removeDragCursorOverlay();
    _emitPreview(force: true);
    widget.onResizeEnd?.call(total);
    setState(() {
      _isDragging = false;
      _accumulatedDelta = 0;
      _lastPreviewEmit = null;
    });
  }

  void _onHorizontalDragCancel() {
    _removeDragCursorOverlay();
    widget.onResizeCancel?.call();
    setState(() {
      _isDragging = false;
      _accumulatedDelta = 0;
      _lastPreviewEmit = null;
    });
  }

  @override
  void dispose() {
    _removeDragCursorOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showActive = _isHovered || _isDragging;
    return SizedBox(
      width: kDictionaryWordColumnResizeHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) {
          if (!_isDragging) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onHorizontalDragCancel: _onHorizontalDragCancel,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: _isDragging ? 4 : (showActive ? 3 : 2),
              height: _isDragging ? 32 : (showActive ? 26 : 18),
              decoration: BoxDecoration(
                color: _isDragging
                    ? theme.colorScheme.primary
                    : showActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.85)
                        : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
                boxShadow: _isDragging
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.45),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Μία γραμμή «κελιών» λεξικού με αυτόματη αποθήκευση στο blur / Enter.
class DictionaryGridRow extends StatefulWidget {
  const DictionaryGridRow({
    super.key,
    required this.row,
    required this.layout,
    required this.categoryOptions,
    required this.onUpdate,
    required this.onDelete,
    this.onSpellingContextChanged,
  });

  final Map<String, dynamic> row;
  final DictionaryTableLayout layout;
  /// Επιλογές dropdown (από ρυθμίσεις λεξικού).
  final List<String> categoryOptions;
  final Future<void> Function(String displayWord, String category) onUpdate;
  final Future<void> Function() onDelete;
  /// Ενημέρωση πάνελ ορθογραφίας όταν αλλάζει εστίαση ή κείμενο στο πεδίο λέξης.
  final void Function(String word)? onSpellingContextChanged;

  double get wordWidth => layout.wordWidth;
  double get sourceWidth => layout.sourceWidth;
  double get categoryWidth => layout.categoryWidth;

  @override
  State<DictionaryGridRow> createState() => _DictionaryGridRowState();
}

class _DictionaryGridRowState extends State<DictionaryGridRow> {
  late final TextEditingController _wordCtrl;
  late final FocusNode _wordFocus;
  late String _lastWord;
  late String _lastCat;
  late String _categoryValue;

  List<String> get _selectableCategoryOptions {
    final base = widget.categoryOptions.isNotEmpty
        ? List<String>.from(widget.categoryOptions)
        : SettingsService.defaultLexiconCategoriesList;
    return base
        .where((c) => c != AppConfig.lexiconCategoryUnspecified)
        .toList();
  }

  List<DropdownMenuItem<String>> _buildCategoryDropdownItems(BuildContext context) {
    final selectable = _selectableCategoryOptions;
    final itemStyle = Theme.of(context).textTheme.bodySmall;
    if (_categoryValue == AppConfig.lexiconCategoryUnspecified) {
      return [
        DropdownMenuItem<String>(
          value: AppConfig.lexiconCategoryUnspecified,
          enabled: false,
          child: Text(
            AppConfig.lexiconCategoryUnspecified,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: itemStyle,
          ),
        ),
        ...selectable.map(
          (e) => DropdownMenuItem<String>(
            value: e,
            child: Text(
              e,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: itemStyle,
            ),
          ),
        ),
      ];
    }
    final opts = List<String>.from(selectable);
    if (_categoryValue.isNotEmpty &&
        !opts.contains(_categoryValue) &&
        _categoryValue != AppConfig.lexiconCategoryUnspecified) {
      opts.add(_categoryValue);
    }
    return opts
        .map(
          (e) => DropdownMenuItem<String>(
            value: e,
            child: Text(
              e,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: itemStyle,
            ),
          ),
        )
        .toList();
  }

  String _normalizeCategoryFromRow() {
    final raw = (widget.row['cat'] as String?)?.trim() ?? '';
    if (raw == AppConfig.lexiconCategoryUnspecified) {
      return AppConfig.lexiconCategoryUnspecified;
    }
    final opts = widget.categoryOptions.isNotEmpty
        ? widget.categoryOptions
        : SettingsService.defaultLexiconCategoriesList;
    if (raw.isEmpty) return opts.first;
    if (opts.contains(raw)) return raw;
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _wordCtrl = TextEditingController(
      text: widget.row['display_word'] as String? ?? '',
    );
    _lastWord = _wordCtrl.text;
    _categoryValue = _normalizeCategoryFromRow();
    _lastCat = _categoryValue;
    _wordFocus = FocusNode();
    _wordFocus.addListener(_onWordFocusChanged);
    _wordCtrl.addListener(_onWordTextChanged);
  }

  @override
  void didUpdateWidget(covariant DictionaryGridRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newWord = widget.row['display_word'] as String? ?? '';
    final oldWord = oldWidget.row['display_word'] as String? ?? '';
    if (newWord != oldWord) {
      _wordCtrl.text = newWord;
      _lastWord = newWord;
      final nextCat = _normalizeCategoryFromRow();
      if (nextCat != _categoryValue) {
        setState(() => _categoryValue = nextCat);
      }
      _lastCat = _categoryValue;
      return;
    }
    if (!_wordFocus.hasFocus) {
      if (newWord != _wordCtrl.text) _wordCtrl.text = newWord;
      final nextCat = _normalizeCategoryFromRow();
      if (nextCat != _categoryValue) {
        setState(() => _categoryValue = nextCat);
      }
      _lastWord = _wordCtrl.text;
      _lastCat = _categoryValue;
    }
  }

  @override
  void dispose() {
    _wordFocus.removeListener(_onWordFocusChanged);
    _wordCtrl.removeListener(_onWordTextChanged);
    _wordFocus.dispose();
    _wordCtrl.dispose();
    super.dispose();
  }

  void _notifySpellingContext() {
    final cb = widget.onSpellingContextChanged;
    if (cb == null) return;
    cb(_wordCtrl.text);
  }

  void _onWordTextChanged() {
    if (!_wordFocus.hasFocus) return;
    _notifySpellingContext();
  }

  void _onWordFocusChanged() {
    if (_wordFocus.hasFocus) {
      _notifySpellingContext();
      return;
    }
    _commitIfChanged();
  }

  Future<void> _commitIfChanged() async {
    final w = _wordCtrl.text.trim();
    final c = _categoryValue;
    if (w == _lastWord && c == _lastCat) return;
    if (w.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η λέξη δεν μπορεί να είναι κενή')),
        );
      }
      _wordCtrl.text = _lastWord;
      return;
    }
    try {
      await widget.onUpdate(w, c);
      if (mounted) {
        _lastWord = w;
        _lastCat = c;
      }
    } catch (_) {
      if (mounted) {
        _wordCtrl.text = _lastWord;
        setState(() => _categoryValue = _lastCat);
      }
    }
  }

  Future<void> _onCategoryChanged(String? value) async {
    if (value == null) return;
    setState(() => _categoryValue = value);
    final w = _wordCtrl.text.trim();
    if (w.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Συμπληρώστε πρώτα τη λέξη')),
        );
      }
      setState(() => _categoryValue = _lastCat);
      return;
    }
    if (w == _lastWord && value == _lastCat) return;
    try {
      await widget.onUpdate(w, value);
      if (mounted) {
        _lastWord = w;
        _lastCat = value;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _categoryValue = _lastCat);
      }
    }
  }

  static InputDecoration _cellDecoration(BuildContext context) {
    return InputDecoration.collapsed(hintText: '').copyWith(
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final src = widget.row['src'] as String? ?? '';
    final srcLabel = DictionaryRepository.lexiconSourceUiLabel(src);
    final lang = widget.row['lang'] as String? ?? '';
    final pending = (widget.row['pending_user'] as int? ?? 0) == 1;

    final items = _buildCategoryDropdownItems(context);
    final safeValue = items.any((e) => e.value == _categoryValue)
        ? _categoryValue
        : (items.isNotEmpty ? items.first.value! : 'Γενική');

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: widget.wordWidth,
              child: TextField(
                controller: _wordCtrl,
                focusNode: _wordFocus,
                decoration: _cellDecoration(context),
                style: theme.textTheme.bodyLarge,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  _commitIfChanged();
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            SizedBox(width: kDictionaryWordColumnResizeHandleWidth),
            SizedBox(
              width: widget.sourceWidth,
              child: Tooltip(
                richMessage: WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _LexiconSourceTooltipRich(
                    lang: lang,
                    pending: pending,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(
                    srcLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: widget.categoryWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: safeValue,
                    isExpanded: true,
                    isDense: true,
                    style: theme.textTheme.bodySmall,
                    items: items,
                    onChanged: _onCategoryChanged,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: kDictionaryGridActionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Διαγραφή',
                    icon: const Text(
                      '🧹',
                      style: TextStyle(fontSize: 20, height: 1),
                    ),
                    onPressed: () => widget.onDelete(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Περιεχόμενο tooltip στήλης «Πηγή»: σημαία· για mix και «Μικτή γραφή»· προαιρετικά «Διπλές».
class _LexiconSourceTooltipRich extends StatelessWidget {
  const _LexiconSourceTooltipRich({
    required this.lang,
    required this.pending,
  });

  final String lang;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(color: cs.onInverseSurface) ??
        TextStyle(fontSize: 12, color: cs.onInverseSurface);
    final asset = _lexiconLangTooltipAsset(lang);
    final label = _lexiconLangTooltipLabel(lang);
    final hasLabel = label.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            asset,
            height: 22,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(
              Icons.flag_outlined,
              size: 20,
              color: cs.onInverseSurface,
            ),
          ),
          if (hasLabel) ...[
            const SizedBox(width: 8),
            Text(label, style: style),
          ],
          if (pending) ...[
            if (hasLabel)
              Text(' · ', style: style)
            else
              const SizedBox(width: 8),
            Text('Διπλές', style: style),
          ],
        ],
      ),
    );
  }
}
