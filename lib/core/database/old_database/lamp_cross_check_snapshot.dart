/// Στιγμιότυπο της βάσης «Λάμπα» για τη διασταύρωση με τον Κατάλογο.
///
/// **Μόνο ανάγνωση.** Η Λάμπα είναι παγωμένο μητρώο: η διασταύρωση τη
/// διαβάζει για να δείξει αποκλίσεις, και κάθε διόρθωση γίνεται στην καρτέλα
/// του Καταλόγου. Το αρχείο ανοίγει με δικό του σύνδεσμο `readOnly` και
/// κλείνει αμέσως, ώστε να μην πειράζει τον σύνδεσμο της οθόνης Λάμπας.
///
/// Το σύνολο είναι μικρό (λίγες χιλιάδες γραμμές) και διαβάζεται ολόκληρο σε
/// μνήμη: οι έλεγχοι χρειάζονται τυχαία πρόσβαση σε κάθε γραφείο και
/// ιδιοκτήτη, και ένα ερώτημα ανά εγγραφή θα έκανε τη σάρωση ατέλειωτη.
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/phone_list_parser.dart';

/// Γραφείο της Λάμπας — αυτό αντιστοιχεί στο «τμήμα» του Καταλόγου.
///
/// Το `department_name` της Λάμπας είναι ο ανώτερος φορέας («Οικονομικό»),
/// κάτω από τον οποίο ζουν πολλά γραφεία («Χρηματικού #1», «Χρηματικού #2»).
/// Κρατιέται μόνο ως δεύτερη ευκαιρία ταύτισης.
class LampOfficeRecord {
  const LampOfficeRecord({
    required this.id,
    required this.name,
    required this.departmentName,
    required this.phones,
  });

  final int id;
  final String name;
  final String departmentName;
  final List<String> phones;

  /// Πώς αναφέρεται το γραφείο στα ευρήματα.
  String get displayName => name.isNotEmpty ? name : departmentName;
}

/// Ιδιοκτήτης της Λάμπας — ο «υπάλληλος» του Καταλόγου.
class LampOwnerRecord {
  const LampOwnerRecord({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.officeId,
    required this.phones,
  });

  final int id;
  final String lastName;
  final String firstName;
  final int? officeId;
  final List<String> phones;

  String get fullName => '$lastName $firstName'.trim();
}

/// Μηχάνημα της Λάμπας.
class LampEquipmentRecord {
  const LampEquipmentRecord({
    required this.code,
    required this.ownerId,
    required this.officeId,
    required this.stateName,
    required this.categoryName,
  });

  final int code;
  final int? ownerId;
  final int? officeId;

  /// Κατάσταση («Σε λειτουργία», «Καταστράφηκε»), κενή όταν δεν δηλώθηκε.
  final String stateName;

  /// Κατηγορία του μοντέλου («Υπολογιστής», «Εκτυπωτής»).
  final String categoryName;

  /// Καταστάσεις που σημαίνουν «δεν υπάρχει πια ως μηχάνημα σε χρήση».
  ///
  /// Συγκρίνονται ως ρίζες λέξεων, γιατί η Λάμπα γράφει τις καταστάσεις
  /// ελεύθερα («Προς καταστροφή», «Καταστράφηκε», «Προς Απόσυρση»). Έξω
  /// μένουν επίτηδες οι προσωρινές («Προς επισκευή», «Προς διάθεση»): εκεί
  /// το μηχάνημα γυρίζει, και μια κλήση πάνω του δεν είναι λάθος.
  static const List<String> retiredStateRoots = [
    'ΚΑΤΑΣΤΡ',
    'ΑΠΟΣΥΡ',
    'ΑΠΩΛΕΙΑ',
    'ΕΠΙΣΤΡΑΦΗΚΕ',
    'ΑΝΤΑΛΛΑΚΤΙΚ',
    'ΑΧΡΗΣΤ',
  ];
}

/// Ό,τι χρειάζεται η διασταύρωση από τη Λάμπα, σε μνήμη.
class LampCrossCheckSnapshot {
  const LampCrossCheckSnapshot({
    required this.offices,
    required this.owners,
    required this.equipmentByCode,
    this.lastEquipmentCode,
  });

  const LampCrossCheckSnapshot.empty()
    : offices = const {},
      owners = const {},
      equipmentByCode = const {},
      lastEquipmentCode = null;

  final Map<int, LampOfficeRecord> offices;
  final Map<int, LampOwnerRecord> owners;

  /// Κλειδί: ο κωδικός ως κείμενο, όπως τον γράφει ο Κατάλογος.
  final Map<String, LampEquipmentRecord> equipmentByCode;

  /// Ο μεγαλύτερος κωδικός που πρόλαβε να δει η Λάμπα.
  ///
  /// Είναι το σύνορο του μητρώου: ό,τι πήρε μεγαλύτερο κωδικό καταγράφηκε
  /// αφότου η Λάμπα έπαψε να χρησιμοποιείται, και η απουσία του από εκεί δεν
  /// είναι σφάλμα. `null` μόνο σε άδειο μητρώο.
  final int? lastEquipmentCode;

  bool get isEmpty =>
      offices.isEmpty && owners.isEmpty && equipmentByCode.isEmpty;
}

/// Διαβάζει τη βάση Λάμπας από τη [databasePath], μόνο για ανάγνωση.
///
/// Πετά [FileSystemException] όταν το αρχείο λείπει — ο καλών το μεταφράζει
/// σε μήνυμα οθόνης, γιατί μόνο εκείνος ξέρει τι ζήτησε ο χρήστης.
Future<LampCrossCheckSnapshot> readLampCrossCheckSnapshot(
  String databasePath, {
  DatabaseFactory? factory,
}) async {
  final path = databasePath.trim();
  if (path.isEmpty) {
    throw const FileSystemException('Δεν έχει οριστεί βάση Λάμπας.');
  }
  if (!await File(path).exists()) {
    throw FileSystemException('Δεν βρέθηκε το αρχείο βάσης Λάμπα.', path);
  }

  final db = factory == null
      ? await openDatabase(path, readOnly: true, singleInstance: false)
      : await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );

  try {
    final offices = <int, LampOfficeRecord>{};
    for (final row in await db.query(
      'offices',
      columns: ['office', 'office_name', 'department_name', 'phones'],
    )) {
      final id = row['office'];
      if (id is! int) continue;
      offices[id] = LampOfficeRecord(
        id: id,
        name: _text(row['office_name']),
        departmentName: _text(row['department_name']),
        phones: PhoneListParser.splitPhones(_text(row['phones'])),
      );
    }

    final owners = <int, LampOwnerRecord>{};
    for (final row in await db.query(
      'owners',
      columns: ['owner', 'last_name', 'first_name', 'office', 'phones'],
    )) {
      final id = row['owner'];
      if (id is! int) continue;
      owners[id] = LampOwnerRecord(
        id: id,
        lastName: _text(row['last_name']),
        firstName: _text(row['first_name']),
        officeId: row['office'] is int ? row['office'] as int : null,
        phones: PhoneListParser.splitPhones(_text(row['phones'])),
      );
    }

    final equipment = <String, LampEquipmentRecord>{};
    int? lastCode;
    for (final row in await db.rawQuery('''
      SELECT e.code AS code,
             e.owner AS owner,
             e.office AS office,
             e.state_name AS state_name,
             m.category_name AS category_name
      FROM equipment e
      LEFT JOIN model m ON m.model = e.model
    ''')) {
      final code = row['code'];
      if (code is! int) continue;
      if (lastCode == null || code > lastCode) lastCode = code;
      equipment['$code'] = LampEquipmentRecord(
        code: code,
        ownerId: row['owner'] is int ? row['owner'] as int : null,
        officeId: row['office'] is int ? row['office'] as int : null,
        stateName: _text(row['state_name']),
        categoryName: _text(row['category_name']),
      );
    }

    return LampCrossCheckSnapshot(
      offices: offices,
      owners: owners,
      equipmentByCode: equipment,
      lastEquipmentCode: lastCode,
    );
  } finally {
    await db.close();
  }
}

/// Μόνο ο τελευταίος κωδικός του μητρώου, χωρίς να διαβαστεί τίποτε άλλο.
///
/// Η οθόνη τον χρειάζεται για να πει στον χρήστη πού σταματά ο έλεγχος, και
/// αυτό πρέπει να φαίνεται **πριν** τρέξει η διασταύρωση. Ένα ολόκληρο
/// στιγμιότυπο θα ήταν σπατάλη για μία γραμμή κειμένου.
///
/// Επιστρέφει `null` όταν η βάση λείπει, δεν διαβάζεται ή είναι άδεια: η
/// ετικέτα απλώς δεν εμφανίζεται, και κανένα μήνυμα σφάλματος δεν ενοχλεί
/// τον χρήστη για κάτι τόσο βοηθητικό.
Future<int?> readLampLastEquipmentCode(
  String databasePath, {
  DatabaseFactory? factory,
}) async {
  final path = databasePath.trim();
  if (path.isEmpty || !await File(path).exists()) return null;

  Database? db;
  try {
    db = factory == null
        ? await openDatabase(path, readOnly: true, singleInstance: false)
        : await factory.openDatabase(
            path,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
    final rows = await db.rawQuery('SELECT MAX(code) AS last FROM equipment');
    final value = rows.isEmpty ? null : rows.first['last'];
    return value is int ? value : null;
  } catch (_) {
    return null;
  } finally {
    await db?.close();
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';
