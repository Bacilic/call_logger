import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/gemini_prompt_template_controller.dart';
import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../../../core/widgets/quick_call_fab.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/models/call_model.dart';
import '../models/lansweeper_connection_status.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/dashboard_provider.dart';
import '../providers/lansweeper_connection_probe_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import 'lansweeper/lansweeper_gemini_prompt_preview_dialog.dart';
import 'lansweeper/gemini_prompt_template_editor_dialog.dart';
import 'lansweeper/lansweeper_connection_settings_dialog.dart';
import 'lansweeper/lansweeper_report_call_list.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper/lansweeper_sync_form.dart';
import 'lansweeper/sync_history_list.dart';

part 'lansweeper_report_settings.dart';
part 'lansweeper_report_items.dart';
part 'lansweeper_report_browser.dart';
part 'lansweeper_report_gemini.dart';
part 'lansweeper_report_registration.dart';

class LansweeperReportDialog extends ConsumerStatefulWidget {
  const LansweeperReportDialog({super.key});

  @override
  ConsumerState<LansweeperReportDialog> createState() =>
      _LansweeperReportDialogState();
}

mixin LansweeperReportDialogStateHost on ConsumerState<LansweeperReportDialog> {
  // ignore: unused_element — απαιτείται από part mixins· ο analyzer δεν το ανιχνεύει.
  Set<String> get _selectedKeys;
  // ignore: unused_element
  SpellCheckController get _titleController;
  // ignore: unused_element
  SpellCheckController get _notesController;
  // ignore: unused_element
  SpellCheckController get _solutionController;
  // ignore: unused_element
  TextEditingController get _lansweeperAgentUsernameController;
  // ignore: unused_element
  TextEditingController get _lansweeperApiUrlController;
  // ignore: unused_element
  TextEditingController get _lansweeperTicketFormUrlController;
  // ignore: unused_element
  TextEditingController get _lansweeperTicketViewUrlController;
  // ignore: unused_element
  TextEditingController get _lansweeperApiKeyController;
  // ignore: unused_element
  TextEditingController get _lansweeperLoginUrlController;
  // ignore: unused_element
  TextEditingController get _lansweeperHelpdeskUsernameController;
  // ignore: unused_element
  TextEditingController get _lansweeperHelpdeskPasswordController;
  // ignore: unused_element
  TextEditingController get _geminiApiKeyController;
  // ignore: unused_element
  GeminiPromptTemplateTextEditingController get _geminiPromptTemplateController;
  // ignore: unused_element
  TextEditingController get _geminiEndpointController;
  // ignore: unused_element
  TextEditingController get _geminiPrimaryModelController;
  // ignore: unused_element
  TextEditingController get _geminiFallbackModelController;

  // ignore: unused_element
  Timer? get _lansweeperSettingsDebounceTimer;
  // ignore: unused_element
  set _lansweeperSettingsDebounceTimer(Timer? value);

  // ignore: unused_element
  String? get _lastPrefilledKey;
  // ignore: unused_element
  set _lastPrefilledKey(String? value);

  // ignore: unused_element
  bool get _aiSuggestRunning;
  // ignore: unused_element
  set _aiSuggestRunning(bool value);

  // ignore: unused_element
  Timer? get _aiSuggestTicker;
  // ignore: unused_element
  set _aiSuggestTicker(Timer? value);

  // ignore: unused_element
  Stopwatch get _aiSuggestStopwatch;

  // ignore: unused_element
  double get _aiSuggestElapsedSeconds;
  // ignore: unused_element
  set _aiSuggestElapsedSeconds(double value);

  // ignore: unused_element
  String? get _aiCurrentModel;
  // ignore: unused_element
  set _aiCurrentModel(String? value);

  // ignore: unused_element
  http.Client? get _aiSuggestClient;
  // ignore: unused_element
  set _aiSuggestClient(http.Client? value);

  // ignore: unused_element
  _LansweeperReportFilter get _reportFilter;
  // ignore: unused_element
  set _reportFilter(_LansweeperReportFilter value);

  void _showDialogSnackBar(SnackBar snackBar, {String? copyText});

  // ignore: unused_element — απαιτείται από part mixins· ο analyzer δεν το ανιχνεύει.
  Future<void> _openTicketViewInBrowser(String ticketId);

  // ignore: unused_element
  String _callerLabel(CallModel call);
  // ignore: unused_element
  String _notes(CallModel call);
  // ignore: unused_element
  String _selectedKeysSignature(List<_ReportCallItem> selected);
  // ignore: unused_element
  String _combinedSelectedNotes(List<_ReportCallItem> selected);
  // ignore: unused_element
  String _combinedGeminiIssue(List<_ReportCallItem> selected);
  // ignore: unused_element
  String _combinedUniqueCallField(
    List<_ReportCallItem> selected,
    String? Function(CallModel call) read,
  );
  // ignore: unused_element
  String _details(CallModel call);
  // ignore: unused_element
  String _durationLabel(int seconds);
  // ignore: unused_element
  String _totalDurationLabel(int totalSeconds);
  // ignore: unused_element
  List<_ReportCallItem> _toItems(List<CallModel> calls);
  // ignore: unused_element
  void _toggleGroup(List<_ReportCallItem> items, bool? checked);
  // ignore: unused_element
  void _toggleItem(_ReportCallItem item, bool? checked);
  // ignore: unused_element
  _ReportCallItem? _primarySelectedItem(List<_ReportCallItem> allItems);
  // ignore: unused_element
  String _normalizedLansweeperState(_ReportCallItem item);
  // ignore: unused_element
  bool _isRegisteredCall(_ReportCallItem item);
  // ignore: unused_element
  bool _isFailedCall(_ReportCallItem item);
  // ignore: unused_element
  List<_ReportCallItem> _filterReportItems(List<_ReportCallItem> items);
}

class _LansweeperReportDialogState extends ConsumerState<LansweeperReportDialog>
    with
        LansweeperReportDialogStateHost,
        LansweeperReportSettingsMixin,
        LansweeperReportItemsMixin,
        LansweeperReportBrowserMixin,
        LansweeperReportGeminiMixin,
        LansweeperReportRegistrationMixin {
  @override
  final Set<String> _selectedKeys = <String>{};
  @override
  final SpellCheckController _titleController = SpellCheckController();
  @override
  final SpellCheckController _notesController = SpellCheckController();
  @override
  final SpellCheckController _solutionController = SpellCheckController();
  @override
  final TextEditingController _lansweeperAgentUsernameController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperApiUrlController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperTicketFormUrlController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperTicketViewUrlController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperApiKeyController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperLoginUrlController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperHelpdeskUsernameController =
      TextEditingController();
  @override
  final TextEditingController _lansweeperHelpdeskPasswordController =
      TextEditingController();
  @override
  final TextEditingController _geminiApiKeyController = TextEditingController();
  @override
  final GeminiPromptTemplateTextEditingController
  _geminiPromptTemplateController =
      GeminiPromptTemplateTextEditingController();
  @override
  final TextEditingController _geminiEndpointController =
      TextEditingController();
  @override
  final TextEditingController _geminiPrimaryModelController =
      TextEditingController();
  @override
  final TextEditingController _geminiFallbackModelController =
      TextEditingController();
  ProviderSubscription<String>? _lansweeperApiUrlSub;
  ProviderSubscription<String>? _lansweeperTicketFormUrlSub;
  ProviderSubscription<String>? _lansweeperTicketViewUrlSub;
  ProviderSubscription<String>? _lansweeperApiKeySub;
  ProviderSubscription<String>? _lansweeperAgentUsernameSub;
  ProviderSubscription<String>? _lansweeperLoginUrlSub;
  ProviderSubscription<String>? _lansweeperHelpdeskUsernameSub;
  ProviderSubscription<String>? _lansweeperHelpdeskPasswordSub;
  ProviderSubscription<String>? _geminiApiKeySub;
  ProviderSubscription<String>? _geminiPromptTemplateSub;
  ProviderSubscription<String>? _geminiEndpointSub;
  ProviderSubscription<String>? _geminiPrimaryModelSub;
  ProviderSubscription<String>? _geminiFallbackModelSub;
  @override
  Timer? _lansweeperSettingsDebounceTimer;
  @override
  String? _lastPrefilledKey;
  @override
  bool _aiSuggestRunning = false;
  @override
  Timer? _aiSuggestTicker;
  @override
  final Stopwatch _aiSuggestStopwatch = Stopwatch();
  @override
  double _aiSuggestElapsedSeconds = 0;
  @override
  http.Client? _aiSuggestClient;
  @override
  String? _aiCurrentModel;
  final GlobalKey<ScaffoldMessengerState> _dialogMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void _showDialogSnackBar(SnackBar snackBar, {String? copyText}) {
    if (!mounted) return;
    final messenger = _dialogMessengerKey.currentState;
    if (messenger == null) return;

    final textToCopy = (copyText ?? '').trim();
    if (textToCopy.isEmpty) {
      messenger.showSnackBar(snackBar);
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: snackBar.content),
            IconButton(
              tooltip: 'Αντιγραφή',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              color: Theme.of(context).colorScheme.inversePrimary,
              onPressed: () => unawaited(_copyDialogSnackBarText(textToCopy)),
            ),
          ],
        ),
        duration: snackBar.duration,
        behavior: snackBar.behavior,
      ),
    );
  }

  Future<void> _copyDialogSnackBarText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _dialogMessengerKey.currentState?.hideCurrentSnackBar();
    _showDialogSnackBar(
      const SnackBar(
        content: Text('Αντιγραφή στο πρόχειρο.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  _LansweeperReportFilter _reportFilter = _LansweeperReportFilter.unsentOnly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lansweeperApiUrlController.text = ref.read(lansweeperApiUrlProvider);
      _lansweeperTicketFormUrlController.text = ref.read(
        lansweeperTicketFormUrlProvider,
      );
      _lansweeperTicketViewUrlController.text = ref.read(
        lansweeperTicketViewUrlProvider,
      );
      _lansweeperApiKeyController.text = ref.read(lansweeperApiKeyProvider);
      _lansweeperAgentUsernameController.text = ref.read(
        lansweeperAgentUsernameProvider,
      );
      _lansweeperLoginUrlController.text = ref.read(
        lansweeperHelpdeskLoginUrlProvider,
      );
      _lansweeperHelpdeskUsernameController.text = ref.read(
        lansweeperHelpdeskWebUsernameProvider,
      );
      _lansweeperHelpdeskPasswordController.text = ref.read(
        lansweeperHelpdeskWebPasswordProvider,
      );
      _geminiApiKeyController.text = ref.read(geminiApiKeyProvider);
      _geminiPromptTemplateController.text = ref.read(
        geminiPromptTemplateProvider,
      );
      _geminiEndpointController.text = ref.read(geminiEndpointProvider);
      _geminiPrimaryModelController.text = ref.read(geminiPrimaryModelProvider);
      _geminiFallbackModelController.text = ref.read(
        geminiFallbackModelProvider,
      );
      if (!mounted) return;
      unawaited(
        ref.read(lansweeperConnectionProbeProvider.notifier).ensureCheck(),
      );
    });
    _lansweeperApiUrlSub = ref.listenManual<String>(lansweeperApiUrlProvider, (
      _,
      next,
    ) {
      if (_lansweeperApiUrlController.text == next) return;
      _lansweeperApiUrlController.text = next;
    });
    _lansweeperTicketFormUrlSub = ref.listenManual<String>(
      lansweeperTicketFormUrlProvider,
      (_, next) {
        if (_lansweeperTicketFormUrlController.text == next) return;
        _lansweeperTicketFormUrlController.text = next;
      },
    );
    _lansweeperTicketViewUrlSub = ref.listenManual<String>(
      lansweeperTicketViewUrlProvider,
      (_, next) {
        if (_lansweeperTicketViewUrlController.text == next) return;
        _lansweeperTicketViewUrlController.text = next;
      },
    );
    _lansweeperApiKeySub = ref.listenManual<String>(lansweeperApiKeyProvider, (
      _,
      next,
    ) {
      if (_lansweeperApiKeyController.text == next) return;
      _lansweeperApiKeyController.text = next;
    });
    _lansweeperAgentUsernameSub = ref.listenManual<String>(
      lansweeperAgentUsernameProvider,
      (_, next) {
        if (_lansweeperAgentUsernameController.text == next) return;
        _lansweeperAgentUsernameController.text = next;
      },
    );
    _lansweeperLoginUrlSub = ref.listenManual<String>(
      lansweeperHelpdeskLoginUrlProvider,
      (_, next) {
        if (_lansweeperLoginUrlController.text == next) return;
        _lansweeperLoginUrlController.text = next;
      },
    );
    _lansweeperHelpdeskUsernameSub = ref.listenManual<String>(
      lansweeperHelpdeskWebUsernameProvider,
      (_, next) {
        if (_lansweeperHelpdeskUsernameController.text == next) return;
        _lansweeperHelpdeskUsernameController.text = next;
      },
    );
    _lansweeperHelpdeskPasswordSub = ref.listenManual<String>(
      lansweeperHelpdeskWebPasswordProvider,
      (_, next) {
        if (_lansweeperHelpdeskPasswordController.text == next) return;
        _lansweeperHelpdeskPasswordController.text = next;
      },
    );
    _geminiApiKeySub = ref.listenManual<String>(geminiApiKeyProvider, (
      _,
      next,
    ) {
      if (_geminiApiKeyController.text == next) return;
      _geminiApiKeyController.text = next;
    });
    _geminiPromptTemplateSub = ref.listenManual<String>(
      geminiPromptTemplateProvider,
      (_, next) {
        if (_geminiPromptTemplateController.text == next) return;
        _geminiPromptTemplateController.text = next;
      },
    );
    _geminiEndpointSub = ref.listenManual<String>(geminiEndpointProvider, (
      _,
      next,
    ) {
      if (_geminiEndpointController.text == next) return;
      _geminiEndpointController.text = next;
    });
    _geminiPrimaryModelSub = ref.listenManual<String>(
      geminiPrimaryModelProvider,
      (_, next) {
        if (_geminiPrimaryModelController.text == next) return;
        _geminiPrimaryModelController.text = next;
      },
    );
    _geminiFallbackModelSub = ref.listenManual<String>(
      geminiFallbackModelProvider,
      (_, next) {
        if (_geminiFallbackModelController.text == next) return;
        _geminiFallbackModelController.text = next;
      },
    );
  }

  bool _connectionReady(LansweeperConnectionStatus status) {
    return status is LansweeperConnectionAvailable;
  }

  Widget _wrapLansweeperConnectionTooltip({
    required LansweeperConnectionStatus status,
    required Widget child,
  }) {
    if (status case LansweeperConnectionUnavailable(:final reason)) {
      return Tooltip(message: reason, child: child);
    }
    return child;
  }

  Widget _connectionAwareIcon({
    required LansweeperConnectionStatus status,
    required IconData icon,
  }) {
    if (status is LansweeperConnectionChecking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(icon);
  }

  @override
  void dispose() {
    _aiSuggestTicker?.cancel();
    _aiSuggestStopwatch.stop();
    _aiSuggestClient?.close();
    _lansweeperSettingsDebounceTimer?.cancel();
    _lansweeperApiUrlSub?.close();
    _lansweeperTicketFormUrlSub?.close();
    _lansweeperTicketViewUrlSub?.close();
    _lansweeperApiKeySub?.close();
    _lansweeperAgentUsernameSub?.close();
    _lansweeperLoginUrlSub?.close();
    _lansweeperHelpdeskUsernameSub?.close();
    _lansweeperHelpdeskPasswordSub?.close();
    _geminiApiKeySub?.close();
    _geminiPromptTemplateSub?.close();
    _geminiEndpointSub?.close();
    _geminiPrimaryModelSub?.close();
    _geminiFallbackModelSub?.close();
    _lansweeperApiUrlController.dispose();
    _lansweeperTicketFormUrlController.dispose();
    _lansweeperTicketViewUrlController.dispose();
    _lansweeperApiKeyController.dispose();
    _lansweeperLoginUrlController.dispose();
    _lansweeperHelpdeskUsernameController.dispose();
    _lansweeperHelpdeskPasswordController.dispose();
    _lansweeperAgentUsernameController.dispose();
    _geminiApiKeyController.dispose();
    _geminiPromptTemplateController.dispose();
    _geminiEndpointController.dispose();
    _geminiPrimaryModelController.dispose();
    _geminiFallbackModelController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    _solutionController.dispose();
    super.dispose();
  }

  Widget _wrapOptionalTooltip({
    required Widget child,
    String? message,
  }) {
    if (message == null || message.isEmpty) return child;
    return Tooltip(message: message, child: child);
  }

  bool _canSetSelectedToState(
    List<_ReportCallItem> selected,
    String targetState,
  ) {
    if (selected.isEmpty) return false;
    final states = selected.map(_normalizedLansweeperState).toSet();
    if (states.length > 1) return true;
    return states.single != targetState;
  }

  String? _disabledStateButtonTooltip(
    List<_ReportCallItem> selected,
    String targetState, {
    required bool isLoading,
  }) {
    if (isLoading) return 'Αναμονή λειτουργίας Lansweeper…';
    if (selected.isEmpty) {
      return 'Επιλέξτε μία ή περισσότερες κλήσεις';
    }
    final states = selected.map(_normalizedLansweeperState).toSet();
    if (states.length > 1) return null;
    if (states.single != targetState) return null;
    return switch (targetState) {
      LansweeperSyncState.excluded =>
        'Όλες οι επιλεγμένες είναι ήδη εξαιρεσμένες',
      LansweeperSyncState.unsent =>
        'Όλες οι επιλεγμένες είναι ήδη ακαταχώρητες',
      LansweeperSyncState.sent =>
        'Όλες οι επιλεγμένες είναι ήδη καταχωρημένες',
      _ => null,
    };
  }

  Widget _buildLansweeperStateButton({
    required List<_ReportCallItem> selected,
    required bool isLoading,
    required String targetState,
    required String label,
    required Future<void> Function() onPressed,
    bool allowWhen = true,
    String? blockedTooltip,
  }) {
    final baseEnabled =
        !isLoading && _canSetSelectedToState(selected, targetState);
    final enabled = baseEnabled && allowWhen;
    final tooltip = !allowWhen && blockedTooltip != null
        ? blockedTooltip
        : _disabledStateButtonTooltip(
            selected,
            targetState,
            isLoading: isLoading,
          );
    final button = OutlinedButton(
      onPressed: enabled ? () => unawaited(onPressed()) : null,
      child: Text(label),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }

  Widget _reportFilterChip({
    required String label,
    required String tooltip,
    required bool selected,
    VoidCallback? onSelect,
  }) {
    return Tooltip(
      message: tooltip,
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelect == null ? null : (_) => onSelect(),
      ),
    );
  }

  static const String _noCallsInRangeFilterTooltip =
      'Δεν υπάρχουν κλήσεις στο τρέχον εύρος ημερομηνιών';

  Widget _buildReportFilterBar({
    required bool hasAnyCallsInRange,
    required String reportRangeTitle,
  }) {
    final disabledTooltip =
        '$_noCallsInRangeFilterTooltip («$reportRangeTitle»).';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _reportFilterChip(
          label: 'Ακαταχώρητες',
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που δεν έχουν καταχωρηθεί στο Lansweeper.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              _reportFilter == _LansweeperReportFilter.unsentOnly,
          onSelect: hasAnyCallsInRange
              ? () => setState(
                  () => _reportFilter = _LansweeperReportFilter.unsentOnly,
                )
              : null,
        ),
        _reportFilterChip(
          label: 'Καταχωρημένες',
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που έχουν καταχωρηθεί στο Lansweeper. '
                    'Δεν είναι υποχρεωτικό αλλά επιθυμητό το αναγνωριστικό αιτήματος (ticket id).'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              _reportFilter == _LansweeperReportFilter.sentOnly,
          onSelect: hasAnyCallsInRange
              ? () => setState(
                  () => _reportFilter = _LansweeperReportFilter.sentOnly,
                )
              : null,
        ),
        _reportFilterChip(
          label: 'Εξαιρεμένες',
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που δεν υπάρχει λόγος να καταχωρηθούν στο Lansweeper.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              _reportFilter == _LansweeperReportFilter.excludedOnly,
          onSelect: hasAnyCallsInRange
              ? () => setState(
                  () => _reportFilter = _LansweeperReportFilter.excludedOnly,
                )
              : null,
        ),
        _reportFilterChip(
          label: 'Αποτυχημένες',
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που απέτυχαν να καταχωρηθούν στο Lansweeper '
                    'με αυτόματο τρόπο.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              _reportFilter == _LansweeperReportFilter.failedOnly,
          onSelect: hasAnyCallsInRange
              ? () => setState(
                  () => _reportFilter = _LansweeperReportFilter.failedOnly,
                )
              : null,
        ),
        _reportFilterChip(
          label: 'Όλες',
          tooltip: hasAnyCallsInRange
              ? 'Εμφάνιση όλων των κλήσεων.'
              : 'Εμφάνιση όλων των κλήσεων στο εύρος «$reportRangeTitle» (κενό).',
          selected: !hasAnyCallsInRange ||
              _reportFilter == _LansweeperReportFilter.all,
          onSelect: hasAnyCallsInRange
              ? () => setState(
                  () => _reportFilter = _LansweeperReportFilter.all,
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildNoCallsInRangeEmptyState(
    BuildContext context,
    String reportRangeTitle,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Δεν βρέθηκαν κλήσεις',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Στο εύρος «$reportRangeTitle» δεν υπάρχουν κλήσεις.\n\n'
              'Αλλάξτε το φίλτρο ημερομηνίας στον πίνακα ελέγχου '
              'και ανοίξτε ξανά την αναφορά.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(dashboardCallsForReportProvider);
    final dashboardFilter = ref.watch(dashboardFilterProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final reportRangeTitle = statsAsync.when(
      loading: () => dashboardFilter.dateFrom == null &&
              dashboardFilter.dateTo == null
          ? 'Όλες: …'
          : dashboardFilter.kpiTotalCallsRangeTitle(),
      error: (_, _) => dashboardFilter.lansweeperReportRangeTitle(),
      data: (stats) => dashboardFilter.lansweeperReportRangeTitle(
        historyDateFrom: stats.historyDateFrom,
        historyDateTo: stats.historyDateTo,
      ),
    );
    final lansweeperApiUrl = ref.watch(lansweeperApiUrlProvider);
    final lansweeperTicketFormUrl = ref.watch(lansweeperTicketFormUrlProvider);
    final lansweeperTicketViewUrl = ref.watch(lansweeperTicketViewUrlProvider);
    final syncState = ref.watch(lansweeperSyncProvider);
    final connectionStatus = ref.watch(lansweeperConnectionProbeProvider);
    final geminiApiKey = ref.watch(geminiApiKeyProvider);
    final connectionReady = _connectionReady(connectionStatus);
    final canSubmitToApi = LansweeperUrlRules.isApiEndpointUrl(
      lansweeperApiUrl,
    );
    final canOpenTicketForm = LansweeperUrlRules.isBrowserLaunchableUrl(
      lansweeperTicketFormUrl,
    );
    final hasAnyCallsInRange = callsAsync.maybeWhen(
      data: (calls) => calls.isNotEmpty,
      orElse: () => true,
    );

    ref.listen(dashboardCallsForReportProvider, (previous, next) {
      next.whenData((calls) {
        if (calls.isNotEmpty || !mounted) return;
        if (_reportFilter == _LansweeperReportFilter.all) return;
        setState(() => _reportFilter = _LansweeperReportFilter.all);
      });
    });

    return ScaffoldMessenger(
      key: _dialogMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AlertDialog(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Αναφορά Lansweeper · $reportRangeTitle',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip:
                'Ρυθμίσεις Lansweeper (API, φόρμα, πράκτορας, αυτόματη σύνδεση Help Desk)',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () {
              unawaited(_openLansweeperConnectionSettingsDialog());
            },
            icon: Image.asset(
              'assets/lansweeper_settings.png',
              height: 28,
              width: 28,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildReportFilterBar(
              hasAnyCallsInRange: hasAnyCallsInRange,
              reportRangeTitle: reportRangeTitle,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: callsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Σφάλμα φόρτωσης κλήσεων: $e')),
                data: (calls) {
                  final allItems = _toItems(calls);
                  final items = _filterReportItems(allItems);
                  final grouped = _groupByCaller(items);
                  final groupedRows = _groupedRowData(grouped);
                  final itemByKey = {
                    for (final item in items) item.key: item,
                  };
                  final selected = items
                      .where((e) => _selectedKeys.contains(e.key))
                      .toList();
                  final primarySelected = _primarySelectedItem(items);
                  final isPrimaryRegistered = primarySelected != null &&
                      _isRegisteredCall(primarySelected);
                  final isPrimaryFailed =
                      primarySelected != null && _isFailedCall(primarySelected);
                  final canImmediateApiSubmit = primarySelected != null &&
                      !syncState.isLoading &&
                      canSubmitToApi &&
                      connectionReady &&
                      !isPrimaryRegistered;
                  final canResubmitApi = canImmediateApiSubmit && isPrimaryFailed;
                  if (primarySelected != null && selected.isNotEmpty) {
                    _prefillForm(primarySelected, selected);
                  }
                  final totalSelectedSeconds = selected.fold<int>(
                    0,
                    (sum, item) => sum + item.durationSeconds,
                  );
                  final selectedCallId = primarySelected?.call.id;
                  final geminiKeyReady = geminiApiKey.trim().isNotEmpty;
                  final aiSuggestEnabled =
                      selected.isNotEmpty && geminiKeyReady && !_aiSuggestRunning;
                  final aiSuggestTooltip = selected.isEmpty
                      ? 'Επιλέξτε κλήση'
                      : !geminiKeyReady
                      ? 'Ορίστε Gemini API key στις ρυθμίσεις'
                      : null;
                  final promptPreviewEnabled =
                      selected.isNotEmpty && !_aiSuggestRunning;
                  final promptPreviewTooltip = selected.isEmpty
                      ? 'Επιλέξτε κλήση'
                      : _aiSuggestRunning
                      ? 'Περιμένετε την ολοκλήρωση της πρότασης'
                      : null;
                  final linksAsync = selectedCallId != null
                      ? ref.watch(callExternalLinksProvider(selectedCallId))
                      : const AsyncData<List<Map<String, dynamic>>>(
                          <Map<String, dynamic>>[],
                        );

                  if (allItems.isEmpty) {
                    return _buildNoCallsInRangeEmptyState(
                      context,
                      reportRangeTitle,
                    );
                  }
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Δεν υπάρχουν κλήσεις στην επιλεγμένη κατηγορία '
                          'Lansweeper.\n'
                          'Δοκιμάστε άλλο φίλτρο (π.χ. «Όλες»).',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Επιλεγμένες: ${selected.length} | '
                                'Σύνολο διάρκειας: '
                                '${_totalDurationLabel(totalSelectedSeconds)}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: LansweeperReportCallList(
                                  grouped: groupedRows,
                                  selectedKeys: _selectedKeys,
                                  totalDurationLabel: _totalDurationLabel,
                                  ticketViewUrlTemplate:
                                      lansweeperTicketViewUrl,
                                  isSyncLoading: syncState.isLoading,
                                  ticketLinkEnabled: connectionReady,
                                  onToggleGroup: (groupItems, checked) {
                                    _toggleGroup(
                                      groupItems
                                          .map((row) => itemByKey[row.key]!)
                                          .toList(),
                                      checked,
                                    );
                                  },
                                  onToggleItem: (row, checked) {
                                    _toggleItem(itemByKey[row.key]!, checked);
                                  },
                                  onBadgePressed: (row) {
                                    unawaited(
                                      _toggleRegistrationFromBadge(
                                        itemByKey[row.key]!,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LansweeperSyncForm(
                                  titleController: _titleController,
                                  notesController: _notesController,
                                  solutionController: _solutionController,
                                  isSuggesting: _aiSuggestRunning,
                                  suggestModelLabel: _aiSuggestRunning
                                      ? _aiCurrentModel
                                      : null,
                                  suggestElapsedLabel: _aiSuggestRunning
                                      ? _aiSuggestElapsedSeconds
                                          .toStringAsFixed(2)
                                      : null,
                                  suggestDisabledTooltip: aiSuggestTooltip,
                                  onSuggest: aiSuggestEnabled
                                      ? () => unawaited(
                                          _suggestWithAi(selected),
                                        )
                                      : null,
                                  previewDisabledTooltip: promptPreviewTooltip,
                                  onPreviewPrompt: promptPreviewEnabled
                                      ? () => unawaited(
                                          _showGeminiPromptPreview(selected),
                                        )
                                      : null,
                                  onEditPromptTemplate: () => unawaited(
                                    _openGeminiPromptTemplateEditorDialog(),
                                  ),
                                ),
                                    const SizedBox(height: 10),
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _wrapOptionalTooltip(
                                              message: isPrimaryRegistered
                                                  ? 'Η κλήση είναι ήδη καταχωρημένη'
                                                  : null,
                                              child: _wrapLansweeperConnectionTooltip(
                                                status: connectionStatus,
                                                child: FilledButton.icon(
                                                  onPressed: canImmediateApiSubmit
                                                      ? () => unawaited(
                                                          _submitSelected(
                                                            primarySelected,
                                                            selected,
                                                            resubmit: false,
                                                          ),
                                                        )
                                                      : null,
                                                  icon: _connectionAwareIcon(
                                                    status: connectionStatus,
                                                    icon: Icons
                                                        .cloud_upload_rounded,
                                                  ),
                                                  label: const Text(
                                                    'Άμεση Καταχώρηση',
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (isPrimaryFailed)
                                              _wrapLansweeperConnectionTooltip(
                                                status: connectionStatus,
                                                child: OutlinedButton.icon(
                                                  onPressed: canResubmitApi
                                                      ? () => unawaited(
                                                          _submitSelected(
                                                            primarySelected,
                                                            selected,
                                                            resubmit: true,
                                                          ),
                                                        )
                                                      : null,
                                                  icon: _connectionAwareIcon(
                                                    status: connectionStatus,
                                                    icon: Icons.refresh_rounded,
                                                  ),
                                                  label: const Text(
                                                    'Επαναϋποβολή',
                                                  ),
                                                ),
                                              ),
                                            OutlinedButton.icon(
                                              onPressed:
                                                  (primarySelected != null &&
                                                      !syncState.isLoading)
                                                  ? () => _manualMark(
                                                      primarySelected,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.edit_note_rounded,
                                              ),
                                              label: const Text(
                                                'Χειροκίνητη Σήμανση',
                                              ),
                                            ),
                                            _buildLansweeperStateButton(
                                              selected: selected,
                                              isLoading: syncState.isLoading,
                                              targetState:
                                                  LansweeperSyncState.excluded,
                                              label: 'Εξαίρεση',
                                              allowWhen: !isPrimaryRegistered,
                                              blockedTooltip:
                                                  'Η κλήση είναι ήδη καταχωρημένη',
                                              onPressed: () =>
                                                  _setStateForAllSelected(
                                                    selected,
                                                    LansweeperSyncState
                                                        .excluded,
                                                  ),
                                            ),
                                            _buildLansweeperStateButton(
                                              selected: selected,
                                              isLoading: syncState.isLoading,
                                              targetState:
                                                  LansweeperSyncState.unsent,
                                              label: 'Ακαταχώρητη',
                                              onPressed: () =>
                                                  _setStateForAllSelected(
                                                    selected,
                                                    LansweeperSyncState.unsent,
                                                  ),
                                            ),
                                            _buildLansweeperStateButton(
                                              selected: selected,
                                              isLoading: syncState.isLoading,
                                              targetState:
                                                  LansweeperSyncState.sent,
                                              label: 'Καταχωρημένη',
                                              onPressed: () =>
                                                  _setStateForAllSelected(
                                                    selected,
                                                    LansweeperSyncState.sent,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    linksAsync.when(
                                      loading: () => const Card(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                      ),
                                      error: (e, _) => Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text('Σφάλμα ιστορικού: $e'),
                                        ),
                                      ),
                                      data: (links) =>
                                          SyncHistoryList(links: links),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ],
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
          child: const Text('Κλείσιμο'),
        ),
        callsAsync.maybeWhen(
          data: (calls) {
            if (calls.isEmpty) return const SizedBox.shrink();
            final items = _toItems(calls);
            final selected = items
                .where((e) => _selectedKeys.contains(e.key))
                .toList();
            final totalSelectedSeconds = selected.fold<int>(
              0,
              (sum, item) => sum + item.durationSeconds,
            );
            final hasSelection = selected.isNotEmpty;
            final hasFormText =
                _titleController.text.trim().isNotEmpty ||
                _notesController.text.trim().isNotEmpty ||
                _solutionController.text.trim().isNotEmpty;
            return _wrapLansweeperConnectionTooltip(
              status: connectionStatus,
              child: FilledButton.icon(
                onPressed: (hasSelection || hasFormText) &&
                        canOpenTicketForm &&
                        connectionReady
                    ? () => _copyAndOpen(
                        ticketFormUrl: lansweeperTicketFormUrl,
                        durationSeconds: hasSelection ? totalSelectedSeconds : null,
                      )
                    : null,
                icon: _connectionAwareIcon(
                  status: connectionStatus,
                  icon: Icons.open_in_new_rounded,
                ),
                label: const Text('Αντιγραφή & Άνοιγμα Lansweeper'),
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      ],
          ),
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: SafeArea(
                child: QuickCallFloatingButton(
                  scope: QuickCallFabScope.overlayRoute,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
