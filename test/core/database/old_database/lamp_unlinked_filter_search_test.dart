// Το φίλτρο «Χωρίς συνδεδεμένο εξοπλισμό» στην αναζήτηση της Λάμπας.
//
// Συμβόλαιο: το φίλτρο δεν κόβει αποτελέσματα — ΟΡΙΖΕΙ τι ψάχνουμε. Με ενεργό
// φίλτρο ο εξοπλισμός κρύβεται, και η αναζήτηση λειτουργεί ακόμη και εντελώς
// κενή («δείξε μου όλα τα γραφεία χωρίς εξοπλισμό»).
//
//   flutter test test/core/database/old_database/lamp_unlinked_filter_search_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_search_filter_selection.dart';
import 'package:call_logger/core/database/old_database/lamp_unlinked_entities.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-unlinked-filter-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Ένας εξοπλισμός στο γραφείο 1· τα γραφεία 2-3 και ο ιδιοκτήτης 9 ασύνδετα.
  Future<void> seed() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('offices', <String, Object?>{
        'office': 1,
        'office_name': 'Αξονικός',
      });
      await db.insert('offices', <String, Object?>{
        'office': 2,
        'office_name': 'Διευθυντής Αιματολογικού',
      });
      await db.insert('offices', <String, Object?>{
        'office': 3,
        'office_name': 'Αποθήκη Υλικού',
      });
      await db.insert('owners', <String, Object?>{
        'owner': 9,
        'last_name': 'Τσουκαλά',
        'first_name': 'Δήμητρα',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 100,
        'description': 'PC Αξονικού',
        'office': 1,
      });
    } finally {
      await db.close();
    }
  }

  /// Δύο ασύνδετοι ιδιοκτήτες — ο ένας με τηλέφωνο — και γραφείο 2 που
  /// στεγάζει ανθρώπους χωρίς να έχει εξοπλισμό.
  Future<void> seedWithContactableOwner() async {
    await seed();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.insert('owners', <String, Object?>{
        'owner': 10,
        'last_name': 'Παπαδοπούλου',
        'first_name': 'Μαρία',
        'phones': '2514',
        'office': 2,
      });
      await db.update(
        'owners',
        <String, Object?>{'office': 2},
        where: 'owner = ?',
        whereArgs: <Object?>[9],
      );
    } finally {
      await db.close();
    }
  }

  /// Εξοπλισμός 300 χωρίς γραφείο, 400 χωρίς ιδιοκτήτη.
  Future<void> seedEquipmentGaps() async {
    await seed();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.insert('equipment', <String, Object?>{
        'code': 300,
        'description': 'Φορητός χωρίς θέση',
        'owner': 9,
      });
      await db.insert('equipment', <String, Object?>{
        'code': 400,
        'description': 'Εκτυπωτής διαδρόμου',
        'office': 1,
      });
    } finally {
      await db.close();
    }
  }

  group('σκέτο φίλτρο, κενή αναζήτηση', () {
    test('επιστρέφει όλες τις ασύνδετες και κρύβει τον εξοπλισμό', () async {
      await seed();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: LampSearchFilterSelection(
        unlinkedKinds: LampUnlinkedEntityKind.values.toSet(),
      ),
      );

      expect(
        result.totalCount,
        0,
        reason: greekExpectMsg(
          'Με ενεργό φίλτρο δεν ψάχνουμε εξοπλισμό — τον ψάχνουμε ρητά αλλού',
        ),
      );
      expect(result.unlinkedTotalCount, 3);
      expect(result.unlinked, hasLength(3));
    });

    test('χωρίς φίλτρο η κενή αναζήτηση παραμένει κενή', () async {
      await seed();

      final result = await repository.globalSearch(dbPath, '', maxDisplay: 10);

      expect(result.isEmpty, isTrue);
      expect(
        result.unlinkedTotalCount,
        0,
        reason: greekExpectMsg(
          'Η σημερινή συμπεριφορά της κενής αναζήτησης δεν αλλάζει — μόνο το '
          'φίλτρο τη μετατρέπει σε έγκυρη είσοδο',
        ),
      );
    });

    test('φίλτρο συγκεκριμένου είδους φέρνει μόνο αυτό', () async {
      await seed();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
        ),
      );

      expect(result.unlinkedTotalCount, 1);
      expect(result.unlinked.single.title, 'Τσουκαλά Δήμητρα');
    });
  });

  test('τα πλήθη ανά είδος αγνοούν την επιλογή ειδών', () async {
    await seed();

    final result = await repository.globalSearch(
      dbPath,
      '',
      maxDisplay: 10,
      filters: const LampSearchFilterSelection(
        unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
      ),
    );

    expect(
      result.unlinkedCountsByKind[LampUnlinkedEntityKind.office],
      2,
      reason: greekExpectMsg(
        'Αν τα πλήθη μετρούσαν μετά την επιλογή, τα ανεπίλεκτα είδη θα '
        'έδειχναν μηδέν στο μενού και δεν θα μπορούσαν να επιλεγούν',
      ),
    );
    expect(result.unlinkedCountsByKind[LampUnlinkedEntityKind.owner], 1);
  });

  test('φίλτρο + κείμενο = τομή', () async {
    await seed();

    final result = await repository.globalSearch(
      dbPath,
      'αιματολογικου',
      maxDisplay: 10,
      filters: LampSearchFilterSelection(
        unlinkedKinds: LampUnlinkedEntityKind.values.toSet(),
      ),
    );

    expect(result.unlinkedTotalCount, 1);
    expect(result.unlinked.single.title, 'Διευθυντής Αιματολογικού');
  });

  test('το όριο εμφάνισης κόβει και τα ασύνδετα, με σωστό σύνολο', () async {
    await seed();

    final result = await repository.globalSearch(
      dbPath,
      '',
      maxDisplay: 2,
      filters: LampSearchFilterSelection(
        unlinkedKinds: LampUnlinkedEntityKind.values.toSet(),
      ),
    );

    expect(result.unlinked, hasLength(2));
    expect(
      result.unlinkedTotalCount,
      3,
      reason: greekExpectMsg(
        'Με 202 ιδιοκτήτες στην πραγματική βάση, χωρίς όριο θα χτίζαμε '
        '202 κάρτες μονομιάς',
      ),
    );
  });

  test('searchByFields: φίλτρο χωρίς πεδία φέρνει όλες τις ασύνδετες', () async {
    await seed();

    final result = await repository.searchByFields(
      dbPath,
      const OldEquipmentSearchFilters(),
      maxDisplay: 10,
      filters: LampSearchFilterSelection(
        unlinkedKinds: LampUnlinkedEntityKind.values.toSet(),
      ),
    );

    expect(result.totalCount, 0);
    expect(result.unlinkedTotalCount, 3);
  });

  test('συνολικά πλήθη για το μενού χωρίς αναζήτηση', () async {
    await seed();

    final counts = await repository.countFilterCandidates(dbPath);

    expect(counts.byKind[LampUnlinkedEntityKind.office], 2);
    expect(counts.byKind[LampUnlinkedEntityKind.owner], 1);
    expect(counts.byKind[LampUnlinkedEntityKind.model], isNull);
  });

  group('κενές εγγραφές', () {
    test('ιδιοκτήτης χωρίς τηλέφωνο και email είναι κενή εγγραφή', () async {
      await seed();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
        ),
      );

      expect(result.unlinked.single.isEmptyRecord, isTrue);
    });

    test('«μόνο οι κενές» περιορίζει το αποτέλεσμα', () async {
      await seedWithContactableOwner();

      final all = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
        ),
      );
      final onlyEmpty = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
          onlyEmptyUnlinked: true,
        ),
      );

      expect(all.unlinkedTotalCount, 2);
      expect(
        onlyEmpty.unlinkedTotalCount,
        1,
        reason: greekExpectMsg(
          'Ο ιδιοκτήτης με τηλέφωνο είναι πιθανότατα υπαρκτός άνθρωπος — δεν '
          'ανήκει στη λίστα των υποψήφιων καταλοίπων',
        ),
      );
      expect(onlyEmpty.unlinked.single.title, 'Τσουκαλά Δήμητρα');
    });

    test('γραφείο με ανθρώπους μέσα ΔΕΝ είναι κενό', () async {
      await seedWithContactableOwner();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{
            LampUnlinkedEntityKind.office,
          },
        ),
      );

      final withPeople = result.unlinked.firstWhere((e) => e.id == 2);
      expect(
        withPeople.isEmptyRecord,
        isFalse,
        reason: greekExpectMsg(
          'Γραφείο χωρίς εξοπλισμό αλλά με ανθρώπους είναι ζωντανό',
        ),
      );
    });
  });

  group('κενά εξοπλισμού', () {
    test('«χωρίς γραφείο» φέρνει μόνο τον εξοπλισμό που του λείπει', () async {
      await seedEquipmentGaps();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          equipmentGaps: <LampEquipmentGapKind>{
            LampEquipmentGapKind.withoutOffice,
          },
        ),
      );

      expect(result.totalCount, 1);
      expect(result.rows.single['code'], 300);
    });

    test('πολλαπλά κενά ενώνονται με «ή»', () async {
      await seedEquipmentGaps();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          equipmentGaps: <LampEquipmentGapKind>{
            LampEquipmentGapKind.withoutOffice,
            LampEquipmentGapKind.withoutOwner,
          },
        ),
      );

      // 1 χωρίς γραφείο (300) + 2 χωρίς ιδιοκτήτη (100, 400) = 3 μοναδικά.
      expect(
        result.totalCount,
        3,
        reason: greekExpectMsg(
          'Το χρήσιμο ερώτημα είναι «χωρίς γραφείο Ή χωρίς ιδιοκτήτη» — η '
          'τομή τους θα ήταν σπάνια και άχρηστη',
        ),
      );
    });

    test('κενά εξοπλισμού μαζί με ασύνδετες: φαίνονται και τα δύο', () async {
      await seedEquipmentGaps();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          unlinkedKinds: <LampUnlinkedEntityKind>{
            LampUnlinkedEntityKind.office,
          },
          equipmentGaps: <LampEquipmentGapKind>{
            LampEquipmentGapKind.withoutOffice,
          },
        ),
      );

      expect(
        result.totalCount,
        greaterThan(0),
        reason: greekExpectMsg(
          'Όταν ζητούνται και τα δύο, ο εξοπλισμός δεν κρύβεται',
        ),
      );
      expect(result.unlinkedTotalCount, greaterThan(0));
    });

    // Σενάριο από πραγματικό στιγμιότυπο 08/08: ο χρήστης τσεκάρει ΜΟΝΟ
    // «Χωρίς ιδιοκτήτη» και η οθόνη απαντά «67 εξοπλισμοί ΚΑΙ 360 οντότητες
    // χωρίς εξοπλισμό» — τις 360 δεν τις ζήτησε κανείς.
    test('σκέτο φίλτρο κενών ΔΕΝ σέρνει μαζί τις ασύνδετες', () async {
      await seedEquipmentGaps();

      final result = await repository.globalSearch(
        dbPath,
        '',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          equipmentGaps: <LampEquipmentGapKind>{
            LampEquipmentGapKind.withoutOwner,
          },
        ),
      );

      expect(result.totalCount, greaterThan(0));
      expect(
        result.unlinkedTotalCount,
        0,
        reason: greekExpectMsg(
          'Χωρίς κείμενο και χωρίς επιλογή ειδών, καμία ασύνδετη δεν έχει '
          'ζητηθεί — το «όλες περνούν» ισχύει μόνο όταν υπάρχει κείμενο να '
          'τις φέρει',
        ),
      );
    });

    test('με κείμενο, οι ασύνδετες συνεχίζουν να συνοδεύουν', () async {
      await seedEquipmentGaps();

      final result = await repository.globalSearch(
        dbPath,
        'αιματολογικου',
        maxDisplay: 10,
        filters: const LampSearchFilterSelection(
          equipmentGaps: <LampEquipmentGapKind>{
            LampEquipmentGapKind.withoutOwner,
          },
        ),
      );

      expect(
        result.unlinkedTotalCount,
        1,
        reason: greekExpectMsg(
          'Όταν ψάχνεις κείμενο, οι ασύνδετες που ταιριάζουν παραμένουν '
          'χρήσιμο εύρημα — αυτό δεν αλλάζει',
        ),
      );
    });

    test('τα πλήθη κενών μετρώνται για το μενού', () async {
      await seedEquipmentGaps();

      final counts = await repository.countFilterCandidates(dbPath);

      expect(counts.equipmentGaps[LampEquipmentGapKind.withoutOffice], 1);
      expect(counts.equipmentGaps[LampEquipmentGapKind.withoutOwner], 2);
    });
  });
}
