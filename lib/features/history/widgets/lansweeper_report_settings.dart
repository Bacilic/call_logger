import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/gemini_settings_provider.dart';
import '../providers/lansweeper_connection_probe_provider.dart';
import 'lansweeper/ai_prompt_template_editor_dialog.dart';
import 'lansweeper/lansweeper_connection_settings_dialog.dart';
import 'lansweeper/lansweeper_settings_persistence.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper_report_dialog.dart';

const _lansweeperSettingsDebounceDuration = Duration(milliseconds: 350);

/// Ρυθμίσεις σύνδεσης Lansweeper/Gemini: διάλογοι, σύνδεσμοι βοήθειας,
/// debounce αποθήκευση.
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportSettings {
  LansweeperReportSettings(this.host);

  final LansweeperReportDialogState host;

  Future<void> openConnectionSettingsDialog() async {
    await showDialog<void>(
      context: host.context,
      builder: (ctx) => LansweeperConnectionSettingsDialog(
        apiUrlController: host.lansweeperApiUrlController,
        ticketFormUrlController: host.lansweeperTicketFormUrlController,
        ticketViewUrlController: host.lansweeperTicketViewUrlController,
        apiKeyController: host.lansweeperApiKeyController,
        agentUsernameController: host.lansweeperAgentUsernameController,
        loginUrlController: host.lansweeperLoginUrlController,
        helpdeskUsernameController: host.lansweeperHelpdeskUsernameController,
        helpdeskPasswordController: host.lansweeperHelpdeskPasswordController,
        geminiApiKeyController: host.geminiApiKeyController,
        geminiEndpointController: host.geminiEndpointController,
        geminiPrimaryModelController: host.geminiPrimaryModelController,
        geminiFallbackModelController: host.geminiFallbackModelController,
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

  Future<void> openAiPromptTemplateEditorDialog() async {
    final savedTemplate = host.ref.read(geminiPromptTemplateProvider);
    await showDialog<void>(
      context: host.context,
      // Σημερινή συμπεριφορά, δηλωμένη: το κλικ έξω δεν κλείνει.
      barrierDismissible: false,
      builder: (ctx) => AiPromptTemplateEditorDialog(
        savedTemplate: savedTemplate,
        onSave: (text) async {
          await host.ref
              .read(geminiPromptTemplateProvider.notifier)
              .setPromptTemplate(text);
          if (host.aiPromptTemplateController.text != text) {
            host.aiPromptTemplateController.text = text;
          }
        },
      ),
    );
  }

  Future<void> _geminiApiHelpFromSettings() async {
    const url = 'https://aistudio.google.com/api-keys';
    if (!host.mounted) return;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      const SnackBar(content: Text('Άνοιξε ο σύνδεσμος: aistudio.google.com')),
    );
  }

  Future<void> _lansweeperApiHelpFromSettings() async {
    final chosen = LansweeperUrlRules.apiUrlForHelpLink(
      host.lansweeperApiUrlController.text,
    );
    if (!host.mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperTicketFormHelpFromSettings() async {
    final chosen = LansweeperUrlRules.ticketFormUrlForHelpLink(
      host.lansweeperTicketFormUrlController.text,
    );
    if (!host.mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperTicketViewHelpFromSettings() async {
    final chosen = LansweeperUrlRules.ticketViewUrlForHelpLink(
      host.lansweeperTicketViewUrlController.text,
    );
    if (!host.mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  Future<void> _lansweeperLoginHelpFromSettings() async {
    final chosen = LansweeperUrlRules.loginPageUrlForHelpLink(
      host.lansweeperLoginUrlController.text,
    );
    if (!host.mounted) return;
    final uri = Uri.tryParse(chosen);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(content: Text('Άνοιξε ο σύνδεσμος: $chosen')),
    );
  }

  void _scheduleLansweeperSettingsSave({bool recheckConnection = false}) {
    host.lansweeperSettingsDebounceTimer?.cancel();
    host.lansweeperSettingsDebounceTimer = Timer(
      _lansweeperSettingsDebounceDuration,
      () {
        if (!host.mounted) return;
        _persistLansweeperSettingsSafely();
        if (!recheckConnection) return;
        unawaited(
          host.ref.read(lansweeperConnectionProbeProvider.notifier).check(),
        );
      },
    );
  }

  void _persistLansweeperSettingsSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted) return;
      persistLansweeperSettings(
        host.ref,
        LansweeperSettingsValues(
          apiUrl: host.lansweeperApiUrlController.text,
          ticketFormUrl: host.lansweeperTicketFormUrlController.text,
          ticketViewUrl: host.lansweeperTicketViewUrlController.text,
          apiKey: host.lansweeperApiKeyController.text,
          agentUsername: host.lansweeperAgentUsernameController.text,
          loginUrl: host.lansweeperLoginUrlController.text,
          helpdeskUsername: host.lansweeperHelpdeskUsernameController.text,
          helpdeskPassword: host.lansweeperHelpdeskPasswordController.text,
          geminiApiKey: host.geminiApiKeyController.text,
          geminiPromptTemplate: host.aiPromptTemplateController.text,
          geminiEndpoint: host.geminiEndpointController.text,
          geminiPrimaryModel: host.geminiPrimaryModelController.text,
          geminiFallbackModel: host.geminiFallbackModelController.text,
        ),
      );
    });
  }
}
