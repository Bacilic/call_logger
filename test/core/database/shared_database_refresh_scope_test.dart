// Τι ξαναδιαβάζεται όταν γράψει ΑΛΛΟ μηχάνημα στην κοινόχρηστη βάση.
//
// Το σκέλος που μετράει εδώ δεν είναι ο φρουρός (ελέγχεται χωριστά) αλλά η
// ΕΜΒΕΛΕΙΑ του: μια ανανέωση που φτάνει μόνο στις Εκκρεμότητες αφήνει το
// Ιστορικό, τα Στατιστικά και την ουρά της Αναφοράς μπαγιάτικα — δηλαδή αφήνει
// άλυτο ακριβώς το καθημερινό πρόβλημα.
//
//   flutter test test/core/database/shared_database_refresh_scope_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/shared_database_refresh.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_report_scope_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Ref? _capturedRef;

final _refCaptureProvider = Provider<int>((ref) {
  _capturedRef = ref;
  return 0;
});

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('refreshSharedDatabaseViews — εμβέλεια', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await CallsRepository(db).insertCall(
        CallModel(
          phoneText: kTestPhoneDigits,
          issue: 'Κλήση για τον έλεγχο εμβέλειας',
          status: 'completed',
        ),
      );
    });

    test('φτάνει στο Ιστορικό, στους μετρητές και στην ουρά της Αναφοράς',
        () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      container.read(_refCaptureProvider);

      container.listen(historyCallsProvider, (_, _) {});
      container.listen(totalCallsCountProvider, (_, _) {});
      container.listen(lansweeperReportCallsProvider, (_, _) {});

      await container.read(historyCallsProvider.future);
      await container.read(totalCallsCountProvider.future);
      await container.read(lansweeperReportCallsProvider.future);

      expect(
        container.read(historyCallsProvider).hasValue,
        isTrue,
        reason: 'προϋπόθεση: οι οθόνες έχουν φορτώσει πριν την ξένη εγγραφή',
      );

      await refreshSharedDatabaseViews(_capturedRef!);

      expect(
        container.read(historyCallsProvider).isLoading,
        isTrue,
        reason: 'το Ιστορικό πρέπει να ξαναρωτά μετά από ξένη εγγραφή',
      );
      expect(
        container.read(totalCallsCountProvider).isLoading,
        isTrue,
        reason: 'οι μετρητές των Στατιστικών το ίδιο',
      );
      expect(
        container.read(lansweeperReportCallsProvider).isLoading,
        isTrue,
        reason:
            'η ουρά της Αναφοράς είναι το πιεστικό: δύο άνθρωποι τη δουλεύουν '
            'ταυτόχρονα κάθε μεσημέρι',
      );
    });

    test('φτάνει και στα τμήματα, που τροφοδοτούν τον χάρτη κτιρίου', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      container.read(_refCaptureProvider);

      container.listen(departmentDirectoryProvider, (_, _) {});
      await container
          .read(departmentDirectoryProvider.notifier)
          .loadDepartments();
      final before = container
          .read(departmentDirectoryProvider)
          .allDepartments
          .length;

      // Το άλλο μηχάνημα τοποθετεί νέο τμήμα στον χάρτη.
      final db = await DatabaseHelper.instance.database;
      await DepartmentRepository(db).getOrCreateDepartmentIdByName(
        'Ακτινολογικό',
      );

      await refreshSharedDatabaseViews(_capturedRef!);

      expect(
        container.read(departmentDirectoryProvider).allDepartments.length,
        greaterThan(before),
        reason:
            'ο χάρτης κρίνει θέσεις ΚΑΙ χρώματα από αυτή τη λίστα· μπαγιάτικη '
            'δίνει σε δύο τμήματα το ίδιο «διακριτό» χρώμα',
      );
    });

    test('η ανανέωση δεν αδειάζει την οθόνη', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      container.read(_refCaptureProvider);

      container.listen(historyCallsProvider, (_, _) {});
      final before = await container.read(historyCallsProvider.future);
      expect(before, isNotEmpty);

      await refreshSharedDatabaseViews(_capturedRef!);

      // Ακύρωση σε provider που ΗΔΗ έχει δεδομένα κρατά την προηγούμενη τιμή
      // ώσπου να έρθει η νέα: η λίστα αντικαθίσταται, δεν αναβοσβήνει.
      expect(
        container.read(historyCallsProvider).value,
        isNotNull,
        reason: 'λίστα που αδειάζει κάθε 12 δευτερόλεπτα είναι χειρότερη από '
            'μπαγιάτικη',
      );
      expect(container.read(historyCallsProvider).value, isNotEmpty);
    });

    // Ο Κατάλογος έλειπε από την ανανέωση: η αλλαγή του συναδέλφου σε
    // υπάλληλο έμενε αόρατη επ' αόριστον, και η καρτέλα άνοιγε με μπαγιάτικη
    // αφετηρία — οπότε ο φρουρός μπλόκαρε τη ΔΙΚΗ μου αποθήκευση, ξανά και
    // ξανά, χωρίς τρόπο να ξεμπλοκάρω.
    test('φτάνει και στον Κατάλογο υπαλλήλων', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      container.read(_refCaptureProvider);

      container.listen(directoryProvider, (_, _) {});
      await container.read(directoryProvider.notifier).loadUsers();
      final before = container.read(directoryProvider).allUsers.length;

      // Το άλλο μηχάνημα προσθέτει υπάλληλο.
      final db = await DatabaseHelper.instance.database;
      await db.insert('users', {
        'first_name': 'Αναστασία',
        'last_name': 'Αναστασιάδη',
      });

      await refreshSharedDatabaseViews(_capturedRef!);

      expect(
        container.read(directoryProvider).allUsers.length,
        before + 1,
        reason:
            'Ο Κατάλογος πρέπει να ξαναδιαβάζεται όπως οι υπόλοιπες οθόνες — '
            'αλλιώς η καρτέλα ανοίγει με αφετηρία που δεν ισχύει πια',
      );
    });
  });
}
