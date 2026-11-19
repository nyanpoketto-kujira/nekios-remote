import 'package:geolocator/geolocator.dart';

/// Sepasang koordinat geografis hasil pengambilan GPS.
class KoordinatGps {
  const KoordinatGps({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Pengambil koordinat yang bisa disuntikkan ke layar
/// Pengaturan demi tes. Implementasi bawaan:
/// [ambilKoordinatGeolocator]. Melempar [Exception] berpesan
/// manusiawi bila posisi tidak bisa didapat.
typedef PengambilKoordinatGps = Future<KoordinatGps> Function();

/// Ambil koordinat HP saat ini lewat geolocator — port perilaku
/// `GpsLocationService` mobile_remote: periksa layanan lokasi,
/// periksa/minta izin, ambil posisi akurasi tinggi dengan batas
/// waktu, dan jatuh ke posisi terakhir yang diketahui bila
/// pengambilan langsung gagal.
Future<KoordinatGps> ambilKoordinatGeolocator() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception(
      'Lokasi HP sedang mati. Nyalakan lokasi (GPS) lalu coba lagi.',
    );
  }
  var izin = await Geolocator.checkPermission();
  if (izin == LocationPermission.denied) {
    izin = await Geolocator.requestPermission();
  }
  if (izin == LocationPermission.deniedForever) {
    throw Exception(
      'Izin lokasi ditolak permanen. Buka Pengaturan HP, izinkan '
      'akses Lokasi untuk aplikasi ini, lalu coba lagi.',
    );
  }
  if (izin == LocationPermission.denied ||
      izin == LocationPermission.unableToDetermine) {
    throw Exception(
      'Izin lokasi belum diberikan. Izinkan akses lokasi lalu '
      'coba lagi.',
    );
  }
  try {
    final posisi = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return KoordinatGps(
      latitude: posisi.latitude,
      longitude: posisi.longitude,
    );
  } catch (_) {
    final terakhir = await Geolocator.getLastKnownPosition();
    if (terakhir != null) {
      return KoordinatGps(
        latitude: terakhir.latitude,
        longitude: terakhir.longitude,
      );
    }
    throw Exception(
      'Posisi GPS belum ditemukan. Coba lagi di tempat yang '
      'lebih terbuka.',
    );
  }
}
