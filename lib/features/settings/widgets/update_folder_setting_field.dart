import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/settings_service.dart';
import '../../../core/updates/network_folder_classifier.dart';
import '../../../core/updates/update_folder_presence.dart';
import '../../../core/updates/update_source_config.dart';
import '../../../core/widgets/save_on_focus_loss.dart';
import '../utils/update_folder_hint.dart';
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
    this.directoryExists,
  });

  /// Εξωτερική επίλυση ενεργής διαδρομής (τεστ / έγχυση).
  final UpdateSourceConfig? updateSourceConfig;

  final SettingsService? settingsService;

  final NetworkFolderClassifier? networkFolderClassifier;

  final Duration networkClassifyDebounce;

  /// Προαιρετικός επιλογέας φακέλου (τεστ)· αλλιώς FilePicker.
  final Future<String?> Function()? pickFolder;

  /// Προαιρετικός έλεγχος ύπαρξης φακέλου (τεστ)· αλλιώς το σύστημα αρχείων.
  final DirectoryExistsProbe? directoryExists;

  @override
  State<UpdateFolderSettingField> createState() =>
      _UpdateFolderSettingFieldState();
}

class _UpdateFolderSettingFieldState extends State<UpdateFolderSettingField> {
  final _controller = TextEditingController();
  late final SearchDebouncer _classifyDebouncer;
  bool _showLocalOnlyWarning = false;
  UpdateFolderPresence _presence = UpdateFolderPresence.unset;

  /// Ο φάκελος που κατέγραψε το πρόγραμμα εγκατάστασης — διαβάζεται μία φορά:
  /// γράφεται στην εγκατάσταση και δεν αλλάζει όσο τρέχει η εφαρμογή.
  String? _installerFolder;

  /// Έχει τιμή η **κοινή** ρύθμιση; Διαφορετικό από «το πεδίο δείχνει κάτι»:
  /// το πεδίο γεμίζει και από τον φάκελο εγκατάστασης.
  bool _hasSavedSetting = false;
  bool _loading = true;

  SettingsService get _settings => widget.settingsService ?? SettingsService();

  NetworkFolderClassifier get _classifier =>
      widget.networkFolderClassifier ?? NetworkFolderClassifier.system();

  UpdateSourceConfig get _sourceConfig =>
      widget.updateSourceConfig ??
      UpdateSourceConfig(
        getUserUpdateFolderPath: () => _settings.catalogs.getUpdateFolderPath(),
      );

  @override
  void initState() {
    super.initState();
    _classifyDebouncer = SearchDebouncer(delay: widget.networkClassifyDebounce);
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
    final saved = (await _sourceConfig.getUserUpdateFolderPath())?.trim();
    final path = await _sourceConfig.resolveUpdateFolderPath() ?? '';
    if (!mounted) return;
    setState(() {
      _controller.text = path;
      _hasSavedSetting = saved != null && saved.isNotEmpty;
      _loading = false;
    });
    _scheduleClassify();
    // Ξεχωριστά, ποτέ μπροστά από το πεδίο: η ανάγνωση του αρχείου αγγίζει τον
    // δίσκο και δεν πρέπει να καθυστερεί την τιμή που ο χρήστης ήρθε να δει.
    unawaited(_loadInstallerFolder());
  }

  Future<void> _loadInstallerFolder() async {
    final folder = await _sourceConfig.readInstallerRecordedFolder();
    if (!mounted) return;
    setState(() => _installerFolder = folder);
  }

  void _onTextChanged() {
    // Η γραμμή επεξήγησης αλλάζει μόλις το πεδίο αδειάσει ή ξαναγεμίσει —
    // χωρίς αναμονή, δεν ρωτά κανέναν.
    setState(() {});
    _scheduleClassify();
  }

  void _scheduleClassify() {
    final text = _controller.text;
    _classifyDebouncer.run(text, (q, isCurrent) async {
      final trimmed = q.trim();
      if (trimmed.isEmpty) {
        if (!isCurrent() || !mounted) return;
        setState(() {
          _showLocalOnlyWarning = false;
          _presence = UpdateFolderPresence.unset;
        });
        return;
      }
      // Ανεξάρτητα, όχι σε σειρά: η ταξινόμηση ρωτά το δίκτυο και μπορεί να
      // αργήσει. Αν η μία περίμενε την άλλη, ένας αργός διακομιστής θα
      // κρατούσε κρυφή και την προειδοποίηση που δεν τον χρειάζεται.
      unawaited(
        probeUpdateFolderPresence(trimmed, exists: widget.directoryExists).then(
          (presence) {
            if (!isCurrent() || !mounted) return;
            setState(() => _presence = presence);
          },
        ),
      );

      final kind = await _classifier.classify(trimmed);
      if (!isCurrent() || !mounted) return;
      setState(() {
        _showLocalOnlyWarning = kind == NetworkFolderKind.localOnly;
      });
    });
  }

  Future<void> _persistFromField() async {
    final trimmed = _controller.text.trim();
    await _settings.catalogs.setUpdateFolderPath(
      trimmed.isEmpty ? null : trimmed,
    );
    if (!mounted) return;
    // Η αποθήκευση αλλάζει την απάντηση στο «ποιον αφορά αυτό;» — η γραμμή
    // από κάτω πρέπει να το πει αμέσως, όχι στο επόμενο άνοιγμα.
    setState(() => _hasSavedSetting = trimmed.isNotEmpty);
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
              child: SaveOnFocusLoss(
                onLostFocus: () => unawaited(_persistFromField()),
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
          UpdateFolderHint.forState(
            fieldValue: _controller.text,
            installerFolder: _installerFolder,
            hasSavedSetting: _hasSavedSetting,
          ),
          key: const Key('settings_update_folder_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            // Το «κανένας έλεγχος» δεν είναι σφάλμα ρύθμισης, είναι όμως
            // απώλεια λειτουργίας: ξεχωρίζει χωρίς να φωνάζει κόκκινο.
            color:
                UpdateFolderHint.isNoSourceState(
                  fieldValue: _controller.text,
                  installerFolder: _installerFolder,
                )
                ? scheme.tertiary
                : scheme.onSurfaceVariant,
          ),
        ),
        if (_presence == UpdateFolderPresence.missing) ...[
          const SizedBox(height: 8),
          Row(
            key: const Key('settings_update_folder_missing_warning'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ο φάκελος δεν βρέθηκε. Η εφαρμογή δεν θα μπορεί να '
                  'ελέγξει για νέα έκδοση όσο η διαδρομή δείχνει εκεί.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
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
