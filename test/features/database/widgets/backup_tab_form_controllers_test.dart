// Τα πεδία της καρτέλας αντιγράφων.
//
// Συμβόλαιο: πεδίο που έχει την εστίαση ΔΕΝ ξαναγράφεται ποτέ από τη ρύθμιση
// — αλλιώς η τιμή που πληκτρολογεί ο χρήστης αντικαθίσταται στη μέση.
//
//   flutter test test/features/database/widgets/backup_tab_form_controllers_test.dart

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/widgets/backup_tab_form_controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _settings = DatabaseBackupSettings.defaults().copyWith(
  destinationDirectory: r'D:\backups',
  retentionQuickMaxCopies: 7,
  retentionQuickMaxAgeDays: 30,
  retentionFullMaxCopies: 3,
  changeThreshold: 25,
  minSpacingMinutes: 60,
  maxWaitMinutes: 240,
);

void main() {
  late BackupTabFormControllers fields;

  setUp(() => fields = BackupTabFormControllers());
  tearDown(() => fields.dispose());

  test('ο συγχρονισμός γεμίζει και τα επτά πεδία από τις ρυθμίσεις', () {
    fields.syncFromSettings(_settings);

    expect(fields.destination.text, r'D:\backups');
    expect(fields.maxCopies.text, '7');
    expect(fields.maxAge.text, '30');
    expect(fields.fullCopies.text, '3');
    expect(fields.threshold.text, '25');
    expect(fields.minSpacing.text, '60');
    expect(fields.maxWait.text, '240');
  });

  testWidgets('πεδίο με εστίαση δεν ξαναγράφεται από τη ρύθμιση', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: fields.destination,
            focusNode: fields.destinationFocus,
          ),
        ),
      ),
    );
    fields.destinationFocus.requestFocus();
    await tester.pump();
    fields.destination.text = r'E:\μισογραμμένο';

    fields.syncFromSettings(_settings);

    expect(
      fields.destination.text,
      r'E:\μισογραμμένο',
      reason: 'Ο χρήστης πληκτρολογεί — η ρύθμιση περιμένει',
    );
  });

  test('οι σημαίες αφήνουν απ έξω μόνο τα πεδία που δεν άλλαξαν', () {
    fields.syncFromSettings(
      _settings,
      syncDestination: false,
      syncRetentionMaxCopies: false,
      syncRetentionMaxAgeDays: false,
    );

    expect(fields.destination.text, isEmpty);
    expect(fields.maxCopies.text, isEmpty);
    expect(fields.maxAge.text, isEmpty);
    // Τα υπόλοιπα δεν έχουν σημαία: συγχρονίζονται πάντα.
    expect(fields.threshold.text, '25');
    expect(fields.minSpacing.text, '60');
  });

  group('αποθήκευση αριθμητικού πεδίου', () {
    test('η τιμή που ψαλιδίστηκε φαίνεται στο πεδίο', () async {
      final controller = TextEditingController(text: '5');
      var saved = 0;

      await persistIntField(
        controller: controller,
        save: (v) async => saved = v,
        // Η αποθήκευση επέβαλε ελάχιστο 15 — το πεδίο πρέπει να το δείξει.
        readApplied: () => '15',
        stillMounted: () => true,
      );

      expect(saved, 5);
      expect(controller.text, '15');
      controller.dispose();
    });

    test('κενό πεδίο δεν αποθηκεύεται, αλλά επανέρχεται στην ισχύουσα τιμή', () async {
      final controller = TextEditingController(text: '   ');
      var saveCalls = 0;

      await persistIntField(
        controller: controller,
        save: (_) async => saveCalls++,
        readApplied: () => '7',
        stillMounted: () => true,
      );

      expect(saveCalls, 0, reason: 'Το κενό δεν είναι τιμή');
      expect(controller.text, '7', reason: 'Το πεδίο δεν μένει άδειο');
      controller.dispose();
    });

    test('μη αριθμητικό κείμενο δεν αποθηκεύεται', () async {
      final controller = TextEditingController(text: 'επτά');
      var saveCalls = 0;

      await persistIntField(
        controller: controller,
        save: (_) async => saveCalls++,
        readApplied: () => '7',
        stillMounted: () => true,
      );

      expect(saveCalls, 0);
      expect(controller.text, '7');
      controller.dispose();
    });

    test('οθόνη που έφυγε δεν αγγίζει πια το πεδίο της', () async {
      final controller = TextEditingController(text: '5');

      await persistIntField(
        controller: controller,
        save: (_) async {},
        readApplied: () => '15',
        stillMounted: () => false,
      );

      expect(
        controller.text,
        '5',
        reason: 'Μετά το dispose της οθόνης, καμία εγγραφή στον controller',
      );
      controller.dispose();
    });
  });
}
