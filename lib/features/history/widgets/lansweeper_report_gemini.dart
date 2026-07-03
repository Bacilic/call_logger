part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportGeminiMixin on LansweeperReportDialogStateHost {
  void _prefillForm(
    _ReportCallItem primary,
    List<_ReportCallItem> selected,
  ) {
    final signature = _selectedKeysSignature(selected);
    if (_lastPrefilledKey == signature) return;
    _lastPrefilledKey = signature;
    final category = (primary.call.category ?? '').trim();
    final id = primary.call.id;
    final idSuffix = id != null ? ' #$id' : '';
    _titleController.text = category.isEmpty
        ? 'Κλήση$idSuffix'
        : '[$category]$idSuffix';
    _notesController.text = _combinedSelectedNotes(selected);
    _solutionController.text = '';
  }

  String _buildGeminiPromptForSelected(List<_ReportCallItem> selected) {
    final inputs = _geminiPromptInputs(selected);
    return GeminiTicketService.buildPrompt(
      promptTemplate: ref.read(geminiPromptTemplateProvider),
      callerText: inputs.callerText,
      equipmentText: inputs.equipmentText,
      departmentText: inputs.departmentText,
      category: inputs.category,
      issue: inputs.issue,
      titleText: inputs.titleText,
      notesText: inputs.notesText,
      solutionText: inputs.solutionText,
    );
  }

  ({
    String callerText,
    String equipmentText,
    String departmentText,
    String category,
    String issue,
    String titleText,
    String notesText,
    String solutionText,
  }) _geminiPromptInputs(List<_ReportCallItem> selected) {
    return (
      callerText: _combinedUniqueCallField(
        selected,
        (call) => call.callerText,
      ),
      equipmentText: _combinedUniqueCallField(
        selected,
        (call) => call.equipmentText,
      ),
      departmentText: _combinedUniqueCallField(
        selected,
        (call) => call.departmentText,
      ),
      category: _combinedUniqueCallField(selected, (call) => call.category),
      issue: _combinedGeminiIssue(selected),
      titleText: _titleController.text,
      notesText: _notesController.text,
      solutionText: _solutionController.text,
    );
  }

  Future<void> _showGeminiPromptPreview(List<_ReportCallItem> selected) async {
    if (selected.isEmpty || _aiSuggestRunning || !mounted) return;
    final prompt = _buildGeminiPromptForSelected(selected);
    await showLansweeperGeminiPromptPreviewDialog(
      context,
      promptText: prompt,
    );
  }

  Future<void> _suggestWithAi(List<_ReportCallItem> selected) async {
    if (_aiSuggestRunning || selected.isEmpty) return;

    final apiKey = ref.read(geminiApiKeyProvider).trim();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Ορίστε Gemini API key στις ρυθμίσεις Lansweeper.'),
        ),
      );
      return;
    }

    final endpointTemplate = ref.read(geminiEndpointProvider);
    final promptTemplate = ref.read(geminiPromptTemplateProvider);
    final primaryModel = ref.read(geminiPrimaryModelProvider).trim();
    if (primaryModel.isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text('Ορίστε κύριο μοντέλο Gemini στις ρυθμίσεις Lansweeper.'),
        ),
      );
      return;
    }
    final fallbackEnabled = ref.read(geminiFallbackEnabledProvider);
    final fallbackModel = ref.read(geminiFallbackModelProvider).trim();

    final attempts = <({String model, String endpoint})>[
      (
        model: primaryModel,
        endpoint: GeminiTicketService.resolveEndpoint(
          endpoint: endpointTemplate,
          apiKey: apiKey,
          primaryModel: primaryModel,
        ),
      ),
    ];
    if (fallbackEnabled &&
        fallbackModel.isNotEmpty &&
        fallbackModel != primaryModel) {
      attempts.add((
        model: fallbackModel,
        endpoint: GeminiTicketService.resolveEndpoint(
          endpoint: GeminiTicketService.endpointWithModel(
            endpointTemplate,
            fallbackModel,
          ),
          apiKey: apiKey,
        ),
      ));
    }

    final inputs = _geminiPromptInputs(selected);

    setState(() => _aiSuggestRunning = true);
    try {
      for (var i = 0; i < attempts.length; i++) {
        final attempt = attempts[i];
        if (!mounted) return;
        _startAiSuggestTicker(model: attempt.model);
        final client = http.Client();
        _aiSuggestClient = client;
        try {
          final result = await GeminiTicketService.suggest(
            apiKey: apiKey,
            endpoint: attempt.endpoint,
            promptTemplate: promptTemplate,
            callerText: inputs.callerText,
            equipmentText: inputs.equipmentText,
            departmentText: inputs.departmentText,
            category: inputs.category,
            issue: inputs.issue,
            titleText: inputs.titleText,
            notesText: inputs.notesText,
            solutionText: inputs.solutionText,
            client: client,
          );
          if (!mounted) return;
          setState(() {
            _titleController.text = result.title;
            _notesController.text = result.description;
            _solutionController.text = result.solution;
          });
          return;
        } catch (e) {
          final statusCode = e is GeminiException ? e.statusCode : null;
          final isLast = i == attempts.length - 1;
          if (!isLast && statusCode == 503) {
            final nextModel = attempts[i + 1].model;
            if (mounted) {
              _showDialogSnackBar(
                SnackBar(
                  content: Text(
                    'Το μοντέλο «${attempt.model}» είναι υπερφορτωμένο (503). '
                    'Υποβάθμιση σε εφεδρικό μοντέλο: «$nextModel».',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            continue;
          }
          if (!mounted) return;
          final errorMessage = e is GeminiException
              ? e.message
              : e.toString().replaceFirst('Exception: ', '');
          _showDialogSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 8),
            ),
            copyText: errorMessage,
          );
          return;
        } finally {
          _aiSuggestClient = null;
          client.close();
          _stopAiSuggestTicker();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _aiSuggestRunning = false);
      }
    }
  }

  void _startAiSuggestTicker({required String model}) {
    _aiSuggestStopwatch
      ..reset()
      ..start();
    setState(() {
      _aiSuggestRunning = true;
      _aiSuggestElapsedSeconds = 0;
      _aiCurrentModel = model;
    });
    _aiSuggestTicker = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) {
        if (!mounted) return;
        setState(() {
          _aiSuggestElapsedSeconds =
              _aiSuggestStopwatch.elapsedMilliseconds / 1000;
        });
      },
    );
  }

  void _stopAiSuggestTicker() {
    _aiSuggestTicker?.cancel();
    _aiSuggestTicker = null;
    _aiSuggestStopwatch.stop();
  }
}
