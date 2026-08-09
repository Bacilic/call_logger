import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/dialog_snackbar_scope.dart';
import '../../../core/widgets/app_asset_image.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/services/ai_prompt_template_controller.dart';
import '../../../core/widgets/quick_call_fab.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../models/lansweeper_connection_status.dart';
import '../models/lansweeper_report_scope.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/dashboard_provider.dart';
import '../providers/gemini_settings_provider.dart';
import '../providers/lansweeper_connection_probe_provider.dart';
import '../providers/lansweeper_report_scope_provider.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../providers/lansweeper_ticket_submit_config_provider.dart';
import 'lansweeper/lansweeper_report_call_list.dart';
import 'lansweeper/lansweeper_report_filter.dart';
import 'lansweeper/lansweeper_report_filter_bar.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper/lansweeper_report_range_bar.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper/lansweeper_sync_form.dart';
import 'lansweeper/sync_history_list.dart';
import 'lansweeper_report_ai.dart';
import 'lansweeper_report_browser.dart';
import 'lansweeper_report_items.dart';
import 'lansweeper_report_knowledge.dart';
import 'lansweeper_report_registration.dart';
import 'lansweeper_report_settings.dart';

class LansweeperReportDialog extends ConsumerStatefulWidget {
  const LansweeperReportDialog({super.key});

  @override
  ConsumerState<LansweeperReportDialog> createState() =>
      LansweeperReportDialogState();
}

/// Δημόσιο State: τα κοινά πεδία της αναφοράς είναι ορατά στους συνεργάτες
/// (ρυθμίσεις, επιλογή, περιηγητής, AI, καταχώρηση) — Σύνθεση.
class LansweeperReportDialogState extends ConsumerState<LansweeperReportDialog>
    with DialogSnackbarHost {
  /// Ρυθμίσεις σύνδεσης Lansweeper/Gemini (διάλογοι, αποθήκευση).
  late final LansweeperReportSettings settingsFlow = LansweeperReportSettings(
    this,
  );

  /// Επιλογή/φιλτράρισμα στοιχείων αναφοράς.
  late final LansweeperReportSelection selectionFlow =
      LansweeperReportSelection(this);

  /// Άνοιγμα σελίδων Lansweeper στον περιηγητή.
  late final LansweeperReportBrowser browserFlow = LansweeperReportBrowser(
    this,
  );

  /// Προσυμπλήρωση φόρμας και προτάσεις AI.
  late final LansweeperReportAi aiFlow = LansweeperReportAi(this);

  /// Καταχώρηση κλήσεων (API, χειροκίνητη, μαζική).
  late final LansweeperReportRegistration registrationFlow =
      LansweeperReportRegistration(this);

  /// «Αποθήκευση ως γνώση» — η λύση γίνεται άρθρο Βάσης Γνώσης.
  late final LansweeperReportKnowledge knowledgeFlow =
      LansweeperReportKnowledge(this);

  final Set<String> selectedKeys = <String>{};
  final SpellCheckController titleController = SpellCheckController();
  final SpellCheckController notesController = SpellCheckController();
  final SpellCheckController solutionController = SpellCheckController();
  final TextEditingController lansweeperAgentUsernameController =
      TextEditingController();
  final TextEditingController lansweeperApiUrlController =
      TextEditingController();
  final TextEditingController lansweeperTicketFormUrlController =
      TextEditingController();
  final TextEditingController lansweeperTicketViewUrlController =
      TextEditingController();
  final TextEditingController lansweeperApiKeyController =
      TextEditingController();
  final TextEditingController lansweeperLoginUrlController =
      TextEditingController();
  final TextEditingController lansweeperHelpdeskUsernameController =
      TextEditingController();
  final TextEditingController lansweeperHelpdeskPasswordController =
      TextEditingController();
  final TextEditingController geminiApiKeyController = TextEditingController();
  final AiPromptTemplateTextEditingController aiPromptTemplateController =
      AiPromptTemplateTextEditingController();
  final TextEditingController geminiEndpointController =
      TextEditingController();
  final TextEditingController geminiPrimaryModelController =
      TextEditingController();
  final TextEditingController geminiFallbackModelController =
      TextEditingController();
  final Map<String, String> customFieldValues = <String, String>{};

  /// Το κείμενο ακριβώς όπως το γύρισε η τελευταία «Πρόταση ΤΝ», για να ξέρει η
  /// κλήση αν στάλθηκε η πρόταση ως έχει ή η διορθωμένη εκδοχή της. `null` όσο
  /// δεν έχει τρέξει πρόταση — τότε ό,τι σταλεί είναι χειρόγραφο.
  String? aiSuggestedNotes;
  String? aiSuggestedSolution;

  String? selectedTicketState;
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
  Timer? lansweeperSettingsDebounceTimer;
  String? lastPrefilledKey;
  bool aiSuggestRunning = false;
  Timer? aiSuggestTicker;
  final Stopwatch aiSuggestStopwatch = Stopwatch();
  double aiSuggestElapsedSeconds = 0;
  http.Client? aiSuggestClient;
  String? aiCurrentModel;
  DateTime? aiCooldownUntil;
  String? aiCooldownModel;
  Timer? aiCooldownTicker;
  bool aiAutoResubmitArmed = false;
  List<ReportCallItem>? aiLastSuggestSelection;

  LansweeperReportFilter reportFilter = LansweeperReportFilter.unsentOnly;

  /// Αλλαγή χρονικού πλαισίου από τα chips της κεφαλίδας.
  ///
  /// Το «όλες οι ακαταχώρητες» ζητά ρητά μία κατάσταση, οπότε επαναφέρει και την
  /// καρτέλα — αλλιώς ο χρήστης θα ζητούσε τις ακαταχώρητες και θα έβλεπε τις
  /// καταχωρημένες όλων των εποχών.
  void _selectRange(LansweeperReportRange range) {
    ref
        .read(lansweeperReportScopeProvider.notifier)
        .set(LansweeperReportScope.range(range));
    if (range == LansweeperReportRange.allUnregistered) {
      setState(() => reportFilter = LansweeperReportFilter.unsentOnly);
    }
  }

  /// Σηματοδοτεί ανανέωση της αναφοράς (rebuild) — χρήση και από συνεργάτες.
  void notifyReportChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      lansweeperApiUrlController.text = ref.read(lansweeperApiUrlProvider);
      lansweeperTicketFormUrlController.text = ref.read(
        lansweeperTicketFormUrlProvider,
      );
      lansweeperTicketViewUrlController.text = ref.read(
        lansweeperTicketViewUrlProvider,
      );
      lansweeperApiKeyController.text = ref.read(lansweeperApiKeyProvider);
      lansweeperAgentUsernameController.text = ref.read(
        lansweeperAgentUsernameProvider,
      );
      lansweeperLoginUrlController.text = ref.read(
        lansweeperHelpdeskLoginUrlProvider,
      );
      lansweeperHelpdeskUsernameController.text = ref.read(
        lansweeperHelpdeskWebUsernameProvider,
      );
      lansweeperHelpdeskPasswordController.text = ref.read(
        lansweeperHelpdeskWebPasswordProvider,
      );
      geminiApiKeyController.text = ref.read(geminiApiKeyProvider);
      aiPromptTemplateController.text = ref.read(geminiPromptTemplateProvider);
      geminiEndpointController.text = ref.read(geminiEndpointProvider);
      geminiPrimaryModelController.text = ref.read(geminiPrimaryModelProvider);
      geminiFallbackModelController.text = ref.read(
        geminiFallbackModelProvider,
      );
      if (!mounted) return;
      unawaited(
        ref.read(lansweeperConnectionProbeProvider.notifier).ensureCheck(),
      );
      unawaited(hydrateTicketSubmitFormPrefs());
    });
    _lansweeperApiUrlSub = ref.listenManual<String>(lansweeperApiUrlProvider, (
      _,
      next,
    ) {
      if (lansweeperApiUrlController.text == next) return;
      lansweeperApiUrlController.text = next;
    });
    _lansweeperTicketFormUrlSub = ref.listenManual<String>(
      lansweeperTicketFormUrlProvider,
      (_, next) {
        if (lansweeperTicketFormUrlController.text == next) return;
        lansweeperTicketFormUrlController.text = next;
      },
    );
    _lansweeperTicketViewUrlSub = ref.listenManual<String>(
      lansweeperTicketViewUrlProvider,
      (_, next) {
        if (lansweeperTicketViewUrlController.text == next) return;
        lansweeperTicketViewUrlController.text = next;
      },
    );
    _lansweeperApiKeySub = ref.listenManual<String>(lansweeperApiKeyProvider, (
      _,
      next,
    ) {
      if (lansweeperApiKeyController.text == next) return;
      lansweeperApiKeyController.text = next;
    });
    _lansweeperAgentUsernameSub = ref.listenManual<String>(
      lansweeperAgentUsernameProvider,
      (_, next) {
        if (lansweeperAgentUsernameController.text == next) return;
        lansweeperAgentUsernameController.text = next;
      },
    );
    _lansweeperLoginUrlSub = ref.listenManual<String>(
      lansweeperHelpdeskLoginUrlProvider,
      (_, next) {
        if (lansweeperLoginUrlController.text == next) return;
        lansweeperLoginUrlController.text = next;
      },
    );
    _lansweeperHelpdeskUsernameSub = ref.listenManual<String>(
      lansweeperHelpdeskWebUsernameProvider,
      (_, next) {
        if (lansweeperHelpdeskUsernameController.text == next) return;
        lansweeperHelpdeskUsernameController.text = next;
      },
    );
    _lansweeperHelpdeskPasswordSub = ref.listenManual<String>(
      lansweeperHelpdeskWebPasswordProvider,
      (_, next) {
        if (lansweeperHelpdeskPasswordController.text == next) return;
        lansweeperHelpdeskPasswordController.text = next;
      },
    );
    _geminiApiKeySub = ref.listenManual<String>(geminiApiKeyProvider, (
      _,
      next,
    ) {
      if (geminiApiKeyController.text == next) return;
      geminiApiKeyController.text = next;
    });
    _geminiPromptTemplateSub = ref.listenManual<String>(
      geminiPromptTemplateProvider,
      (_, next) {
        if (aiPromptTemplateController.text == next) return;
        aiPromptTemplateController.text = next;
      },
    );
    _geminiEndpointSub = ref.listenManual<String>(geminiEndpointProvider, (
      _,
      next,
    ) {
      if (geminiEndpointController.text == next) return;
      geminiEndpointController.text = next;
    });
    _geminiPrimaryModelSub = ref.listenManual<String>(
      geminiPrimaryModelProvider,
      (_, next) {
        if (geminiPrimaryModelController.text == next) return;
        geminiPrimaryModelController.text = next;
      },
    );
    _geminiFallbackModelSub = ref.listenManual<String>(
      geminiFallbackModelProvider,
      (_, next) {
        if (geminiFallbackModelController.text == next) return;
        geminiFallbackModelController.text = next;
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

  Future<void> hydrateTicketSubmitFormPrefs() async {
    try {
      await ref
          .read(lansweeperTicketSubmitConfigProvider.notifier)
          .hydrationFuture;
    } catch (_) {}
    if (!mounted) return;
    final config = ref.read(lansweeperTicketSubmitConfigProvider);
    if (!config.rememberFormSelections) return;

    final db = await DatabaseHelper.instance.database;
    if (!mounted) return;
    final raw = await SettingsRepository(
      db,
    ).getSetting(kLansweeperTicketSubmitFormPrefsSettingKey);
    if (!mounted || raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final valuesRaw = map['customFieldValues'];
      final nextValues = <String, String>{};
      if (valuesRaw is Map) {
        valuesRaw.forEach((key, value) {
          if (key != null) {
            nextValues[key.toString()] = value?.toString() ?? '';
          }
        });
      }
      final ticketState = map['ticketState']?.toString();
      setState(() {
        customFieldValues
          ..clear()
          ..addAll(nextValues);
        if (ticketState != null && ticketState.trim().isNotEmpty) {
          selectedTicketState = ticketState.trim();
        }
      });
    } catch (_) {}
  }

  Future<void> persistTicketSubmitFormPrefs() async {
    final config = ref.read(lansweeperTicketSubmitConfigProvider);
    if (!config.rememberFormSelections) return;
    final payload = <String, dynamic>{
      'customFieldValues': Map<String, String>.from(customFieldValues),
      'ticketState': selectedTicketState ?? config.defaultTicketState,
    };
    final db = await DatabaseHelper.instance.database;
    if (!mounted) return;
    await SettingsRepository(db).saveSetting(
      kLansweeperTicketSubmitFormPrefsSettingKey,
      jsonEncode(payload),
    );
  }

  @override
  void dispose() {
    aiSuggestTicker?.cancel();
    aiCooldownTicker?.cancel();
    aiSuggestStopwatch.stop();
    aiSuggestClient?.close();
    lansweeperSettingsDebounceTimer?.cancel();
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
    lansweeperApiUrlController.dispose();
    lansweeperTicketFormUrlController.dispose();
    lansweeperTicketViewUrlController.dispose();
    lansweeperApiKeyController.dispose();
    lansweeperLoginUrlController.dispose();
    lansweeperHelpdeskUsernameController.dispose();
    lansweeperHelpdeskPasswordController.dispose();
    lansweeperAgentUsernameController.dispose();
    geminiApiKeyController.dispose();
    aiPromptTemplateController.dispose();
    geminiEndpointController.dispose();
    geminiPrimaryModelController.dispose();
    geminiFallbackModelController.dispose();
    titleController.dispose();
    notesController.dispose();
    solutionController.dispose();
    super.dispose();
  }

  Widget _wrapOptionalTooltip({required Widget child, String? message}) {
    if (message == null || message.isEmpty) return child;
    return Tooltip(message: message, child: child);
  }

  bool _canSetSelectedToState(
    List<ReportCallItem> selected,
    String targetState,
  ) {
    if (selected.isEmpty) return false;
    final states = selected
        .map(LansweeperReportItemMapper.normalizedLansweeperState)
        .toSet();
    if (states.length > 1) return true;
    return states.single != targetState;
  }

  String? _disabledStateButtonTooltip(
    List<ReportCallItem> selected,
    String targetState, {
    required bool isLoading,
  }) {
    if (isLoading) return 'Αναμονή λειτουργίας Lansweeper…';
    if (selected.isEmpty) {
      return 'Επιλέξτε μία ή περισσότερες κλήσεις';
    }
    final states = selected
        .map(LansweeperReportItemMapper.normalizedLansweeperState)
        .toSet();
    if (states.length > 1) return null;
    if (states.single != targetState) return null;
    return switch (targetState) {
      LansweeperSyncState.excluded =>
        'Όλες οι επιλεγμένες είναι ήδη εξαιρεσμένες',
      LansweeperSyncState.unsent =>
        'Όλες οι επιλεγμένες είναι ήδη ακαταχώρητες',
      LansweeperSyncState.sent => 'Όλες οι επιλεγμένες είναι ήδη καταχωρημένες',
      _ => null,
    };
  }

  Widget _buildLansweeperStateButton({
    required List<ReportCallItem> selected,
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
              'Δοκιμάστε άλλο διάστημα από τα κουμπιά «Διάστημα» παραπάνω — '
              'το «Όλες οι ακαταχώρητες» αγνοεί εντελώς τις ημερομηνίες.',
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
    final callsAsync = ref.watch(lansweeperReportCallsProvider);
    final scope = ref.watch(lansweeperReportScopeProvider);
    final dashboardFilter = ref.watch(dashboardFilterProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final String reportRangeTitle =
        scope.label ??
        statsAsync.when(
          loading: () =>
              dashboardFilter.dateFrom == null && dashboardFilter.dateTo == null
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
    final ticketConfig = ref.watch(lansweeperTicketSubmitConfigProvider);
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
    final reportCounts = callsAsync.maybeWhen(
      data: (calls) => lansweeperReportCategoryCounts(
        calls.map((call) => call.lansweeperState),
      ),
      orElse: () => null,
    );

    ref.listen(lansweeperReportCallsProvider, (previous, next) {
      next.whenData((calls) {
        if (!mounted) return;
        if (calls.isEmpty) {
          if (reportFilter == LansweeperReportFilter.all) return;
          setState(() => reportFilter = LansweeperReportFilter.all);
          return;
        }
        if (reportFilter != LansweeperReportFilter.all &&
            lansweeperReportCategoryCounts(
                  calls.map((call) => call.lansweeperState),
                ).forFilter(reportFilter) ==
                0) {
          setState(() => reportFilter = LansweeperReportFilter.all);
        }
      });
    });

    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            // Λαβή συρσίματος είναι μόνο ο τίτλος· το κουμπί ρυθμίσεων μένει
            // έξω από αυτήν ώστε το πάτημά του να μη διαβάζεται ως σύρσιμο.
            child: DraggableDialogShell(
              title: Text(
                'Αναφορά Lansweeper · $reportRangeTitle',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              builder: (titleHandle) => AlertDialog(
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleHandle),
                    CompactTooltip(
                      message:
                          'Ρυθμίσεις Lansweeper (API, φόρμα, πράκτορας, αυτόματη σύνδεση Help Desk)',
                      child: IconButton(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () {
                          unawaited(
                            settingsFlow.openConnectionSettingsDialog(),
                          );
                        },
                        icon: AppAssetImage(
                          assetPath: 'assets/lansweeper_settings.png',
                          height: 28,
                          width: 28,
                          filterQuality: FilterQuality.medium,
                          fallbackIcon: Icons.settings,
                        ),
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
                      LansweeperReportRangeBar(
                        scope: scope,
                        onSelect: _selectRange,
                      ),
                      const SizedBox(height: 8),
                      LansweeperReportFilterBar(
                        selected: reportFilter,
                        counts: reportCounts,
                        hasAnyCallsInRange: hasAnyCallsInRange,
                        reportRangeTitle: reportRangeTitle,
                        onSelect: (filter) =>
                            setState(() => reportFilter = filter),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: callsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(
                            child: Text(
                              'Σφάλμα φόρτωσης κλήσεων: ${humanizeUserFacingError(e)}',
                            ),
                          ),
                          data: (calls) {
                            final allItems = LansweeperReportItemMapper.toItems(
                              calls,
                            );
                            final items = selectionFlow.filterReportItems(
                              allItems,
                            );
                            final grouped =
                                LansweeperReportItemMapper.groupByCaller(items);
                            final groupedRows =
                                LansweeperReportItemMapper.groupedRowData(
                                  grouped,
                                );
                            final itemByKey = {
                              for (final item in items) item.key: item,
                            };
                            final selected = items
                                .where((e) => selectedKeys.contains(e.key))
                                .toList();
                            final primarySelected = selectionFlow
                                .primarySelectedItem(items);
                            final isPrimaryRegistered =
                                primarySelected != null &&
                                LansweeperReportItemMapper.isRegisteredCall(
                                  primarySelected,
                                );
                            final isPrimaryFailed =
                                primarySelected != null &&
                                LansweeperReportItemMapper.isFailedCall(
                                  primarySelected,
                                );
                            final canImmediateApiSubmit =
                                primarySelected != null &&
                                !syncState.isLoading &&
                                canSubmitToApi &&
                                connectionReady &&
                                !isPrimaryRegistered;
                            final canResubmitApi =
                                canImmediateApiSubmit && isPrimaryFailed;
                            if (primarySelected != null &&
                                selected.isNotEmpty) {
                              aiFlow.prefillForm(primarySelected, selected);
                            }
                            final totalSelectedSeconds = selected.fold<int>(
                              0,
                              (sum, item) => sum + item.durationSeconds,
                            );
                            final selectedCallId = primarySelected?.call.id;
                            final geminiKeyReady = geminiApiKey
                                .trim()
                                .isNotEmpty;
                            final aiCooldownActive = aiFlow.isAiCooldownActive;
                            final aiCooldownSeconds =
                                aiFlow.aiCooldownRemainingSeconds;
                            final aiSuggestEnabled =
                                selected.isNotEmpty &&
                                geminiKeyReady &&
                                !aiSuggestRunning &&
                                !aiCooldownActive;
                            final aiSuggestTooltip = selected.isEmpty
                                ? 'Επιλέξτε κλήση'
                                : !geminiKeyReady
                                ? 'Ορίστε Gemini API key στις ρυθμίσεις'
                                : aiCooldownActive
                                ? 'Αναμένεται διαθεσιμότητα ποσόστωσης'
                                : null;
                            final promptPreviewEnabled =
                                selected.isNotEmpty &&
                                !aiSuggestRunning &&
                                !aiCooldownActive;
                            final promptPreviewTooltip = selected.isEmpty
                                ? 'Επιλέξτε κλήση'
                                : aiSuggestRunning
                                ? 'Περιμένετε την ολοκλήρωση της πρότασης'
                                : null;
                            final linksAsync = selectedCallId != null
                                ? ref.watch(
                                    callExternalLinksProvider(selectedCallId),
                                  )
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    'Δεν υπάρχουν κλήσεις στην επιλεγμένη κατηγορία '
                                    'Lansweeper.\n'
                                    'Δοκιμάστε άλλο φίλτρο (π.χ. «Όλες»).',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Επιλεγμένες: ${selected.length} | '
                                        'Σύνολο διάρκειας: '
                                        '${LansweeperReportItemMapper.totalDurationLabel(totalSelectedSeconds)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: LansweeperReportCallList(
                                          grouped: groupedRows,
                                          selectedKeys: selectedKeys,
                                          totalDurationLabel:
                                              LansweeperReportItemMapper
                                                  .totalDurationLabel,
                                          ticketViewUrlTemplate:
                                              lansweeperTicketViewUrl,
                                          isSyncLoading: syncState.isLoading,
                                          ticketLinkEnabled: connectionReady,
                                          onToggleGroup: (groupItems, checked) {
                                            selectionFlow.toggleGroup(
                                              groupItems
                                                  .map(
                                                    (row) =>
                                                        itemByKey[row.key]!,
                                                  )
                                                  .toList(),
                                              checked,
                                            );
                                          },
                                          onToggleItem: (row, checked) {
                                            selectionFlow.toggleItem(
                                              itemByKey[row.key]!,
                                              checked,
                                            );
                                          },
                                          onBadgePressed: (row) {
                                            unawaited(
                                              registrationFlow
                                                  .toggleRegistrationFromBadge(
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
                                    // Κενό δεξιά ώστε η μπάρα κύλησης να μην
                                    // πέφτει πάνω στα πεδία και στη λαβή τους.
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        LansweeperSyncForm(
                                          titleController: titleController,
                                          notesController: notesController,
                                          solutionController:
                                              solutionController,
                                          config: ticketConfig,
                                          customFieldValues: customFieldValues,
                                          onCustomFieldChanged: (id, value) =>
                                              setState(
                                                () => customFieldValues[id] =
                                                    value,
                                              ),
                                          ticketState:
                                              selectedTicketState ??
                                              ticketConfig.defaultTicketState,
                                          onTicketStateChanged: (value) =>
                                              setState(
                                                () =>
                                                    selectedTicketState = value,
                                              ),
                                          isSuggesting: aiSuggestRunning,
                                          suggestModelLabel: aiSuggestRunning
                                              ? aiCurrentModel
                                              : null,
                                          suggestElapsedLabel: aiSuggestRunning
                                              ? aiSuggestElapsedSeconds
                                                    .toStringAsFixed(2)
                                              : null,
                                          cooldownRemainingSeconds:
                                              aiCooldownActive
                                              ? aiCooldownSeconds
                                              : null,
                                          cooldownModelLabel: aiCooldownActive
                                              ? aiCooldownModel
                                              : null,
                                          onCancelAutoResubmit:
                                              aiCooldownActive &&
                                                  aiAutoResubmitArmed
                                              ? aiFlow.cancelAiAutoResubmit
                                              : null,
                                          suggestDisabledTooltip:
                                              aiSuggestTooltip,
                                          onSuggest: aiSuggestEnabled
                                              ? () => unawaited(
                                                  aiFlow.suggestWithAi(
                                                    selected,
                                                  ),
                                                )
                                              : null,
                                          previewDisabledTooltip:
                                              promptPreviewTooltip,
                                          onPreviewPrompt: promptPreviewEnabled
                                              ? () => unawaited(
                                                  aiFlow.showAiPromptPreview(
                                                    selected,
                                                  ),
                                                )
                                              : null,
                                          onEditPromptTemplate: () => unawaited(
                                            settingsFlow
                                                .openAiPromptTemplateEditorDialog(),
                                          ),
                                          saveAsKnowledgeDisabledTooltip:
                                              knowledgeFlow
                                                  .saveDisabledReason(selected),
                                          onSaveAsKnowledge:
                                              knowledgeFlow.saveDisabledReason(
                                                    selected,
                                                  ) ==
                                                  null
                                              ? () => unawaited(
                                                  knowledgeFlow.saveAsKnowledge(
                                                    selected,
                                                  ),
                                                )
                                              : null,
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
                                                      onPressed:
                                                          canImmediateApiSubmit
                                                          ? () => unawaited(
                                                              registrationFlow
                                                                  .submitSelected(
                                                                    primarySelected,
                                                                    selected,
                                                                    resubmit:
                                                                        false,
                                                                  ),
                                                            )
                                                          : null,
                                                      icon: _connectionAwareIcon(
                                                        status:
                                                            connectionStatus,
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
                                                              registrationFlow
                                                                  .submitSelected(
                                                                    primarySelected,
                                                                    selected,
                                                                    resubmit:
                                                                        true,
                                                                  ),
                                                            )
                                                          : null,
                                                      icon: _connectionAwareIcon(
                                                        status:
                                                            connectionStatus,
                                                        icon: Icons
                                                            .refresh_rounded,
                                                      ),
                                                      label: const Text(
                                                        'Επαναϋποβολή',
                                                      ),
                                                    ),
                                                  ),
                                                OutlinedButton.icon(
                                                  onPressed:
                                                      (primarySelected !=
                                                              null &&
                                                          !syncState.isLoading)
                                                      ? () => registrationFlow
                                                            .manualMark(
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
                                                  isLoading:
                                                      syncState.isLoading,
                                                  targetState:
                                                      LansweeperSyncState
                                                          .excluded,
                                                  label: 'Εξαίρεση',
                                                  allowWhen:
                                                      !isPrimaryRegistered,
                                                  blockedTooltip:
                                                      'Η κλήση είναι ήδη καταχωρημένη',
                                                  onPressed: () =>
                                                      registrationFlow
                                                          .setStateForAllSelected(
                                                            selected,
                                                            LansweeperSyncState
                                                                .excluded,
                                                          ),
                                                ),
                                                _buildLansweeperStateButton(
                                                  selected: selected,
                                                  isLoading:
                                                      syncState.isLoading,
                                                  targetState:
                                                      LansweeperSyncState
                                                          .unsent,
                                                  label: 'Ακαταχώρητη',
                                                  onPressed: () =>
                                                      registrationFlow
                                                          .setStateForAllSelected(
                                                            selected,
                                                            LansweeperSyncState
                                                                .unsent,
                                                          ),
                                                ),
                                                _buildLansweeperStateButton(
                                                  selected: selected,
                                                  isLoading:
                                                      syncState.isLoading,
                                                  targetState:
                                                      LansweeperSyncState.sent,
                                                  label: 'Καταχωρημένη',
                                                  onPressed: () =>
                                                      registrationFlow
                                                          .setStateForAllSelected(
                                                            selected,
                                                            LansweeperSyncState
                                                                .sent,
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
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                          ),
                                          error: (e, _) => Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                'Σφάλμα ιστορικού: ${humanizeUserFacingError(e)}',
                                              ),
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
                      final items = LansweeperReportItemMapper.toItems(calls);
                      final selected = items
                          .where((e) => selectedKeys.contains(e.key))
                          .toList();
                      final totalSelectedSeconds = selected.fold<int>(
                        0,
                        (sum, item) => sum + item.durationSeconds,
                      );
                      final hasSelection = selected.isNotEmpty;
                      final hasFormText =
                          titleController.text.trim().isNotEmpty ||
                          notesController.text.trim().isNotEmpty ||
                          solutionController.text.trim().isNotEmpty;
                      return _wrapLansweeperConnectionTooltip(
                        status: connectionStatus,
                        child: FilledButton.icon(
                          onPressed:
                              (hasSelection || hasFormText) &&
                                  canOpenTicketForm &&
                                  connectionReady
                              ? () => browserFlow.copyAndOpen(
                                  ticketFormUrl: lansweeperTicketFormUrl,
                                  callIds: selected
                                      .map((item) => item.call.id)
                                      .whereType<int>()
                                      .toList(),
                                  durationSeconds: hasSelection
                                      ? totalSelectedSeconds
                                      : null,
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
    );
  }
}
