import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/domain/editor_jadwal.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/layanan/penyimpanan_draf.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/editor_master_data.dart';
import 'package:nekios_remote/ui/layar_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';

Map<String, dynamic> muatFixture() {
  final teks = File('test/fixtures/jadwal-sekolah.json').readAsStringSync();
  return jsonDecode(teks) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteStore store;
  late PenyimpananDrafEditor penyimpananDraf;
  late DokumenEditor editor;

  Future<void> siapkan(WidgetTester tester) async {
    // Permukaan seukuran HP sungguhan supaya daftar & lembar
    // bawah editor tertata seperti di perangkat.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = RemoteStore(
      klien: KlienPalsu(),
      penyimpanan: PenyimpananDisplay(prefs),
      jedaPing: const Duration(minutes: 5),
    );
    penyimpananDraf = PenyimpananDrafEditor(prefs);
    editor = DokumenEditor.dariDokumen(
      muatFixture(),
      labelSumber: 'Fixture uji',
    );
  }

  Future<void> tampilkan(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaNekios(Brightness.light),
        home: LayarEditorJadwal(
          store: store,
          penyimpananDraf: penyimpananDraf,
          editorAwal: editor,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> bersihkan(WidgetTester tester) async {
    await store.putuskan();
    store.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('tahap 1: master data tampil dengan jumlah guru & mapel', (
    tester,
  ) async {
    await siapkan(tester);
    await tampilkan(tester);

    expect(find.text('Guru (36)'), findsOneWidget);
    expect(find.text('Agus Priyono, S.T.'), findsOneWidget);
    // Seksi mapel ada di bawah daftar 36 guru — gulir sampai tampak.
    await tester.scrollUntilVisible(
      find.text('Mapel (15)'),
      300,
      scrollable: find.descendant(
        of: find.byType(MasterDataView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Mapel (15)'), findsOneWidget);

    await bersihkan(tester);
  });

  testWidgets('tahap 2: tab hari berpindah & slot non-pelajaran redup', (
    tester,
  ) async {
    await siapkan(tester);
    await tampilkan(tester);

    await tester.tap(find.text('Plotting'));
    await tester.pumpAndSettle();

    // Senin: slot upacara tampil sebagai non-pelajaran, slot
    // pelajaran pertama 08.00–08.45 terisi IPAS.
    expect(find.text('UPACARA / APEL BERSAMA'), findsOneWidget);
    expect(find.text('08.00 – 08.45'), findsOneWidget);
    expect(find.text('IPAS'), findsWidgets);

    // Pindah ke Selasa: jam pertama berbeda (07.30–08.15).
    await tester.tap(find.text('Selasa'));
    await tester.pumpAndSettle();
    expect(find.text('07.30 – 08.15'), findsWidgets);

    await bersihkan(tester);
  });

  testWidgets('tap slot → bottom sheet assign mengubah entri slot', (
    tester,
  ) async {
    await siapkan(tester);
    await tampilkan(tester);

    await tester.tap(find.text('Plotting'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('08.00 – 08.45'));
    await tester.pumpAndSettle();
    // Bottom sheet assign terbuka.
    expect(find.text('Terapkan'), findsOneWidget);
    expect(find.text('Senin • 08.00 – 08.45'), findsOneWidget);

    // Pilih mapel MTK lalu guru Yulia H (KG 24, pengajar MTK).
    await tester.tap(find.widgetWithText(ChoiceChip, 'MTK'));
    await tester.pump();
    final chipGuru = find.widgetWithText(ChoiceChip, 'Yulia H, S.Pd.');
    await tester.ensureVisible(chipGuru);
    await tester.pump();
    await tester.tap(chipGuru);
    await tester.pump();

    final tombolTerapkan = find.text('Terapkan');
    await tester.ensureVisible(tombolTerapkan);
    await tester.pump();
    await tester.tap(tombolTerapkan);
    await tester.pumpAndSettle();

    // Sheet tertutup dan entri slot berubah di model maupun tampilan.
    expect(find.text('Terapkan'), findsNothing);
    expect(editor.entriAktif(0, 1), const EntriSlot(kodeMapel: 'MTK', kg: 24));
    expect(find.text('MTK'), findsOneWidget);
    expect(find.textContaining('Matematika'), findsOneWidget);

    await bersihkan(tester);
  });
}
