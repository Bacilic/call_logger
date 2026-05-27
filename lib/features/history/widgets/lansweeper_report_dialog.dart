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
  final TextEditingController _lansweeperLoginUrlController =
      TextEditingController();
  final TextEditingController _lansweeperHelpdeskUsernameController =
      TextEditingController();
  final TextEditingController _lansweeperHelpdeskPasswordController =
      TextEditingController();
  ProviderSubscription<String>? _lansweeperApiUrlSub;
  ProviderSubscription<String>? _lansweeperTicketFormUrlSub;
  ProviderSubscription<String>? _lansweeperApiKeySub;
  ProviderSubscription<String>? _lansweeperAgentUsernameSub;
  ProviderSubscription<String>? _lansweeperLoginUrlSub;
  ProviderSubscription<String>? _lansweeperHelpdeskUsernameSub;
  ProviderSubscription<String>? _lansweeperHelpdeskPasswordSub;
  Timer? _lansweeperSettingsDebounceTimer;
  String? _lastPrefilledKey;
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
  }

  Future<void> _openLansweeperConnectionSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => LansweeperConnectionSettingsDialog(
        apiUrlController: _lansweeperApiUrlController,
        ticketFormUrlController: _lansweeperTicketFormUrlController,
        apiKeyController: _lansweeperApiKeyController,
        agentUsernameController: _lansweeperAgentUsernameController,
        loginUrlController: _lansweeperLoginUrlController,
        helpdeskUsernameController: _lansweeperHelpdeskUsernameController,
        helpdeskPasswordController: _lansweeperHelpdeskPasswordController,
        onSettingsChanged: _scheduleLansweeperSettingsSave,
        onApiHelpLink: () {
          unawaited(_lansweeperApiHelpFromSettings());
        },
        onTicketFormHelpLink: () {
          unawaited(_lansweeperTicketFormHelpFromSettings());
        },
        onLoginHelpLink: () {
          unawaited(_lansweeperLoginHelpFromSettings());
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
    _lansweeperLoginUrlSub?.close();
    _lansweeperHelpdeskUsernameSub?.close();
    _lansweeperHelpdeskPasswordSub?.close();
    _lansweeperApiUrlController.dispose();
    _lansweeperTicketFormUrlController.dispose();
    _lansweeperApiKeyController.dispose();
    _lansweeperLoginUrlController.dispose();
    _lansweeperHelpdeskUsernameController.dispose();
    _lansweeperHelpdeskPasswordController.dispose();
    _lansweeperAgentUsernameController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    if (issue.isNotEmpty) return issue;
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
      return;
    }
    if (mounted && openedLoginTab) {
      ScaffoldMessenger.of(context).showSnackBar(
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

  void _prefillForm(_ReportCallItem item) {
    if (_lastPrefilledKey == item.key) return;
    _lastPrefilledKey = item.key;
    final category = (item.call.category ?? '').trim();
    final id = item.call.id;
    final idSuffix = id != null ? ' #$id' : '';
    _titleController.text = category.isEmpty
        ? 'Κλήση$idSuffix'
        : '[$category]$idSuffix';
    _notesController.text = item.notes;
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

    if (_lansweeperAgentUsernameController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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

  Widget _buildReportFilterBar() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilterChip(
          label: const Text('Ακαταχώρητες'),
          selected: _reportFilter == _LansweeperReportFilter.unsentOnly,
          onSelected: (_) => setState(
            () => _reportFilter = _LansweeperReportFilter.unsentOnly,
          ),
        ),
        FilterChip(
          label: const Text('Καταχωρημένες'),
          selected: _reportFilter == _LansweeperReportFilter.sentOnly,
          onSelected: (_) =>
              setState(() => _reportFilter = _LansweeperReportFilter.sentOnly),
        ),
        FilterChip(
          label: const Text('Εξαιρεμένες'),
          selected: _reportFilter == _LansweeperReportFilter.excludedOnly,
          onSelected: (_) => setState(
            () => _reportFilter = _LansweeperReportFilter.excludedOnly,
          ),
        ),
        FilterChip(
          label: const Text('Αποτυχημένες'),
          selected: _reportFilter == _LansweeperReportFilter.failedOnly,
          onSelected: (_) => setState(
            () => _reportFilter = _LansweeperReportFilter.failedOnly,
          ),
        ),
        FilterChip(
          label: const Text('Όλες'),
          selected: _reportFilter == _LansweeperReportFilter.all,
          onSelected: (_) =>
              setState(() => _reportFilter = _LansweeperReportFilter.all),
        ),
      ],
    );
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
      await _markAsUnsentWithTicketPrompt(item);
    } else if (nextState == LansweeperSyncState.sent) {
      await _applyRegistration(
        item: item,
        title: 'Καταχώρηση κλήσης',
        subtitle: 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).',
      );
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
            _buildReportFilterBar(),
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

                  if (allItems.isEmpty) {
                    return const Center(
                      child: Text(
                        'Δεν βρέθηκαν κλήσεις για τα τρέχοντα φίλτρα ημερομηνίας.',
                      ),
                    );
                  }
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Δεν υπάρχουν κλήσεις σε αυτή την κατηγορία Lansweeper.',
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
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Checkbox(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    value: _selectedKeys
                                                        .contains(item.key),
                                                    onChanged: (v) =>
                                                        _toggleItem(item, v),
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                '$date • ${_durationLabel(item.durationSeconds)}',
                                                              ),
                                                            ),
                                                            LansweeperStateBadge(
                                                              state: state,
                                                              ticketId: item
                                                                  .call
                                                                  .lansweeperMainTicketId,
                                                              onPressed: syncState
                                                                      .isLoading
                                                                  ? null
                                                                  : () => unawaited(
                                                                      _toggleRegistrationFromBadge(
                                                                        item,
                                                                      ),
                                                                    ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          item.details.isNotEmpty
                                                              ? '${item.notes}\n${item.details}'
                                                              : item.notes,
                                                          maxLines: 3,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
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
                                              child: const Text('Καταχωρημένη'),
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
