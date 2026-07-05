part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportAiMixin on LansweeperReportDialogStateHost {
  void _prefillForm(
    ReportCallItem primary,
    List<ReportCallItem> selected,
  ) {
    final signature = LansweeperReportItemMapper.selectedKeysSignature(selected);
    if (_lastPrefilledKey == signature) return;
    _lastPrefilledKey = signature;
    final category = (primary.call.category ?? '').trim();
    final id = primary.call.id;
    _titleController.text = LansweeperAiPresenter.prefillTitle(
      category: category,
      id: id,
    );
    _notesController.text =
        LansweeperReportItemMapper.combinedSelectedNotes(selected);
    _solutionController.text = '';
  }

  String _buildAiPromptForSelected(List<ReportCallItem> selected) {
    final service = ref.read(aiTicketSuggestionServiceProvider);
    return service.buildPrompt(_aiPromptInputs(selected));
  }

  AiTicketSuggestionRequest _aiPromptInputs(List<ReportCallItem> selected) {
    return LansweeperAiPresenter.buildRequest(
      selected: selected,
      titleText: _titleController.text,
      notesText: _notesController.text,
      solutionText: _solutionController.text,
    );
  }

  Future<void> _showAiPromptPreview(List<ReportCallItem> selected) async {
    if (selected.isEmpty || _aiSuggestRunning || _isAiCooldownActive) return;
    final prompt = _buildAiPromptForSelected(selected);
    await showLansweeperAiPromptPreviewDialog(
      context,
      promptText: prompt,
    );
  }

  bool get _isAiCooldownActive => LansweeperAiPresenter.isCooldownActive(
        _aiCooldownUntil,
        DateTime.now(),
      );

  int? get _aiCooldownRemainingSeconds =>
      LansweeperAiPresenter.cooldownRemainingSeconds(
        _aiCooldownUntil,
        DateTime.now(),
      );

  void _cancelAiAutoResubmit() {
    _aiAutoResubmitArmed = false;
    _stopAiCooldownTicker(clearState: true);
    if (mounted) setState(() {});
  }

  void _stopAiCooldownTicker({bool clearState = false}) {
    _aiCooldownTicker?.cancel();
    _aiCooldownTicker = null;
    if (clearState) {
      _aiCooldownUntil = null;
      _aiCooldownModel = null;
    }
  }

  void _startAiCooldownTicker({
    required DateTime until,
    required String model,
    required List<ReportCallItem> selected,
  }) {
    _stopAiCooldownTicker();
    _aiCooldownUntil = until;
    _aiCooldownModel = model;
    _aiLastSuggestSelection = selected;
    _aiAutoResubmitArmed = ref.read(geminiAutoResubmitEnabledProvider);

    void tick() {
      if (!mounted) return;
      if (!_isAiCooldownActive) {
        _stopAiCooldownTicker(clearState: true);
        final shouldResubmit =
            _aiAutoResubmitArmed && _aiLastSuggestSelection != null;
        _aiAutoResubmitArmed = false;
        setState(() {});
        if (shouldResubmit && mounted) {
          unawaited(_suggestWithAi(_aiLastSuggestSelection!));
        }
        return;
      }
      setState(() {});
    }

    tick();
    _aiCooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _suggestWithAi(List<ReportCallItem> selected) async {
    if (_aiSuggestRunning || selected.isEmpty || _isAiCooldownActive) return;

    final service = ref.read(aiTicketSuggestionServiceProvider);
    final configError = service.validateConfiguration();
    if (configError != null) {
      if (!mounted) return;
      showDialogSnackBar(
        SnackBar(content: Text(configError)),
      );
      return;
    }

    final request = _aiPromptInputs(selected);
    _aiLastSuggestSelection = selected;
    _aiAutoResubmitArmed = false;

    setState(() => _aiSuggestRunning = true);
    final client = http.Client();
    _aiSuggestClient = client;
    try {
      final result = await service.suggest(
        request,
        client: client,
        onModelAttempt: (model) {
          if (!mounted) return;
          _stopAiSuggestTicker();
          _startAiSuggestTicker(model: model);
        },
        onFallback: (fromModel, toModel, reason) {
          if (!mounted) return;
          showDialogSnackBar(
            SnackBar(
              content: Text(
                LansweeperAiPresenter.fallbackMessage(
                  fromModel: fromModel,
                  toModel: toModel,
                  reason: reason,
                ),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        },
      );

      if (!mounted) return;
      _aiAutoResubmitArmed = false;
      setState(() {
        _titleController.text = result.title;
        _notesController.text = result.description;
        _solutionController.text = result.solution;
      });
    } on AiSuggestionException catch (e) {
      if (!mounted) return;
      _aiAutoResubmitArmed = false;

      if (e.scope == AiSuggestionFailureScope.infrastructure) {
        showDialogSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
          ),
          copyText: e.message,
        );
        return;
      }

      showDialogSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 8),
        ),
        copyText: e.message,
      );

      if (e.retryAvailableAt != null) {
        _startAiCooldownTicker(
          until: e.retryAvailableAt!,
          model: e.waitingModel ?? _aiCurrentModel ?? '',
          selected: selected,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _aiAutoResubmitArmed = false;
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      showDialogSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 8),
        ),
        copyText: errorMessage,
      );
    } finally {
      _aiSuggestClient = null;
      client.close();
      _stopAiSuggestTicker();
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
