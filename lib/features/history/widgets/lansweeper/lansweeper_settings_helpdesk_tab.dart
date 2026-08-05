import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lansweeper_helpdesk_login_probe.dart';
import '../../providers/lansweeper_settings_provider.dart';
import 'lansweeper_settings_card.dart';

/// Καρτέλα «Help Desk / Browser»: φόρμα νέου αιτήματος και αυτόματη σύνδεση.
class LansweeperSettingsHelpdeskTab extends ConsumerStatefulWidget {
  const LansweeperSettingsHelpdeskTab({
    required this.ticketFormUrlController,
    required this.ticketViewUrlController,
    required this.loginUrlController,
    required this.helpdeskUsernameController,
    required this.helpdeskPasswordController,
    required this.onSettingsChanged,
    required this.onLansweeperUrlChanged,
    required this.onTicketFormHelpLink,
    required this.onTicketViewHelpLink,
    required this.onLoginHelpLink,
    super.key,
  });

  final TextEditingController ticketFormUrlController;
  final TextEditingController ticketViewUrlController;
  final TextEditingController loginUrlController;
  final TextEditingController helpdeskUsernameController;
  final TextEditingController helpdeskPasswordController;
  final VoidCallback onSettingsChanged;
  final VoidCallback onLansweeperUrlChanged;
  final VoidCallback onTicketFormHelpLink;
  final VoidCallback onTicketViewHelpLink;
  final VoidCallback onLoginHelpLink;

  @override
  ConsumerState<LansweeperSettingsHelpdeskTab> createState() =>
      _LansweeperSettingsHelpdeskTabState();
}

class _LansweeperSettingsHelpdeskTabState
    extends ConsumerState<LansweeperSettingsHelpdeskTab> {
  bool _obscureHelpdeskPassword = true;
  bool _credentialTestRunning = false;
  bool? _credentialTestOk;
  String? _credentialTestMessage;

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

  Widget _buildTicketFormCard() {
    return LansweeperSettingsCard(
      icon: Icons.language_rounded,
      title: 'Φόρμα νέου αιτήματος (browser)',
      children: [
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

  Widget _buildAutoLoginCard(BuildContext context) {
    final autoLogin = ref.watch(lansweeperHelpdeskAutoLoginProvider);

    return LansweeperSettingsCard(
      icon: Icons.lock_outline_rounded,
      title: 'Αυτόματη σύνδεση Help Desk',
      children: [
        Text(
          'Η εφαρμογή δεν μεταφέρει συνεδρία στον περιηγητή. Με ενεργή επιλογή ανοίγει πρώτα η σελίδα σύνδεσης και μετά η φόρμα. Χρησιμοποιήστε «Έλεγχος διαπιστευτηρίων» για επαλήθευση.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Άνοιγμα σελίδας σύνδεσης πριν τη φόρμα'),
          value: autoLogin,
          onChanged: (v) {
            unawaited(
              ref
                  .read(lansweeperHelpdeskAutoLoginProvider.notifier)
                  .setEnabled(v),
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
            _credentialTestRunning ? 'Έλεγχος…' : 'Έλεγχος διαπιστευτηρίων',
          ),
        ),
        if (_credentialTestMessage != null) ...[
          const SizedBox(height: 10),
          LansweeperProbeResultBanner(
            ok: _credentialTestOk == true,
            message: _credentialTestMessage!,
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
        Expanded(child: _buildTicketFormCard()),
        const SizedBox(width: 14),
        Expanded(child: _buildAutoLoginCard(context)),
      ],
    );
  }
}
