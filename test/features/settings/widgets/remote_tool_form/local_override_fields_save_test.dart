import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/overridable_settings.dart';
import 'package:call_logger/core/services/remote_tool_connect_wait.dart';
import 'package:call_logger/core/services/save_confirmation_summary.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Οι δύο ρυθμίσεις «σε αυτόν τον υπολογιστή» μέσα στη φόρμα εργαλείου.
///
/// Το σφάλμα που φυλάνε: ταξιδεύουν αλλού από τον κοινό ορισμό (στις
/// προτιμήσεις του σταθμού, όχι στη βάση), και γι' αυτό γράφονταν μόνες τους
/// μόλις έφευγε η εστίαση — με το κουμπί «Αποθήκευση» να μένει γκρι. Ο
/// χρήστης έγραφε τιμή και **δεν μάθαινε ποτέ** αν πιάστηκε. Πλέον είναι
/// κανονικά πεδία της φόρμας: ανάβουν το κουμπί, γράφονται μαζί με τα
/// υπόλοιπα, και μπαίνουν στη σύνοψη.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toolId = 7;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  RemoteTool tool({int waitSeconds = 30}) => RemoteTool(
    id: toolId,
    name: 'Απομακρυσμένη',
    role: ToolRole.rdp,
    executablePath: r'C:\shared\mstsc.exe',
    sortOrder: 1,
    isActive: true,
    connectWaitSeconds: waitSeconds,
  );

  Future<RemoteToolFormController> openForm({int waitSeconds = 30}) async {
    final c = RemoteToolFormController(
      initialTool: tool(waitSeconds: waitSeconds),
    );
    addTearDown(c.dispose);
    await c.loadLocalOverrides();
    return c;
  }

  Future<String?> storedPath() => OverridableSettings.overrideOf(
    OverridableSettingKeys.remoteToolExecutablePath.forId(toolId),
  );

  group('Το κουμπί «Αποθήκευση»', () {
    test('ανάβει όταν αλλάζει ΜΟΝΟ ο τοπικός χρόνος', () async {
      final c = await openForm();

      expect(c.canSubmitSave, isFalse);
      c.localWaitC.text = '40';
      expect(
        c.canSubmitSave,
        isTrue,
        reason:
            'Ο χρήστης έγραψε 40 και το κουμπί έμενε γκρι — δεν είχε κανέναν '
            'τρόπο να μάθει αν η τιμή πιάστηκε.',
      );
    });

    test('ανάβει όταν αλλάζει ΜΟΝΟ η τοπική διαδρομή', () async {
      final c = await openForm();

      expect(c.canSubmitSave, isFalse);
      c.localPathC.text = r'D:\local\mstsc.exe';
      c.markLocalPathOverridden();
      expect(c.canSubmitSave, isTrue);
    });

    test('η φόρτωση των τοπικών τιμών ΔΕΝ βρομίζει τη φόρμα', () async {
      await RemoteToolConnectWait.setLocalOverride(toolId, 40);
      await OverridableSettings.setOverride(
        OverridableSettingKeys.remoteToolExecutablePath.forId(toolId),
        r'D:\local\mstsc.exe',
      );

      final c = await openForm();

      expect(c.localWaitC.text, '40');
      expect(c.localPathC.text, r'D:\local\mstsc.exe');
      expect(
        c.isDirty,
        isFalse,
        reason:
            'Οι τιμές έρχονται ασύγχρονα· αν δεν ξαναοριζόταν η αφετηρία, η '
            'άφιξή τους θα φαινόταν ως αλλαγή του χρήστη.',
      );
    });
  });

  group('Η εγγραφή γίνεται με το κουμπί, όχι νωρίτερα', () {
    test('χωρίς αποθήκευση δεν γράφεται τίποτα', () async {
      final c = await openForm();

      c.localWaitC.text = '40';
      c.localPathC.text = r'D:\local\mstsc.exe';
      c.markLocalPathOverridden();

      expect(await RemoteToolConnectWait.localOverrideSeconds(toolId), isNull);
      expect(await storedPath(), isNull);
    });

    test('με την αποθήκευση γράφονται και οι δύο', () async {
      final c = await openForm();

      c.localWaitC.text = '40';
      c.localPathC.text = r'D:\local\mstsc.exe';
      c.markLocalPathOverridden();
      await c.commitLocalOverrides(toolId);

      expect(await RemoteToolConnectWait.localOverrideSeconds(toolId), 40);
      expect(await storedPath(), r'D:\local\mstsc.exe');
    });

    test('μετά την αποθήκευση η φόρμα ησυχάζει', () async {
      final c = await openForm();

      c.localWaitC.text = '40';
      await c.commitLocalOverrides(toolId);

      expect(c.hasLocalOverrideChanges, isFalse);
      expect(c.localOverrideChangeLines(), isEmpty);
    });
  });

  group('Επιστροφή στις κοινές τιμές', () {
    test('άδειασμα του χρόνου αίρει την παράκαμψη', () async {
      await RemoteToolConnectWait.setLocalOverride(toolId, 40);
      final c = await openForm();

      c.useSharedConnectWait();
      expect(c.canSubmitSave, isTrue);
      await c.commitLocalOverrides(toolId);

      expect(await RemoteToolConnectWait.localOverrideSeconds(toolId), isNull);
    });

    test(
      '«χρήση της κοινής διαδρομής» αίρει τη δήλωση, δεν γράφει κενό',
      () async {
        await OverridableSettings.setOverride(
          OverridableSettingKeys.remoteToolExecutablePath.forId(toolId),
          r'D:\local\mstsc.exe',
        );
        final c = await openForm();

        c.useSharedPath();
        await c.commitLocalOverrides(toolId);

        expect(
          await storedPath(),
          isNull,
          reason:
              'Κενή δηλωμένη παράκαμψη σημαίνει «κανένα πρόγραμμα εδώ» — άλλο '
              'πράγμα από «ακολουθώ την κοινή».',
        );
      },
    );

    test('ρητά κενή διαδρομή γράφεται ως κενή, όχι ως άρση', () async {
      final c = await openForm();

      c.markLocalPathOverridden();
      c.localPathC.text = '';
      await c.commitLocalOverrides(toolId);

      expect(await storedPath(), '');
    });
  });

  group('Η σύνοψη αποθήκευσης', () {
    test(
      'αναφέρει την τοπική αλλαγή ακόμη κι αν ο κοινός ορισμός έμεινε ίδιος',
      () async {
        final c = await openForm();
        c.localWaitC.text = '40';

        final message = buildRemoteToolSaveMessage(
          oldTool: tool(),
          newTool: c.toRemoteTool(id: toolId),
          localChanges: c.localOverrideChangeLines(),
        );

        expect(message, contains('αυτόν τον υπολογιστή'));
        expect(message, contains('40'));
        expect(
          message,
          isNot(equals(kSaveConfirmationNoChangesMessage)),
          reason:
              'Αλλαγή που αφορά μόνο το μηχάνημά του δεν επιτρέπεται να '
              'διαβαστεί ως «καμία αλλαγή».',
        );
      },
    );

    test('«χωρίς κλείδωμα» λέγεται με λόγια, όχι με μηδενικό', () async {
      final c = await openForm();
      c.localWaitC.text = '0';

      expect(c.localOverrideChangeLines().single, contains('χωρίς κλείδωμα'));
    });
  });
}
