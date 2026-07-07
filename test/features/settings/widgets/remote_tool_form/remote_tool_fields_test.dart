import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_basic_fields.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_behavior_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({required int id, required String name}) => RemoteTool(
      id: id,
      name: name,
      role: ToolRole.generic,
      executablePath: 'x.exe',
      sortOrder: id,
      isActive: true,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Εξαγμένα παρουσιαστικά πεδία φόρμας εργαλείου', () {
    testWidgets('NameAutocompleteField: * σε δημιουργία και σφάλμα σε διπλότυπο',
        (tester) async {
      final controller = TextEditingController(text: 'Foo');
      final focus = FocusNode();
      final formKey = GlobalKey<FormState>();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        _host(
          Form(
            key: formKey,
            child: NameAutocompleteField(
              controller: controller,
              focusNode: focus,
              suggestions: const [],
              nonDeleted: [_tool(id: 1, name: 'Foo')],
              excludeId: null,
              isCreate: true,
            ),
          ),
        ),
      );

      expect(find.text('Όνομα εργαλείου *'), findsOneWidget);
      formKey.currentState!.validate();
      await tester.pump();
      expect(find.text('Υπάρχει ήδη εργαλείο με αυτό το όνομα.'), findsOneWidget);
    });

    testWidgets('ExecutablePathField: μήνυμα όταν η διαδρομή δεν υπάρχει',
        (tester) async {
      final controller =
          TextEditingController(text: r'Z:\__does_not_exist__\tool.exe');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          ExecutablePathField(
            controller: controller,
            onPick: () {},
            enabled: true,
            isCreate: false,
          ),
        ),
      );

      expect(find.text('Το αρχείο δεν βρέθηκε στη διαδρομή.'), findsOneWidget);
    });

    testWidgets('RoleDropdown: εμφανίζει ετικέτα ρόλου και τρέχουσα επιλογή',
        (tester) async {
      await tester.pumpWidget(
        _host(
          RoleDropdown(value: ToolRole.rdp, onChanged: (_) {}),
        ),
      );

      expect(find.text('Ρόλος'), findsOneWidget);
      expect(find.text('RDP Hostname/IP'), findsOneWidget);
    });
  });
}
