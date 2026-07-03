part of 'main_shell.dart';

/// Περιεχόμενο προορισμού πλοήγησης και στήλη κύριου panel.
mixin MainShellDestinationContentMixin on ConsumerState<MainShell> {
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
        return PrimaryScrollController.none(
          child: const TasksScreen(),
        );
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
  Widget _absorbTasksScrollForOuterAppBar(MainNavDestination dest, Widget child) {
    if (dest != MainNavDestination.tasks) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: child,
    );
  }

  Widget _destinationContentColumn(
    MainNavDestination dest, {
    required bool pendingRestartDueToPathChange,
  }) {
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
        if (pendingRestartDueToPathChange)
          Material(
            color: Colors.grey.shade800,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          children: [
                            const TextSpan(
                              text:
                                  'Έγινε αλλαγή διαδρομής βάσης. Παρακαλώ επανεκκινήστε την εφαρμογή για να ισχύσει πλήρως. ',
                            ),
                            TextSpan(
                              text: 'Επανεκκίνηση...',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  exit(0);
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
