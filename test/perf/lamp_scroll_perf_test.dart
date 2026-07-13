// ΠΡΟΣΩΡΙΝΟ μετρητικό τεστ απόδοσης κύλισης της λίστας αποτελεσμάτων Λάμπας.
// Δεν κάνει assertions ποιότητας — τυπώνει χρόνους build/frame για σύγκριση Α/Β.
import 'package:call_logger/features/lamp/widgets/lamp_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('el');
  });

  testWidgets('ΜΕΤΡΗΣΗ: κύλιση 40 καρτών σε desktop πλάτος (1400px)', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final vmWatch = Stopwatch()..start();
    final viewModels = List.generate(
      40,
      (i) => EquipmentViewModel.fromRow(_row(i)),
    );
    vmWatch.stop();

    final buildWatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('el'),
        supportedLocales: const [Locale('el', 'GR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: Scaffold(
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: viewModels.length,
            itemBuilder: (context, index) => EquipmentResultCard(
              viewModel: viewModels[index],
            ),
          ),
        ),
      ),
    );
    buildWatch.stop();

    final frameMicros = <int>[];
    for (var i = 0; i < 60; i++) {
      final w = Stopwatch()..start();
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -240),
        warnIfMissed: false,
      );
      await tester.pump();
      w.stop();
      frameMicros.add(w.elapsedMicroseconds);
    }
    frameMicros.sort();
    String ms(int micros) => (micros / 1000).toStringAsFixed(1);
    final p50 = frameMicros[frameMicros.length ~/ 2];
    final p90 = frameMicros[(frameMicros.length * 0.9).floor()];
    final max = frameMicros.last;
    final avg =
        frameMicros.reduce((a, b) => a + b) ~/ frameMicros.length;

    debugPrint('==== ΜΕΤΡΗΣΗ ΚΥΛΙΣΗΣ ΛΑΜΠΑΣ ====');
    debugPrint('fromRow x40:      ${ms(vmWatch.elapsedMicroseconds)} ms');
    debugPrint('Αρχικό build:     ${ms(buildWatch.elapsedMicroseconds)} ms');
    debugPrint('Καρέ κύλισης (60 δείγματα, drag 240px):');
    debugPrint('  μέσος: ${ms(avg)} ms · p50: ${ms(p50)} ms · '
        'p90: ${ms(p90)} ms · max: ${ms(max)} ms');
    debugPrint('  (στόχος για 60fps: < 16.7 ms ανά καρέ σε release — '
        'εδώ debug VM, μετράμε ΣΥΓΚΡΙΤΙΚΑ)');
    debugPrint('=================================');
  });
}

Map<String, Object?> _row(int i) => <String, Object?>{
      'code': 1000 + i,
      'description': 'Εκτυπωτής Laser A3 · μηχάνημα ορόφου $i',
      'serial_no': 'SN12345678$i',
      'asset_no': 'INV-2021-00$i',
      'state_name': 'Ενεργός',
      'set_master': 1000,
      'receiving_date': '2021-03-15',
      'end_of_guarantee_date': '2024-03-15',
      'cost': '850',
      'equipment_comments': 'Δικτυακός εκτυπωτής γραφείου με αναφορά $i',
      'model_id': 42,
      'model_name': 'LaserJet Pro MFP M42$i',
      'category_name': 'Εκτυπωτές',
      'subcategory_name': 'Laser',
      'manufacturer_name': 'HP',
      'model_attributes': 'A3, 40ppm, Δικτυακός',
      'consumables': 'Toner HP 59A',
      'contract_id': 15,
      'contract_name': 'ΣΥΜ-2021-$i',
      'contract_category_name': 'Εκτυπωτικός Εξοπλισμός',
      'supplier_name': 'Office Solutions A.E.',
      'contract_award': 'ΑΝΑΘ-2021-12',
      'contract_declaration': 'ΔΙΑΚ-2020-45',
      'maintenance_contract': 'Συντήρηση',
      'contract_comments': 'Ετήσια υποστήριξη',
      'owner_id': 7,
      'last_name': 'Παπαδόπουλος',
      'first_name': 'Γιώργος',
      'owner_email': 'g.papadopoulos$i@org.gr',
      'owner_phones': '210 1234567; 690000000$i',
      'office_id': 3,
      'office_name': 'Τμήμα Πληροφορικής',
      'organization_name': 'Δ/νση Τεχνολογιών',
      'office_email': 'info@dept.gr',
      'office_phones': '210 9876543',
      'building': 'Κτίριο Α',
      'level': 2,
      'ip_address': '10.10.212.$i',
      'network_name': 'PC10$i',
      'network_node': '257',
      'network_vlan': 'Μαιευτική',
      'network_mac': '0025228750A$i',
      'network_description': 'VERO PC P4 2.6GHz',
    };
