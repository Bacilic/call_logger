import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteToolFormController — lock πριν εξαγωγή', () {
    test('νέο εργαλείο: isDirty false στην αρχή, true μετά από αλλαγή πεδίου',
        () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      expect(c.isDirty, isFalse);
      c.nameC.text = 'Tool A';
      expect(c.isDirty, isTrue);
    });

    test('createHasRequiredFields: true μόνο όταν name και path μη κενά', () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      expect(c.createHasRequiredFields, isFalse);
      c.nameC.text = 'Tool';
      expect(c.createHasRequiredFields, isFalse);
      c.pathC.text = r'C:\tool.exe';
      expect(c.createHasRequiredFields, isTrue);
    });

    test('canSubmitSave: νέο vs επεξεργασία', () {
      final create = RemoteToolFormController();
      addTearDown(create.dispose);

      expect(create.canSubmitSave, isFalse);
      create.nameC.text = 'New';
      create.pathC.text = r'C:\new.exe';
      expect(create.canSubmitSave, isTrue);
      create.saving = true;
      expect(create.canSubmitSave, isFalse);

      final existing = RemoteTool(
        id: 5,
        name: 'Existing',
        role: ToolRole.generic,
        executablePath: r'C:\old.exe',
        sortOrder: 1,
        isActive: true,
      );
      final edit = RemoteToolFormController(initialTool: existing);
      addTearDown(edit.dispose);

      expect(edit.canSubmitSave, isFalse);
      edit.nameC.text = 'Existing edited';
      expect(edit.canSubmitSave, isTrue);
    });

    test('toRemoteTool: πεδία, trim, φιλτράρισμα κενών ορισμάτων, null optional',
        () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      c.nameC.text = '  My Tool  ';
      c.pathC.text = '  C:\\app.exe  ';
      c.iconC.text = '   ';
      c.testIpC.text = '  ';
      c.role = ToolRole.rdp;
      c.isActive = false;
      c.addArg();
      c.argRows[0].valueC.text = '  -host=x  ';
      c.argRows[0].descC.text = ' desc ';
      c.addArg();
      c.argRows[1].valueC.text = '   ';
      c.argRows[1].descC.text = 'ignored';

      final tool = c.toRemoteTool(id: 42);

      expect(tool.id, 42);
      expect(tool.name, 'My Tool');
      expect(tool.executablePath, r'C:\app.exe');
      expect(tool.role, ToolRole.rdp);
      expect(tool.sortOrder, 0);
      expect(tool.isActive, isFalse);
      expect(tool.isExclusive, isFalse);
      expect(tool.iconAssetKey, isNull);
      expect(tool.suggestedValuesJson, isNull);
      expect(tool.testTargetIp, isNull);
      expect(tool.arguments, hasLength(1));
      expect(tool.arguments.single.value, '-host=x');
      expect(tool.arguments.single.description, 'desc');
    });

    test('validateName: κενό όνομα και διπλότυπο case-insensitive', () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      expect(c.validateName([]), 'Υποχρεωτικό όνομα εργαλείου.');

      c.nameC.text = 'Alpha';
      final catalog = [
        RemoteTool(
          id: 1,
          name: 'alpha',
          role: ToolRole.generic,
          executablePath: 'a',
          sortOrder: 1,
          isActive: true,
        ),
      ];
      expect(c.validateName(catalog), 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.');

      final edit = RemoteToolFormController(
        initialTool: RemoteTool(
          id: 2,
          name: 'Alpha',
          role: ToolRole.generic,
          executablePath: 'a',
          sortOrder: 1,
          isActive: true,
        ),
      );
      addTearDown(edit.dispose);
      edit.nameC.text = 'Alpha';
      expect(
        edit.validateName([
          RemoteTool(
            id: 2,
            name: 'Alpha',
            role: ToolRole.generic,
            executablePath: 'a',
            sortOrder: 1,
            isActive: true,
          ),
        ]),
        isNull,
      );
    });

    test('toRemoteTool: νέο εργαλείο — suggestedValuesJson null', () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      c.nameC.text = 'Tool';
      c.pathC.text = r'C:\tool.exe';

      expect(c.toRemoteTool(id: 1).suggestedValuesJson, isNull);
    });

    test(
      'toRemoteTool: επεξεργασία — διατήρηση suggestedValuesJson αμετάβλητη',
      () {
        const json = '{"host":["192.168.1.1"]}';
        final existing = RemoteTool(
          id: 7,
          name: 'With Suggestions',
          role: ToolRole.generic,
          executablePath: r'C:\tool.exe',
          sortOrder: 1,
          isActive: true,
          suggestedValuesJson: json,
        );
        final c = RemoteToolFormController(initialTool: existing);
        addTearDown(c.dispose);

        c.nameC.text = 'With Suggestions edited';

        expect(c.toRemoteTool(id: 7).suggestedValuesJson, json);
      },
    );

    test('toRemoteTool: επεξεργασία διατηρεί αρχικό sort_order', () {
      final existing = RemoteTool(
        id: 9,
        name: 'Ordered',
        role: ToolRole.generic,
        executablePath: r'C:\tool.exe',
        sortOrder: 7,
        isActive: true,
      );
      final c = RemoteToolFormController(initialTool: existing);
      addTearDown(c.dispose);

      c.nameC.text = 'Ordered edited';

      expect(c.toRemoteTool(id: 9).sortOrder, 7);
    });

    test(
      'toRemoteTool: isExclusive πάντα false ακόμα κι αν το αρχικό εργαλείο ήταν exclusive',
      () {
        final existing = RemoteTool(
          id: 11,
          name: 'Was Exclusive',
          role: ToolRole.vnc,
          executablePath: r'C:\vnc.exe',
          sortOrder: 3,
          isActive: true,
          isExclusive: true,
        );
        final c = RemoteToolFormController(initialTool: existing);
        addTearDown(c.dispose);

        expect(c.toRemoteTool(id: 11).isExclusive, isFalse);
      },
    );

    test('formStateSignature: αλλάζει με reorder και (απ)ενεργοποίηση ορίσματος',
        () {
      final c = RemoteToolFormController();
      addTearDown(c.dispose);

      c.addArg();
      c.addArg();
      c.argRows[0].valueC.text = 'a';
      c.argRows[1].valueC.text = 'b';
      final sigBefore = c.formStateSignature();

      c.reorderArgs(0, 1);
      expect(c.formStateSignature(), isNot(equals(sigBefore)));

      final sigAfterReorder = c.formStateSignature();
      c.setArgActive(0, false);
      expect(c.formStateSignature(), isNot(equals(sigAfterReorder)));
    });
  });
}
