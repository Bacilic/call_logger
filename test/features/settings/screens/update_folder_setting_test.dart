import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/updates/network_folder_classifier.dart';
import 'package:call_logger/core/updates/update_source_config.dart';
import 'package:call_logger/features/settings/widgets/update_folder_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Ο φάκελος ενημερώσεων είναι **κοινός** από τη Φάση 2: τον ορίζει ο
  // διαχειριστής και από εκεί παίρνουν όλοι τις εκδόσεις. Δεν ζει πια στις
  // τοπικές ρυθμίσεις, οπότε ο έλεγχος γίνεται στον πάροχο κοινών ρυθμίσεων —
  // το ίδιο σημείο που χρησιμοποιεί η εφαρμογή μετά το άνοιγμα της βάσης.
  late Map<String, String> sharedStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sharedStore = <String, String>{};
    SettingsService.registerAppSettingsProvider(
      (key) async => sharedStore[key],
      (key, value) async => sharedStore[key] = value,
    );
  });

  NetworkFolderClassifier fixedKind(NetworkFolderKind kind) {
    return _FixedKindClassifier(kind);
  }

  Future<void> pumpField(
    WidgetTester tester, {
    required UpdateSourceConfig config,
    NetworkFolderClassifier? classifier,
    Future<String?> Function()? pickFolder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateFolderSettingField(
            updateSourceConfig: config,
            settingsService: SettingsService(),
            networkFolderClassifier:
                classifier ?? fixedKind(NetworkFolderKind.unknown),
            networkClassifyDebounce: Duration.zero,
            pickFolder: pickFolder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows active path from UpdateSourceConfig', (tester) async {
    const active = r'\\fileserver\updates\call_logger';
    await pumpField(
      tester,
      config: UpdateSourceConfig(getUserUpdateFolderPath: () async => active),
    );

    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('settings_update_folder_field')),
          )
          .controller!
          .text,
      active,
    );
  });

  testWidgets('change is saved to update_folder_path', (tester) async {
    await pumpField(
      tester,
      config: UpdateSourceConfig(
        getUserUpdateFolderPath: () async => null,
        executableDirectoryResolver: () => r'C:\app',
        readUpdateSourceJson: (_) async => null,
      ),
    );

    const next = r'\\share\call_logger_updates';
    await tester.enterText(
      find.byKey(const Key('settings_update_folder_field')),
      next,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(sharedStore['update_folder_path'], next);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey('update_folder_path'),
      isFalse,
      reason: 'Κοινή ρύθμιση δεν γράφεται στις τοπικές ρυθμίσεις.',
    );
  });

  testWidgets('localOnly warning visible only for localOnly', (tester) async {
    await pumpField(
      tester,
      config: UpdateSourceConfig(
        getUserUpdateFolderPath: () async => r'C:\local\updates',
      ),
      classifier: fixedKind(NetworkFolderKind.localOnly),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings_update_folder_local_only_warning')),
      findsOneWidget,
    );
  });

  testWidgets('no warning for networkUnc / unknown', (tester) async {
    await pumpField(
      tester,
      config: UpdateSourceConfig(
        getUserUpdateFolderPath: () async => r'\\server\share',
      ),
      classifier: fixedKind(NetworkFolderKind.networkUnc),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings_update_folder_local_only_warning')),
      findsNothing,
    );

    await pumpField(
      tester,
      config: UpdateSourceConfig(getUserUpdateFolderPath: () async => r'C:\x'),
      classifier: fixedKind(NetworkFolderKind.unknown),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings_update_folder_local_only_warning')),
      findsNothing,
    );
  });
}

class _FixedKindClassifier extends NetworkFolderClassifier {
  _FixedKindClassifier(this.kind)
    : super(
        driveTypeResolver: (_) async => false,
        localSharesProvider: () async => const <String>[],
        isWindows: () => true,
      );

  final NetworkFolderKind kind;

  @override
  Future<NetworkFolderKind> classify(String path) async => kind;
}
