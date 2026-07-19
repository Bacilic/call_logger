import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/settings_service.dart';
import '../../../core/updates/network_folder_classifier.dart';
import '../../../core/updates/update_source_config.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/search_debouncer.dart';

/// Πεδίο «Φάκελος ελέγχου ενημερώσεων» για τις Ρυθμίσεις.
class UpdateFolderSettingField extends StatefulWidget {
  const UpdateFolderSettingField({
    super.key,
    this.updateSourceConfig,
    this.settingsService,
    this.networkFolderClassifier,
    this.networkClassifyDebounce = const Duration(milliseconds: 400),
    this.pickFolder,
  });

  /// Εξωτερική επίλυση ενεργής διαδρομής (τεστ / έγχυση).
  final UpdateSourceConfig? updateSourceConfig;

  final SettingsService? settingsService;

  final NetworkFolderClassifier? networkFolderClassifier;

  final Duration networkClassifyDebounce;

  /// Προαιρετικός επιλογέας φακέλου (τεστ)· αλλιώς FilePicker.
  final Future<String?> Function()? pickFolder;

  @override
  State<UpdateFolderSettingField> createState() =>
      _UpdateFolderSettingFieldState();
}

class _UpdateFolderSettingFieldState extends State<UpdateFolderSettingField> {
  final _controller = TextEditingController();
  late final SearchDebouncer _classifyDebouncer;
  bool _showLocalOnlyWarning = false;
  bool _loading = true;

  SettingsService get _settings =>
      widget.settingsService ?? SettingsService();

  NetworkFolderClassifier get _classifier =>
      widget.networkFolderClassifier ?? NetworkFolderClassifier.system();

  UpdateSourceConfig get _sourceConfig =>
      widget.updateSourceConfig ??
      UpdateSourceConfig(
        getUserUpdateFolderPath: () => _settings.getUpdateFolderPath(),
      );

  @override
  void initState() {
    super.initState();
    _classifyDebouncer = SearchDebouncer(
      delay: widget.networkClassifyDebounce,
    );
    _controller.addListener(_onTextChanged);
    unawaited(_loadActivePath());
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _classifyDebouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadActivePath() async {
    final path = await _sourceConfig.resolveUpdateFolderPath() ?? '';
    if (!mounted) return;
    setState(() {
      _controller.text = path;
      _loading = false;
    });
    _scheduleClassify();
  }

  void _onTextChanged() {
    _scheduleClassify();
  }

  void _scheduleClassify() {
    final text = _controller.text;
    _classifyDebouncer.run(text, (q, isCurrent) async {
      final trimmed = q.trim();
      if (trimmed.isEmpty) {
        if (!isCurrent() || !mounted) return;
        setState(() => _showLocalOnlyWarning = false);
        return;
      }
      final kind = await _classifier.classify(trimmed);
      if (!isCurrent() || !mounted) return;
      setState(() {
        _showLocalOnlyWarning = kind == NetworkFolderKind.localOnly;
      });
    });
  }

  Future<void> _persistFromField() async {
    final trimmed = _controller.text.trim();
    await _settings.setUpdateFolderPath(trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _pickFolder() async {
    if (widget.pickFolder != null) {
      final path = await widget.pickFolder!();
      if (path == null || !mounted) return;
      setState(() => _controller.text = path);
      await _persistFromField();
      _scheduleClassify();
      return;
    }

    if (FilePickerSession.takeLastRefocusedExisting()) return;
    final initialDirectory = initialDirectoryForFilePicker(_controller.text);
    final session = await FilePickerSession.run(
      () => FilePicker.getDirectoryPath(
        dialogTitle: 'Φάκελος ελέγχου ενημερώσεων',
        initialDirectory: initialDirectory,
      ),
    );
    if (session.refocusedExisting) return;
    final path = session.value;
    if (path == null || !mounted) return;
    setState(() => _controller.text = path);
    await _persistFromField();
    _scheduleClassify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('settings_update_folder_field'),
                controller: _controller,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Φάκελος ελέγχου ενημερώσεων',
                  hintText: r'\\server\share\call_logger_updates',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onEditingComplete: () => unawaited(_persistFromField()),
                onSubmitted: (_) => unawaited(_persistFromField()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('settings_update_folder_pick_button'),
              tooltip: 'Επιλογή φακέλου',
              onPressed: _loading ? null : () => unawaited(_pickFolder()),
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Με κενό πεδίο η εφαρμογή χρησιμοποιεί αυτόματα το '
          'update_source.json δίπλα στο εκτελέσιμο.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (_showLocalOnlyWarning) ...[
          const SizedBox(height: 8),
          Row(
            key: const Key('settings_update_folder_local_only_warning'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Αυτή φαίνεται τοπική διαδρομή — οι συνάδελφοι δεν θα '
                  'έχουν πρόσβαση. Προτιμήστε κοινόχρηστο φάκελο δικτύου '
                  '(\\διακομιστής\\...) ή μοιραστείτε αυτόν τον φάκελο '
                  'στο δίκτυο.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
