import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/models/call_model.dart';
import '../models/lansweeper_connection_status.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/dashboard_provider.dart';
import '../providers/lansweeper_connection_probe_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import 'lansweeper/lansweeper_connection_settings_dialog.dart';
import 'lansweeper/lansweeper_report_call_list.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper/lansweeper_sync_form.dart';
import 'lansweeper/sync_history_list.dart';

class LansweeperReportDialog extends ConsumerStatefulWidget {
  const LansweeperReportDialog({super.key});

  @override
  ConsumerState<LansweeperReportDialog> createState() =>
      _LansweeperReportDialogState();
}

class _LansweeperReportDialogState
    extends ConsumerState<LansweeperReportDialog> {
  static const Duration _lansweeperSettingsDebounceDuration = Duration(
    milliseconds: 350,
  );

  final Set<String> _selectedKeys = <String>{};
  final SpellCheckController _titleController = SpellCheckController();
  final SpellCheckController _notesController = SpellCheckController();
  final TextEditingController _lansweeperAgentUsernameController =
      TextEditingController();
  final TextEditingController _lansweeperApiUrlController =
      TextEditingController();
  final TextEditingController _lansweeperTicketFormUrlController =
      TextEditingController();
  final TextEditingController _lansweeperTicketViewUrlController =
      TextEditingController();
  final TextEditingController _lansweeperApiKeyController =
      TextEditingController();
  final TextEditingController _lansweeperLoginUrlController =
      TextEditingController();
  final TextEditingController _lansweeperHelpdeskUsernameController =
      TextEditingController();
  final TextEditingController _lansweeperHelpdeskPasswordController =
      TextEditingController();
  final TextEditingController _geminiApiKeyController = TextEditingController();
  final TextEditingController _geminiPromptTemplateController =
      TextEditingController();
  final TextEditingController _geminiEndpointController =
      TextEditingController();
  final TextEditingController _geminiPrimaryModelController =
      TextEditingController();
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
  Timer? _lansweeperSettingsDebounceTimer;
  String? _lastPrefilledKey;
  bool _aiSuggestRunning = false;
  Timer? _aiSuggestTicker;
  final Stopwatch _aiSuggestStopwatch = Stopwatch();
  double _aiSuggestElapsedSeconds = 0;
  http.Client? _aiSuggestClient;
  String? _aiCurrentModel;
  final GlobalKey<ScaffoldMessengerState> _dialogMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

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

  Future<void> _openLansweeperConnectionSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => LansweeperConnectionSettingsDialog(
        apiUrlController: _lansweeperApiUrlController,
        ticketFormUrlController: _lansweeperTicketFormUrlController,
        ticketViewUrlController: _lansweeperTicketViewUrlController,
        apiKeyController: _lansweeperApiKeyController,
        agentUsernameController: _lansweeperAgentUsernameController,
        loginUrlController: _lansweeperLoginUrlController,
        helpdeskUsernameController: _lansweeperHelpdeskUsernameController,
        helpdeskPasswordController: _lansweeperHelpdeskPasswordController,
        geminiApiKeyController: _geminiApiKeyController,
        geminiPromptTemplateController: _geminiPromptTemplateController,
        geminiEndpointController: _geminiEndpointController,
        geminiPrimaryModelController: _geminiPrimaryModelController,
        geminiFallbackModelController: _geminiFallbackModelController,
        onSettingsChanged: () => _scheduleLansweeperSettingsSave(),
        onLansweeperUrlChanged: () =>
            _scheduleLansweeperSettingsSave(recheckConnection: true),
        onApiHelpLink: () {
          unawaited(_lansweeperApiHelpFromSettings());
        },
        onTicketFormHelpLink: () {
          unawaited(_lansweeperTicketFormHelpFromSettings());
        },
        onTicketViewHelpLink: () {
          unawaited(_lansweeperTicketViewHelpFromSettings());
        },
        onLoginHelpLink: () {
          unawaited(_lansweeperLoginHelpFromSettings());
        },
        onAiHelpLink: () {
          unawaited(_geminiApiHelpFromSettings());
        },
      ),
    );
  }

  Future<void> _geminiApiHelpFromSettings() async {
    const url = 'https://aistudio.google.com/api-keys';
    if (!mounted) return;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    _showDialogSnackBar(
      const SnackBar(content: Text('Άνοιξε ο σύνδεσμος: aistudio.google.com')),
    );
  }

  Future<void> _lansweeperApiHelpFromSettings() async {
    final chosen = LansweeperUrlRules.apiUrlForHelpLink(
      _lansweeperApiUrlController.text,
    );
    if (!mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    _showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperTicketFormHelpFromSettings() async {
    final chosen = LansweeperUrlRules.ticketFormUrlForHelpLink(
      _lansweeperTicketFormUrlController.text,
    );
    if (!mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    _showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperTicketViewHelpFromSettings() async {
    final chosen = LansweeperUrlRules.ticketViewUrlForHelpLink(
      _lansweeperTicketViewUrlController.text,
    );
    if (!mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    _showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperLoginHelpFromSettings() async {
    final chosen = LansweeperUrlRules.loginPageUrlForHelpLink(
      _lansweeperLoginUrlController.text,
    );
    if (!mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    _showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  void _scheduleLansweeperSettingsSave({bool recheckConnection = false}) {
    _lansweeperSettingsDebounceTimer?.cancel();
    _lansweeperSettingsDebounceTimer = Timer(
      _lansweeperSettingsDebounceDuration,
      () {
        if (!mounted) return;
        _persistLansweeperSettingsSafely();
        if (!recheckConnection) return;
        unawaited(
          ref.read(lansweeperConnectionProbeProvider.notifier).check(),
        );
      },
    );
  }

  void _persistLansweeperSettingsSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(lansweeperApiUrlProvider.notifier)
            .setApiUrl(_lansweeperApiUrlController.text),
      );
      unawaited(
        ref
            .read(lansweeperTicketFormUrlProvider.notifier)
            .setTicketFormUrl(_lansweeperTicketFormUrlController.text),
      );
      unawaited(
        ref
            .read(lansweeperTicketViewUrlProvider.notifier)
            .setTicketViewUrl(_lansweeperTicketViewUrlController.text),
      );
      unawaited(
        ref
            .read(lansweeperApiKeyProvider.notifier)
            .setApiKey(_lansweeperApiKeyController.text),
      );
      unawaited(
        ref
            .read(lansweeperAgentUsernameProvider.notifier)
            .setAgentUsername(_lansweeperAgentUsernameController.text),
      );
      unawaited(
        ref
            .read(lansweeperHelpdeskLoginUrlProvider.notifier)
            .setLoginUrl(_lansweeperLoginUrlController.text),
      );
      unawaited(
        ref
            .read(lansweeperHelpdeskWebUsernameProvider.notifier)
            .setUsername(_lansweeperHelpdeskUsernameController.text),
      );
      unawaited(
        ref
            .read(lansweeperHelpdeskWebPasswordProvider.notifier)
            .setPassword(_lansweeperHelpdeskPasswordController.text),
      );
      unawaited(
        ref
            .read(geminiApiKeyProvider.notifier)
            .setApiKey(_geminiApiKeyController.text),
      );
      unawaited(
        ref
            .read(geminiPromptTemplateProvider.notifier)
            .setPromptTemplate(_geminiPromptTemplateController.text),
      );
      unawaited(
        ref
            .read(geminiEndpointProvider.notifier)
            .setEndpoint(_geminiEndpointController.text),
      );
      unawaited(
        ref
            .read(geminiPrimaryModelProvider.notifier)
            .setPrimaryModel(_geminiPrimaryModelController.text),
      );
      unawaited(
        ref
            .read(geminiFallbackModelProvider.notifier)
            .setFallbackModel(_geminiFallbackModelController.text),
      );
    });
  }

  String _callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? '-' : value;
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
    super.dispose();
  }

  String _notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    if (issue.isNotEmpty) return issue;
    return '-';
  }

  String _selectedKeysSignature(List<_ReportCallItem> selected) {
    final keys = selected.map((e) => e.key).toList()..sort();
    return keys.join('|');
  }

  String _combinedSelectedNotes(List<_ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) return selected.first.notes;
    return selected
        .map((e) {
          final date = DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(_callDateTime(e.call));
          final details = e.details.isNotEmpty ? ' • ${e.details}' : '';
          return '[$date] ${e.caller}: ${e.notes}$details';
        })
        .join('\n');
  }

  String _combinedGeminiIssue(List<_ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) {
      return (selected.first.call.issue ?? '').trim();
    }
    final parts = <String>[];
    for (final item in selected) {
      final issue = (item.call.issue ?? '').trim();
      if (issue.isEmpty) continue;
      final date = DateFormat('dd/MM/yyyy HH:mm').format(_callDateTime(item.call));
      parts.add('[$date] ${item.caller}: $issue');
    }
    return parts.join('\n');
  }

  String _combinedUniqueCallField(
    List<_ReportCallItem> selected,
    String? Function(CallModel call) read,
  ) {
    final values = <String>{};
    for (final item in selected) {
      final value = (read(item.call) ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.join(', ');
  }

  String _details(CallModel call) {
    final parts = <String>[];
    final equipmentCode = (call.equipmentText ?? '').trim();
    final department = (call.departmentText ?? '').trim();
    final problemCategory = (call.category ?? '').trim();

    if (equipmentCode.isNotEmpty) {
      parts.add('Κωδικός εξοπλισμού: $equipmentCode');
    }
    if (department.isNotEmpty) {
      parts.add('Τμήμα: $department');
    }
    if (problemCategory.isNotEmpty) {
      parts.add('Κατηγορία προβλήματος: $problemCategory');
    }

    return parts.join(' • ');
  }

  String _durationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _totalDurationLabel(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final totalMinutes = (safe / 60).ceil();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '$hours ώρ ${mins.toString().padLeft(2, '0')} λ';
    }
    return '$totalMinutes λ';
  }

  DateTime _callDateTime(CallModel call) {
    final dateRaw = (call.date ?? '').trim();
    final timeRaw = (call.time ?? '').trim();
    final parsed = DateTime.tryParse('$dateRaw $timeRaw');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_ReportCallItem> _toItems(List<CallModel> calls) {
    return calls.indexed.map((entry) {
      final i = entry.$1;
      final call = entry.$2;
      final id = call.id;
      final key = id != null ? 'id_$id' : 'idx_$i';
      return _ReportCallItem(
        key: key,
        call: call,
        caller: _callerLabel(call),
        notes: _notes(call),
        details: _details(call),
        durationSeconds: call.duration ?? 0,
      );
    }).toList();
  }

  Map<String, List<_ReportCallItem>> _groupByCaller(
    List<_ReportCallItem> items,
  ) {
    final grouped = <String, List<_ReportCallItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.caller, () => <_ReportCallItem>[]).add(item);
    }
    return grouped;
  }

  LansweeperReportCallRowData _toRowData(_ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return LansweeperReportCallRowData(
      key: item.key,
      call: item.call,
      dateLabel: DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_callDateTime(item.call)),
      durationLabel: _durationLabel(item.durationSeconds),
      lansweeperState: state,
      ticketId: item.call.lansweeperMainTicketId,
      notes: item.notes,
      details: item.details,
      durationSeconds: item.durationSeconds,
    );
  }

  Map<String, List<LansweeperReportCallRowData>> _groupedRowData(
    Map<String, List<_ReportCallItem>> grouped,
  ) {
    return grouped.map(
      (caller, callerItems) =>
          MapEntry(caller, callerItems.map(_toRowData).toList()),
    );
  }

  void _toggleGroup(List<_ReportCallItem> items, bool? checked) {
    setState(() {
      if (checked == true) {
        for (final item in items) {
          _selectedKeys.add(item.key);
        }
      } else {
        for (final item in items) {
          _selectedKeys.remove(item.key);
        }
      }
    });
  }

  void _toggleItem(_ReportCallItem item, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedKeys.add(item.key);
      } else {
        _selectedKeys.remove(item.key);
      }
    });
  }

  Future<({bool opened, bool openedLoginTab})> _launchHelpdeskBrowserUrl(
    String targetUrl, {
    required String invalidUrlMessage,
    required String openFailureMessage,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(targetUrl)) {
      if (mounted) {
        _showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
      }
      return (opened: false, openedLoginTab: false);
    }

    final autoLogin = ref.read(lansweeperHelpdeskAutoLoginProvider);
    final loginPageRaw = ref.read(lansweeperHelpdeskLoginUrlProvider).trim();
    var openedLoginTab = false;
    if (autoLogin &&
        LansweeperUrlRules.isBrowserLaunchableUrl(loginPageRaw)) {
      final loginUri = Uri.tryParse(loginPageRaw);
      if (loginUri != null && loginUri.hasScheme) {
        openedLoginTab = await launchUrl(
          loginUri,
          mode: LaunchMode.externalApplication,
        );
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }

    final uri = Uri.tryParse(targetUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        _showDialogSnackBar(SnackBar(content: Text(invalidUrlMessage)));
      }
      return (opened: false, openedLoginTab: openedLoginTab);
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showDialogSnackBar(SnackBar(content: Text(openFailureMessage)));
    }
    return (opened: opened, openedLoginTab: openedLoginTab);
  }

  Future<void> _openTicketViewInBrowser(String ticketId) async {
    final templateRaw = _lansweeperTicketViewUrlController.text.trim();
    final template = templateRaw.isNotEmpty
        ? templateRaw
        : ref.read(lansweeperTicketViewUrlProvider);
    final url = LansweeperUrlRules.buildTicketViewUrl(template, ticketId);
    if (url == null) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL προβολής ticket στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final result = await _launchHelpdeskBrowserUrl(
      url,
      invalidUrlMessage: 'Μη έγκυρο URL προβολής ticket.',
      openFailureMessage: 'Αποτυχία ανοίγματος ticket στον περιηγητή.',
    );
    if (!mounted) return;
    if (result.openedLoginTab) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στο ticket.',
          ),
        ),
      );
    } else if (!result.opened) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Αποτυχία ανοίγματος ticket στον περιηγητή.'),
        ),
      );
    }
  }

  Future<void> _copyAndOpen({
    required String ticketFormUrl,
  }) async {
    if (!LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL φόρμας νέου αιτήματος στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    await Clipboard.setData(ClipboardData(text: '$title\n\n$notes'));

    if (!mounted) return;
    _showDialogSnackBar(
      const SnackBar(content: Text('Αντιγράφηκαν τίτλος και σημειώσεις.')),
    );

    final result = await _launchHelpdeskBrowserUrl(
      ticketFormUrl,
      invalidUrlMessage: 'Μη έγκυρο URL φόρμας εισιτηρίου.',
      openFailureMessage: 'Αποτυχία ανοίγματος URL φόρμας.',
    );
    if (mounted && result.openedLoginTab) {
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ανοίχτηκαν καρτέλες στον περιηγητή· αν χρειάζεται, συνδεθείτε στη σελίδα σύνδεσης και επιστρέψτε στη φόρμα αιτήματος.',
          ),
        ),
      );
    }
  }

  _ReportCallItem? _primarySelectedItem(List<_ReportCallItem> allItems) {
    for (final item in allItems) {
      if (_selectedKeys.contains(item.key)) return item;
    }
    return null;
  }

  String _normalizedLansweeperState(_ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return state.isEmpty ? LansweeperSyncState.unsent : state;
  }

  bool _isRegisteredCall(_ReportCallItem item) =>
      _normalizedLansweeperState(item) == LansweeperSyncState.sent;

  bool _isFailedCall(_ReportCallItem item) =>
      _normalizedLansweeperState(item) == LansweeperSyncState.failed;

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

  void _prefillForm(
    _ReportCallItem primary,
    List<_ReportCallItem> selected,
  ) {
    final signature = _selectedKeysSignature(selected);
    if (_lastPrefilledKey == signature) return;
    _lastPrefilledKey = signature;
    final category = (primary.call.category ?? '').trim();
    final id = primary.call.id;
    final idSuffix = id != null ? ' #$id' : '';
    _titleController.text = category.isEmpty
        ? 'Κλήση$idSuffix'
        : '[$category]$idSuffix';
    _notesController.text = _combinedSelectedNotes(selected);
  }

  Future<void> _suggestWithAi(List<_ReportCallItem> selected) async {
    if (_aiSuggestRunning || selected.isEmpty) return;

    final apiKey = ref.read(geminiApiKeyProvider).trim();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Ορίστε Gemini API key στις ρυθμίσεις Lansweeper.'),
        ),
      );
      return;
    }

    final endpointTemplate = ref.read(geminiEndpointProvider);
    final promptTemplate = ref.read(geminiPromptTemplateProvider);
    final primaryModel = ref.read(geminiPrimaryModelProvider).trim();
    if (primaryModel.isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Ορίστε κύριο μοντέλο Gemini στις ρυθμίσεις Lansweeper.'),
        ),
      );
      return;
    }
    final fallbackEnabled = ref.read(geminiFallbackEnabledProvider);
    final fallbackModel = ref.read(geminiFallbackModelProvider).trim();

    final attempts = <({String model, String endpoint})>[
      (
        model: primaryModel,
        endpoint: GeminiTicketService.resolveEndpoint(
          endpoint: endpointTemplate,
          apiKey: apiKey,
          primaryModel: primaryModel,
        ),
      ),
    ];
    if (fallbackEnabled &&
        fallbackModel.isNotEmpty &&
        fallbackModel != primaryModel) {
      attempts.add((
        model: fallbackModel,
        endpoint: GeminiTicketService.resolveEndpoint(
          endpoint: GeminiTicketService.endpointWithModel(
            endpointTemplate,
            fallbackModel,
          ),
          apiKey: apiKey,
        ),
      ));
    }

    final callerText = _combinedUniqueCallField(
      selected,
      (call) => call.callerText,
    );
    final equipmentText = _combinedUniqueCallField(
      selected,
      (call) => call.equipmentText,
    );
    final departmentText = _combinedUniqueCallField(
      selected,
      (call) => call.departmentText,
    );
    final category = _combinedUniqueCallField(selected, (call) => call.category);
    final issue = _combinedGeminiIssue(selected);
    final draftTitle = _titleController.text;
    final draftNotes = _notesController.text;

    setState(() => _aiSuggestRunning = true);
    try {
      for (var i = 0; i < attempts.length; i++) {
        final attempt = attempts[i];
        if (!mounted) return;
        _startAiSuggestTicker(model: attempt.model);
        final client = http.Client();
        _aiSuggestClient = client;
        try {
          final result = await GeminiTicketService.suggest(
            apiKey: apiKey,
            endpoint: attempt.endpoint,
            promptTemplate: promptTemplate,
            callerText: callerText,
            equipmentText: equipmentText,
            departmentText: departmentText,
            category: category,
            issue: issue,
            titleText: draftTitle,
            notesText: draftNotes,
            client: client,
          );
          if (!mounted) return;
          setState(() {
            _titleController.text = result.title;
            _notesController.text = result.description;
          });
          return;
        } catch (e) {
          final statusCode = e is GeminiException ? e.statusCode : null;
          final isLast = i == attempts.length - 1;
          if (!isLast && statusCode == 503) {
            final nextModel = attempts[i + 1].model;
            if (mounted) {
              _showDialogSnackBar(
                SnackBar(
                  content: Text(
                    'Το μοντέλο «${attempt.model}» είναι υπερφορτωμένο (503). '
                    'Υποβάθμιση σε εφεδρικό μοντέλο: «$nextModel».',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            continue;
          }
          if (!mounted) return;
          final errorMessage = e is GeminiException
              ? e.message
              : e.toString().replaceFirst('Exception: ', '');
          _showDialogSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 8),
            ),
            copyText: errorMessage,
          );
          return;
        } finally {
          _aiSuggestClient = null;
          client.close();
          _stopAiSuggestTicker();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _aiSuggestRunning = false);
      }
    }
  }

  void _startAiSuggestTicker({required String model}) {
    _aiSuggestStopwatch
      ..reset()
      ..start();
    setState(() {
      _aiSuggestRunning = true;
      _aiSuggestElapsedSeconds = 0;
      _aiCurrentModel = model;
    });
    _aiSuggestTicker = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) {
        if (!mounted) return;
        setState(() {
          _aiSuggestElapsedSeconds =
              _aiSuggestStopwatch.elapsedMilliseconds / 1000;
        });
      },
    );
  }

  void _stopAiSuggestTicker() {
    _aiSuggestTicker?.cancel();
    _aiSuggestTicker = null;
    _aiSuggestStopwatch.stop();
  }

  Future<void> _submitSelected(
    _ReportCallItem item, {
    required bool resubmit,
  }) async {
    final callId = item.call.id;
    if (callId == null) return;
    if (_titleController.text.trim().isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(content: Text('Ο τίτλος είναι υποχρεωτικός.')),
      );
      return;
    }

    if (_lansweeperAgentUsernameController.text.trim().isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε τον πράκτορα API (username) στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final apiUrl = ref.read(lansweeperApiUrlProvider);
    if (!LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL API (…/api.aspx) στις ρυθμίσεις Lansweeper για καταχώρηση.',
          ),
        ),
      );
      return;
    }

    if (resubmit &&
        (item.call.lansweeperMainTicketId ?? '').trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Επαναϋποβολή'),
          content: const Text(
            'Η κλήση έχει ήδη κύριο Ticket ID. Θέλεις να γίνει νέα καταχώρηση;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final notifier = ref.read(lansweeperSyncProvider.notifier);
    final input = LansweeperSubmitInput(
      title: _titleController.text,
      notes: _notesController.text,
      agentUsername: _lansweeperAgentUsernameController.text,
    );
    final result = resubmit
        ? await notifier.resubmitCall(callId: callId, input: input)
        : await notifier.submitCall(callId: callId, input: input);
    if (!mounted) return;
    if (result.success) {
      final ticketId = (result.ticketId ?? '').trim();
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            'Καταχώρηση επιτυχής. Ticket: ${ticketId.isEmpty ? '-' : ticketId}',
          ),
        ),
      );
      if (!resubmit && ticketId.isNotEmpty) {
        final openTicketAfterSubmit =
            await readLansweeperOpenTicketAfterApiSubmitSetting();
        if (openTicketAfterSubmit) {
          await _openTicketViewInBrowser(ticketId);
        }
      }
      return;
    }

    final failureMessage = 'Αποτυχία καταχώρησης: ${result.message}';
    _showDialogSnackBar(
      SnackBar(
        content: Text(failureMessage),
        duration: const Duration(seconds: 8),
      ),
      copyText: failureMessage,
    );

    final reportText = (result.failureReport ?? result.message).trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αναφορά αποτυχίας καταχώρησης'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: SelectableText(reportText)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: reportText));
              if (!ctx.mounted) return;
              _showDialogSnackBar(
                const SnackBar(
                  content: Text('Η αναφορά αντιγράφηκε στο πρόχειρο.'),
                ),
              );
            },
            child: const Text('Αντιγραφή αναφοράς'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }

  Future<bool> _markAsUnsentWithTicketPrompt(_ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return false;
    final storedTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    if (storedTicket.isEmpty) {
      await notifier.setUnsent(callId);
      return true;
    }
    final choice = await showDialog<_UnsentTicketChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ακαταχώρητη κλήση'),
        content: Text(
          'Η κλήση έχει καταχωρηθεί με id: #$storedTicket στο Lansweeper.\n\n'
          'Τι θέλεις να γίνει με το ticket id;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.cancel),
            child: const Text('Άκυρο'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.clear),
            child: const Text('Μηδενισμός id'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.retain),
            child: const Text('Διατήρηση id'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _UnsentTicketChoice.cancel) return false;
    await notifier.setUnsent(
      callId,
      retainTicketId: choice == _UnsentTicketChoice.retain,
    );
    return true;
  }

  Future<_DuplicateTicketAction> _promptDuplicateTicketWarning({
    required String ticketId,
    required int callId,
  }) async {
    final count = await ref
        .read(lansweeperSyncProvider.notifier)
        .countRegisteredCallsWithTicketId(ticketId, excludeCallId: callId);
    if (count <= 0) return _DuplicateTicketAction.proceed;
    if (!mounted) return _DuplicateTicketAction.cancel;
    final callsLabel = count == 1 ? 'άλλη κλήση' : 'άλλες κλήσεις';
    return await showDialog<_DuplicateTicketAction>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ίδιο Ticket ID'),
            content: Text(
              'Υπάρχουν $count $callsLabel καταχωρημένες με ticket #$ticketId.\n\n'
              'Συνήθως ένα ticket Lansweeper αντιστοιχεί σε ένα περιστατικό· '
              'πολλές κλήσεις με το ίδιο id επιτρέπονται (π.χ. ίδιος καλών / '
              'ομαδοποιημένες κλήσεις).',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.cancel),
                child: const Text('Άκυρο'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.changeId),
                child: const Text('Αλλαγή id'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.proceed),
                child: const Text('Πρόσθεση'),
              ),
            ],
          ),
        ) ??
        _DuplicateTicketAction.cancel;
  }

  Future<void> _applyRegistration({
    required _ReportCallItem item,
    String? comment,
    String title = 'Καταχώρηση κλήσης',
    String? subtitle,
  }) async {
    final callId = item.call.id;
    if (callId == null) return;
    var initialTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    while (mounted) {
      final ticketId = await _promptOptionalTicketId(
        initialTicketId: initialTicket.isEmpty ? null : initialTicket,
        title: title,
        subtitle: subtitle,
      );
      if (ticketId == null) return;
      if (ticketId.isNotEmpty) {
        final duplicateAction = await _promptDuplicateTicketWarning(
          ticketId: ticketId,
          callId: callId,
        );
        if (duplicateAction == _DuplicateTicketAction.cancel) return;
        if (duplicateAction == _DuplicateTicketAction.changeId) {
          final next = await _promptOptionalTicketId(
            initialTicketId: ticketId,
            title: 'Αλλαγή Ticket ID',
          );
          if (next == null) return;
          initialTicket = next;
          continue;
        }
      }
      await ref.read(lansweeperSyncProvider.notifier).markRegistered(
        callId: callId,
        ticketId: ticketId.isEmpty ? null : ticketId,
        comment: comment,
      );
      if (!mounted) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            ticketId.isEmpty
                ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).',
          ),
        ),
      );
      return;
    }
  }

  Future<String?> _promptOptionalTicketId({
    String? initialTicketId,
    String title = 'Ticket Lansweeper',
    String? subtitle,
  }) async {
    final prefilled = await _resolveSuggestedTicketId(initialTicketId);
    if (!mounted) return null;
    final ticketController = TextEditingController(text: prefilled);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: ticketController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ticket ID (προαιρετικό)',
                    hintText: 'π.χ. 17132',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      );
      if (accepted != true) return null;
      return ticketController.text.trim();
    } finally {
      ticketController.dispose();
    }
  }

  Future<String> _resolveSuggestedTicketId(String? existingTicketId) async {
    final trimmed = (existingTicketId ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return await ref
            .read(lansweeperSyncProvider.notifier)
            .suggestedNextLansweeperTicketId() ??
        '';
  }

  Future<void> _manualMark(_ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return;
    final initialTicket = await _resolveSuggestedTicketId(
      item.call.lansweeperMainTicketId,
    );
    if (!mounted) return;
    final ticketController = TextEditingController(text: initialTicket);
    final commentController = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Χειροκίνητη Σήμανση'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ticketController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ticket ID (προαιρετικό)',
                    hintText: 'π.χ. 17132',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Σχόλιο/Αιτιολογία (προαιρετικό)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      var ticketId = ticketController.text.trim();
      final comment = commentController.text;
      while (mounted) {
        if (ticketId.isNotEmpty) {
          final duplicateAction = await _promptDuplicateTicketWarning(
            ticketId: ticketId,
            callId: callId,
          );
          if (duplicateAction == _DuplicateTicketAction.cancel) return;
          if (duplicateAction == _DuplicateTicketAction.changeId) {
            final next = await _promptOptionalTicketId(
              initialTicketId: ticketId,
              title: 'Αλλαγή Ticket ID',
            );
            if (next == null) return;
            ticketId = next;
            continue;
          }
        }
        await ref.read(lansweeperSyncProvider.notifier).markRegistered(
          callId: callId,
          ticketId: ticketId.isEmpty ? null : ticketId,
          comment: comment,
        );
        if (!mounted) return;
        _showDialogSnackBar(
          SnackBar(
            content: Text(
              ticketId.isEmpty
                  ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                  : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).',
            ),
          ),
        );
        return;
      }
    } finally {
      ticketController.dispose();
      commentController.dispose();
    }
  }

  Future<void> _toggleRegistrationFromBadge(_ReportCallItem item) async {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    if (state == LansweeperSyncState.sent) {
      final changed = await _markAsUnsentWithTicketPrompt(item);
      if (!changed || !mounted) return;
      _showDialogSnackBar(
        const SnackBar(content: Text('Η κλήση σημειώθηκε ως ακαταχώρητη.')),
      );
      return;
    }
    await _applyRegistration(
      item: item,
      title: 'Καταχώρηση κλήσης',
      subtitle: 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).',
    );
  }

  bool _matchesReportFilter(String state) {
    final normalized = state.trim().isEmpty
        ? LansweeperSyncState.unsent
        : state.trim();
    return switch (_reportFilter) {
      _LansweeperReportFilter.unsentOnly =>
        normalized == LansweeperSyncState.unsent,
      _LansweeperReportFilter.sentOnly => normalized == LansweeperSyncState.sent,
      _LansweeperReportFilter.excludedOnly =>
        normalized == LansweeperSyncState.excluded,
      _LansweeperReportFilter.failedOnly =>
        normalized == LansweeperSyncState.failed,
      _LansweeperReportFilter.all => true,
    };
  }

  List<_ReportCallItem> _filterReportItems(List<_ReportCallItem> items) {
    return items
        .where(
          (item) => _matchesReportFilter(item.call.lansweeperState ?? ''),
        )
        .toList();
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

  Future<void> _applyBulkRegistration(List<_ReportCallItem> items) async {
    final validItems = items.where((item) => item.call.id != null).toList();
    if (validItems.isEmpty) return;

    final count = validItems.length;
    var initialTicket = count == 1
        ? (validItems.first.call.lansweeperMainTicketId ?? '').trim()
        : '';
    initialTicket = await _resolveSuggestedTicketId(
      initialTicket.isEmpty ? null : initialTicket,
    );
    if (!mounted) return;

    while (mounted) {
      final ticketId = await _promptOptionalTicketId(
        initialTicketId: initialTicket.isEmpty ? null : initialTicket,
        title: count == 1 ? 'Καταχώρηση κλήσης' : 'Καταχώρηση $count κλήσεων',
        subtitle: count == 1
            ? 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).'
            : 'Ο αριθμός ticket Lansweeper είναι προαιρετικός και θα εφαρμοστεί σε όλες τις επιλεγμένες κλήσεις.',
      );
      if (ticketId == null) return;
      if (ticketId.isNotEmpty) {
        final duplicateAction = await _promptDuplicateTicketWarning(
          ticketId: ticketId,
          callId: validItems.first.call.id!,
        );
        if (duplicateAction == _DuplicateTicketAction.cancel) return;
        if (duplicateAction == _DuplicateTicketAction.changeId) {
          final next = await _promptOptionalTicketId(
            initialTicketId: ticketId,
            title: 'Αλλαγή Ticket ID',
          );
          if (next == null) return;
          initialTicket = next;
          continue;
        }
      }

      final notifier = ref.read(lansweeperSyncProvider.notifier);
      for (final item in validItems) {
        await notifier.markRegistered(
          callId: item.call.id!,
          ticketId: ticketId.isEmpty ? null : ticketId,
        );
      }
      if (!mounted) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? ticketId.isEmpty
                      ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                      : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).'
                : ticketId.isEmpty
                ? '$count κλήσεις επισημάνθηκαν ως καταχωρημένες.'
                : '$count κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #$ticketId).',
          ),
        ),
      );
      return;
    }
  }

  Future<void> _setStateForAllSelected(
    List<_ReportCallItem> selected,
    String nextState,
  ) async {
    final toUpdate = selected
        .where((item) => _normalizedLansweeperState(item) != nextState)
        .toList();
    if (toUpdate.isEmpty) return;

    if (nextState == LansweeperSyncState.excluded) {
      final notifier = ref.read(lansweeperSyncProvider.notifier);
      var count = 0;
      for (final item in toUpdate) {
        final callId = item.call.id;
        if (callId == null) continue;
        await notifier.setExcluded(callId);
        count++;
      }
      if (!mounted || count == 0) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Η κλήση επισημάνθηκε ως εξαιρεμένη.'
                : '$count κλήσεις επισημάνθηκαν ως εξαιρεμένες.',
          ),
        ),
      );
      return;
    }

    if (nextState == LansweeperSyncState.unsent) {
      var count = 0;
      for (final item in toUpdate) {
        final changed = await _markAsUnsentWithTicketPrompt(item);
        if (!changed) break;
        count++;
      }
      if (!mounted || count == 0) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Η κλήση σημειώθηκε ως ακαταχώρητη.'
                : '$count κλήσεις σημειώθηκαν ως ακαταχώρητες.',
          ),
        ),
      );
      return;
    }

    if (nextState == LansweeperSyncState.sent) {
      await _applyBulkRegistration(toUpdate);
    }
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
        body: Center(
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
            const SizedBox(height: 10),
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

                  return Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Επιλεγμένες: ${selected.length} | Σύνολο διάρκειας: ${_totalDurationLabel(totalSelectedSeconds)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: LansweeperReportCallList(
                                grouped: groupedRows,
                                selectedKeys: _selectedKeys,
                                totalDurationLabel: _totalDurationLabel,
                                ticketViewUrlTemplate: lansweeperTicketViewUrl,
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
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LansweeperSyncForm(
                                      titleController: _titleController,
                                      notesController: _notesController,
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
                                                      ? () => _submitSelected(
                                                          primarySelected,
                                                          resubmit: false,
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
                                                      ? () => _submitSelected(
                                                          primarySelected,
                                                          resubmit: true,
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
            final hasSelection = items.any(
              (e) => _selectedKeys.contains(e.key),
            );
            final hasFormText =
                _titleController.text.trim().isNotEmpty ||
                _notesController.text.trim().isNotEmpty;
            return _wrapLansweeperConnectionTooltip(
              status: connectionStatus,
              child: FilledButton.icon(
                onPressed: (hasSelection || hasFormText) &&
                        canOpenTicketForm &&
                        connectionReady
                    ? () => _copyAndOpen(
                        ticketFormUrl: lansweeperTicketFormUrl,
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
    );
  }
}

enum _LansweeperReportFilter {
  unsentOnly,
  sentOnly,
  excludedOnly,
  failedOnly,
  all,
}

enum _UnsentTicketChoice { clear, retain, cancel }

enum _DuplicateTicketAction { proceed, changeId, cancel }

class _ReportCallItem {
  const _ReportCallItem({
    required this.key,
    required this.call,
    required this.caller,
    required this.notes,
    required this.details,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String caller;
  final String notes;
  final String details;
  final int durationSeconds;
}
