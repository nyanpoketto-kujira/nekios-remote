/// Validasi berkas jadwal di sisi remote — cerminan aturan §7 dokumen
/// arsitektur data nekios-school, setara semantik `validasiJadwal`
/// di nekios-school (`lib/domain/validasi.dart`), tetapi bekerja di
/// atas JSON MENTAH (hasil `jsonDecode`) karena remote tidak memuat
/// model nekios-school.
///
/// Perbedaan sadar dari sisi display: remote juga memeriksa STRUKTUR
/// (field hilang / tipe salah / format jam rusak) dengan pesan yang
/// layak tampil, karena berkas yang strukturnya rusak bahkan tidak
/// bisa dibaca model display. Daftar kesalahan kosong = valid.
library;

/// Ringkasan jadwal hasil parse — ditampilkan sebelum pengiriman dan
/// dipakai sebagai bukti struktur dasar terbaca.
class RingkasanJadwal {
  const RingkasanJadwal({
    required this.sekolah,
    required this.judul,
    required this.tahunPelajaran,
    required this.jurusan,
    required this.jumlahKelas,
    required this.jumlahGuru,
    required this.jumlahMapel,
    required this.jumlahHari,
    required this.totalSlot,
    required this.totalSlotPelajaran,
  });

  final String sekolah;
  final String judul;
  final String tahunPelajaran;
  final String jurusan;
  final int jumlahKelas;
  final int jumlahGuru;
  final int jumlahMapel;
  final int jumlahHari;
  final int totalSlot;
  final int totalSlotPelajaran;
}

/// Hasil validasi: daftar [kesalahan] (kosong = valid) dan
/// [ringkasan] bila struktur dasar berkas terbaca.
class HasilValidasiJadwal {
  const HasilValidasiJadwal({required this.kesalahan, required this.ringkasan});

  final List<String> kesalahan;
  final RingkasanJadwal? ringkasan;

  bool get valid => kesalahan.isEmpty;
}

const Set<String> _tipeSlotDikenal = {
  'pelajaran',
  'istirahat',
  'isoma',
  'upacara',
  'khusus',
};

final RegExp _polaWarna = RegExp(r'^#[0-9A-Fa-f]{6}$');
final RegExp _polaJam = RegExp(r'^(\d{1,2})\.(\d{2})$');

/// Menit sejak tengah malam dari format "JJ.MM"; null bila format
/// atau rentangnya tidak masuk akal.
int? _menitDariJam(Object? nilai) {
  if (nilai is! String) return null;
  final cocok = _polaJam.firstMatch(nilai);
  if (cocok == null) return null;
  final jam = int.parse(cocok.group(1)!);
  final menit = int.parse(cocok.group(2)!);
  if (jam > 23 || menit > 59) return null;
  return jam * 60 + menit;
}

HasilValidasiJadwal validasiJadwalJson(Object? json) {
  final errors = <String>[];

  if (json is! Map<String, dynamic>) {
    return const HasilValidasiJadwal(
      kesalahan: ['Berkas bukan objek JSON jadwal (akar harus objek).'],
      ringkasan: null,
    );
  }

  // --- meta ---------------------------------------------------------------
  var sekolah = '', judul = '', tahunPelajaran = '', jurusan = '';
  final meta = json['meta'];
  if (meta is! Map<String, dynamic>) {
    errors.add('Bagian "meta" hilang atau bukan objek.');
  } else {
    String ambilMeta(String kunci) {
      final nilai = meta[kunci];
      if (nilai is! String || nilai.trim().isEmpty) {
        errors.add('meta.$kunci hilang atau kosong.');
        return '';
      }
      return nilai;
    }

    sekolah = ambilMeta('sekolah');
    judul = ambilMeta('judul');
    tahunPelajaran = ambilMeta('tahunPelajaran');
    jurusan = ambilMeta('jurusan');
  }

  // --- tabel referensi ------------------------------------------------------
  final kelasIds = <String>[];
  final kelasJson = json['kelas'];
  if (kelasJson is! List) {
    errors.add('Bagian "kelas" hilang atau bukan daftar.');
  } else {
    if (kelasJson.isEmpty) errors.add('Daftar "kelas" kosong.');
    for (final k in kelasJson) {
      if (k is! Map<String, dynamic> ||
          k['id'] is! String ||
          k['nama'] is! String ||
          k['urutan'] is! int) {
        errors.add('Entri kelas tidak lengkap (wajib id, nama, urutan).');
        continue;
      }
      final id = k['id'] as String;
      if (kelasIds.contains(id)) {
        errors.add('ID kelas ganda: "$id".');
      }
      kelasIds.add(id);
    }
  }

  final kgValid = <int>{};
  final guruJson = json['guru'];
  if (guruJson is! List) {
    errors.add('Bagian "guru" hilang atau bukan daftar.');
  } else {
    for (final g in guruJson) {
      if (g is! Map<String, dynamic> ||
          g['kg'] is! int ||
          g['nama'] is! String) {
        errors.add('Entri guru tidak lengkap (wajib kg angka dan nama).');
        continue;
      }
      final kg = g['kg'] as int;
      if (!kgValid.add(kg)) errors.add('KG ganda: $kg.');
    }
  }

  final mapelValid = <String>{};
  final mapelJson = json['mapel'];
  if (mapelJson is! List) {
    errors.add('Bagian "mapel" hilang atau bukan daftar.');
  } else {
    for (final m in mapelJson) {
      if (m is! Map<String, dynamic> || m['kode'] is! String) {
        errors.add('Entri mapel tidak lengkap (wajib kode).');
        continue;
      }
      final kode = m['kode'] as String;
      if (!mapelValid.add(kode)) errors.add('Kode mapel ganda: "$kode".');
      // Aturan 5: setiap mapel punya namaPanjang dan warna #RRGGBB.
      final namaPanjang = m['namaPanjang'];
      if (namaPanjang is! String || namaPanjang.trim().isEmpty) {
        errors.add('Mapel $kode: namaPanjang kosong.');
      }
      final warna = m['warna'];
      if (warna is! String || !_polaWarna.hasMatch(warna)) {
        errors.add('Mapel $kode: warna "$warna" bukan format #RRGGBB.');
      }
    }
  }

  // --- hari & slot ------------------------------------------------------------
  var totalSlot = 0;
  var totalSlotPelajaran = 0;
  var jumlahHari = 0;
  final hariJson = json['hari'];
  if (hariJson is! List) {
    errors.add('Bagian "hari" hilang atau bukan daftar.');
  } else {
    if (hariJson.isEmpty) errors.add('Daftar "hari" kosong.');
    jumlahHari = hariJson.length;
    for (final h in hariJson) {
      if (h is! Map<String, dynamic> || h['nama'] is! String) {
        errors.add('Entri hari tidak lengkap (wajib nama).');
        continue;
      }
      final namaHari = h['nama'] as String;
      final slotsJson = h['slots'];
      if (slotsJson is! List) {
        errors.add('Hari $namaHari: "slots" hilang atau bukan daftar.');
        continue;
      }
      int? prevMulai, prevSelesai;
      String? prevRentang;
      for (final s in slotsJson) {
        totalSlot++;
        if (s is! Map<String, dynamic>) {
          errors.add('Hari $namaHari: entri slot bukan objek.');
          continue;
        }
        final mulaiMentah = s['mulai'];
        final selesaiMentah = s['selesai'];
        final konteks = '$namaHari slot $mulaiMentah–$selesaiMentah';
        final tipe = s['tipe'];
        if (tipe is! String || !_tipeSlotDikenal.contains(tipe)) {
          errors.add('$konteks: tipe slot tidak dikenal "$tipe".');
          continue;
        }
        final adalahPelajaran = tipe == 'pelajaran';
        if (adalahPelajaran) totalSlotPelajaran++;
        final mulai = _menitDariJam(mulaiMentah);
        final selesai = _menitDariJam(selesaiMentah);
        if (mulai == null || selesai == null) {
          errors.add('$konteks: format jam harus JJ.MM (mis. 07.15).');
          continue;
        }
        // Aturan 4: mulai < selesai di semua slot.
        if (mulai >= selesai) {
          errors.add('$konteks: mulai harus sebelum selesai.');
        }
        // Aturan 1: slot terurut dan tidak tumpang tindih dalam satu hari.
        if (prevMulai != null && prevSelesai != null) {
          if (mulai < prevMulai) {
            errors.add('$konteks: slot tidak terurut.');
          }
          if (mulai < prevSelesai) {
            errors.add(
              '$konteks: tumpang tindih dengan slot sebelumnya ($prevRentang).',
            );
          }
        }
        prevMulai = mulai;
        prevSelesai = selesai;
        prevRentang = '$mulaiMentah–$selesaiMentah';

        // Entri per kelas.
        final entriMentah = s['entri'];
        final Map<String, dynamic> entri;
        if (entriMentah == null) {
          entri = const {};
        } else if (entriMentah is Map<String, dynamic>) {
          entri = entriMentah;
        } else {
          errors.add('$konteks: "entri" harus objek per kelas.');
          continue;
        }
        // Aturan 3: slot pelajaran tepat satu entri per kelas;
        // slot non-pelajaran tidak boleh punya entri.
        if (adalahPelajaran) {
          if (entri.length != kelasIds.length ||
              !entri.keys.toSet().containsAll(kelasIds)) {
            errors.add(
              '$konteks: slot pelajaran wajib punya tepat '
              '${kelasIds.length} entri (satu per kelas).',
            );
          }
        } else if (entri.isNotEmpty) {
          errors.add('$konteks: slot $tipe tidak boleh punya entri.');
        }
        // Aturan 2: foreign key entri harus ada di tabel referensi.
        for (final e in entri.entries) {
          if (!kelasIds.contains(e.key)) {
            errors.add('$konteks: kelas tidak dikenal "${e.key}".');
          }
          final nilai = e.value;
          if (nilai is! Map<String, dynamic>) {
            errors.add('$konteks: entri kelas "${e.key}" bukan objek.');
            continue;
          }
          if (!mapelValid.contains(nilai['mapel'])) {
            errors.add('$konteks: mapel tidak dikenal "${nilai['mapel']}".');
          }
          if (!kgValid.contains(nilai['kg'])) {
            errors.add('$konteks: KG tidak dikenal ${nilai['kg']}.');
          }
        }
      }
    }
  }

  final strukturTerbaca =
      meta is Map<String, dynamic> &&
      kelasJson is List &&
      guruJson is List &&
      mapelJson is List &&
      hariJson is List;
  return HasilValidasiJadwal(
    kesalahan: errors,
    ringkasan: strukturTerbaca
        ? RingkasanJadwal(
            sekolah: sekolah,
            judul: judul,
            tahunPelajaran: tahunPelajaran,
            jurusan: jurusan,
            jumlahKelas: kelasIds.length,
            jumlahGuru: kgValid.length,
            jumlahMapel: mapelValid.length,
            jumlahHari: jumlahHari,
            totalSlot: totalSlot,
            totalSlotPelajaran: totalSlotPelajaran,
          )
        : null,
  );
}
