import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gemini_settings_provider.dart';
import '../../providers/lansweeper_connection_probe_provider.dart';
import 'gemini_model_field.dart';
import 'lansweeper_connection_status_indicator.dart';
import 'lansweeper_settings_ai_tab.dart';
import 'lansweeper_settings_api_tab.dart';
import 'lansweeper_settings_helpdesk_tab.dart';
import 'lansweeper_ticket_submit_settings_section.dart';

/// Διάλογος «Ρυθμίσεις Lansweeper» σε 4 θεματικές καρτέλες
/// (Σύνδεση API, Help Desk / Browser, Τεχνητή Νοημοσύνη, Καταχώρηση εισιτηρίου)
/// με μόνιμη ένδειξη κατάστασης σύνδεσης ορατή από κάθε καρτέλα.
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

  Widget _tab(IconData icon, String label) {
    return Tab(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _scrollableTab(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(lansweeperConnectionProbeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = math.min(920.0, screenSize.width - 120);
    final contentHeight = math.min(600.0, screenSize.height - 240);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_requestClose());
      },
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.settings_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Text('Ρυθμίσεις Lansweeper'),
          ],
        ),
        content: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: DefaultTabController(
            length: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  tabs: [
                    _tab(Icons.power_rounded, 'Σύνδεση API'),
                    _tab(Icons.language_rounded, 'Help Desk / Browser'),
                    _tab(Icons.auto_awesome_rounded, 'Τεχνητή Νοημοσύνη'),
                    _tab(
                      Icons.confirmation_number_outlined,
                      'Καταχώρηση εισιτηρίου',
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _scrollableTab(
                        LansweeperSettingsApiTab(
                          apiUrlController: widget.apiUrlController,
                          apiKeyController: widget.apiKeyController,
                          agentUsernameController:
                              widget.agentUsernameController,
                          onSettingsChanged: widget.onSettingsChanged,
                          onLansweeperUrlChanged: widget.onLansweeperUrlChanged,
                          onApiHelpLink: widget.onApiHelpLink,
                        ),
                      ),
                      _scrollableTab(
                        LansweeperSettingsHelpdeskTab(
                          ticketFormUrlController:
                              widget.ticketFormUrlController,
                          ticketViewUrlController:
                              widget.ticketViewUrlController,
                          loginUrlController: widget.loginUrlController,
                          helpdeskUsernameController:
                              widget.helpdeskUsernameController,
                          helpdeskPasswordController:
                              widget.helpdeskPasswordController,
                          onSettingsChanged: widget.onSettingsChanged,
                          onLansweeperUrlChanged: widget.onLansweeperUrlChanged,
                          onTicketFormHelpLink: widget.onTicketFormHelpLink,
                          onTicketViewHelpLink: widget.onTicketViewHelpLink,
                          onLoginHelpLink: widget.onLoginHelpLink,
                        ),
                      ),
                      _scrollableTab(
                        LansweeperSettingsAiTab(
                          geminiApiKeyController: widget.geminiApiKeyController,
                          geminiEndpointController:
                              widget.geminiEndpointController,
                          geminiPrimaryModelController:
                              widget.geminiPrimaryModelController,
                          geminiFallbackModelController:
                              widget.geminiFallbackModelController,
                          onSettingsChanged: widget.onSettingsChanged,
                          onAiHelpLink: widget.onAiHelpLink,
                        ),
                      ),
                      _scrollableTab(
                        const LansweeperTicketSubmitSettingsSection(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                LansweeperConnectionStatusIndicator(status: connectionStatus),
              ],
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
