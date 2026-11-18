import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_tes_masjid.dart';

import 'masjid_palsu.dart';

SyncPacket paketFixture(String nama) =>
    SyncPacket.fromJson(File('test/fixtures/$nama').readAsStringSync());

/// Snapshot fixture dengan konfigurasi tanpa shalat Jumat.
SyncPacket snapshotTanpaJumat() {
  final mentah =
      jsonDecode(
            File(
              'test/fixtures/paket_snapshot_masjid.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final payload = mentah['payload'] as Map<String, dynamic>;
  (payload['config'] as Map<String, dynamic>)['hasFridayPrayer'] = false;
  return SyncPacket.fromJson(jsonEncode(mentah));
}

const displayMasjid = DisplayTersimpan(
  nama: 'TV Masjid',
  ip: '192.168.1.30',
  tipe: TipeDisplay.masjid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransportMasjidPalsu transport;
  late MasjidStore store;

  setUp(() {
    transport = TransportMasjidPalsu();
    store = MasjidStore(
      buatTransport: (_) => transport,
      batasBukti: const Duration(seconds: 5),
    );
  });

  tearDown(() => store.dispose());

  Widget bungkus() => MaterialApp(
    theme: temaNekios(Brightness.light),
    home: Scaffold(body: LayarTesMasjid(store: store)),
  );

  /// Sambungkan, beri snapshot (+ status bila diminta), lalu tampil.
  /// Snapshot selalu diberikan agar penunggu snapshot perdana store
  /// tuntas (timer-nya tidak bocor ke teardown test).
  Future<void> tampil(
    WidgetTester tester, {
    SyncPacket? snapshot,
    bool denganStatus = true,
  }) async {
    // Viewport tinggi: seluruh ListView ikut terbangun.
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await store.sambungkan(displayMasjid);
    transport.terima(snapshot ?? paketFixture('paket_snapshot_masjid.json'));
    if (denganStatus) {
      transport.terima(paketFixture('paket_state_update_masjid.json'));
    }
    await tester.pumpWidget(bungkus());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> selesai(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  List<SyncPacket> paketPaksaFase() => transport.terkirim
      .where((p) => p.action == SyncAction.forcePhase)
      .toList();

  bool tombolAktif(WidgetTester tester, String label) {
    final tombol = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    return tombol.onPressed != null;
  }

  testWidgets('kartu status menampilkan fase + shalat + hitung mundur', (
    tester,
  ) async {
    await tampil(tester);
    expect(find.text('Menu Tes — Simulasi Waktu Shalat'), findsOneWidget);
    expect(find.text('Jeda Ikamah'), findsOneWidget);
    expect(find.text('Shalat Dzuhur'), findsOneWidget);
    // Total 900 detik deterministik dari fixture.
    expect(find.text('dari total 15:00'), findsOneWidget);
    // Sisa berjalan lokal di sekitar 754 detik (12:34).
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^12:3\d$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(find.text('Paksa Fase — Hari Biasa'), findsOneWidget);
    expect(find.text('Paksa Fase — Hari Jumat'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('belum ada stateUpdate → kartu jujur belum ada status', (
    tester,
  ) async {
    await tampil(tester, denganStatus: false);
    expect(find.text('Belum ada status fase dari TV.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('terputus → ajakan tampil, tombol fase tidak ada', (
    tester,
  ) async {
    await tester.pumpWidget(bungkus());
    await tester.pump();
    expect(find.text('Belum terhubung ke display'), findsOneWidget);
    expect(find.text('Paksa Fase — Hari Biasa'), findsNothing);
    await selesai(tester);
  });

  testWidgets('fase non-Normal wajib konfirmasi; Batal tidak mengirim', (
    tester,
  ) async {
    await tampil(tester);
    await tester.tap(find.text('ADHAN · Azan Berkumandang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paksa fase Azan?'), findsOneWidget);
    expect(paketPaksaFase(), isEmpty);

    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paksa fase Azan?'), findsNothing);
    expect(paketPaksaFase(), isEmpty);
    await selesai(tester);
  });

  testWidgets('konfirmasi disetujui → forcePhase terkirim + bukti menutup '
      'dengan sukses', (tester) async {
    await tampil(tester);
    await tester.tap(find.text('ADHAN · Azan Berkumandang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Paksa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketPaksaFase(), hasLength(1));
    expect(paketPaksaFase().single.payload, {'phase': 'adhan'});

    transport.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Perintah paksa fase Azan terkirim.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('Normal terkirim seketika TANPA dialog konfirmasi', (
    tester,
  ) async {
    await tampil(tester);
    await tester.tap(find.text('Normal (Standby)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AlertDialog), findsNothing);
    expect(paketPaksaFase(), hasLength(1));
    expect(paketPaksaFase().single.payload, {'phase': 'normal'});

    transport.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('Perintah paksa fase Normal (Standby) terkirim.'),
      findsOneWidget,
    );
    await selesai(tester);
  });

  testWidgets('Khutbah nonaktif + keterangan bila hasFridayPrayer false', (
    tester,
  ) async {
    await tampil(tester, snapshot: snapshotTanpaJumat());
    expect(tombolAktif(tester, 'KHUTBAH · Khutbah Jumat'), isFalse);
    expect(
      find.textContaining('konfigurasi TV tidak memakai shalat Jumat'),
      findsOneWidget,
    );
    // Fase biasa tetap aktif.
    expect(tombolAktif(tester, 'ADHAN · Azan Berkumandang'), isTrue);
    await selesai(tester);
  });

  testWidgets('Khutbah aktif bila hasFridayPrayer true', (tester) async {
    await tampil(tester);
    expect(tombolAktif(tester, 'KHUTBAH · Khutbah Jumat'), isTrue);
    expect(
      find.textContaining('konfigurasi TV tidak memakai shalat Jumat'),
      findsNothing,
    );
    await selesai(tester);
  });

  testWidgets('semua tombol nonaktif selama perintah menunggu bukti', (
    tester,
  ) async {
    await tampil(tester);
    await tester.tap(find.text('Normal (Standby)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isTrue);
    expect(tombolAktif(tester, 'SHALAT · Shalat Berlangsung'), isFalse);
    expect(tombolAktif(tester, 'KHUTBAH · Khutbah Jumat'), isFalse);

    transport.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isFalse);
    expect(tombolAktif(tester, 'SHALAT · Shalat Berlangsung'), isTrue);
    await selesai(tester);
  });
}
