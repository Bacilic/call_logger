// Ο διάλογος εκκρεμότητας δανείζεται τα πεδία καλούντα της οθόνης Κλήσεων.
// Δανείζεται ΜΟΝΟ τα πεδία: η κατάσταση των Κλήσεων δεν είναι δική του.
//
//   flutter test test/features/tasks/task_form_does_not_touch_calls_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/tasks/models/task_settings_config.dart';
import 'package:call_logger/features/tasks/providers/task_settings_config_provider.dart';
import 'package:call_logger/features/tasks/screens/task_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kOpenDialogButton = 'OPEN_TASK_FORM_DIALOG';

class _TestTaskSettingsConfigNotifier extends TaskSettingsConfigNotifier {
  @override
  Future<TaskSettingsConfig> build() async =>
      TaskSettingsConfig.defaultConfig();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerCallLoggerIsolatedDatabaseHooks();

  group('Ο διάλογος εκκρεμότητας δεν αγγίζει την οθόνη Κλήσεων', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
    });

    testWidgets(
      'επιλογή καλούντα μέσα στη φόρμα εκκρεμότητας δεν επιβεβαιώνει πεδίο '
      'της κλήσης',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        late ProviderContainer root;
        // Το στήσιμο και η επιλογή καλούντα αγγίζουν τη βάση (λεξικό, ευρετήριο
        // καταλόγου): με πλαστό ρολόι οι χρονιστές του sqflite μένουν εκκρεμείς.
        await tester.runAsync(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...callLoggerTestProviderOverrides(),
                enableSpellCheckProvider.overrideWith((ref) async => false),
                spellCheckServiceProvider.overrideWith((ref) async {
                  final svc = LexiconSpellCheckService();
                  await svc.init(lexiconVariants: {});
                  return svc;
                }),
                taskSettingsConfigProvider.overrideWith(
                  () => _TestTaskSettingsConfigNotifier(),
                ),
              ],
              child: MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () => showTaskFormDialog(context),
                        child: const Text(_kOpenDialogButton),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await pumpUntilSettledLong(tester);
          root = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          await root.read(lookupServiceProvider.future);

          await tester.tap(find.text(_kOpenDialogButton));
          await pumpUntilSettledLong(tester);

          // Ο χρήστης διαλέγει καλούντα μέσα στη φόρμα εκκρεμότητας.
          root
              .read(taskSmartEntityProvider.notifier)
              .setCaller(
                UserModel(
                  id: 77,
                  firstName: 'Βαρβάρα',
                  lastName: 'Νακαστσή',
                ),
              );
          await pumpUntilSettledLong(tester);
        });

        expect(
          root.read(callsFieldConfirmationsProvider).caller,
          isFalse,
          reason: greekExpectMsg(
            'Η φόρμα εκκρεμότητας δεν επιβεβαιώνει πεδία της οθόνης Κλήσεων',
          ),
        );
        expect(
          root.read(callsScreenExpandedLatchProvider),
          isFalse,
          reason: greekExpectMsg(
            'Ούτε ανοίγει τη μεγάλη προβολή της οθόνης Κλήσεων',
          ),
        );
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
