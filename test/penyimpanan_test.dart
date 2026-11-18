import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PenyimpananDisplay> buatPenyimpanan(Map<String, Object> awal) async {
    SharedPreferences.setMockInitialValues(awal);
    return PenyimpananDisplay(await SharedPreferences.getInstance());
  }

  test('daftar display pulang-pergi (round-trip)', () async {
    final simpan = await buatPenyimpanan({});
    expect(simpan.daftar(), isEmpty);
    await simpan.simpanDaftar(const [
      DisplayTersimpan(nama: 'TV Pameran', ip: '192.168.1.20'),
      DisplayTersimpan(nama: 'TV Kelas', ip: '10.0.0.8'),
    ]);
    // Baca ulang dari instance baru (meniru mulai ulang aplikasi).
    final baca = PenyimpananDisplay(await SharedPreferences.getInstance());
    expect(baca.daftar(), hasLength(2));
    expect(baca.daftar().first.nama, 'TV Pameran');
    expect(baca.daftar().last.ip, '10.0.0.8');
  });

  test('IP terakhir tersimpan otomatis dan terbaca lagi', () async {
    final simpan = await buatPenyimpanan({});
    expect(simpan.ipTerakhir, isNull);
    await simpan.simpanIpTerakhir('192.168.1.20');
    final baca = PenyimpananDisplay(await SharedPreferences.getInstance());
    expect(baca.ipTerakhir, '192.168.1.20');
  });

  test('data rusak diabaikan menjadi daftar kosong', () async {
    final simpan = await buatPenyimpanan({
      PenyimpananDisplay.kunciDaftar: 'bukan-json{{',
    });
    expect(simpan.daftar(), isEmpty);
  });
}
