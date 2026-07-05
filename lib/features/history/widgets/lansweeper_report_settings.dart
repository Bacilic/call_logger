part of 'lansweeper_report_dialog.dart';

const _lansweeperSettingsDebounceDuration = Duration(milliseconds: 350);

mixin LansweeperReportSettingsMixin on LansweeperReportDialogStateHost {
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

  Future<void> _openAiPromptTemplateEditorDialog() async {
    final savedTemplate = ref.read(geminiPromptTemplateProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AiPromptTemplateEditorDialog(
        savedTemplate: savedTemplate,
        onSave: (text) async {
          await ref
              .read(geminiPromptTemplateProvider.notifier)
              .setPromptTemplate(text);
          if (_aiPromptTemplateController.text != text) {
            _aiPromptTemplateController.text = text;
          }
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
    showDialogSnackBar(
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
    showDialogSnackBar(
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
    showDialogSnackBar(
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
    showDialogSnackBar(
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
    showDialogSnackBar(
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
      persistLansweeperSettings(
        ref,
        LansweeperSettingsValues(
          apiUrl: _lansweeperApiUrlController.text,
          ticketFormUrl: _lansweeperTicketFormUrlController.text,
          ticketViewUrl: _lansweeperTicketViewUrlController.text,
          apiKey: _lansweeperApiKeyController.text,
          agentUsername: _lansweeperAgentUsernameController.text,
          loginUrl: _lansweeperLoginUrlController.text,
          helpdeskUsername: _lansweeperHelpdeskUsernameController.text,
          helpdeskPassword: _lansweeperHelpdeskPasswordController.text,
          geminiApiKey: _geminiApiKeyController.text,
          geminiPromptTemplate: _aiPromptTemplateController.text,
          geminiEndpoint: _geminiEndpointController.text,
          geminiPrimaryModel: _geminiPrimaryModelController.text,
          geminiFallbackModel: _geminiFallbackModelController.text,
        ),
      );
    });
  }
}
