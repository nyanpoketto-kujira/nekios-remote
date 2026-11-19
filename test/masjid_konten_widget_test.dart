import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nekios_remote/layanan/gambar_banner.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_banner_masjid.dart';
import 'package:nekios_remote/ui/layar_gambar_khusus.dart';
import 'package:nekios_remote/ui/layar_gambar_latar.dart';
import 'package:nekios_remote/ui/layar_kas_masjid.dart';
import 'package:nekios_remote/ui/layar_logo_masjid.dart';
import 'package:nekios_remote/ui/layar_konten_masjid.dart';
import 'package:nekios_remote/ui/layar_teks_berjalan.dart';

import 'masjid_palsu.dart';

SyncPacket paketFixture(String nama) =>
    SyncPacket.fromJson(File('test/fixtures/$nama').readAsStringSync());

/// Snapshot fixture yang payload-nya diubah [ubah] lebih dulu —
/// untuk mensimulasikan bukti susulan TV setelah sebuah mutasi.
SyncPacket snapshotDengan(void Function(Map<String, dynamic> payload) ubah) {
  final mentah =
      jsonDecode(
            File(
              'test/fixtures/paket_snapshot_masjid.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  ubah(mentah['payload'] as Map<String, dynamic>);
  return SyncPacket.fromJson(jsonEncode(mentah));
}

Map<String, dynamic> payloadFixture() =>
    (jsonDecode(
              File(
                'test/fixtures/paket_snapshot_masjid.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)['payload']
        as Map<String, dynamic>;

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

  Widget bungkus(Widget anak) => MaterialApp(
    theme: temaNekios(Brightness.light),
    home: Scaffold(body: anak),
  );

  /// Sambungkan + beri snapshot fixture, lalu tampilkan [anak].
  Future<void> tampil(WidgetTester tester, Widget anak) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await store.sambungkan(displayMasjid);
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pumpWidget(bungkus(anak));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> selesai(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  List<SyncPacket> paketAksi(SyncAction aksi) =>
      transport.terkirim.where((p) => p.action == aksi).toList();

  List<dynamic> daftarPaket(SyncAction aksi, String kunci) =>
      paketAksi(aksi).last.payload[kunci] as List<dynamic>;

  /// Seret pegangan susun-ulang ke bawah sejauh [jarak].
  /// ReorderableDragStartListener memakai recognizer seret
  /// seketika: gestur harus LANGSUNG bergerak setelah pointer
  /// turun — menahan pointer diam ±600ms justru membatalkan
  /// seretan (terverifikasi empiris di Flutter versi ini), dan
  /// onReorderItem baru terpanggil setelah animasi jatuhnya
  /// item selesai (±250ms) begitu pointer dilepas.
  Future<void> seretBaris(
    WidgetTester tester,
    Finder pegangan,
    double jarak,
  ) async {
    final gestur = await tester.startGesture(tester.getCenter(pegangan));
    await tester.pump();
    await gestur.moveBy(Offset(0, jarak * 0.4));
    await tester.pump();
    await gestur.moveBy(Offset(0, jarak * 0.6));
    await tester.pump();
    await gestur.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  // ------------------------------------------------------------------
  // Kerangka Konten
  // ------------------------------------------------------------------

  testWidgets('konten: enam sub-tab, Teks Berjalan tampil pertama', (
    tester,
  ) async {
    await tampil(tester, LayarKontenMasjid(store: store));
    // Finder dibatasi ke TabBar: label seperti 'Kas' juga muncul
    // sebagai chip kategori di editor.
    Finder tabSub(String label) => find.descendant(
      of: find.byType(TabBar),
      matching: find.text(label),
    );
    for (final label in [
      'Teks Berjalan',
      'Banner',
      'Kas',
      'Gambar Khusus',
      'Gambar Latar',
      'Logo',
    ]) {
      expect(tabSub(label), findsOneWidget);
    }
    // Sub-tab pertama langsung berisi editor teks berjalan.
    expect(find.text('Kajian rutin Sabtu'), findsOneWidget);

    // Sub-tab Kas sudah berisi editor sungguhan (A2c).
    await tester.tap(tabSub('Kas'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Infaq Jumat'), findsOneWidget);
    expect(find.text('Saldo Kas'), findsOneWidget);

    // Sub-tab Gambar Khusus sudah berisi editor sungguhan (A2d).
    await tester.tap(tabSub('Gambar Khusus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Renovasi tempat wudhu'), findsOneWidget);

    // Sub-tab Logo sudah berisi editor sungguhan (A2d); fixture
    // membawa logo sehingga tombolnya "Ganti logo".
    await tester.tap(tabSub('Logo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ganti logo'), findsOneWidget);
    expect(find.textContaining('sedang disiapkan'), findsNothing);
    await selesai(tester);
  });

  // ------------------------------------------------------------------
  // Teks Berjalan
  // ------------------------------------------------------------------

  testWidgets('teks berjalan: seed tampil berurutan + nomor + sakelar', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Kajian rutin Sabtu'), findsOneWidget);
    expect(find.text('Saldo kas pekan ini'), findsOneWidget);
    expect(find.text('Kajian'), findsOneWidget);
    expect(find.text('Kas'), findsOneWidget);
    final sakelar = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(sakelar.map((s) => s.value), [true, false]);
    expect(find.text('Nonaktif'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('teks berjalan: snapshot belum tiba → editor menahan diri', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await store.sambungkan(displayMasjid);
    await tester.pumpWidget(bungkus(LayarTeksBerjalan(store: store)));
    await tester.pump();
    expect(find.text('Belum ada data dari TV'), findsOneWidget);
    expect(find.text('Tambah'), findsNothing);
    expect(paketAksi(SyncAction.updateRunningText), isEmpty);

    // Snapshot tiba → editor langsung terisi dari data TV.
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Kajian rutin Sabtu'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('teks berjalan: tambah isi kosong ditolak, isi sah terkirim '
      'sebagai daftar penuh', (tester) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tambah Teks Berjalan'), findsOneWidget);

    // Isi kosong → Simpan nonaktif, tidak ada paket yang terkirim.
    final simpan = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Simpan'),
        matching: find.byType(TextButton),
      ),
    );
    expect(simpan.onPressed, isNull);
    expect(find.text('Isi teks tidak boleh kosong.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Pengajian Ahad pagi');
    await tester.pump();
    await tester.tap(find.text('Pengumuman'));
    await tester.pump();
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final terkirim = paketAksi(SyncAction.updateRunningText);
    expect(terkirim, hasLength(1));
    final pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    final fixture = payloadFixture()['runningTexts'] as List<dynamic>;
    expect(pesan.length, 3);
    expect(pesan[0], fixture[0]);
    expect(pesan[1], fixture[1]);
    expect(pesan[2]['content'], 'Pengajian Ahad pagi');
    expect(pesan[2]['category'], 'Pengumuman');
    expect(pesan[2]['isActive'], isTrue);
    expect((pesan[2]['id'] as String).isNotEmpty, isTrue);

    // Tunggu rute dialog layar penuh keluar sepenuhnya — selama
    // animasi keluarnya masih berjalan, SnackBar bisa tampil di
    // dua Scaffold sekaligus (artefak transisi, bukan bug).
    await tester.pump(const Duration(milliseconds: 400));
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Teks berjalan ditambahkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('teks berjalan: sunting mengubah isi pada paket daftar penuh', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ubah Teks Berjalan'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'Kajian rutin Sabtu ba\'da Subuh',
    );
    await tester.pump();
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateRunningText), hasLength(1));
    final pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    final fixture = payloadFixture()['runningTexts'] as List<dynamic>;
    expect(pesan.length, 2);
    expect(pesan[0]['id'], 'rt1');
    expect(pesan[0]['content'], 'Kajian rutin Sabtu ba\'da Subuh');
    expect(pesan[0]['category'], 'Kajian');
    expect(pesan[1], fixture[1]);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  testWidgets('teks berjalan: sakelar membalik isActive pada daftar terkirim', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    // Baris kedua (rt2) sedang nonaktif → nyalakan.
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateRunningText), hasLength(1));
    final pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    expect(pesan[0]['isActive'], isTrue);
    expect(pesan[1]['id'], 'rt2');
    expect(pesan[1]['isActive'], isTrue);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  testWidgets('teks berjalan: seret mengubah urutan daftar terkirim', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    await seretBaris(tester, find.byIcon(Icons.drag_handle).first, 160);

    expect(paketAksi(SyncAction.updateRunningText), hasLength(1));
    final pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    expect(pesan.map((m) => m['id']), ['rt2', 'rt1']);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  testWidgets('teks berjalan: hapus terkirim, Urungkan mengembalikan ke '
      'indeks asal', (tester) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateRunningText), hasLength(1));
    var pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    expect(pesan.map((m) => m['id']), ['rt2']);

    // Bukti TV: snapshot tanpa rt1 → SnackBar urungkan muncul.
    transport.terima(
      snapshotDengan((p) {
        p['runningTexts'] = [(p['runningTexts'] as List<dynamic>)[1]];
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Teks berjalan dihapus.'), findsOneWidget);

    // Ketuk aksi SnackBar hanya setelah animasi masuknya tuntas;
    // ketukan di tengah animasi bisa meleset dari tombolnya.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Urungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paketAksi(SyncAction.updateRunningText), hasLength(2));
    pesan = daftarPaket(SyncAction.updateRunningText, 'messages');
    expect(pesan.map((m) => m['id']), ['rt1', 'rt2']);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    // SnackBar sukses mengantre di belakang SnackBar hapus yang
    // baru saja ditutup aksinya — beri waktu animasi berganti.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Penghapusan diurungkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('teks berjalan: kontrol membeku selama menunggu bukti', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isTrue);

    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.onChanged, isNull);
    }
    final tambah = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Tambah'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(tambah.onPressed, isNull);
    final sunting = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined).first,
        matching: find.byType(IconButton),
      ),
    );
    expect(sunting.onPressed, isNull);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isFalse);
    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.onChanged, isNotNull);
    }
    await selesai(tester);
  });

  testWidgets('teks berjalan: snapshot bukti menjadi seed baru', (
    tester,
  ) async {
    await tampil(tester, LayarTeksBerjalan(store: store));
    expect(find.text('Kajian rutin Sabtu'), findsOneWidget);

    transport.terima(
      snapshotDengan((p) {
        (p['runningTexts'] as List<dynamic>)[0]['content'] =
            'Isi berubah dari TV';
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Isi berubah dari TV'), findsOneWidget);
    expect(find.text('Kajian rutin Sabtu'), findsNothing);
    await selesai(tester);
  });

  // ------------------------------------------------------------------
  // Banner
  // ------------------------------------------------------------------

  Uint8List pngKecil() {
    final gambar = img.Image(width: 4, height: 2);
    img.fill(gambar, color: img.ColorRgb8(0, 106, 96));
    return Uint8List.fromList(img.encodePng(gambar));
  }

  testWidgets('banner: seed tampil sebagai kartu + header + judul', (
    tester,
  ) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    expect(find.text('DONASI'), findsOneWidget);
    expect(find.text('Infaq Pembangunan'), findsOneWidget);
    expect(find.text('Salurkan untuk ruang belajar'), findsOneWidget);
    expect(find.text('INFO MASJID'), findsOneWidget);
    expect(find.text('Jadwal Kajian'), findsOneWidget);
    final sakelar = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(sakelar.map((s) => s.value), [true, true]);
    await selesai(tester);
  });

  testWidgets('banner: tambah hanya dengan gambar sah; base64 terkirim '
      'adalah hasil perkecil', (tester) async {
    final mentah = pngKecil();
    await tampil(
      tester,
      LayarBannerMasjid(
        store: store,
        pemilihGambarMentah: () async => mentah,
      ),
    );
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tambah Banner'), findsOneWidget);

    // Semua kosong → Simpan nonaktif.
    final simpanAwal = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Simpan'),
        matching: find.byType(TextButton),
      ),
    );
    expect(simpanAwal.onPressed, isNull);
    expect(
      find.text('Isi minimal salah satu: judul, isi, atau gambar.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Pilih gambar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final simpan = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Simpan'),
        matching: find.byType(TextButton),
      ),
    );
    expect(simpan.onPressed, isNotNull);

    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateBanners), hasLength(1));
    final banners = daftarPaket(SyncAction.updateBanners, 'banners');
    final fixture = payloadFixture()['banners'] as List<dynamic>;
    expect(banners.length, 3);
    expect(banners[0], fixture[0]);
    expect(banners[1], fixture[1]);
    final harapBase64 = base64Encode(await perkecilUntukBanner(mentah));
    expect(banners[2]['base64Image'], harapBase64);
    expect(banners[2]['header'], 'INFO MASJID');
    expect(banners[2]['title'], '');
    expect(banners[2]['content'], '');
    expect(banners[2]['isActive'], isTrue);

    // Tunggu rute dialog keluar sepenuhnya (lihat tes tambah teks).
    await tester.pump(const Duration(milliseconds: 400));
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Banner ditambahkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('banner: tambah serba kosong ditolak tanpa paket', (
    tester,
  ) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Kosongkan juga header bawaan — header tidak ikut syarat sah.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    final simpan = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Simpan'),
        matching: find.byType(TextButton),
      ),
    );
    expect(simpan.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(paketAksi(SyncAction.updateBanners), isEmpty);
    await selesai(tester);
  });

  testWidgets('banner: sunting mengubah judul pada paket daftar penuh', (
    tester,
  ) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ubah Banner'), findsOneWidget);

    // Field kedua = Judul (setelah Header).
    await tester.enterText(
      find.byType(TextField).at(1),
      'Jadwal Kajian Rutin',
    );
    await tester.pump();
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateBanners), hasLength(1));
    final banners = daftarPaket(SyncAction.updateBanners, 'banners');
    final fixture = payloadFixture()['banners'] as List<dynamic>;
    expect(banners[0], fixture[0]);
    expect(banners[1]['id'], 'b2');
    expect(banners[1]['title'], 'Jadwal Kajian Rutin');
    expect(banners[1]['content'], 'Setiap Sabtu ba\'da Subuh');

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  testWidgets('banner: sakelar membalik isActive pada daftar terkirim', (
    tester,
  ) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateBanners), hasLength(1));
    final banners = daftarPaket(SyncAction.updateBanners, 'banners');
    expect(banners[0]['id'], 'b1');
    expect(banners[0]['isActive'], isFalse);
    expect(banners[1]['isActive'], isTrue);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  testWidgets('banner: hapus terkirim, Urungkan mengembalikan ke indeks '
      'asal', (tester) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateBanners), hasLength(1));
    var banners = daftarPaket(SyncAction.updateBanners, 'banners');
    expect(banners.map((b) => b['id']), ['b2']);

    transport.terima(
      snapshotDengan((p) {
        p['banners'] = [(p['banners'] as List<dynamic>)[1]];
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Banner dihapus.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Urungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paketAksi(SyncAction.updateBanners), hasLength(2));
    banners = daftarPaket(SyncAction.updateBanners, 'banners');
    expect(banners.map((b) => b['id']), ['b1', 'b2']);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Penghapusan diurungkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('banner: seret mengubah urutan daftar terkirim', (
    tester,
  ) async {
    await tampil(tester, LayarBannerMasjid(store: store));
    await seretBaris(tester, find.byIcon(Icons.drag_handle).first, 220);

    expect(paketAksi(SyncAction.updateBanners), hasLength(1));
    final banners = daftarPaket(SyncAction.updateBanners, 'banners');
    expect(banners.map((b) => b['id']), ['b2', 'b1']);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });

  // ------------------------------------------------------------------
  // Kas (A2c)
  // ------------------------------------------------------------------

  testWidgets('kas: seed tampil + ringkasan konsisten dengan daftar', (
    tester,
  ) async {
    await tampil(tester, LayarKasMasjid(store: store));
    // Baris sesuai urutan TV + format tanggal & nominal bertanda.
    expect(find.text('Infaq Jumat'), findsOneWidget);
    expect(find.text('Masuk · 14 Agu 2026, 09:30'), findsOneWidget);
    expect(find.text('+Rp2.500.000'), findsOneWidget);
    expect(find.text('Listrik masjid'), findsOneWidget);
    expect(find.text('Keluar · 15 Agu 2026, 10:00'), findsOneWidget);
    expect(find.text('-Rp750.000'), findsOneWidget);
    // Ringkasan: saldo = 2.500.000 - 750.000.
    expect(find.text('Saldo Kas'), findsOneWidget);
    expect(find.text('Rp1.750.000'), findsOneWidget);
    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('Rp2.500.000'), findsOneWidget);
    expect(find.text('Pengeluaran'), findsOneWidget);
    expect(find.text('Rp750.000'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('kas: snapshot belum tiba → editor menahan diri', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await store.sambungkan(displayMasjid);
    await tester.pumpWidget(bungkus(LayarKasMasjid(store: store)));
    await tester.pump();
    // Kas full-replace: tanpa snapshot, TIDAK ada jalan mengirim
    // daftar kosong hasil seed yang gagal.
    expect(find.text('Belum ada data dari TV'), findsOneWidget);
    expect(find.text('Tambah'), findsNothing);
    expect(paketAksi(SyncAction.updateKas), isEmpty);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Infaq Jumat'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('kas: tambah keluar dengan tanggal mundur terkirim sebagai '
      'daftar penuh', (tester) async {
    await tampil(
      tester,
      LayarKasMasjid(
        store: store,
        pemilihTanggal: (_, _) async => DateTime(2026, 8, 1),
      ),
    );
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tambah Transaksi Kas'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '500000');
    await tester.pump();
    expect(find.text('Terbaca: Rp500.000'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Beli lampu teras');
    await tester.pump();
    await tester.tap(find.text('Keluar'));
    await tester.pump();
    await tester.tap(find.text('Pilih tanggal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('1 Agu 2026'), findsOneWidget);

    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateKas), hasLength(1));
    final transaksi = daftarPaket(SyncAction.updateKas, 'transactions');
    final fixture = payloadFixture()['kasTransactions'] as List<dynamic>;
    expect(transaksi.length, 3);
    expect(transaksi[0], fixture[0]);
    expect(transaksi[1], fixture[1]);
    // Transaksi baru DITAMBAHKAN di akhir (paritas mobile_remote).
    expect(transaksi[2]['type'], 'keluar');
    expect(transaksi[2]['amount'], 500000);
    expect(transaksi[2]['description'], 'Beli lampu teras');
    // Tanggal dari pemilih (mundur), jam dari saat menyimpan.
    expect(
      (transaksi[2]['date'] as String).startsWith('2026-08-01T'),
      isTrue,
    );
    expect((transaksi[2]['id'] as String).isNotEmpty, isTrue);

    await tester.pump(const Duration(milliseconds: 400));
    transport.terima(
      snapshotDengan((p) {
        (p['kasTransactions'] as List<dynamic>).add(transaksi[2]);
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Transaksi kas ditambahkan.'), findsOneWidget);
    // Ringkasan ikut bukti: saldo 1.750.000 - 500.000 = 1.250.000
    // dan pengeluaran 750.000 + 500.000 = 1.250.000 — angka yang
    // sama muncul di dua tempat, keduanya benar.
    expect(find.text('Rp1.250.000'), findsNWidgets(2));
    await selesai(tester);
  });

  testWidgets('kas: tambah dengan nominal/keterangan tidak sah ditolak', (
    tester,
  ) async {
    await tampil(tester, LayarKasMasjid(store: store));
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    TextButton tombolSimpan() => tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Simpan'),
        matching: find.byType(TextButton),
      ),
    );

    // Serba kosong: kedua pesan galat tampil, Simpan nonaktif.
    expect(find.text('Nominal tidak boleh kosong.'), findsOneWidget);
    expect(find.text('Keterangan tidak boleh kosong.'), findsOneWidget);
    expect(tombolSimpan().onPressed, isNull);

    // Nominal 0 tetap tidak sah.
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.pump();
    expect(find.text('Nominal harus lebih dari Rp0.'), findsOneWidget);
    expect(tombolSimpan().onPressed, isNull);

    // Nominal sah tapi keterangan masih kosong → tetap ditolak.
    await tester.enterText(find.byType(TextField).first, '25000');
    await tester.pump();
    expect(tombolSimpan().onPressed, isNull);
    expect(paketAksi(SyncAction.updateKas), isEmpty);

    // Keterangan terisi → Simpan aktif.
    await tester.enterText(find.byType(TextField).last, 'Infaq hamba Allah');
    await tester.pump();
    expect(tombolSimpan().onPressed, isNotNull);
    await selesai(tester);
  });

  testWidgets('kas: hapus terkirim, Urungkan mengembalikan ke indeks asal', (
    tester,
  ) async {
    await tampil(tester, LayarKasMasjid(store: store));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(paketAksi(SyncAction.updateKas), hasLength(1));
    var transaksi = daftarPaket(SyncAction.updateKas, 'transactions');
    expect(transaksi.map((t) => t['id']), ['k2']);

    transport.terima(
      snapshotDengan((p) {
        p['kasTransactions'] = [(p['kasTransactions'] as List<dynamic>)[1]];
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Transaksi dihapus.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Urungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paketAksi(SyncAction.updateKas), hasLength(2));
    transaksi = daftarPaket(SyncAction.updateKas, 'transactions');
    expect(transaksi.map((t) => t['id']), ['k1', 'k2']);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Penghapusan diurungkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('kas: kontrol membeku selama menunggu bukti', (tester) async {
    await tampil(tester, LayarKasMasjid(store: store));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isTrue);

    final tambah = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Tambah'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(tambah.onPressed, isNull);
    final hapus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.delete_outline),
        matching: find.byType(IconButton),
      ),
    );
    expect(hapus.onPressed, isNull);

    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.sedangMengirim, isFalse);
    await selesai(tester);
  });

  testWidgets('kas: snapshot bukti menjadi seed baru', (tester) async {
    await tampil(tester, LayarKasMasjid(store: store));
    expect(find.text('Infaq Jumat'), findsOneWidget);

    transport.terima(
      snapshotDengan((p) {
        (p['kasTransactions'] as List<dynamic>)[0]['description'] =
            'Infaq Jumat (revisi TV)';
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Infaq Jumat (revisi TV)'), findsOneWidget);
    expect(find.text('Infaq Jumat'), findsNothing);
    await selesai(tester);
  });

  testWidgets('kas: daftar kosong yang sah tampil ramah + ringkasan nol', (
    tester,
  ) async {
    await tampil(tester, LayarKasMasjid(store: store));
    transport.terima(
      snapshotDengan((p) {
        p['kasTransactions'] = <dynamic>[];
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Belum ada catatan kas di TV'), findsOneWidget);
    // Saldo + pemasukan + pengeluaran semuanya Rp0.
    expect(find.text('Rp0'), findsNWidgets(3));
    final tambah = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Tambah'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(tambah.onPressed, isNotNull);
    await selesai(tester);
  });

  // ------------------------------------------------------------------
  // Gambar Khusus (A2d)
  // ------------------------------------------------------------------

  testWidgets('gambar khusus: seed tampil + keterangan + sakelar', (
    tester,
  ) async {
    await tampil(tester, LayarGambarKhusus(store: store));
    expect(find.text('Gambar 1'), findsOneWidget);
    expect(find.text('Renovasi tempat wudhu'), findsOneWidget);
    expect(find.text('Tampil di TV'), findsOneWidget);
    final sakelar = tester.widget<Switch>(find.byType(Switch));
    expect(sakelar.value, isTrue);
    expect(paketAksi(SyncAction.updateSideImages), isEmpty);
    await selesai(tester);
  });

  testWidgets('gambar khusus: tambah memilih gambar lalu keterangan, '
      'satu paket updateSideImages terkirim', (tester) async {
    await tampil(
      tester,
      LayarGambarKhusus(
        store: store,
        pemilihGambarMentah: () async => pngKecil(),
      ),
    );
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Dialog keterangan muncul sesudah gambar dipilih & diperkecil.
    expect(find.text('Gambar Khusus Baru'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Foto gerbang');
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final terkirim = paketAksi(SyncAction.updateSideImages);
    expect(terkirim, hasLength(1));
    final daftar = daftarPaket(SyncAction.updateSideImages, 'images');
    expect(daftar, hasLength(2));
    expect(daftar[0]['id'], 's1');
    expect(daftar[1]['caption'], 'Foto gerbang');
    expect(daftar[1]['isActive'], isTrue);
    // Base64 terkirim adalah JPEG hasil perkecil, bukan PNG asli.
    expect(
      base64Decode(daftar[1]['base64Image'] as String).length,
      greaterThan(0),
    );
    transport.terima(
      snapshotDengan((p) {
        (p['sideImages'] as List<dynamic>).add(daftar[1]);
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Gambar khusus ditambahkan.'), findsOneWidget);
    // Dialog keterangan sudah selesai animasi keluar.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Foto gerbang'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('gambar khusus: berkas bukan gambar ditolak tanpa paket', (
    tester,
  ) async {
    await tampil(
      tester,
      LayarGambarKhusus(
        store: store,
        pemilihGambarMentah: () async =>
            Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('tidak terbaca sebagai gambar'),
      findsOneWidget,
    );
    expect(find.text('Gambar Khusus Baru'), findsNothing);
    expect(paketAksi(SyncAction.updateSideImages), isEmpty);
    await selesai(tester);
  });

  testWidgets('gambar khusus: sakelar mengirim isActive terbaru', (
    tester,
  ) async {
    await tampil(tester, LayarGambarKhusus(store: store));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final daftar = daftarPaket(SyncAction.updateSideImages, 'images');
    expect(daftar, hasLength(1));
    expect(daftar[0]['isActive'], isFalse);
    transport.terima(
      snapshotDengan((p) {
        (p['sideImages'] as List<dynamic>)[0]['isActive'] = false;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Tidak tampil di TV'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('gambar khusus: hapus lalu urungkan mengembalikan '
      'indeks asal', (tester) async {
    await tampil(tester, LayarGambarKhusus(store: store));
    await tester.tap(find.byTooltip('Hapus gambar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    var daftar = daftarPaket(SyncAction.updateSideImages, 'images');
    expect(daftar, isEmpty);
    transport.terima(
      snapshotDengan((p) {
        p['sideImages'] = <dynamic>[];
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Gambar khusus dihapus.'), findsOneWidget);

    // Tunggu animasi masuk snackbar selesai sebelum mengetuk
    // aksinya (pola tes hapus kas/banner).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Urungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    daftar = daftarPaket(SyncAction.updateSideImages, 'images');
    expect(daftar, hasLength(1));
    expect(daftar[0]['id'], 's1');
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Renovasi tempat wudhu'), findsOneWidget);
    await selesai(tester);
  });

  // ------------------------------------------------------------------
  // Gambar Latar (A2d)
  // ------------------------------------------------------------------

  testWidgets('gambar latar: seed tampil + interval dari config', (
    tester,
  ) async {
    await tampil(tester, LayarGambarLatar(store: store));
    expect(find.text('Gambar 1 · Tampil di TV'), findsOneWidget);
    expect(find.text('Gambar 2 · Tidak tampil di TV'), findsOneWidget);
    expect(find.text('45 detik'), findsOneWidget);
    expect(paketAksi(SyncAction.updateBackgroundImages), isEmpty);
    expect(paketAksi(SyncAction.updateConfig), isEmpty);
    await selesai(tester);
  });

  testWidgets('gambar latar: stepper interval mengirim updateConfig '
      'satu field dari config utuh', (tester) async {
    await tampil(tester, LayarGambarLatar(store: store));
    await tester.tap(find.byTooltip('Tambah interval'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final terkirim = paketAksi(SyncAction.updateConfig);
    expect(terkirim, hasLength(1));
    expect(terkirim.single.payload['backgroundSlideSeconds'], 50);
    // Field config lain tidak berubah dari fixture.
    expect(
      terkirim.single.payload['name'],
      payloadFixture()['config']['name'],
    );
    transport.terima(
      snapshotDengan((p) {
        (p['config'] as Map<String, dynamic>)['backgroundSlideSeconds'] =
            50;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('50 detik'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('gambar latar: tambah menyimpan berkas ASLI apa adanya', (
    tester,
  ) async {
    final mentah = pngKecil();
    await tampil(
      tester,
      LayarGambarLatar(
        store: store,
        pemilihGambarMentah: () async => mentah,
      ),
    );
    await tester.tap(find.text('Tambah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final daftar = daftarPaket(SyncAction.updateBackgroundImages, 'images');
    expect(daftar, hasLength(3));
    // Tanpa perkecil/encode ulang: base64 persis berkas pilihan.
    expect(daftar[2]['base64Image'], base64Encode(mentah));
    expect(daftar[2]['isActive'], isTrue);
    transport.terima(
      snapshotDengan((p) {
        (p['backgroundImages'] as List<dynamic>).add(daftar[2]);
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Gambar latar ditambahkan.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('gambar latar: sakelar tanpa kompresi diteruskan ke '
      'store + transport', (tester) async {
    await tampil(tester, LayarGambarLatar(store: store));
    expect(store.kirimLatarTanpaKompresi, isFalse);
    final sakelar = find.descendant(
      of: find.byType(SwitchListTile),
      matching: find.byType(Switch),
    );
    await tester.tap(sakelar);
    await tester.pump();
    expect(store.kirimLatarTanpaKompresi, isTrue);
    expect(transport.tanpaKompresiTerakhir, isTrue);
    await selesai(tester);
  });

  test('store: preferensi tanpa kompresi dititipkan saat menyambung '
      'dan callback persistensi terpanggil', () async {
    final transport2 = TransportMasjidPalsu();
    var tersimpan = false;
    final store2 = MasjidStore(
      buatTransport: (_) => transport2,
      kirimLatarTanpaKompresiAwal: true,
      onKirimLatarTanpaKompresiBerubah: (nilai) => tersimpan = nilai,
    );
    addTearDown(store2.dispose);
    await store2.sambungkan(displayMasjid);
    // Nilai awal langsung diterapkan ke transport yang baru dibuat.
    expect(transport2.tanpaKompresiTerakhir, isTrue);
    store2.aturKirimLatarTanpaKompresi(false);
    expect(transport2.tanpaKompresiTerakhir, isFalse);
    expect(tersimpan, isFalse);
  });

  // ------------------------------------------------------------------
  // Logo (A2d)
  // ------------------------------------------------------------------

  testWidgets('logo: seed berlogo menampilkan Ganti + Hapus', (
    tester,
  ) async {
    await tampil(tester, LayarLogoMasjid(store: store));
    expect(find.text('Ganti logo'), findsOneWidget);
    expect(find.text('Hapus logo'), findsOneWidget);
    expect(paketAksi(SyncAction.updateLogo), isEmpty);
    await selesai(tester);
  });

  testWidgets('logo: pilih gambar mengirim updateLogo hasil olah 512px', (
    tester,
  ) async {
    await tampil(
      tester,
      LayarLogoMasjid(
        store: store,
        pemilihGambarMentah: () async => pngKecil(),
      ),
    );
    await tester.tap(find.text('Ganti logo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final terkirim = paketAksi(SyncAction.updateLogo);
    expect(terkirim, hasLength(1));
    final logoBaru = terkirim.single.payload['logoBase64'] as String;
    expect(logoBaru, isNot('bG9nbw=='));
    expect(base64Decode(logoBaru).length, greaterThan(0));
    transport.terima(
      snapshotDengan((p) {
        p['mosqueLogo'] = logoBaru;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Logo masjid diperbarui.'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('logo: hapus lewat konfirmasi mengirim logoBase64 null', (
    tester,
  ) async {
    await tampil(tester, LayarLogoMasjid(store: store));
    await tester.tap(find.text('Hapus logo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hapus logo masjid?'), findsOneWidget);
    await tester.tap(find.text('Hapus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final terkirim = paketAksi(SyncAction.updateLogo);
    expect(terkirim, hasLength(1));
    expect(terkirim.single.payload['logoBase64'], isNull);
    transport.terima(
      snapshotDengan((p) {
        p['mosqueLogo'] = null;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Pilih logo'), findsOneWidget);
    expect(find.text('Belum ada logo'), findsOneWidget);
    await selesai(tester);
  });
}
