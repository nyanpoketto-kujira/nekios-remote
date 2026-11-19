import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_core/nekios_core.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/ui/layar_beranda.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';

/// Bangun Beranda yang sudah terhubung ke display palsu dengan
/// snapshot bel aktif + satu bel terakhir. Mengembalikan klien
/// palsu untuk memeriksa paket yang terkirim.
Future<KlienPalsu> _pumpBeranda(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final klien = KlienPalsu();
  klien.payloadSnapshot = payloadSnapshotContoh()
    ..['belAktif'] = true
    ..['belTerakhir'] = {
      'berkas': 'audio/bel_jam_3.mp3',
      'pada': '2026-11-18T09:05:00',
    };
  final store = RemoteStore(
    klien: klien,
    penyimpanan: PenyimpananDisplay(await SharedPreferences.getInstance()),
    jedaPing: const Duration(minutes: 5),
  );
  addTearDown(store.dispose);
  await tester.runAsync(() async {
    await store.sambungkan(
      const DisplayTersimpan(nama: 'SMKN 1 Ukui', ip: '10.0.2.2'),
    );
    // Balasan ping (ack + snapshot) tiba lewat rantai microtask
    // klien palsu — beri satu putaran jam nyata agar snapshot
    // mendarat sebelum tree dibangun di zona FakeAsync.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  expect(store.snapshot, isNotNull);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: LayarBeranda(store: store))),
  );
  await tester.pump();
  return klien;
}

void main() {
  testWidgets('Kartu Bel: info bel terakhir tampil, saklar mengirim '
      'audio.konfigurasi', (tester) async {
    final klien = await _pumpBeranda(tester);

    expect(find.text('Bel sekolah'), findsOneWidget);
    expect(
      find.text('Bel terakhir: Jam pelajaran ke-3 • 09:05'),
      findsOneWidget,
    );
    final saklar = find.byType(Switch);
    expect(tester.widget<Switch>(saklar).value, isTrue);

    await tester.tap(saklar);
    await tester.pump();
    await tester.pump();
    final konfigurasi = klien.terkirim
        .where((p) => p.type == TipePaket.audioKonfigurasi)
        .toList();
    expect(konfigurasi, hasLength(1));
    expect(konfigurasi.single.payload?['belAktif'], isFalse);
    expect(find.text('Bel sekolah dimatikan.'), findsOneWidget);
  });

  testWidgets('Kartu Bel: tombol Tes Bel mengirim audio.tes', (
    tester,
  ) async {
    final klien = await _pumpBeranda(tester);

    await tester.tap(find.text('Tes Bel'));
    await tester.pump();
    await tester.pump();
    expect(
      klien.terkirim.where((p) => p.type == TipePaket.audioTes),
      hasLength(1),
    );
    expect(find.text('Tes bel diputar di TV.'), findsOneWidget);
  });
}
