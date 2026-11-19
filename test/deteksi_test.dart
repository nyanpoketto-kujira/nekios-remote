import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_core/nekios_core.dart';
import 'package:nekios_remote/layanan/klien_remote.dart';
import 'package:nekios_remote/layanan/penyelidik.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/masjid/transport_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

/// Test pendeteksi auto-detect (ADR-004): probing paralel dua
/// protokol — jawaban valid pertama menentukan identitas.
void main() {
  PendekteksiDisplay buat({
    Future<String?> Function(String ip)? sekolah,
    Future<String?> Function(String ip)? masjid,
  }) => PendekteksiDisplay(
    selidikiSekolah: sekolah ?? (_) async => null,
    selidikiMasjid: masjid ?? (_) async => null,
  );

  test('hanya sekolah menjawab → TerdeteksiSekolah + nama', () async {
    final deteksi = buat(sekolah: (_) async => 'SMKN 1 Ukui');
    final hasil = await deteksi.deteksi('10.0.0.1');
    expect(hasil, isA<TerdeteksiSekolah>());
    expect((hasil as TerdeteksiSekolah).namaSekolah, 'SMKN 1 Ukui');
  });

  test('hanya masjid menjawab → TerdeteksiMasjid + nama', () async {
    final deteksi = buat(masjid: (_) async => 'Masjid Al-Hikmah');
    final hasil = await deteksi.deteksi('10.0.0.2');
    expect(hasil, isA<TerdeteksiMasjid>());
    expect((hasil as TerdeteksiMasjid).namaMasjid, 'Masjid Al-Hikmah');
  });

  test('keduanya senyap → TidakTerdeteksi', () async {
    final hasil = await buat().deteksi('10.0.0.3');
    expect(hasil, isA<TidakTerdeteksi>());
  });

  test('penyelidik melempar → dianggap senyap, bukan crash', () async {
    final deteksi = buat(
      sekolah: (_) async => throw Exception('jaringan putus'),
      masjid: (_) async => 'Masjid Al-Hikmah',
    );
    final hasil = await deteksi.deteksi('10.0.0.4');
    expect(hasil, isA<TerdeteksiMasjid>());
  });

  test('jawaban pertama menang: masjid cepat vs sekolah lambat', () async {
    final deteksi = buat(
      sekolah: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'SMKN 1 Ukui';
      },
      masjid: (_) async => 'Masjid Al-Hikmah',
    );
    final hasil = await deteksi.deteksi('10.0.0.5');
    expect(hasil, isA<TerdeteksiMasjid>());
  });

  test('jawaban pertama menang: sekolah cepat vs masjid lambat', () async {
    final deteksi = buat(
      sekolah: (_) async => 'SMKN 1 Ukui',
      masjid: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'Masjid Al-Hikmah';
      },
    );
    final hasil = await deteksi.deteksi('10.0.0.6');
    expect(hasil, isA<TerdeteksiSekolah>());
  });

  test('kedua penyelidik dipanggil paralel dengan IP yang sama', () async {
    final terpanggil = <String>[];
    final deteksi = buat(
      sekolah: (ip) async {
        terpanggil.add('sekolah:$ip');
        return null;
      },
      masjid: (ip) async {
        terpanggil.add('masjid:$ip');
        return null;
      },
    );
    await deteksi.deteksi('10.0.0.7');
    expect(terpanggil, containsAll(['sekolah:10.0.0.7', 'masjid:10.0.0.7']));
  });

  test('nama kosong tetap jawaban valid (bukan senyap)', () async {
    final deteksi = buat(sekolah: (_) async => '');
    final hasil = await deteksi.deteksi('10.0.0.8');
    expect(hasil, isA<TerdeteksiSekolah>());
    expect((hasil as TerdeteksiSekolah).namaSekolah, isEmpty);
  });

  group('regresi bug hang deteksi (ADR-005)', () {
    test('penyelidik sekolah kembali walau sambung & putus macet',
        () async {
      // Dulu: finally menunggu putus() yang tidak pernah selesai
      // → penyelidik tidak pernah kembali → deteksi macet.
      final nama = await selidikiSekolahNekios(
        '10.0.0.9',
        batas: const Duration(milliseconds: 100),
        buatKlien: _KlienMacet.new,
      ).timeout(const Duration(seconds: 5));
      expect(nama, isNull);
    });

    test('penyelidik masjid kembali walau sambung & putus macet',
        () async {
      final nama = await selidikiMasjidWs(
        '10.0.0.10',
        batas: const Duration(milliseconds: 100),
        buatTransport: _TransportMacet.new,
      ).timeout(const Duration(seconds: 5));
      expect(nama, isNull);
    });

    test('deteksi selesai di tenggat walau kedua penyelidik macet',
        () async {
      final deteksi = buat(
        sekolah: (_) => Completer<String?>().future,
        masjid: (_) => Completer<String?>().future,
      );
      final hasil = await deteksi
          .deteksi(
            '10.0.0.11',
            batasTotal: const Duration(milliseconds: 200),
          )
          .timeout(const Duration(seconds: 5));
      expect(hasil, isA<TidakTerdeteksi>());
    });

    test('penyelidik macet tidak menahan jawaban penyelidik lain',
        () async {
      final deteksi = buat(
        sekolah: (_) => Completer<String?>().future,
        masjid: (_) async => 'Masjid Al-Hikmah',
      );
      final hasil = await deteksi
          .deteksi('10.0.0.12', batasTotal: const Duration(seconds: 30))
          .timeout(const Duration(seconds: 5));
      expect(hasil, isA<TerdeteksiMasjid>());
    });
  });
}

/// Klien yang sambungannya macet di tengah handshake DAN
/// penutupannya tidak pernah selesai — mereproduksi kondisi bug
/// lapangan 2026-11-18: `sink.close()` pada kanal WebSocket yang
/// belum terhubung tidak kunjung kembali.
class _KlienMacet implements KlienRemote {
  @override
  bool get terhubung => false;

  @override
  Stream<NekiosPacket> get paketMasuk => Stream<NekiosPacket>.empty();

  @override
  Future<void> sambung(String host, {int port = kNekiosPort}) =>
      Completer<void>().future;

  @override
  void kirim(NekiosPacket paket) {}

  @override
  Future<void> putus() => Completer<void>().future;
}

/// Transport masjid dengan kegagalan yang sama seperti
/// [_KlienMacet]: sambung macet, putus tidak pernah selesai.
class _TransportMacet implements TransportMasjid {
  @override
  bool get terhubung => false;

  @override
  Stream<SyncPacket> get paketMasuk => Stream<SyncPacket>.empty();

  @override
  Stream<String> get kesalahan => Stream<String>.empty();

  @override
  Future<void> sambung(DisplayTersimpan display) =>
      Completer<void>().future;

  @override
  void kirim(SyncPacket paket) {}

  @override
  void aturKirimTanpaKompresiLatar(bool nilai) {}

  @override
  Future<void> putus() => Completer<void>().future;
}
