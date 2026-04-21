import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../models/department_model.dart';

/// Επιλογή autocomplete: τμήμα καταλόγου + αν είναι τοποθετημένο σε διαθέσιμο φύλλο χάρτη.
class _DeptMapOption {
  const _DeptMapOption({
    required this.department,
    required this.isPlacedOnMap,
  });

  final DepartmentModel department;
  final bool isPlacedOnMap;
}

bool _departmentPlacedOnMap(
  DepartmentModel d,
  List<BuildingMapFloor> floors,
) {
  final floorIds = floors.map((f) => f.id).toSet();
  final mf = d.mapFloor?.trim();
  if (mf == null || mf.isEmpty) return false;
  final fid = int.tryParse(mf);
  return fid != null && floorIds.contains(fid);
}

/// Όλα τα τμήματα που ταιριάζουν στην αναζήτηση: πρώτα όσα είναι στο χάρτη, μετά τα υπόλοιπα· αλφαβητικά μέσα σε κάθε ομάδα.
List<_DeptMapOption> _departmentMapOptions({
  required LookupService? lookup,
  required String query,
  required List<BuildingMapFloor> floors,
}) {
  if (lookup == null || floors.isEmpty) return const [];
  final searched = lookup.searchDepartments(query.trim());
  final opts = searched
      .map(
        (d) => _DeptMapOption(
          department: d,
          isPlacedOnMap: _departmentPlacedOnMap(d, floors),
        ),
      )
      .toList();
  opts.sort((a, b) {
    if (a.isPlacedOnMap != b.isPlacedOnMap) {
      return a.isPlacedOnMap ? -1 : 1;
    }
    return a.department.name.compareTo(b.department.name);
  });
  return opts;
}

/// Πεδίο αναζήτησης τμήματος στον χάρτη (προβολή): `Autocomplete` όπως στην οθόνη κλήσεων.
class BuildingMapDepartmentSearchField extends StatefulWidget {
  const BuildingMapDepartmentSearchField({
    super.key,
    required this.enabled,
    required this.lookupService,
    required this.floors,
    required this.controller,
    required this.focusNode,
    required this.onNavigateToDepartment,
    required this.onSubmitFallback,
  });

  final bool enabled;
  final LookupService? lookupService;
  final List<BuildingMapFloor> floors;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Επιλογή τμήματος που **είναι** στο χάρτη.
  final Future<void> Function(DepartmentModel department) onNavigateToDepartment;

  /// Enter χωρίς επιλεγμένη πρόταση / fallback substring ([jumpToDepartmentFromSearch]).
  final Future<void> Function(String rawQuery) onSubmitFallback;

  @override
  State<BuildingMapDepartmentSearchField> createState() =>
      _BuildingMapDepartmentSearchFieldState();
}

class _BuildingMapDepartmentSearchFieldState
    extends State<BuildingMapDepartmentSearchField> {
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();

  /// Μήνυμα όταν επιλέγεται τμήμα που δεν είναι τοποθετημένο στο χάρτη.
  String? _offMapNotice;

  /// Κατά την προγραμματιστική ενημέρωση του controller (μετά από επιλογή) ώστε να μη «σβήνει» το μήνυμα ο listener.
  bool _ignoreControllerListener = false;

  @override
  void initState() {
    super.initState();
    _typedQuery = widget.controller.text;
    widget.controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(covariant BuildingMapDepartmentSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      widget.controller.addListener(_onTextChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChange);
    _optionsScrollController.dispose();
    super.dispose();
  }

  void _onTextChange() {
    if (_ignoreControllerListener) return;
    if (_isKeyboardPreview) return;
    final currentText = widget.controller.text;
    if (_typedQuery != currentText) {
      _typedQuery = currentText;
    }
    if (currentText.trim().isEmpty) {
      _keyboardOptionIndex = -1;
      _lastAutoScrollIndex = -1;
    }
    if (mounted && _offMapNotice != null) {
      setState(() => _offMapNotice = null);
    }
  }

  void _setControllerText(TextEditingController c, String value) {
    _ignoreControllerListener = true;
    c.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _ignoreControllerListener = false;
  }

  List<_DeptMapOption> _options(String query) {
    return _departmentMapOptions(
      lookup: widget.lookupService,
      query: query,
      floors: widget.floors,
    );
  }

  Future<void> _commitOption(_DeptMapOption opt) async {
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _isKeyboardPreview = false;
    _setControllerText(widget.controller, opt.department.name);
    _typedQuery = opt.department.name;
    if (!opt.isPlacedOnMap) {
      if (mounted) {
        setState(() {
          _offMapNotice = 'Το τμήμα δεν βρέθηκε στο χάρτη.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _offMapNotice = null);
    }
    await widget.onNavigateToDepartment(opt.department);
  }

  Future<void> _handleSubmitRaw() async {
    final lookup = widget.lookupService;
    final trimmed = widget.controller.text.trim();
    if (lookup != null && trimmed.isNotEmpty) {
      final byName = lookup.findDepartmentByName(trimmed);
      if (byName != null) {
        await _commitOption(
          _DeptMapOption(
            department: byName,
            isPlacedOnMap: _departmentPlacedOnMap(byName, widget.floors),
          ),
        );
        return;
      }
    }
    await widget.onSubmitFallback(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lookup = widget.lookupService;
    final enabled = widget.enabled;

    final noticeStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (!enabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Αναζήτηση τμήματος (όλα τα φύλλα)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );
    }

    final fieldColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Autocomplete<_DeptMapOption>(
          displayStringForOption: (o) => o.department.name,
          focusNode: widget.focusNode,
          textEditingController: widget.controller,
          optionsBuilder: (TextEditingValue value) {
            final effectiveText =
                _isKeyboardPreview ? _typedQuery : value.text;
            return _departmentMapOptions(
              lookup: lookup,
              query: effectiveText,
              floors: widget.floors,
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final optionsList = options.toList();
            final muted = theme.colorScheme.onSurface.withValues(alpha: 0.42);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                color: theme.colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    minWidth: 280,
                  ),
                  child: ListView.builder(
                    controller: _optionsScrollController,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: optionsList.length,
                    itemBuilder: (context, index) {
                      final opt = optionsList[index];
                      final frameworkHighlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      final keyboardHighlighted =
                          _keyboardOptionIndex >= 0 &&
                          _keyboardOptionIndex == index;
                      final isHighlighted = _isKeyboardPreview
                          ? keyboardHighlighted
                          : frameworkHighlighted;
                      if (isHighlighted && _isKeyboardPreview) {
                        if (_lastAutoScrollIndex != index) {
                          _lastAutoScrollIndex = index;
                          syncAutocompleteHighlightedListScroll(
                            controller: _optionsScrollController,
                            highlightedIndex: index,
                            itemExtent: 48,
                            viewportExtent: 240,
                          );
                        }
                      }
                      return ListTile(
                        dense: true,
                        selected: isHighlighted,
                        selectedTileColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        title: Text(
                          opt.department.name,
                          style: opt.isPlacedOnMap
                              ? null
                              : theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                        ),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            );
          },
          onSelected: (option) {
            _commitOption(option);
          },
          fieldViewBuilder:
              (context, textController, focusNodeParam, onFieldSubmitted) {
            return Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                final options = _options(_typedQuery);
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (options.isEmpty) return KeyEventResult.ignored;
                  _keyboardOptionIndex =
                      (_keyboardOptionIndex + 1).clamp(0, options.length - 1);
                  _isKeyboardPreview = true;
                  _setControllerText(
                    textController,
                    options[_keyboardOptionIndex].department.name,
                  );
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  if (options.isEmpty) return KeyEventResult.ignored;
                  _keyboardOptionIndex = _keyboardOptionIndex <= 0
                      ? 0
                      : _keyboardOptionIndex - 1;
                  _isKeyboardPreview = true;
                  _setControllerText(
                    textController,
                    options[_keyboardOptionIndex].department.name,
                  );
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    options.isNotEmpty &&
                    _keyboardOptionIndex >= 0 &&
                    _keyboardOptionIndex < options.length) {
                  _commitOption(options[_keyboardOptionIndex]);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: textController,
                focusNode: focusNodeParam,
                spellCheckConfiguration: platformSpellCheckConfiguration,
                decoration: InputDecoration(
                  labelText: 'Αναζήτηση τμήματος (όλα τα φύλλα)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Semantics(
                    label: 'Καθαρισμός αναζήτησης χάρτη',
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        textController.clear();
                        _typedQuery = '';
                        _keyboardOptionIndex = -1;
                        setState(() => _offMapNotice = null);
                      },
                      tooltip: 'Καθαρισμός',
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (_isKeyboardPreview) {
                    _isKeyboardPreview = false;
                    return;
                  }
                  _typedQuery = value;
                  _keyboardOptionIndex = -1;
                  _lastAutoScrollIndex = -1;
                },
                onSubmitted: (_) async {
                  final options = _options(_typedQuery);
                  if (options.isNotEmpty &&
                      _keyboardOptionIndex >= 0 &&
                      _keyboardOptionIndex < options.length) {
                    await _commitOption(options[_keyboardOptionIndex]);
                    return;
                  }
                  await _handleSubmitRaw();
                },
              ),
            );
          },
        ),
        if (_offMapNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _offMapNotice!,
              style: noticeStyle,
            ),
          ),
      ],
    );

    return fieldColumn;
  }
}
