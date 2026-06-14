import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/gemini_ticket_service.dart';
import '../../providers/dashboard_provider.dart';

enum _GeminiModelSlot { primary, fallback }

enum _DuplicateModelAction { replace, pickOther, cancel }

/// Έλεγχος ότι κύριο και εφεδρικό μοντέλο δεν συμπίπτουν.
bool geminiPrimaryFallbackModelsAreDistinct({
  required String primaryModel,
  required String fallbackModel,
  required bool fallbackEnabled,
}) {
  if (!fallbackEnabled) return true;
  final primary = primaryModel.trim();
  final fallback = fallbackModel.trim();
  if (primary.isEmpty || fallback.isEmpty) return true;
  return primary != fallback;
}

/// Κύριο + εφεδρικό μοντέλο Gemini με κοινή λίστα και μαζικό έλεγχο ποσόστωσης.
class GeminiModelsSection extends ConsumerStatefulWidget {
  const GeminiModelsSection({
    required this.primaryModelController,
    required this.fallbackModelController,
    required this.apiKeyController,
    required this.onChanged,
    this.fallbackEnabled = true,
    this.endpointTemplate = kDefaultGeminiEndpoint,
    super.key,
  });

  final TextEditingController primaryModelController;
  final TextEditingController fallbackModelController;
  final TextEditingController apiKeyController;
  final VoidCallback onChanged;
  final bool fallbackEnabled;
  final String endpointTemplate;

  @override
  ConsumerState<GeminiModelsSection> createState() => _GeminiModelsSectionState();
}

class _GeminiModelsSectionState extends ConsumerState<GeminiModelsSection> {
  static const Duration _probeStaleAfter = Duration(days: 90);
  static const Duration _typedQuotaProbeDebounce = Duration(milliseconds: 400);
  static const String _typedQuotaWarningMessage =
      'Το μοντέλο που καταχωρήσατε δεν έχει διαθέσιμη ποσόστωση (> 0). '
      'Μπορείτε να το κρατήσετε.';

  List<GeminiTextModel> _allModels = <GeminiTextModel>[];
  List<GeminiTextModel> _availableModels = <GeminiTextModel>[];
  bool _loadingModels = false;
  bool _probing = false;
  String? _statusMessage;
  String? _probeProgress;
  GeminiModelsQuotaProbeResult? _probeResult;
  _GeminiModelSlot _chipTarget = _GeminiModelSlot.primary;
  String _lastCommittedPrimary = '';
  String _lastCommittedFallback = '';
  bool _resolvingDuplicate = false;
  bool _cacheRestored = false;
  DateTime? _probeCheckedAt;
  Timer? _typedQuotaProbeTimer;
  int _typedQuotaProbeGeneration = 0;
  final Map<String, bool> _modelQuotaOkCache = <String, bool>{};
  final Map<_GeminiModelSlot, String> _failedQuotaModelBySlot =
      <_GeminiModelSlot, String>{};

  List<GeminiTextModel> get _pickerModels =>
      _availableModels.isNotEmpty ? _availableModels : _allModels;

  String get _primaryValue => widget.primaryModelController.text.trim();
  String get _fallbackValue => widget.fallbackModelController.text.trim();

  @override
  void initState() {
    super.initState();
    _lastCommittedPrimary = _primaryValue;
    _lastCommittedFallback = _fallbackValue;
    widget.primaryModelController.addListener(_onControllersChanged);
    widget.fallbackModelController.addListener(_onControllersChanged);
  }

  @override
  void dispose() {
    _typedQuotaProbeTimer?.cancel();
    widget.primaryModelController.removeListener(_onControllersChanged);
    widget.fallbackModelController.removeListener(_onControllersChanged);
    super.dispose();
  }

  void _onControllersChanged() {
    if (mounted && !_resolvingDuplicate) setState(() {});
  }

  void _applyProbeCache(GeminiModelsProbeCache cache) {
    setState(() {
      _probeResult = cache.result;
      _availableModels = cache.result.availableModels;
      _probeCheckedAt = cache.checkedAt;
      _syncQuotaWarningsFromProbeResult(cache.result);
    });
  }

  String _valueFor(_GeminiModelSlot slot) {
    return slot == _GeminiModelSlot.primary ? _primaryValue : _fallbackValue;
  }

  void _syncQuotaWarningsFromProbeResult(GeminiModelsQuotaProbeResult result) {
    for (final model in result.availableModels) {
      _modelQuotaOkCache[model.id] = true;
    }
    for (final warning in result.typedModelWarnings) {
      _modelQuotaOkCache[warning.modelId] = false;
    }

    _failedQuotaModelBySlot
      ..remove(_GeminiModelSlot.primary)
      ..remove(_GeminiModelSlot.fallback);

    for (final warning in result.typedModelWarnings) {
      final slot = _slotFromWarningLabel(warning.slotLabel);
      if (slot == null) continue;
      if (_valueFor(slot) != warning.modelId) continue;
      if (slot == _GeminiModelSlot.fallback && !widget.fallbackEnabled) continue;
      _failedQuotaModelBySlot[slot] = warning.modelId;
    }
  }

  _GeminiModelSlot? _slotFromWarningLabel(String slotLabel) {
    return switch (slotLabel) {
      'κύριο' => _GeminiModelSlot.primary,
      'εφεδρικό' => _GeminiModelSlot.fallback,
      _ => null,
    };
  }

  void _clearSlotQuotaWarning(_GeminiModelSlot slot) {
    if (_failedQuotaModelBySlot.remove(slot) != null && mounted) {
      setState(() {});
    }
  }

  void _scheduleTypedQuotaProbe(_GeminiModelSlot slot) {
    _typedQuotaProbeTimer?.cancel();
    final current = _valueFor(slot);
    if (current.isEmpty) {
      _clearSlotQuotaWarning(slot);
      return;
    }

    final stale = _failedQuotaModelBySlot[slot];
    if (stale != null && stale != current) {
      setState(() => _failedQuotaModelBySlot.remove(slot));
    }

    if (_availableModels.any((model) => model.id == current)) {
      _clearSlotQuotaWarning(slot);
      _modelQuotaOkCache[current] = true;
      return;
    }

    final cachedOk = _modelQuotaOkCache[current];
    if (cachedOk != null) {
      setState(() {
        if (cachedOk) {
          _failedQuotaModelBySlot.remove(slot);
        } else if (_valueFor(slot) == current) {
          _failedQuotaModelBySlot[slot] = current;
        }
      });
      return;
    }

    _typedQuotaProbeTimer = Timer(_typedQuotaProbeDebounce, () {
      unawaited(_probeTypedModelQuota(slot));
    });
  }

  Future<void> _probeTypedModelQuota(_GeminiModelSlot slot) async {
    if (slot == _GeminiModelSlot.fallback && !widget.fallbackEnabled) {
      _clearSlotQuotaWarning(slot);
      return;
    }

    final generation = ++_typedQuotaProbeGeneration;
    final modelId = _valueFor(slot);
    if (modelId.isEmpty) {
      _clearSlotQuotaWarning(slot);
      return;
    }

    if (_availableModels.any((model) => model.id == modelId)) {
      _modelQuotaOkCache[modelId] = true;
      _clearSlotQuotaWarning(slot);
      return;
    }

    final apiKey = widget.apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    final result = await GeminiTicketService.probeModel(
      apiKey: apiKey,
      model: modelId,
      endpointTemplate: widget.endpointTemplate,
    );
    if (!mounted || generation != _typedQuotaProbeGeneration) return;
    if (_valueFor(slot) != modelId) return;

    _modelQuotaOkCache[modelId] = result.ok;
    setState(() {
      if (result.ok) {
        _failedQuotaModelBySlot.remove(slot);
      } else {
        _failedQuotaModelBySlot[slot] = modelId;
      }
    });
  }

  void _tryRestoreProbeCache(GeminiModelsProbeCache? cache) {
    if (_cacheRestored || cache == null || _probeResult != null || _probing) {
      return;
    }
    _cacheRestored = true;
    _applyProbeCache(cache);
  }

  bool get _probeIsStale {
    final checkedAt = _probeCheckedAt;
    if (checkedAt == null) return false;
    return DateTime.now().difference(checkedAt) > _probeStaleAfter;
  }

  String? _formatLastProbeLabel() {
    final checkedAt = _probeCheckedAt;
    if (checkedAt == null) return null;
    final formatted = DateFormat('dd/MM/yyyy HH:mm').format(checkedAt);
    return 'Τελευταίος έλεγχος: $formatted';
  }

  TextEditingController _controllerFor(_GeminiModelSlot slot) {
    return slot == _GeminiModelSlot.primary
        ? widget.primaryModelController
        : widget.fallbackModelController;
  }

  String _lastCommittedFor(_GeminiModelSlot slot) {
    return slot == _GeminiModelSlot.primary
        ? _lastCommittedPrimary
        : _lastCommittedFallback;
  }

  void _commitSlot(_GeminiModelSlot slot, String value) {
    if (slot == _GeminiModelSlot.primary) {
      _lastCommittedPrimary = value.trim();
    } else {
      _lastCommittedFallback = value.trim();
    }
  }

  _GeminiModelSlot _otherSlot(_GeminiModelSlot slot) {
    return slot == _GeminiModelSlot.primary
        ? _GeminiModelSlot.fallback
        : _GeminiModelSlot.primary;
  }

  String _slotLabel(_GeminiModelSlot slot) {
    return slot == _GeminiModelSlot.primary ? 'κύριο' : 'εφεδρικό';
  }

  Future<_DuplicateModelAction?> _showDuplicateDialog({
    required String modelId,
    required _GeminiModelSlot existingSlot,
  }) async {
    return showDialog<_DuplicateModelAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ίδιο μοντέλο'),
        content: Text(
          'Το ίδιο μοντέλο «$modelId» έχει ήδη οριστεί ως '
          '${_slotLabel(existingSlot)}.\n\nΘέλετε:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DuplicateModelAction.cancel),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_DuplicateModelAction.pickOther),
            child: const Text('Επιλογή άλλου μοντέλου'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_DuplicateModelAction.replace),
            child: const Text('Αντικατάσταση'),
          ),
        ],
      ),
    );
  }

  Future<void> _assignModel(String modelId, _GeminiModelSlot slot) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;

    final targetCtrl = _controllerFor(slot);
    final previousTarget = _lastCommittedFor(slot);
    final otherSlot = _otherSlot(slot);
    final otherValue = _controllerFor(otherSlot).text.trim();

    if (widget.fallbackEnabled &&
        otherValue.isNotEmpty &&
        otherValue == trimmed &&
        slot != otherSlot) {
      _resolvingDuplicate = true;
      targetCtrl.text = previousTarget;
      final action = await _showDuplicateDialog(
        modelId: trimmed,
        existingSlot: otherSlot,
      );
      _resolvingDuplicate = false;
      if (!mounted || action == null || action == _DuplicateModelAction.cancel) {
        setState(() {});
        return;
      }
      if (action == _DuplicateModelAction.replace) {
        targetCtrl.text = trimmed;
        _controllerFor(otherSlot).text = '';
        _commitSlot(slot, trimmed);
        _commitSlot(otherSlot, '');
        _clearSlotQuotaWarning(otherSlot);
      } else {
        targetCtrl.text = trimmed;
        _commitSlot(slot, trimmed);
        if (!mounted) return;
        await _openModelPicker(
          slot: otherSlot,
          title: otherSlot == _GeminiModelSlot.primary
              ? 'Επιλογή κύριου μοντέλου'
              : 'Επιλογή εφεδρικού μοντέλου',
          excludeModelId: trimmed,
        );
      }
    } else {
      targetCtrl.text = trimmed;
      _commitSlot(slot, trimmed);
    }

    if (!mounted) return;
    widget.onChanged();
    _scheduleTypedQuotaProbe(slot);
  }

  Future<void> _handleFieldChange(String value, _GeminiModelSlot slot) async {
    if (_resolvingDuplicate) return;

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _commitSlot(slot, '');
      _typedQuotaProbeTimer?.cancel();
      _clearSlotQuotaWarning(slot);
      widget.onChanged();
      return;
    }

    final otherSlot = _otherSlot(slot);
    final otherValue = _controllerFor(otherSlot).text.trim();

    if (widget.fallbackEnabled &&
        otherValue.isNotEmpty &&
        otherValue == trimmed) {
      final previous = _lastCommittedFor(slot);
      _resolvingDuplicate = true;
      _controllerFor(slot).text = previous;
      final action = await _showDuplicateDialog(
        modelId: trimmed,
        existingSlot: otherSlot,
      );
      _resolvingDuplicate = false;
      if (!mounted) return;
      if (action == null || action == _DuplicateModelAction.cancel) {
        setState(() {});
        return;
      }
      if (action == _DuplicateModelAction.replace) {
        _controllerFor(slot).text = trimmed;
        _controllerFor(otherSlot).text = '';
        _commitSlot(slot, trimmed);
        _commitSlot(otherSlot, '');
        _clearSlotQuotaWarning(otherSlot);
      } else {
        _controllerFor(slot).text = trimmed;
        _commitSlot(slot, trimmed);
        await _openModelPicker(
          slot: otherSlot,
          title: otherSlot == _GeminiModelSlot.primary
              ? 'Επιλογή κύριου μοντέλου'
              : 'Επιλογή εφεδρικού μοντέλου',
          excludeModelId: trimmed,
        );
      }
      if (!mounted) return;
      widget.onChanged();
      _scheduleTypedQuotaProbe(slot);
      if (action == _DuplicateModelAction.replace) {
        _scheduleTypedQuotaProbe(otherSlot);
      }
      return;
    }

    _commitSlot(slot, trimmed);
    if (!mounted) return;
    widget.onChanged();
    _scheduleTypedQuotaProbe(slot);
  }

  Future<void> _loadModels() async {
    final apiKey = widget.apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _statusMessage = 'Συμπληρώστε πρώτα το Gemini API key.';
      });
      return;
    }

    setState(() {
      _loadingModels = true;
      _statusMessage = null;
      _probeProgress = null;
    });
    try {
      final models = await GeminiTicketService.listTextModels(apiKey: apiKey);
      if (!mounted) return;
      setState(() {
        _allModels = models;
        _statusMessage = models.isEmpty
            ? 'Δεν βρέθηκαν μοντέλα κειμένου.'
            : '${models.length} διαθέσιμα μοντέλα κειμένου.';
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _probeAllModels() async {
    final apiKey = widget.apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _probeResult = const GeminiModelsQuotaProbeResult(
          availableModels: [],
          totalChecked: 0,
          message: 'Συμπληρώστε πρώτα το Gemini API key.',
        );
      });
      return;
    }

    setState(() {
      _probing = true;
      _probeResult = null;
      _probeProgress = null;
      _availableModels = <GeminiTextModel>[];
    });

    if (_allModels.isEmpty && !_loadingModels) {
      await _loadModels();
      if (!mounted || _allModels.isEmpty) {
        setState(() => _probing = false);
        return;
      }
    }

    final result = await GeminiTicketService.probeModelsWithQuota(
      apiKey: apiKey,
      endpointTemplate: widget.endpointTemplate,
      typedPrimaryModel: _primaryValue,
      typedFallbackModel: _fallbackValue,
      checkTypedFallback: widget.fallbackEnabled,
      onProgress: (current, total, modelId) {
        if (!mounted) return;
        setState(() {
          _probeProgress = 'Έλεγχος $current/$total ($modelId)…';
        });
      },
    );
    if (!mounted) return;
    if (result.totalChecked > 0) {
      await ref.read(geminiModelsProbeCacheProvider.notifier).saveFromResult(
            result,
          );
    }
    final savedCache = ref.read(geminiModelsProbeCacheProvider);
    setState(() {
      _probing = false;
      _probeProgress = null;
      _probeResult = result;
      _availableModels = result.availableModels;
      _probeCheckedAt = savedCache?.checkedAt ?? _probeCheckedAt;
      _statusMessage = result.totalChecked > 0 ? null : result.message;
      _syncQuotaWarningsFromProbeResult(result);
    });
  }

  Future<void> _openModelPicker({
    required _GeminiModelSlot slot,
    required String title,
    String? excludeModelId,
  }) async {
    if (slot == _GeminiModelSlot.fallback && !widget.fallbackEnabled) return;

    if (_pickerModels.isEmpty && !_loadingModels) {
      await _loadModels();
      if (!mounted || _pickerModels.isEmpty) return;
    }

    final exclude = excludeModelId?.trim() ?? '';
    final models = exclude.isEmpty
        ? _pickerModels
        : _pickerModels.where((m) => m.id != exclude).toList();

    if (models.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν υπάρχουν άλλα διαθέσιμα μοντέλα.'),
        ),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _GeminiModelPickerDialog(
        title: title,
        models: models,
      ),
    );
    if (!mounted || selected == null) return;
    await _assignModel(selected, slot);
  }

  Widget _buildSlotQuotaWarning(_GeminiModelSlot slot) {
    if (slot == _GeminiModelSlot.fallback && !widget.fallbackEnabled) {
      return const SizedBox.shrink();
    }
    final failedId = _failedQuotaModelBySlot[slot];
    if (failedId == null || failedId != _valueFor(slot)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _typedQuotaWarningMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelFieldWithQuotaWarning({
    required _GeminiModelSlot slot,
    required String labelText,
    required String? helperText,
    required String pickerTitle,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelField(
          slot: slot,
          labelText: labelText,
          helperText: helperText,
          pickerTitle: pickerTitle,
          enabled: enabled,
        ),
        _buildSlotQuotaWarning(slot),
      ],
    );
  }

  Widget _modelField({
    required _GeminiModelSlot slot,
    required String labelText,
    required String? helperText,
    required String pickerTitle,
    required bool enabled,
  }) {
    final controller = _controllerFor(slot);
    return TextFormField(
      controller: controller,
      enabled: enabled,
      onChanged: (value) => unawaited(_handleFieldChange(value, slot)),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: 'π.χ. $kDefaultGeminiFallbackModel',
        helperText: helperText,
        helperMaxLines: helperText == null ? null : 4,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Λίστα μοντέλων',
          onPressed: !enabled || _loadingModels
              ? null
              : () => unawaited(
                    _openModelPicker(slot: slot, title: pickerTitle),
                  ),
          icon: const Icon(Icons.list_alt_rounded, size: 20),
        ),
      ),
    );
  }

  Widget _buildModelChip(GeminiTextModel model) {
    final isPrimary = model.id == _primaryValue;
    final isFallback = model.id == _fallbackValue;
    final isAssigned = isPrimary || isFallback;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final tooltip = _modelChipTooltip(
      model: model,
      isPrimary: isPrimary,
      isFallback: isFallback,
      isAssigned: isAssigned,
    );

    return InputChip(
      label: Text(
        model.id,
        style: isAssigned
            ? TextStyle(color: onSurfaceVariant.withValues(alpha: 0.65))
            : null,
      ),
      tooltip: tooltip,
      backgroundColor: isAssigned
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      side: isAssigned
          ? BorderSide(color: onSurfaceVariant.withValues(alpha: 0.35))
          : null,
      onPressed: isAssigned
          ? null
          : () => unawaited(_assignModel(model.id, _chipTarget)),
    );
  }

  /// Tooltip μόνο όταν προσθέτει πληροφορία πέρα από το κείμενο του chip.
  String? _modelChipTooltip({
    required GeminiTextModel model,
    required bool isPrimary,
    required bool isFallback,
    required bool isAssigned,
  }) {
    if (isAssigned) {
      return isPrimary
          ? 'Ήδη ορισμένο ως κύριο μοντέλο'
          : 'Ήδη ορισμένο ως εφεδρικό μοντέλο';
    }

    final displayName = model.displayName.trim();
    if (displayName.isEmpty ||
        displayName.toLowerCase() == model.id.toLowerCase()) {
      return null;
    }
    return displayName;
  }

  Widget _buildProbeMetaLines(Color onSurfaceVariant) {
    final lastProbeLabel = _formatLastProbeLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lastProbeLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            lastProbeLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: onSurfaceVariant,
                ),
          ),
        ],
        if (_probeIsStale) ...[
          const SizedBox(height: 4),
          Text(
            'Προτείνεται ανανέωση (πάνω από 3 μήνες).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade900,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildProbeResultsCard({
    required GeminiModelsQuotaProbeResult probe,
    required bool showChipTarget,
    required Color onSurfaceVariant,
  }) {
    final hasAvailable = probe.availableModels.isNotEmpty;
    final accent = hasAvailable ? Colors.green : Colors.orange;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasAvailable
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: hasAvailable
                      ? Colors.green.shade800
                      : Colors.orange.shade900,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        probe.message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      _buildProbeMetaLines(onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
            if (showChipTarget) ...[
              const SizedBox(height: 10),
              Text(
                'Επόμενη επιλογή chip:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<_GeminiModelSlot>(
                segments: const [
                  ButtonSegment(
                    value: _GeminiModelSlot.primary,
                    label: Text('Κύριο'),
                    icon: Icon(Icons.looks_one_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _GeminiModelSlot.fallback,
                    label: Text('Εφεδρικό'),
                    icon: Icon(Icons.looks_two_outlined, size: 18),
                  ),
                ],
                selected: {_chipTarget},
                onSelectionChanged: (selection) {
                  setState(() => _chipTarget = selection.first);
                },
              ),
            ],
            if (hasAvailable) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final model in probe.availableModels)
                    _buildModelChip(model),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GeminiModelsProbeCache?>(geminiModelsProbeCacheProvider, (
      _,
      next,
    ) {
      _tryRestoreProbeCache(next);
    });
    final cachedProbe = ref.watch(geminiModelsProbeCacheProvider);
    if (cachedProbe != null &&
        !_cacheRestored &&
        _probeResult == null &&
        !_probing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryRestoreProbeCache(cachedProbe);
      });
    }

    final probe = _probeResult;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final showChipTarget =
        widget.fallbackEnabled &&
        probe != null &&
        probe.availableModels.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelFieldWithQuotaWarning(
          slot: _GeminiModelSlot.primary,
          labelText: 'Κύριο μοντέλο',
          helperText:
              'Αντικαθιστά το {προτεύων μοντέλο} στο endpoint. '
              'Επιλογή από λίστα ή χειροκίνητη πληκτρολόγηση.',
          pickerTitle: 'Επιλογή κύριου μοντέλου',
          enabled: true,
        ),
        const SizedBox(height: 8),
        _modelFieldWithQuotaWarning(
          slot: _GeminiModelSlot.fallback,
          labelText: 'Εφεδρικό μοντέλο',
          helperText: widget.fallbackEnabled
              ? 'Χρησιμοποιείται σε 503 (υπερφόρτωση).'
              : 'Απενεργοποιημένο.',
          pickerTitle: 'Επιλογή εφεδρικού μοντέλου',
          enabled: widget.fallbackEnabled,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: _probing
                  ? 'Ολοκληρώστε πρώτα τον έλεγχο μοντέλων'
                  : 'Ανανέωση λίστας μοντέλων από το API',
              child: MouseRegion(
                cursor: (_loadingModels || _probing)
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: FilledButton.tonalIcon(
                  onPressed: (_loadingModels || _probing)
                      ? null
                      : () => unawaited(_loadModels()),
                  icon: _loadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_loadingModels ? 'Φόρτωση…' : 'Ανανέωση λίστας'),
                ),
              ),
            ),
            Tooltip(
              message: _loadingModels
                  ? 'Ολοκληρώστε πρώτα την ανανέωση λίστας'
                  : 'Έλεγχος ποσόστωσης όλων των μοντέλων κειμένου',
              child: MouseRegion(
                cursor: (_probing || _loadingModels)
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: FilledButton.tonalIcon(
                  onPressed: (_probing || _loadingModels)
                      ? null
                      : () => unawaited(_probeAllModels()),
                  icon: _probing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined, size: 18),
                  label: Text(_probing ? 'Έλεγχος…' : 'Έλεγχος μοντέλων'),
                ),
              ),
            ),
          ],
        ),
        if (_probeProgress != null) ...[
          const SizedBox(height: 6),
          Text(
            _probeProgress!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: onSurfaceVariant,
                ),
          ),
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _statusMessage!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: onSurfaceVariant,
                ),
          ),
        ],
        if (probe != null && probe.totalChecked > 0) ...[
          const SizedBox(height: 8),
          _buildProbeResultsCard(
            probe: probe,
            showChipTarget: showChipTarget,
            onSurfaceVariant: onSurfaceVariant,
          ),
        ],
      ],
    );
  }
}

class _GeminiModelPickerDialog extends StatefulWidget {
  const _GeminiModelPickerDialog({
    required this.title,
    required this.models,
  });

  final String title;
  final List<GeminiTextModel> models;

  @override
  State<_GeminiModelPickerDialog> createState() =>
      _GeminiModelPickerDialogState();
}

class _GeminiModelPickerDialogState extends State<_GeminiModelPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GeminiTextModel> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.models;
    return widget.models
        .where(
          (m) =>
              m.id.toLowerCase().contains(q) ||
              m.displayName.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Αναζήτηση',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Δεν βρέθηκαν μοντέλα.'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final model = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(model.id),
                          subtitle: Text(model.displayName),
                          onTap: () => Navigator.of(ctx).pop(model.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
      ],
    );
  }
}
