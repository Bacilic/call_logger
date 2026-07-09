import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_data_issue_type_labels.dart';
import 'package:call_logger/core/database/old_database/lamp_network_sheet_importer.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('lampNetworkHostnameCode — εξαγωγή κωδικού από hostname', () {
    test('hostnames τύπου εξοπλισμού δίνουν το αριθμητικό μέρος', () {
      expect(lampNetworkHostnameCode('PC3846'), 3846);
      expect(lampNetworkHostnameCode('pr1802'), 1802);
      expect(lampNetworkHostnameCode('PR0018'), 18);
      expect(lampNetworkHostnameCode('HP03'), 3);
      expect(lampNetworkHostnameCode('LAPTOP12'), 12);
      expect(lampNetworkHostnameCode('SW2678'), 2678);
      expect(lampNetworkHostnameCode('PRINT7'), 7);
    });

    test('ονόματα χρήστη / περιγραφικά / κενά δεν δίνουν κωδικό', () {
      expect(lampNetworkHostnameCode('user29'), isNull);
      expect(lampNetworkHostnameCode('iuser71'), isNull);
      expect(lampNetworkHostnameCode('LOGISTIRIO'), isNull);
      expect(lampNetworkHostnameCode(''), isNull);
      expect(lampNetworkHostnameCode('PC'), isNull);
      expect(lampNetworkHostnameCode('PC12A'), isNull);
    });
  });

  group('lampNetworkHeaderIndexes — κεφαλίδες φύλλου network', () {
    test('αναγνωρίζει τις ελληνικές κεφαλίδες του CSV', () {
      final indexes = lampNetworkHeaderIndexes(<String?>[
        'Κωδικός',
        'IP',
        'Εξοπλισμός',
        'ΦυσικήΔιεύθυνσηMAC',
        'VLAN',
        'Hostname',
        'ΟμάδαΕργασίας',
        'Internet',
        'Σχόλια',
      ]);
      expect(indexes['positionCode'], 0);
      expect(indexes['ip'], 1);
      expect(indexes['equipmentText'], 2);
      expect(indexes['mac'], 3);
      expect(indexes['vlan'], 4);
      expect(indexes['hostname'], 5);
      expect(indexes['workgroup'], 6);
      expect(indexes['internet'], 7);
      expect(indexes['comments'], 8);
    });

    test('αναγνωρίζει τις αγγλικές κεφαλίδες του φύλλου network', () {
      final indexes = lampNetworkHeaderIndexes(<String?>[
        'node_code',
        'ip',
        'equipment_code',
        'equipment_description',
        'mac',
        'vlan',
        'hostname',
        'workgroup',
        'internet',
        'comments',
      ]);
      expect(indexes['positionCode'], 0);
      expect(indexes['ip'], 1);
      expect(indexes['equipmentCode'], 2);
      expect(indexes['equipmentText'], 3);
      expect(indexes['mac'], 4);
      expect(indexes['vlan'], 5);
      expect(indexes['hostname'], 6);
      expect(indexes['workgroup'], 7);
      expect(indexes['internet'], 8);
      expect(indexes['comments'], 9);
    });
  });

  group('lampDataIssueTypeDisplayLabel — ελληνικές ετικέτες δικτύου', () {
    test('όλα τα είδη δικτύου έχουν ελληνική περιγραφή', () {
      const types = <String>[
        kLampNetworkIssueNoHostname,
        kLampNetworkIssueCodeNotFound,
        kLampNetworkIssueDuplicateHostname,
        kLampNetworkIssueHostnameUnmatched,
        kLampNetworkIssueIpInComments,
        kLampNetworkIssueModelMismatch,
        'network_sheet_invalid',
      ];
      for (final type in types) {
        final label = lampDataIssueTypeDisplayLabel(type);
        expect(label, isNot(type), reason: 'Λείπει ετικέτα για $type');
        expect(label, startsWith('Δίκτυο'));
      }
    });
  });

  group('lampNetworkModelsAgree — ενισχυτής μοντέλου', () {
    test('αντέχει σε χαμένα κενά της πηγής', () {
      expect(
        lampNetworkModelsAgree(
          'TURBOXFlexworkMi3414',
          'TURBO X Flexwork Mi 3414',
        ),
        isTrue,
      );
    });

    test('κενές τιμές είναι ελλιπή στοιχεία, όχι ασυμφωνία', () {
      expect(lampNetworkModelsAgree('', 'Cisco SG350X-24'), isTrue);
      expect(lampNetworkModelsAgree('DELL', ''), isTrue);
    });

    test('πραγματικά διαφορετικά μοντέλα δίνουν ασυμφωνία', () {
      expect(
        lampNetworkModelsAgree('ΕΝΣΥΡΜΑΤΟ ΠΟΝΤΙΚΙ HP X900', 'Cisco SG350X-24'),
        isFalse,
      );
    });
  });

  group('planLampNetworkEnrichment — πλάνο εμπλουτισμού', () {
    const dell = LampNetworkEquipmentInfo(
      description: 'Υπολογιστής DELL Optiplex 380',
      modelText: '64',
    );

    test('hostname εξοπλισμού με υπαρκτό code → εγγραφή IP και ονόματος', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '5',
            ip: '10.0.0.5',
            equipmentText: 'DELL Optiplex 380',
            mac: '70B5E869B696',
            vlan: 'Λογιστήριο',
            hostname: 'PC3846',
            comments: 'Ασύρματο',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{3846: dell},
      );
      expect(plan.issues, isEmpty);
      final update = plan.updates.single;
      expect(update.code, 3846);
      expect(update.ip, '10.0.0.5');
      expect(update.networkName, 'PC3846');
      expect(update.networkSource, contains('hostname «PC3846»'));
      expect(update.networkSource, isNot(contains('ΑΣΥΜΦΩΝΙΑ')));
      expect(update.node, '5');
      expect(update.vlan, 'Λογιστήριο');
      expect(update.mac, '70B5E869B696');
      expect(update.description, 'DELL Optiplex 380');
      expect(update.comments, 'Ασύρματο');
    });

    test('γραμμή χωρίς IP γράφει μόνο όνομα δικτύου με σχετική σημείωση', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(positionCode: '5', hostname: 'PC3846'),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{3846: dell},
      );
      final update = plan.updates.single;
      expect(update.ip, isNull);
      expect(update.networkName, 'PC3846');
      expect(update.networkSource, contains('χωρίς IP στην πηγή'));
    });

    test('ανύπαρκτος κωδικός → ουρά network_code_not_found, καμία εγγραφή', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(positionCode: '9', ip: '10.0.0.9', hostname: 'HP03'),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{3846: dell},
      );
      expect(plan.updates, isEmpty);
      final issue = plan.issues.single;
      expect(issue.issueType, kLampNetworkIssueCodeNotFound);
      expect(issue.message, contains('HP03'));
    });

    test('ασυμφωνία μοντέλου → εγγραφή ΚΑΙ επισήμανση προς επιθεώρηση', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '7',
            ip: '10.0.0.7',
            equipmentText: 'ΕΝΣΥΡΜΑΤΟ ΠΟΝΤΙΚΙ HP X900',
            hostname: 'SW2678',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{
          2678: LampNetworkEquipmentInfo(description: 'Cisco SG350X-24'),
        },
      );
      final update = plan.updates.single;
      expect(update.ip, '10.0.0.7');
      expect(update.networkSource, contains('ΑΣΥΜΦΩΝΙΑ ΜΟΝΤΕΛΟΥ'));
      final issue = plan.issues.single;
      expect(issue.issueType, kLampNetworkIssueModelMismatch);
      expect(issue.rowNumber, 2678);
    });

    test('διπλό όνομα χρήστη → μόνο ουρά, καμία αυτόματη εγγραφή', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(positionCode: '1', ip: '10.0.0.1', hostname: 'user1'),
          LampNetworkRow(positionCode: '2', ip: '10.0.0.2', hostname: 'user1'),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{3846: dell},
      );
      expect(plan.updates, isEmpty);
      expect(plan.issues, hasLength(2));
      for (final issue in plan.issues) {
        expect(issue.issueType, kLampNetworkIssueDuplicateHostname);
        expect(issue.message, contains('2 φορές'));
      }
    });

    test(
      'διπλό hostname εξοπλισμού στον ίδιο κωδικό → μία εγγραφή, κρατά την IP',
      () {
        final plan = planLampNetworkEnrichment(
          rows: const <LampNetworkRow>[
            LampNetworkRow(positionCode: '1', hostname: 'PC3846'),
            LampNetworkRow(
              positionCode: '2',
              ip: '10.10.226.12',
              hostname: 'pc3846',
            ),
          ],
          equipmentByCode: const <int, LampNetworkEquipmentInfo>{3846: dell},
        );
        expect(plan.issues, isEmpty);
        final update = plan.updates.single;
        expect(update.code, 3846);
        expect(update.ip, '10.10.226.12');
      },
    );

    test('όνομα χρήστη με υποψηφίους από αναζήτηση κειμένου → στην ουρά', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '3',
            ip: '10.0.0.3',
            hostname: 'iuser71',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{
          190: LampNetworkEquipmentInfo(
            description: 'Σταθερός υπολογιστής',
            comments: 'ΑΝΑΒΑΘΜΙΣΗ 9/1/2014 - ΠΡΩΗΝ ΕΝΩΣΗΣ ΓΙΑΤΡΩΝ IUSER71',
          ),
        },
      );
      expect(plan.updates, isEmpty);
      final issue = plan.issues.single;
      expect(issue.issueType, kLampNetworkIssueHostnameUnmatched);
      expect(issue.message, contains('Πιθανοί υποψήφιοι'));
      expect(issue.message, contains('190'));
    });

    test('γραμμή χωρίς hostname → ουρά network_no_hostname', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(positionCode: '44', ip: '10.0.0.44'),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{},
      );
      expect(plan.updates, isEmpty);
      final issue = plan.issues.single;
      expect(issue.issueType, kLampNetworkIssueNoHostname);
      expect(issue.rowNumber, 44);
    });

    test('κενή κύρια IP με IP μέσα στα σχόλια → network_ip_in_comments', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '16',
            hostname: 'duser2019',
            comments: '10.168.252.206 | Μάσκα:255.255.255.0',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{},
      );
      expect(plan.updates, isEmpty);
      expect(plan.issues.single.issueType, kLampNetworkIssueIpInComments);
    });

    test('ρητός equipment_code χωρίς hostname → εγγραφή IP (μόνο)', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '16',
            ip: '10.0.0.16',
            equipmentCode: '2774',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{
          2774: LampNetworkEquipmentInfo(description: 'Οθόνη Philips'),
        },
      );
      expect(plan.issues, isEmpty);
      final update = plan.updates.single;
      expect(update.code, 2774);
      expect(update.ip, '10.0.0.16');
      expect(update.networkName, isNull);
      expect(update.networkSource, contains('ρητή αντιστοίχιση'));
    });

    test('ρητός equipment_code προηγείται της ευρετικής hostname', () {
      // Το «user1» θα πήγαινε στην ουρά ως διπλότυπο· ο ρητός κωδικός
      // (χειροκίνητη επιβεβαίωση) πρέπει να γράψει κανονικά.
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '2',
            ip: '10.0.0.2',
            equipmentCode: '301',
            hostname: 'user1',
          ),
          LampNetworkRow(positionCode: '8', ip: '10.0.0.8', hostname: 'user1'),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{
          301: LampNetworkEquipmentInfo(description: 'Η/Υ γραμματείας'),
        },
      );
      final update = plan.updates.single;
      expect(update.code, 301);
      expect(update.ip, '10.0.0.2');
      expect(update.networkName, 'user1');
      expect(update.networkSource, contains('ρητή αντιστοίχιση'));
      expect(update.networkSource, contains('hostname «user1»'));
      // Η δεύτερη γραμμή user1 (χωρίς κωδικό) παραμένει στην ουρά.
      expect(plan.issues.single.issueType, kLampNetworkIssueDuplicateHostname);
    });

    test('ρητός equipment_code σε ανύπαρκτο κωδικό → ουρά, καμία εγγραφή', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '3',
            ip: '10.0.0.3',
            equipmentCode: '9999',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{},
      );
      expect(plan.updates, isEmpty);
      final issue = plan.issues.single;
      expect(issue.issueType, kLampNetworkIssueCodeNotFound);
      expect(issue.message, contains('equipment_code'));
      expect(issue.message, contains('9999'));
    });

    test('ρητός κωδικός δεν περνά από ενισχυτή μοντέλου', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[
          LampNetworkRow(
            positionCode: '4',
            ip: '10.0.0.4',
            equipmentCode: '2678',
            equipmentText: 'ΕΝΣΥΡΜΑΤΟ ΠΟΝΤΙΚΙ HP X900',
            hostname: 'duser2019',
          ),
        ],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{
          2678: LampNetworkEquipmentInfo(description: 'Cisco SG350X-24'),
        },
      );
      expect(plan.issues, isEmpty);
      expect(plan.updates.single.networkSource, isNot(contains('ΑΣΥΜΦΩΝΙΑ')));
    });

    test('εντελώς κενή γραμμή παραλείπεται σιωπηλά', () {
      final plan = planLampNetworkEnrichment(
        rows: const <LampNetworkRow>[LampNetworkRow()],
        equipmentByCode: const <int, LampNetworkEquipmentInfo>{},
      );
      expect(plan.updates, isEmpty);
      expect(plan.issues, isEmpty);
    });
  });

  group('OldExcelImporter — εισαγωγή Excel με φύλλο network', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lamp-network-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'το φύλλο network εμπλουτίζει τον εξοπλισμό και τροφοδοτεί την ουρά',
      () async {
        final excel = Excel.createExcel();
        void appendTexts(String sheet, List<String> values) {
          excel[sheet].appendRow(
            values.map<CellValue?>(TextCellValue.new).toList(),
          );
        }

        appendTexts('offices', <String>['office', 'office_name']);
        appendTexts('owners', <String>['owner', 'last_name']);
        appendTexts('model', <String>['model', 'model_name']);
        appendTexts('contracts', <String>['contract', 'contract_name']);
        appendTexts('equipment', <String>['code', 'description']);
        appendTexts('equipment', <String>[
          '3846',
          'Υπολογιστής DELL Optiplex 380',
        ]);
        appendTexts('equipment', <String>['1802', 'EPSON WORKFORCE AL-M320DN']);
        appendTexts('equipment', <String>['555', 'Οθόνη Samsung']);
        appendTexts('network', <String>[
          'node_code',
          'ip',
          'equipment_code',
          'equipment_description',
          'mac',
          'vlan',
          'hostname',
          'workgroup',
          'internet',
          'comments',
        ]);
        appendTexts('network', <String>[
          '1',
          '10.0.0.5',
          '',
          'DELL Optiplex 380',
          '',
          '',
          'PC3846',
          'wg',
          'ΝΑΙ',
          '',
        ]);
        appendTexts('network', <String>[
          '2',
          '10.0.0.6',
          '',
          'Lexmark MS421',
          '',
          '',
          'PR1802',
          '',
          'ΝΑΙ',
          '',
        ]);
        appendTexts('network', <String>[
          '3',
          '10.0.0.7',
          '',
          '',
          '',
          '',
          'user7',
          '',
          '',
          '',
        ]);
        // Χειροκίνητα επιλυμένη γραμμή: ρητός κωδικός, χωρίς hostname.
        appendTexts('network', <String>[
          '4',
          '10.0.0.8',
          '555',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);

        final xlsxPath = p.join(tempDir.path, 'lamp.xlsx');
        File(xlsxPath).writeAsBytesSync(excel.encode()!);
        final dbPath = p.join(tempDir.path, 'lamp.db');

        final result = await OldExcelImporter().importExcel(
          excelPath: xlsxPath,
          databasePath: dbPath,
        );
        expect(result.importedRows['equipment'], 3);
        expect(result.importedRows['network'], 3);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final match = await db.query(
            'equipment',
            where: 'code = ?',
            whereArgs: <Object?>[3846],
          );
          expect(match.single['ip_address'], '10.0.0.5');
          expect(match.single['network_name'], 'PC3846');
          expect(
            match.single['network_source'],
            isNot(contains('ΑΣΥΜΦΩΝΙΑ')),
          );

          final mismatch = await db.query(
            'equipment',
            where: 'code = ?',
            whereArgs: <Object?>[1802],
          );
          expect(mismatch.single['ip_address'], '10.0.0.6');
          expect(
            mismatch.single['network_source'].toString(),
            contains('ΑΣΥΜΦΩΝΙΑ ΜΟΝΤΕΛΟΥ'),
          );

          final mismatchIssues = await db.query(
            'data_issues',
            where: 'issue_type = ?',
            whereArgs: <Object?>[kLampNetworkIssueModelMismatch],
          );
          expect(mismatchIssues, hasLength(1));

          final unmatchedIssues = await db.query(
            'data_issues',
            where: 'issue_type = ?',
            whereArgs: <Object?>[kLampNetworkIssueHostnameUnmatched],
          );
          expect(unmatchedIssues, hasLength(1));
          expect(
            unmatchedIssues.single['raw_value'].toString(),
            contains('user7'),
          );

          final manual = await db.query(
            'equipment',
            where: 'code = ?',
            whereArgs: <Object?>[555],
          );
          expect(manual.single['ip_address'], '10.0.0.8');
          expect(manual.single['network_name'], isNull);
          expect(
            manual.single['network_source'].toString(),
            contains('ρητή αντιστοίχιση'),
          );
        } finally {
          await db.close();
        }
      },
    );

    test('χωρίς φύλλο network η εισαγωγή δεν επηρεάζεται', () async {
      final excel = Excel.createExcel();
      void appendTexts(String sheet, List<String> values) {
        excel[sheet].appendRow(
          values.map<CellValue?>(TextCellValue.new).toList(),
        );
      }

      appendTexts('offices', <String>['office', 'office_name']);
      appendTexts('owners', <String>['owner', 'last_name']);
      appendTexts('model', <String>['model', 'model_name']);
      appendTexts('contracts', <String>['contract', 'contract_name']);
      appendTexts('equipment', <String>['code', 'description']);
      appendTexts('equipment', <String>['10', 'Οθόνη LG']);

      final xlsxPath = p.join(tempDir.path, 'lamp.xlsx');
      File(xlsxPath).writeAsBytesSync(excel.encode()!);
      final dbPath = p.join(tempDir.path, 'lamp.db');

      final result = await OldExcelImporter().importExcel(
        excelPath: xlsxPath,
        databasePath: dbPath,
      );
      expect(result.importedRows['equipment'], 1);
      expect(result.importedRows.containsKey('network'), isFalse);

      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final row = await db.query(
          'equipment',
          where: 'code = ?',
          whereArgs: <Object?>[10],
        );
        expect(row.single['ip_address'], isNull);
        final networkIssues = await db.query(
          'data_issues',
          where: "issue_type LIKE 'network_%'",
        );
        expect(networkIssues, isEmpty);
      } finally {
        await db.close();
      }
    });
  });
}
