// Η αναίρεση της γρήγορης καταχώρησης σβήνει ό,τι ΓΕΝΝΗΘΗΚΕ — τίποτε άλλο.
//
// Το κρίσιμο σενάριο δεν είναι «σβήνει σωστά», είναι «ΔΕΝ σβήνει το
// Αιματολογικό επειδή η καταχώρηση το ανέφερε». Η διάκριση δημιουργήθηκε /
// υπήρχε είναι όλη η ουσία του πακέτου αναίρεσης.
//
//   flutter test test/features/calls/quick_add_undo_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/quick_add_undo_record.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Το μήνυμα απαριθμεί μόνο ό,τι σβήστηκε', () {
    test('τίποτα', () {
      expect(
        quickAddUndoSummary(QuickAddUndoRecord.empty),
        'Δεν υπήρχε τίποτα να αναιρεθεί.',
      );
    });

    test('μόνο τηλέφωνο', () {
      expect(
        quickAddUndoSummary(const QuickAddUndoRecord(createdPhone: '9999')),
        'Αναιρέθηκε: διαγράφηκε το τηλέφωνο 9999.',
      );
    });

    test('υπάλληλος και τμήμα', () {
      expect(
        quickAddUndoSummary(
          const QuickAddUndoRecord(
            createdUserId: 1,
            createdUserName: 'Μάντω Δημητρακοπούλου',
            createdDepartmentId: 2,
            createdDepartmentName: 'Νέο Τμήμα',
          ),
        ),
        'Αναιρέθηκε: διαγράφηκαν ο υπάλληλος «Μάντω Δημητρακοπούλου» '
        'και το τμήμα «Νέο Τμήμα».',
      );
    });

    test('πακέτο χωρίς δημιουργίες είναι κενό', () {
      expect(QuickAddUndoRecord.empty.isEmpty, isTrue);
      expect(
        const QuickAddUndoRecord(createdDepartmentId: 5).isNotEmpty,
        isTrue,
      );
    });
  });

  group('Η αναίρεση πάνω σε πραγματική βάση', () {
    late Database db;

    registerCallLoggerIsolatedDatabaseHooks();

    setUp(() async {
      await seedIsolatedTestDatabase();
      db = await DatabaseHelper.instance.database;
    });

    Future<int> insertDepartment(String name) {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    Future<int?> deletedFlagOfDepartment(String name) async {
      final rows = await db.query(
        'departments',
        columns: ['is_deleted'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['is_deleted'] as int?;
    }

    Future<int?> deletedFlagOfPhone(String number) async {
      final rows = await db.query(
        'phones',
        columns: ['is_deleted'],
        where: 'number = ?',
        whereArgs: [number],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['is_deleted'] as int?;
    }

    Future<ProviderContainer> containerReady() async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      await container.read(lookupServiceProvider.future);
      return container;
    }

    Future<void> quickAddOrphan(
      ProviderContainer container, {
      required String department,
      required String phone,
    }) async {
      final notifier = container.read(callSmartEntityProvider.notifier);
      notifier.updateDepartmentText(department);
      notifier.checkContent(departmentText: department);
      notifier.updatePhone(phone);
      notifier.checkContent(phoneText: phone);
      await notifier.quickAddOrphanToDepartment(forceSharedOnConflict: true);
    }

    test('ό,τι γεννήθηκε σβήνεται', () async {
      final container = await containerReady();
      addTearDown(container.dispose);

      await quickAddOrphan(container, department: 'Νέο Τμήμα', phone: '9999');

      expect(
        await deletedFlagOfDepartment('Νέο Τμήμα'),
        0,
        reason: 'το τμήμα δημιουργήθηκε',
      );
      expect(await deletedFlagOfPhone('9999'), 0);

      final notifier = container.read(callSmartEntityProvider.notifier);
      expect(notifier.hasQuickAddUndoOffer, isTrue);

      final summary = await notifier.undoLastQuickAdd();

      expect(summary, isNotNull);
      expect(summary, contains('9999'));
      expect(summary, contains('Νέο Τμήμα'));
      expect(await deletedFlagOfDepartment('Νέο Τμήμα'), 1);
      expect(await deletedFlagOfPhone('9999'), 1);
    });

    test('τμήμα που ΥΠΗΡΧΕ δεν σβήνεται ποτέ', () async {
      await insertDepartment('Αιματολογικό');
      final container = await containerReady();
      addTearDown(container.dispose);

      await quickAddOrphan(
        container,
        department: 'Αιματολογικό',
        phone: '8888',
      );

      final notifier = container.read(callSmartEntityProvider.notifier);
      final summary = await notifier.undoLastQuickAdd();

      expect(
        await deletedFlagOfDepartment('Αιματολογικό'),
        0,
        reason: 'η αναίρεση σβήνει ό,τι γέννησε, όχι ό,τι βρήκε',
      );
      expect(
        summary,
        isNot(contains('Αιματολογικό')),
        reason: 'το μήνυμα δεν ανακοινώνει διαγραφή που δεν έγινε',
      );
      expect(await deletedFlagOfPhone('8888'), 1);
    });

    test('η προσφορά σβήνει μόλις χρησιμοποιηθεί', () async {
      final container = await containerReady();
      addTearDown(container.dispose);

      await quickAddOrphan(container, department: 'Μιας Χρήσης', phone: '7777');
      final notifier = container.read(callSmartEntityProvider.notifier);

      await notifier.undoLastQuickAdd();

      expect(notifier.hasQuickAddUndoOffer, isFalse);
      expect(
        await notifier.undoLastQuickAdd(),
        isNull,
        reason: 'δεύτερο πάτημα δεν ξανασβήνει τίποτα',
      );
    });

    test('το κλείσιμο του κύκλου αποσύρει την προσφορά', () async {
      final container = await containerReady();
      addTearDown(container.dispose);

      await quickAddOrphan(container, department: 'Προσωρινό', phone: '6666');
      final notifier = container.read(callSmartEntityProvider.notifier);
      expect(notifier.hasQuickAddUndoOffer, isTrue);

      notifier.settleQuickAddUndoOffer();

      expect(notifier.hasQuickAddUndoOffer, isFalse);
      expect(
        await deletedFlagOfDepartment('Προσωρινό'),
        0,
        reason: 'η απόσυρση δεν αναιρεί — η καταχώρηση μένει',
      );
    });
  });
}
