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

  Future<void> _openGeminiPromptTemplateEditorDialog() async {
    final savedTemplate = ref.read(geminiPromptTemplateProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => GeminiPromptTemplateEditorDialog(
        savedTemplate: savedTemplate,
        onSave: (text) async {
          await ref
              .read(geminiPromptTemplateProvider.notifier)
              .setPromptTemplate(text);
          if (_geminiPromptTemplateController.text != text) {
            _geminiPromptTemplateController.text = text;
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
    _showDialogSnackBar(
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
    _showDialogSnackBar(
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
    _showDialogSnackBar(
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
    _showDialogSnackBar(
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
    _showDialogSnackBar(
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
            .read(lansweeperTicketViewUrlProvider.notifier)
            .setTicketViewUrl(_lansweeperTicketViewUrlController.text),
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
      unawaited(
        ref
            .read(geminiApiKeyProvider.notifier)
            .setApiKey(_geminiApiKeyController.text),
      );
      unawaited(
        ref
            .read(geminiPromptTemplateProvider.notifier)
            .setPromptTemplate(_geminiPromptTemplateController.text),
      );
      unawaited(
        ref
            .read(geminiEndpointProvider.notifier)
            .setEndpoint(_geminiEndpointController.text),
      );
      unawaited(
        ref
            .read(geminiPrimaryModelProvider.notifier)
            .setPrimaryModel(_geminiPrimaryModelController.text),
      );
      unawaited(
        ref
            .read(geminiFallbackModelProvider.notifier)
            .setFallbackModel(_geminiFallbackModelController.text),
      );
    });
  }
}
