import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/layanan/penyelidik.dart';

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
}
