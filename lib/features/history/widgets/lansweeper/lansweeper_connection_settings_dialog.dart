import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/gemini_ticket_service.dart';
import '../../../../core/services/lansweeper_agent_api_probe.dart';
import '../../../../core/services/lansweeper_helpdesk_login_probe.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/lansweeper_connection_probe_provider.dart';
import 'gemini_model_field.dart';
import 'lansweeper_connection_status_indicator.dart';

/// Διάλογος: API (`api.aspx`), φόρμα αιτήματος, πράκτορας, αυτόματη σύνδεση Help Desk.
class LansweeperConnectionSettingsDialog extends ConsumerStatefulWidget {
  const LansweeperConnectionSettingsDialog({
    required this.apiUrlController,
    required this.ticketFormUrlController,
    required this.ticketViewUrlController,
    required this.apiKeyController,
    required this.agentUsernameController,
    required this.loginUrlController,
    required this.helpdeskUsernameController,
    required this.helpdeskPasswordController,
    required this.geminiApiKeyController,
    required this.geminiPromptTemplateController,
    required this.geminiEndpointController,
    required this.geminiPrimaryModelController,
    required this.geminiFallbackModelController,
    required this.onSettingsChanged,
    required this.onLansweeperUrlChanged,
    required this.onApiHelpLink,
    required this.onTicketFormHelpLink,
    required this.onTicketViewHelpLink,
    required this.onLoginHelpLink,
    required this.onAiHelpLink,
    super.key,
  });

  final TextEditingController apiUrlController;
  final TextEditingController ticketFormUrlController;
  final TextEditingController ticketViewUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController agentUsernameController;
  final TextEditingController loginUrlController;
  final TextEditingController helpdeskUsernameController;
  final TextEditingController helpdeskPasswordController;
  final TextEditingController geminiApiKeyController;
  final TextEditingController geminiPromptTemplateController;
  final TextEditingController geminiEndpointController;
  final TextEditingController geminiPrimaryModelController;
  final TextEditingController geminiFallbackModelController;
  final VoidCallback onSettingsChanged;
  final VoidCallback onLansweeperUrlChanged;
  final VoidCallback onApiHelpLink;
  final VoidCallback onTicketFormHelpLink;
  final VoidCallback onTicketViewHelpLink;
  final VoidCallback onLoginHelpLink;
  final VoidCallback onAiHelpLink;

  @override
  ConsumerState<LansweeperConnectionSettingsDialog> createState() =>
      _LansweeperConnectionSettingsDialogState();
}

class _LansweeperConnectionSettingsDialogState
    extends ConsumerState<LansweeperConnectionSettingsDialog> {
  bool _obscureHelpdeskPassword = true;
  bool _obscureGeminiKey = true;
  bool _credentialTestRunning = false;
  bool? _credentialTestOk;
  String? _credentialTestMessage;
  bool _agentProbeRunning = false;
  bool? _agentProbeOk;
  String? _agentProbeMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Future<void> _runAgentApiProbe() async {
    setState(() {
      _agentProbeRunning = true;
      _agentProbeOk = null;
      _agentProbeMessage = null;
    });
    final result = await LansweeperAgentApiProbe.verify(
      apiUrl: widget.apiUrlController.text,
      apiKey: widget.apiKeyController.text,
      agentUsername: widget.agentUsernameController.text,
    );
    if (!mounted) return;
    setState(() {
      _agentProbeRunning = false;
      _agentProbeOk = result.ok;
      _agentProbeMessage = result.message;
    });
  }

  void _insertPromptPlaceholder(String token) {
    final controller = widget.geminiPromptTemplateController;
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, token);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    widget.onSettingsChanged();
  }

  Future<void> _runCredentialTest() async {
    setState(() {
      _credentialTestRunning = true;
      _credentialTestOk = null;
      _credentialTestMessage = null;
    });
    final result = await LansweeperHelpdeskLoginProbe.test(
      loginPageUrl: widget.loginUrlController.text,
      username: widget.helpdeskUsernameController.text,
      password: widget.helpdeskPasswordController.text,
    );
    if (!mounted) return;
    setState(() {
      _credentialTestRunning = false;
      _credentialTestOk = result.ok;
      _credentialTestMessage = result.message;
    });
  }

  bool _geminiModelsAreValid() {
    return geminiPrimaryFallbackModelsAreDistinct(
      primaryModel: widget.geminiPrimaryModelController.text,
      fallbackModel: widget.geminiFallbackModelController.text,
      fallbackEnabled: ref.read(geminiFallbackEnabledProvider),
    );
  }

  Future<void> _showDuplicateModelsBlockDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ίδιο μοντέλο'),
        content: const Text(
          'Το κύριο και το εφεδρικό μοντέλο δεν μπορεί να είναι το ίδιο. '
          'Διορθώστε τις τιμές πριν το κλείσιμο.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!_geminiModelsAreValid()) {
      await _showDuplicateModelsBlockDialog();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final autoLogin = ref.watch(lansweeperHelpdeskAutoLoginProvider);
    final geminiFallbackEnabled = ref.watch(geminiFallbackEnabledProvider);
    final connectionStatus = ref.watch(lansweeperConnectionProbeProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_requestClose());
      },
      child: AlertDialog(
      title: const Text('Ρυθμίσεις Lansweeper'),
      content: SizedBox(
        width: 520,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(right: 16),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('Σύνδεση API (Ticket API)'),
              TextFormField(
                controller: widget.apiUrlController,
                onChanged: (_) => widget.onLansweeperUrlChanged(),
                decoration: const InputDecoration(
                  labelText: 'URL API (api.aspx)',
                  hintText: 'http://[διακομιστής]:[πύλη]/api.aspx',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onApiHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: widget.apiKeyController,
                onChanged: (_) => widget.onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Lansweeper API key',
                  hintText: 'API key…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const Divider(height: 24),
              _sectionTitle('Φόρμα νέου αιτήματος (browser)'),
              TextFormField(
                controller: widget.ticketFormUrlController,
                onChanged: (_) => widget.onLansweeperUrlChanged(),
                decoration: const InputDecoration(
                  labelText: 'URL φόρμας νέου αιτήματος',
                  hintText: '…/helpdesk/NewTicket.aspx…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onTicketFormHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.ticketViewUrlController,
                onChanged: (_) => widget.onLansweeperUrlChanged(),
                decoration: const InputDecoration(
                  labelText: 'URL προβολής ticket',
                  hintText: '…/helpdesk/ticket.aspx?tid={tid}',
                  helperText:
                      'Χρησιμοποιήστε {tid} ως θέση του αριθμού ticket στη λίστα αναφοράς.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onTicketViewHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const Divider(height: 24),
              _sectionTitle('Πράκτορας & αιτών API (ίδια τιμή)'),
              TextFormField(
                controller: widget.agentUsernameController,
                onChanged: (_) => widget.onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Πράκτορας = αιτών (username / UPN)',
                  hintText: 'π.χ. v.drosos ή v.drosos@gnk.local',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Στο AddTicket στέλνονται AgentUsername και Displayname με την ίδια τιμή· '
                  'αν περιέχει @, στέλνεται και Email (UPN). '
                  'Ο έλεγχος καλεί το API με δοκιμαστικό αίτημα — αν επιτύχει, δημιουργείται ticket που μπορείτε να διαγράψετε.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _agentProbeRunning ? null : _runAgentApiProbe,
                icon: _agentProbeRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.badge_outlined, size: 20),
                label: Text(
                  _agentProbeRunning
                      ? 'Έλεγχος πράκτορα…'
                      : 'Έλεγχος πράκτορα API',
                ),
              ),
              if (_agentProbeMessage != null) ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (_agentProbeOk == true ? Colors.green : Colors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_agentProbeOk == true ? Colors.green : Colors.red)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _agentProbeOk == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _agentProbeOk == true
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _agentProbeMessage!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Divider(height: 24),
              _sectionTitle('Help Desk — αυτόματη σύνδεση (browser)'),
              Text(
                'Η εφαρμογή δεν μεταφέρει συνεδρία στον περιηγητή. Με ενεργή επιλογή ανοίγει πρώτα η σελίδα σύνδεσης και μετά η φόρμα. Χρησιμοποιήστε «Έλεγχος διαπιστευτηρίων» για επαλήθευση.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Άνοιγμα σελίδας σύνδεσης πριν τη φόρμα'),
                value: autoLogin,
                onChanged: (v) {
                  unawaited(
                    ref.read(lansweeperHelpdeskAutoLoginProvider.notifier).setEnabled(v),
                  );
                },
              ),
              TextFormField(
                controller: widget.loginUrlController,
                onChanged: (_) => widget.onLansweeperUrlChanged(),
                decoration: const InputDecoration(
                  labelText: 'URL σελίδας σύνδεσης (login.aspx)',
                  hintText: 'http://…/login.aspx',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onLoginHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.helpdeskUsernameController,
                onChanged: (_) => widget.onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Όνομα χρήστη Help Desk',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.helpdeskPasswordController,
                onChanged: (_) => widget.onSettingsChanged(),
                obscureText: _obscureHelpdeskPassword,
                decoration: InputDecoration(
                  labelText: 'Κωδικός Help Desk',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: _obscureHelpdeskPassword
                        ? 'Εμφάνιση κωδικού'
                        : 'Απόκρυψη κωδικού',
                    onPressed: () {
                      setState(() {
                        _obscureHelpdeskPassword = !_obscureHelpdeskPassword;
                      });
                    },
                    icon: Icon(
                      _obscureHelpdeskPassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _credentialTestRunning ? null : _runCredentialTest,
                icon: _credentialTestRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined, size: 20),
                label: Text(
                  _credentialTestRunning
                      ? 'Έλεγχος…'
                      : 'Έλεγχος διαπιστευτηρίων',
                ),
              ),
              if (_credentialTestMessage != null) ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (_credentialTestOk == true
                            ? Colors.green
                            : Colors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_credentialTestOk == true
                              ? Colors.green
                              : Colors.red)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _credentialTestOk == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _credentialTestOk == true
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _credentialTestMessage!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Divider(height: 24),
              _sectionTitle('Τεχνητή Νοημοσύνη'),
              Text(
                'Απαιτείται για την αυτόματη πρόταση τίτλου/περιγραφής ticket.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onAiHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text(
                    'Δωρεάν κλειδί από: aistudio.google.com',
                  ),
                ),
              ),
              TextFormField(
                controller: widget.geminiApiKeyController,
                onChanged: (_) => widget.onSettingsChanged(),
                obscureText: _obscureGeminiKey,
                decoration: InputDecoration(
                  labelText: 'Gemini API key',
                  hintText: 'AIza…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: _obscureGeminiKey
                        ? 'Εμφάνιση κλειδιού'
                        : 'Απόκρυψη κλειδιού',
                    onPressed: () {
                      setState(() {
                        _obscureGeminiKey = !_obscureGeminiKey;
                      });
                    },
                    icon: Icon(
                      _obscureGeminiKey
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Προτροπή (prompt) για πρόταση τίτλου/περιγραφής. '
                'Εισάγετε placeholders στη θέση του κέρσορα:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final placeholder in kGeminiPromptPlaceholders)
                    ActionChip(
                      label: Text(placeholder.label),
                      onPressed: () =>
                          _insertPromptPlaceholder(placeholder.token),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.geminiPromptTemplateController,
                onChanged: (_) => widget.onSettingsChanged(),
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Προτροπή Gemini',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.geminiEndpointController,
                onChanged: (_) => widget.onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Διεύθυνση κλήσης API του Gemini',
                  hintText:
                      '…/models/{προτεύων μοντέλο}:generateContent?key={κλειδί API}',
                  helperText:
                      'Χρησιμοποιήστε {προτεύων μοντέλο} και {κλειδί API} ως placeholders.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Υποβάθμιση σε εφεδρικό μοντέλο'),
                subtitle: const Text(
                  'Αν το κύριο μοντέλο είναι υπερφορτωμένο (503), δοκιμάζεται '
                  'αυτόματα το εφεδρικό μοντέλο.',
                ),
                value: geminiFallbackEnabled,
                onChanged: (v) {
                  unawaited(
                    ref
                        .read(geminiFallbackEnabledProvider.notifier)
                        .setEnabled(v),
                  );
                },
              ),
              const SizedBox(height: 4),
              GeminiModelsSection(
                primaryModelController: widget.geminiPrimaryModelController,
                fallbackModelController: widget.geminiFallbackModelController,
                apiKeyController: widget.geminiApiKeyController,
                fallbackEnabled: geminiFallbackEnabled,
                endpointTemplate: widget.geminiEndpointController.text.trim().isEmpty
                    ? kDefaultGeminiEndpoint
                    : widget.geminiEndpointController.text,
                onChanged: widget.onSettingsChanged,
              ),
              const Divider(height: 24),
              _sectionTitle('Κατάσταση σύνδεσης'),
              LansweeperConnectionStatusIndicator(status: connectionStatus),
            ],
          ),
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_requestClose()),
          child: const Text('Κλείσιμο'),
        ),
      ],
      ),
    );
  }
}
