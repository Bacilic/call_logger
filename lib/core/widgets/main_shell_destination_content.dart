part of 'main_shell.dart';

/// Περιεχόμενο προορισμού πλοήγησης και στήλη κύριου panel.
mixin MainShellDestinationContentMixin on ConsumerState<MainShell> {
  /// Η λωρίδα παλιάς/κενής βάσης έκλεισε σε αυτή τη συνεδρία.
  bool _databaseNoticeDismissedThisSession = false;
  bool _acknowledgedNoticeLoaded = false;
  String? _acknowledgedNoticeIdentity;
  late DatabaseStateNotice _databaseStateNotice;

  void _initDatabaseStateNotice() {
    _databaseStateNotice = _evaluateCurrentDatabaseNotice();
    unawaited(_loadAcknowledgedDatabaseNoticeIdentity());
  }

  void _syncDatabaseStateNotice(MainShell oldWidget) {
    if (oldWidget.databaseProfile != widget.databaseProfile ||
        oldWidget.databaseResult.path != widget.databaseResult.path) {
      final next = _evaluateCurrentDatabaseNotice();
      if (next.identity != _databaseStateNotice.identity) {
        _databaseNoticeDismissedThisSession = false;
      }
      _databaseStateNotice = next;
    }
  }

  DatabaseStateNotice _evaluateCurrentDatabaseNotice() {
    final path = widget.databaseResult.path?.trim() ?? '';
    var modifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
    if (path.isNotEmpty) {
      try {
        modifiedAt = File(path).lastModifiedSync();
      } catch (_) {}
    }
    return evaluateDatabaseStateNotice(
      profile: widget.databaseProfile,
      dbPath: path,
      fileModifiedAt: modifiedAt,
      now: DateTime.now(),
    );
  }

  Future<void> _loadAcknowledgedDatabaseNoticeIdentity() async {
    final value = await SettingsService()
        .getAcknowledgedDatabaseNoticeIdentity();
    if (!mounted) return;
    setState(() {
      _acknowledgedNoticeIdentity = value;
      _acknowledgedNoticeLoaded = true;
    });
  }

  Future<void> _dismissDatabaseStateNotice() async {
    final identity = _databaseStateNotice.identity;
    setState(() {
      _databaseNoticeDismissedThisSession = true;
      _acknowledgedNoticeIdentity = identity;
    });
    await SettingsService().setAcknowledgedDatabaseNoticeIdentity(identity);
  }

  bool get _showDatabaseStateNotice {
    if (!_acknowledgedNoticeLoaded) return false;
    if (_databaseStateNotice.kind == DatabaseNoticeKind.none) return false;
    if (_databaseNoticeDismissedThisSession) return false;
    return _acknowledgedNoticeIdentity != _databaseStateNotice.identity;
  }

  Future<void> _openDatabaseSettingsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DatabaseSettingsPanel(
                onDatabaseLifecycleChanged:
                    widget.onDatabaseReopened ?? () async {},
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _contentForDestination(MainNavDestination dest) {
    switch (dest) {
      case MainNavDestination.calls:
        return const CallsScreen();
      case MainNavDestination.tasks:
        return PrimaryScrollController.none(child: const TasksScreen());
      case MainNavDestination.directory:
        return const DirectoryScreen();
      case MainNavDestination.history:
        return const HistoryScreen();
      case MainNavDestination.database:
        return DatabaseBrowserScreen(
          databaseResult: widget.databaseResult,
          onOpenDatabaseSettings: _openDatabaseSettingsDialog,
          onDatabaseReopened: widget.onDatabaseReopened,
        );
      case MainNavDestination.dictionary:
        return DictionaryManagerScreen(databaseResult: widget.databaseResult);
      case MainNavDestination.lamp:
        return const LampScreen();
      case MainNavDestination.debugScenarios:
        return const ErrorScenariosScreen();
    }
  }

  /// Απορροφά scroll notifications από εκκρεμότητες ώστε το εξωτερικό AppBar
  /// να μην ενεργοποιεί Material 3 scrolled-under tint.
  Widget _absorbTasksScrollForOuterAppBar(
    MainNavDestination dest,
    Widget child,
  ) {
    if (dest != MainNavDestination.tasks) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: child,
    );
  }

  Widget _destinationContentColumn(MainNavDestination dest) {
    final switchSuccessMessage = ref.watch(databaseSwitchSuccessNoticeProvider);
    final topBanner = topDatabaseBanner(
      showStateNotice: _showDatabaseStateNotice,
      hasSwitchSuccess: switchSuccessMessage != null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isLocalDevMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.amber,
            child: Text(
              'ΛΕΙΤΟΥΡΓΙΑ ΑΝΑΠΤΥΞΗΣ - Τοπική Βάση Δεδομένων',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (topBanner == TopDatabaseBanner.warning)
          Material(
            color: Colors.amber.shade200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _databaseStateNotice.message,
                      key: const ValueKey('database_state_notice_banner'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('database_state_notice_dismiss'),
                    tooltip: 'Κλείσιμο',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.black87,
                    ),
                    onPressed: () {
                      unawaited(_dismissDatabaseStateNotice());
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        if (topBanner == TopDatabaseBanner.success)
          Material(
            color: Colors.green.shade200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switchSuccessMessage!,
                      key: const ValueKey('database_switch_success_banner'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('database_switch_success_dismiss'),
                    tooltip: 'Κλείσιμο',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.black87,
                    ),
                    onPressed: () {
                      ref
                          .read(databaseSwitchSuccessNoticeProvider.notifier)
                          .clear();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        if (dest == MainNavDestination.database &&
            !widget.databaseResult.isSuccess)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.databaseResult.message ??
                            'Άγνωστο σφάλμα με τη βάση δεδομένων.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                      if (widget.databaseResult.details != null) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: widget.databaseResult.details!,
                          child: Text(
                            widget.databaseResult.details!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.red.shade300,
                                  fontSize: 11,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ρυθμίσεις βάσης δεδομένων',
                  icon: const Icon(Icons.dataset_linked),
                  onPressed: _openDatabaseSettingsDialog,
                ),
              ],
            ),
          ),
        Expanded(child: _contentForDestination(dest)),
      ],
    );
  }
}
