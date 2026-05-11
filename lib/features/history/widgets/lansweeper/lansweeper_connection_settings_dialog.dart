import 'package:flutter/material.dart';

/// Διάλογος: URL API (`api.aspx`), URL φόρμας εισιτηρίου, API key, πράκτορας.
class LansweeperConnectionSettingsDialog extends StatelessWidget {
  const LansweeperConnectionSettingsDialog({
    required this.apiUrlController,
    required this.ticketFormUrlController,
    required this.apiKeyController,
    required this.agentUsernameController,
    required this.onSettingsChanged,
    required this.onApiHelpLink,
    required this.onTicketFormHelpLink,
    super.key,
  });

  final TextEditingController apiUrlController;
  final TextEditingController ticketFormUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController agentUsernameController;
  final VoidCallback onSettingsChanged;
  final VoidCallback onApiHelpLink;
  final VoidCallback onTicketFormHelpLink;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ρυθμίσεις Lansweeper'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: apiUrlController,
                onChanged: (_) => onSettingsChanged(),
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
                  onPressed: onApiHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: apiKeyController,
                onChanged: (_) => onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Lansweeper API key',
                  hintText: 'API key...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: ticketFormUrlController,
                onChanged: (_) => onSettingsChanged(),
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
                  onPressed: onTicketFormHelpLink,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Έλεγχος συνδέσμου'),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: agentUsernameController,
                onChanged: (_) => onSettingsChanged(),
                decoration: const InputDecoration(
                  labelText: 'Πράκτορας (username)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}
