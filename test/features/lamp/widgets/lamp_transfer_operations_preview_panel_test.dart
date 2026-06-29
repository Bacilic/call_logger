import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/features/lamp/services/lamp_transfer_preview.dart';
import 'package:call_logger/features/lamp/widgets/lamp_transfer_operations_preview_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLampTransferPreview', () {
    test('νέα εγγραφή κάτοχου — created για τηλέφωνα χωρίς προορισμό', () {
      final preview = buildLampTransferPreview(
        draft: _ownerDraft(),
        currentFormValues: const {
          'first_name': 'Μαρία',
          'last_name': 'Παπαδοπούλου',
          'phones': '2101111111',
          'equipment_codes': '',
          'department_name': 'Φαρμακείο',
          'location': '',
          'notes': '',
        },
        selectedCandidateId: null,
        departmentExistsCheck: (_) => false,
      );

      expect(preview.result.mainEntityMode, TransferEntityMode.newEntry);
      final phones = preview.fields.firstWhere((f) => f.formKey == 'phones');
      expect(phones.action, TransferFieldAction.created);
    });

    test('buildTransferActionSummary συνοψίζει ενέργειες', () {
      final preview = buildLampTransferPreview(
        draft: _departmentDraft(),
        currentFormValues: const {
          'name': 'Φαρμακείο',
          'building': 'Κτίριο Α',
          'level': '2',
          'notes': '',
        },
        selectedCandidateId: null,
        departmentExistsCheck: (_) => false,
      );

      final summary = buildTransferActionSummary(preview);
      expect(summary, contains('Έτοιμο για αποθήκευση'));
      expect(summary, contains('νέα'));
    });
  });

  group('LampTransferMigrationForm', () {
    testWidgets(
      'Scrollbar δένει ρητό ScrollController με τη λίστα πεδίων (Windows-safe)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 560,
                child: _ReactiveFormHarness(
                  draft: _departmentDraft(),
                  selectedCandidateId: null,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
        final listView = tester.widget<ListView>(find.byType(ListView));

        expect(scrollbar.controller, isNotNull);
        expect(listView.controller, isNotNull);
        expect(scrollbar.controller, same(listView.controller));
        expect(listView.primary, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reactive chip — κείμενο σε κενό πεδίο γίνεται Νέο', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(460, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 460,
              height: 900,
              child: _ReactiveFormHarness(
                draft: _departmentDraft(),
                selectedCandidateId: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Κενές σημειώσεις/τηλέφωνα σε νέα εγγραφή → Αμετάβλητο· τα υπόλοιπα → Νέο.
      expect(find.text('Αμετάβλητο'), findsNWidgets(2));
      expect(find.text('Νέο'), findsNWidgets(3));

      await tester.enterText(
        find.byKey(const Key('transfer_field_notes')),
        'Σημείωση μεταφοράς',
      );
      await tester.pump();

      expect(find.text('Αμετάβλητο'), findsOneWidget);
      expect(find.text('Νέο'), findsNWidgets(4));
    });

    test('isTransferFieldReadOnly — κενό unchanged πεδίο παραμένει επεξεργάσιμο', () {
      expect(
        isTransferFieldReadOnly(
          TransferFieldAction.unchanged,
          currentValue: '',
          destinationValue: null,
        ),
        isFalse,
      );
      expect(
        isTransferFieldReadOnly(
          TransferFieldAction.unchanged,
          currentValue: 'Φαρμακείο',
          destinationValue: 'Φαρμακείο',
        ),
        isTrue,
      );
      expect(
        isTransferFieldReadOnly(TransferFieldAction.linked),
        isTrue,
      );
    });

    test('reactive αξιολόγηση — τροποποίηση σημειώσεων σε υπάρχον τμήμα', () {
      final draft = _departmentDraft(
        candidateFormValues: {
          5: const {
            'name': 'Φαρμακείο',
            'building': 'Κτίριο Α',
            'level': '2',
            'notes': 'Παλιά σημείωση',
          },
        },
      );
      final preview = buildLampTransferPreview(
        draft: draft,
        currentFormValues: const {
          'name': 'Φαρμακείο',
          'building': 'Κτίριο Α',
          'level': '2',
          'notes': 'Νέα σημείωση',
        },
        selectedCandidateId: 5,
        departmentExistsCheck: (_) => true,
      );

      final notes = preview.fields.firstWhere((f) => f.formKey == 'notes');
      expect(notes.action, TransferFieldAction.updated);
    });

    testWidgets('κλειδώνει πεδίο με action linked ή unchanged', (tester) async {
      final draft = _departmentDraft(
        candidateFormValues: {
          5: const {
            'name': 'Φαρμακείο',
            'building': 'Κτίριο Α',
            'level': '2',
            'notes': 'Παλιά σημείωση',
          },
        },
        candidates: const [
          LampMigrationCandidate(
            id: 5,
            label: 'Φαρμακείο',
            confidence: 100,
            isExact: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 460,
              height: 620,
              child: _ReactiveFormHarness(
                draft: draft,
                selectedCandidateId: 5,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('transfer_field_name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.readOnly, isTrue);
    });

    testWidgets('εμφανίζει σύνοψη και κουμπί αποθήκευσης', (tester) async {
      var saved = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 460,
              height: 620,
              child: _ReactiveFormHarness(
                draft: _departmentDraft(),
                selectedCandidateId: null,
                onSave: () => saved = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Έτοιμο για αποθήκευση'), findsOneWidget);
      expect(find.text('Δημιουργία'), findsOneWidget);

      await tester.tap(find.text('Δημιουργία'));
      await tester.pump();
      expect(saved, isTrue);
    });
  });
}

class _ReactiveFormHarness extends StatefulWidget {
  const _ReactiveFormHarness({
    required this.draft,
    required this.selectedCandidateId,
    this.onSave,
  });

  final LampMigrationDraft draft;
  final int? selectedCandidateId;
  final VoidCallback? onSave;

  @override
  State<_ReactiveFormHarness> createState() => _ReactiveFormHarnessState();
}

class _ReactiveFormHarnessState extends State<_ReactiveFormHarness> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = <String, TextEditingController>{};
    final initialValues = widget.selectedCandidateId == null
        ? widget.draft.newRecordFormValues
        : widget.draft.candidateFormValues[widget.selectedCandidateId!] ??
              widget.draft.newRecordFormValues;
    for (final spec in lampTransferFormFieldSpecs(widget.draft.target)) {
      final controller = TextEditingController(
        text: initialValues[spec.formKey] ?? '',
      );
      controller.addListener(_rebuild);
      _controllers[spec.formKey] = controller;
    }
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_rebuild);
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> _currentValues() {
    return {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = buildLampTransferPreview(
      draft: widget.draft,
      currentFormValues: _currentValues(),
      selectedCandidateId: widget.selectedCandidateId,
      departmentExistsCheck: (_) => false,
    );

    return LampTransferMigrationForm(
      target: widget.draft.target,
      preview: preview,
      controllers: _controllers,
      saving: false,
      saveLabel: 'Δημιουργία',
      onCancel: () {},
      onSave: widget.onSave ?? () {},
    );
  }
}

LampMigrationDraft _ownerDraft({
  Map<int, Map<String, String>>? candidateFormValues,
  List<LampMigrationCandidate> candidates = const [],
}) {
  return LampMigrationDraft(
    target: LampTransferTarget.owner,
    oldValues: const {'Παλιός κάτοχος': 'Παπαδοπούλου Μαρία'},
    formValues: const {
      'first_name': 'Μαρία',
      'last_name': 'Παπαδοπούλου',
      'phones': '2101111111',
      'equipment_codes': '',
      'department_name': 'Φαρμακείο',
      'location': '',
      'notes': '',
    },
    newRecordFormValues: const {
      'first_name': 'Μαρία',
      'last_name': 'Παπαδοπούλου',
      'phones': '2101111111',
      'equipment_codes': '',
      'department_name': 'Φαρμακείο',
      'location': '',
      'notes': '',
    },
    candidateFormValues: candidateFormValues ?? const {},
    candidates: candidates,
    selectedCandidateId: null,
    updatesExistingRecord: false,
  );
}

/// Φύλλο «2» ώστε το level του draft να μην ενεργοποιεί προειδοποίηση
/// (το banner σπρώχνει το τελευταίο πεδίο εκτός viewport του ListView).
BuildingMapFloor _departmentDraftFloorSheet() {
  return BuildingMapFloor(
    id: 99,
    sortOrder: 0,
    label: '2',
    imagePath: 'test/floor.png',
    rotationDegrees: 0,
  );
}

LampMigrationDraft _departmentDraft({
  Map<int, Map<String, String>>? candidateFormValues,
  List<LampMigrationCandidate> candidates = const [],
  List<BuildingMapFloor>? buildingMapFloors,
}) {
  return LampMigrationDraft(
    target: LampTransferTarget.department,
    oldValues: const {'Παλιό τμήμα': 'Φαρμακείο'},
    formValues: const {
      'name': 'Φαρμακείο',
      'building': 'Κτίριο Α',
      'level': '2',
      'phones': '',
      'notes': '',
    },
    newRecordFormValues: const {
      'name': 'Φαρμακείο',
      'building': 'Κτίριο Α',
      'level': '2',
      'phones': '',
      'notes': '',
    },
    candidateFormValues: candidateFormValues ?? const {},
    candidates: candidates,
    selectedCandidateId: null,
    updatesExistingRecord: false,
    buildingMapFloors: buildingMapFloors ?? [_departmentDraftFloorSheet()],
  );
}
