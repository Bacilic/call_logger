import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lansweeper_settings_provider.dart';
import 'lansweeper_settings_card.dart';

/// Καρτέλα «Help Desk / Browser»: φόρμα νέου αιτήματος και προβολή ticket.
class LansweeperSettingsHelpdeskTab extends ConsumerWidget {
  const LansweeperSettingsHelpdeskTab({
    required this.ticketFormUrlController,
    required this.ticketViewUrlController,
    required this.onLansweeperUrlChanged,
    required this.onTicketFormHelpLink,
    required this.onTicketViewHelpLink,
    super.key,
  });

  final TextEditingController ticketFormUrlController;
  final TextEditingController ticketViewUrlController;
  final VoidCallback onLansweeperUrlChanged;
  final VoidCallback onTicketFormHelpLink;
  final VoidCallback onTicketViewHelpLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LansweeperSettingsCard(
      icon: Icons.language_rounded,
      title: 'Φόρμα νέου αιτήματος (browser)',
      children: [
        TextFormField(
          controller: ticketFormUrlController,
          onChanged: (_) => onLansweeperUrlChanged(),
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
        const SizedBox(height: 8),
        TextFormField(
          controller: ticketViewUrlController,
          onChanged: (_) => onLansweeperUrlChanged(),
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
            onPressed: onTicketViewHelpLink,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Έλεγχος συνδέσμου'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Άνοιγμα ticket μετά την Άμεση Καταχώρηση'),
          subtitle: const Text(
            'Μετά επιτυχή καταχώρηση μέσω API, άνοιγμα του αιτήματος '
            'στον περιηγητή με βάση το URL προβολής ticket.',
          ),
          value: ref.watch(lansweeperOpenTicketAfterApiSubmitProvider),
          onChanged: (v) {
            unawaited(
              ref
                  .read(lansweeperOpenTicketAfterApiSubmitProvider.notifier)
                  .setEnabled(v),
            );
          },
        ),
      ],
    );
  }
}
