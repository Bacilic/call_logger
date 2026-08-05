import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/lansweeper_agent_api_probe.dart';
import '../../../../core/services/lansweeper_ticket_requester_fields.dart';
import 'lansweeper_settings_card.dart';

/// Καρτέλα «Σύνδεση API»: στοιχεία Ticket API και πράκτορας/αιτών.
class LansweeperSettingsApiTab extends StatefulWidget {
  const LansweeperSettingsApiTab({
    required this.apiUrlController,
    required this.apiKeyController,
    required this.agentUsernameController,
    required this.onSettingsChanged,
    required this.onLansweeperUrlChanged,
    required this.onApiHelpLink,
    super.key,
  });

  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController agentUsernameController;
  final VoidCallback onSettingsChanged;
  final VoidCallback onLansweeperUrlChanged;
  final VoidCallback onApiHelpLink;

  @override
  State<LansweeperSettingsApiTab> createState() =>
      _LansweeperSettingsApiTabState();
}

class _LansweeperSettingsApiTabState extends State<LansweeperSettingsApiTab> {
  bool _obscureApiKey = true;
  bool _agentProbeRunning = false;
  bool? _agentProbeOk;
  String? _agentProbeMessage;

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

  Widget _buildApiConnectionCard() {
    return LansweeperSettingsCard(
      icon: Icons.power_rounded,
      title: 'Σύνδεση API (Ticket API)',
      children: [
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
          obscureText: _obscureApiKey,
          decoration: InputDecoration(
            labelText: 'Lansweeper API key',
            hintText: 'API key…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscureApiKey
                  ? 'Εμφάνιση κλειδιού'
                  : 'Απόκρυψη κλειδιού',
              onPressed: () {
                setState(() => _obscureApiKey = !_obscureApiKey);
              },
              icon: Icon(
                _obscureApiKey
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgentCard(BuildContext context) {
    return LansweeperSettingsCard(
      icon: Icons.badge_outlined,
      title: 'Πράκτορας & αιτών API (ίδια τιμή)',
      children: [
        TextFormField(
          controller: widget.agentUsernameController,
          onChanged: (_) {
            widget.onSettingsChanged();
            setState(() {});
          },
          decoration: const InputDecoration(
            labelText: 'Πράκτορας = αιτών (domain\\username)',
            hintText: 'π.χ. gnk\\v.drosos',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Στο AddTicket στέλνονται Username και AgentUsername με την ίδια τιμή '
            '(όπως στο Lansweeper: domain\\username). '
            'Ο έλεγχος καλεί το API με δοκιμαστικό αίτημα — αν επιτύχει, δημιουργείται ticket που μπορείτε να διαγράψετε.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (lansweeperAgentValueLooksLikeDisplayName(
          widget.agentUsernameController.text,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Η τιμή δεν μοιάζει με έγκυρη ταυτότητα (domain\\username ή '
              'email). Ελέγξτε τη μορφή πριν τον έλεγχο API.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
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
            _agentProbeRunning ? 'Έλεγχος πράκτορα…' : 'Έλεγχος πράκτορα API',
          ),
        ),
        if (_agentProbeMessage != null) ...[
          const SizedBox(height: 10),
          LansweeperProbeResultBanner(
            ok: _agentProbeOk == true,
            message: _agentProbeMessage!,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildApiConnectionCard()),
        const SizedBox(width: 14),
        Expanded(child: _buildAgentCard(context)),
      ],
    );
  }
}
