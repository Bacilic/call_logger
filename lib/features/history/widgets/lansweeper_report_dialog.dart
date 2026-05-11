import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/models/call_model.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/dashboard_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import 'lansweeper/lansweeper_connection_settings_dialog.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper/lansweeper_state_badge.dart';
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
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _lansweeperAgentUsernameController =
      TextEditingController();
  final TextEditingController _lansweeperApiUrlController =
      TextEditingController();
  final TextEditingController _lansweeperTicketFormUrlController =
      TextEditingController();
  final TextEditingController _lansweeperApiKeyController =
      TextEditingController();
  ProviderSubscription<String>? _lansweeperApiUrlSub;
  ProviderSubscription<String>? _lansweeperTicketFormUrlSub;
  ProviderSubscription<String>? _lansweeperApiKeySub;
  ProviderSubscription<String>? _lansweeperAgentUsernameSub;
  Timer? _lansweeperSettingsDebounceTimer;
  String? _lastPrefilledKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lansweeperApiUrlController.text = ref.read(lansweeperApiUrlProvider);
      _lansweeperTicketFormUrlController.text = ref.read(
        lansweeperTicketFormUrlProvider,
      );
      _lansweeperApiKeyController.text = ref.read(lansweeperApiKeyProvider);
      _lansweeperAgentUsernameController.text = ref.read(
        lansweeperAgentUsernameProvider,
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
  }

  Future<void> _openLansweeperConnectionSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => LansweeperConnectionSettingsDialog(
        apiUrlController: _lansweeperApiUrlController,
        ticketFormUrlController: _lansweeperTicketFormUrlController,
        apiKeyController: _lansweeperApiKeyController,
        agentUsernameController: _lansweeperAgentUsernameController,
        onSettingsChanged: _scheduleLansweeperSettingsSave,
        onApiHelpLink: () {
          unawaited(_lansweeperApiHelpFromSettings());
        },
        onTicketFormHelpLink: () {
          unawaited(_lansweeperTicketFormHelpFromSettings());
        },
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  void _scheduleLansweeperSettingsSave() {
    _lansweeperSettingsDebounceTimer?.cancel();
    _lansweeperSettingsDebounceTimer = Timer(
      _lansweeperSettingsDebounceDuration,
      _persistLansweeperSettingsSafely,
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
            .read(lansweeperApiKeyProvider.notifier)
            .setApiKey(_lansweeperApiKeyController.text),
      );
      unawaited(
        ref
            .read(lansweeperAgentUsernameProvider.notifier)
            .setAgentUsername(_lansweeperAgentUsernameController.text),
      );
    });
  }

  String _callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? '-' : value;
  }

  @override
  void dispose() {
    _lansweeperSettingsDebounceTimer?.cancel();
    _lansweeperApiUrlSub?.close();
    _lansweeperTicketFormUrlSub?.close();
    _lansweeperApiKeySub?.close();
    _lansweeperAgentUsernameSub?.close();
    _lansweeperApiUrlController.dispose();
    _lansweeperTicketFormUrlController.dispose();
    _lansweeperApiKeyController.dispose();
    _lansweeperAgentUsernameController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    final solution = (call.solution ?? '').trim();
    if (issue.isNotEmpty && solution.isNotEmpty) return '$issue — $solution';
    if (issue.isNotEmpty) return issue;
    if (solution.isNotEmpty) return solution;
    return '-';
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

  bool? _groupCheckedValue(List<_ReportCallItem> items) {
    if (items.isEmpty) return false;
    final selectedCount = items
        .where((e) => _selectedKeys.contains(e.key))
        .length;
    if (selectedCount == 0) return false;
    if (selectedCount == items.length) return true;
    return null;
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

  Future<void> _copyAndOpen({
    required List<_ReportCallItem> allItems,
    required String ticketFormUrl,
  }) async {
    final selected = allItems
        .where((e) => _selectedKeys.contains(e.key))
        .toList();
    if (selected.isEmpty) return;

    if (!LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL φόρμας νέου αιτήματος στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final lines = selected.map((e) {
      final details = e.details.isNotEmpty ? ' • ${e.details}' : '';
      return '${e.caller}: ${e.notes}$details [${_durationLabel(e.durationSeconds)}]';
    }).toList();
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Αντιγράφηκαν οι επιλεγμένες κλήσεις.')),
    );

    final uri = Uri.tryParse(ticketFormUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Μη έγκυρο URL φόρμας εισιτηρίου.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία ανοίγματος URL φόρμας.')),
      );
    }
  }

  _ReportCallItem? _primarySelectedItem(List<_ReportCallItem> allItems) {
    for (final item in allItems) {
      if (_selectedKeys.contains(item.key)) return item;
    }
    return null;
  }

  void _prefillForm(_ReportCallItem item) {
    if (_lastPrefilledKey == item.key) return;
    _lastPrefilledKey = item.key;
    final category = (item.call.category ?? '').trim();
    _titleController.text = category.isEmpty
        ? item.caller
        : '[$category] ${item.caller}';
    final mergedNotes = item.details.isEmpty
        ? item.notes
        : '${item.notes}\n${item.details}';
    _notesController.text = mergedNotes;
  }

  Future<void> _submitSelected(
    _ReportCallItem item, {
    required bool resubmit,
  }) async {
    final callId = item.call.id;
    if (callId == null) return;
    if (_titleController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ο τίτλος είναι υποχρεωτικός.')),
      );
      return;
    }

    final apiUrl = ref.read(lansweeperApiUrlProvider);
    if (!LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Καταχώρηση επιτυχής. Ticket: ${result.ticketId ?? '-'}',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Αποτυχία καταχώρησης: ${result.message}')),
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
              ScaffoldMessenger.of(ctx).showSnackBar(
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

  Future<void> _manualMark(_ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return;
    final ticketController = TextEditingController();
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
                  decoration: const InputDecoration(
                    labelText: 'Ticket ID',
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
      final ticketId = ticketController.text.trim();
      if (ticketId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Το Ticket ID είναι υποχρεωτικό.')),
          );
        }
        return;
      }
      await ref
          .read(lansweeperSyncProvider.notifier)
          .markAsPassedManually(
            callId: callId,
            ticketId: ticketId,
            comment: commentController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η κλήση επισημάνθηκε ως περασμένη.')),
      );
    } finally {
      ticketController.dispose();
      commentController.dispose();
    }
  }

  Future<void> _setStateForSelected(
    _ReportCallItem item,
    String nextState,
  ) async {
    final callId = item.call.id;
    if (callId == null) return;
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    if (nextState == LansweeperSyncState.excluded) {
      await notifier.setExcluded(callId);
    } else if (nextState == LansweeperSyncState.unsent) {
      await notifier.setUnsent(callId);
    } else if (nextState == LansweeperSyncState.sent) {
      await notifier.setSent(callId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(dashboardCallsForReportProvider);
    final lansweeperApiUrl = ref.watch(lansweeperApiUrlProvider);
    final lansweeperTicketFormUrl = ref.watch(lansweeperTicketFormUrlProvider);
    final syncState = ref.watch(lansweeperSyncProvider);
    final canSubmitToApi = LansweeperUrlRules.isApiEndpointUrl(
      lansweeperApiUrl,
    );
    final canOpenTicketForm = LansweeperUrlRules.isBrowserLaunchableUrl(
      lansweeperTicketFormUrl,
    );

    return AlertDialog(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: Text('Αναφορά Lansweeper')),
          IconButton(
            tooltip:
                'Ρυθμίσεις Lansweeper (URL API, φόρμα εισιτηρίου, API key, πράκτορας)',
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
            Expanded(
              child: callsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Σφάλμα φόρτωσης κλήσεων: $e')),
                data: (calls) {
                  final items = _toItems(calls);
                  final grouped = _groupByCaller(items);
                  final selected = items
                      .where((e) => _selectedKeys.contains(e.key))
                      .toList();
                  final primarySelected = _primarySelectedItem(items);
                  if (primarySelected != null) {
                    _prefillForm(primarySelected);
                  }
                  final totalSelectedSeconds = selected.fold<int>(
                    0,
                    (sum, item) => sum + item.durationSeconds,
                  );
                  final selectedCallId = primarySelected?.call.id;
                  final linksAsync = selectedCallId != null
                      ? ref.watch(callExternalLinksProvider(selectedCallId))
                      : const AsyncData<List<Map<String, dynamic>>>(
                          <Map<String, dynamic>>[],
                        );

                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Δεν βρέθηκαν κλήσεις για τα τρέχοντα φίλτρα.',
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
                              flex: 3,
                              child: ListView(
                                children: grouped.entries.map((entry) {
                                  final caller = entry.key;
                                  final callerItems = entry.value;
                                  final groupSeconds = callerItems.fold<int>(
                                    0,
                                    (sum, item) => sum + item.durationSeconds,
                                  );
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        8,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CheckboxListTile(
                                            tristate: true,
                                            dense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                            value: _groupCheckedValue(
                                              callerItems,
                                            ),
                                            onChanged: (v) =>
                                                _toggleGroup(callerItems, v),
                                            title: Text(
                                              caller,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${callerItems.length} κλήσεις • ${_totalDurationLabel(groupSeconds)}',
                                            ),
                                          ),
                                          const Divider(height: 8),
                                          ...callerItems.map((item) {
                                            final date = DateFormat(
                                              'dd/MM/yyyy HH:mm',
                                            ).format(_callDateTime(item.call));
                                            final state =
                                                (item.call.lansweeperState ??
                                                        LansweeperSyncState
                                                            .unsent)
                                                    .trim();
                                            final hasTicket =
                                                (item.call.lansweeperMainTicketId ??
                                                        '')
                                                    .trim()
                                                    .isNotEmpty;
                                            return CheckboxListTile(
                                              dense: true,
                                              value: _selectedKeys.contains(
                                                item.key,
                                              ),
                                              onChanged: (v) =>
                                                  _toggleItem(item, v),
                                              title: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '$date • ${_durationLabel(item.durationSeconds)}',
                                                    ),
                                                  ),
                                                  LansweeperStateBadge(
                                                    state: state,
                                                    hasTicket: hasTicket,
                                                  ),
                                                ],
                                              ),
                                              subtitle: Text(
                                                item.details.isNotEmpty
                                                    ? '${item.notes}\n${item.details}'
                                                    : item.notes,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LansweeperSyncForm(
                                      titleController: _titleController,
                                      notesController: _notesController,
                                    ),
                                    const SizedBox(height: 10),
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.icon(
                                              onPressed:
                                                  (primarySelected != null &&
                                                      !syncState.isLoading &&
                                                      canSubmitToApi)
                                                  ? () => _submitSelected(
                                                      primarySelected,
                                                      resubmit: false,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.cloud_upload_rounded,
                                              ),
                                              label: const Text(
                                                'Άμεση Καταχώρηση',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed:
                                                  (primarySelected != null &&
                                                      !syncState.isLoading &&
                                                      canSubmitToApi)
                                                  ? () => _submitSelected(
                                                      primarySelected,
                                                      resubmit: true,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                              label: const Text('Επαναϋποβολή'),
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
                                            OutlinedButton(
                                              onPressed: primarySelected == null
                                                  ? null
                                                  : () => _setStateForSelected(
                                                      primarySelected,
                                                      LansweeperSyncState
                                                          .excluded,
                                                    ),
                                              child: const Text('Εξαίρεση'),
                                            ),
                                            OutlinedButton(
                                              onPressed: primarySelected == null
                                                  ? null
                                                  : () => _setStateForSelected(
                                                      primarySelected,
                                                      LansweeperSyncState
                                                          .unsent,
                                                    ),
                                              child: const Text('Ακαταχώρητη'),
                                            ),
                                            OutlinedButton(
                                              onPressed: primarySelected == null
                                                  ? null
                                                  : () => _setStateForSelected(
                                                      primarySelected,
                                                      LansweeperSyncState.sent,
                                                    ),
                                              child: const Text('Περασμένη'),
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
            final items = _toItems(calls);
            final hasSelection = items.any(
              (e) => _selectedKeys.contains(e.key),
            );
            return FilledButton.icon(
              onPressed: hasSelection && canOpenTicketForm
                  ? () => _copyAndOpen(
                      allItems: items,
                      ticketFormUrl: lansweeperTicketFormUrl,
                    )
                  : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Αντιγραφή & Άνοιγμα Lansweeper'),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

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
