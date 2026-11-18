/// Model tampilan dari payload `state.snapshot` nekios-school (R1).
///
/// Kontrak payload (pemilik: nekios-school, `DisplayStore.snapshotPaket`):
/// `{status, jamEfektif, simulasiAktif, mading, hasLogo, jamKeAktif,
/// slotAktif{mulai, selesai, tipe, label}|null, belBerikutnya,
/// sisaKeBelDetik, jadwal{...}|null}`. Parser di sini toleran: field
/// yang hilang/salah tipe jatuh ke nilai aman, bukan lempar — snapshot
/// yang agak berbeda tidak boleh menjatuhkan remote.
library;

/// Status tampilan display sebagaimana dilaporkan snapshot.
enum StatusDisplay {
  pelajaran,
  istirahat,
  isoma,
  khusus,
  sebelumMasuk,
  pulang,
  tidakAdaJadwal,
  belumSiap,
  tidakDikenal;

  static StatusDisplay dariString(String? nilai) => switch (nilai) {
        'pelajaran' => StatusDisplay.pelajaran,
        'istirahat' => StatusDisplay.istirahat,
        'isoma' => StatusDisplay.isoma,
        'khusus' => StatusDisplay.khusus,
        'sebelumMasuk' => StatusDisplay.sebelumMasuk,
        'pulang' => StatusDisplay.pulang,
        'tidakAdaJadwal' => StatusDisplay.tidakAdaJadwal,
        'belumSiap' => StatusDisplay.belumSiap,
        _ => StatusDisplay.tidakDikenal,
      };
}

/// Slot yang sedang aktif di display (bentuk mentah dari snapshot).
class SlotAktif {
  const SlotAktif({
    required this.mulai,
    required this.selesai,
    required this.tipe,
    this.label,
  });

  final String mulai;
  final String selesai;
  final String tipe;
  final String? label;

  factory SlotAktif.fromJson(Map<String, dynamic> json) => SlotAktif(
        mulai: json['mulai'] as String? ?? '',
        selesai: json['selesai'] as String? ?? '',
        tipe: json['tipe'] as String? ?? '',
        label: json['label'] as String?,
      );
}

/// Ringkasan jadwal yang sedang dimuat display (dari snapshot).
class RingkasanJadwalSnapshot {
  const RingkasanJadwalSnapshot({
    required this.sekolah,
    required this.judul,
    required this.tahunPelajaran,
    required this.jurusan,
    required this.jumlahKelas,
    required this.jumlahHari,
    required this.hariAktif,
  });

  final String sekolah;
  final String judul;
  final String tahunPelajaran;
  final String jurusan;
  final int jumlahKelas;
  final int jumlahHari;
  final String hariAktif;

  factory RingkasanJadwalSnapshot.fromJson(Map<String, dynamic> json) =>
      RingkasanJadwalSnapshot(
        sekolah: json['sekolah'] as String? ?? '',
        judul: json['judul'] as String? ?? '',
        tahunPelajaran: json['tahunPelajaran'] as String? ?? '',
        jurusan: json['jurusan'] as String? ?? '',
        jumlahKelas: (json['jumlahKelas'] as num?)?.toInt() ?? 0,
        jumlahHari: (json['jumlahHari'] as num?)?.toInt() ?? 0,
        hariAktif: json['hariAktif'] as String? ?? '',
      );
}

/// Potret keadaan display pada saat snapshot dibuat.
///
/// [jamEfektif] & [sisaKeBelDetik] adalah nilai PADA SAAT snapshot
/// dibuat; gunakan [jamEfektifPada] / [sisaKeBelPada] dengan waktu
/// terima lokal supaya tampilan tetap berjalan di antara snapshot.
class SnapshotDisplay {
  const SnapshotDisplay({
    required this.statusMentah,
    required this.jamEfektif,
    required this.simulasiAktif,
    required this.mading,
    required this.hasLogo,
    required this.jamKeAktif,
    required this.slotAktif,
    required this.belBerikutnya,
    required this.sisaKeBelDetik,
    required this.jadwal,
  });

  /// Nilai `status` mentah dari payload (untuk diagnosis).
  final String statusMentah;

  /// Jam efektif display (sudah termasuk offset simulasi); null bila
  /// display belum siap.
  final DateTime? jamEfektif;

  /// Apakah display sedang menjalankan simulasi jam.
  final bool simulasiAktif;

  /// Teks mading aktif; string kosong = sambutan bawaan display.
  final String mading;

  /// Apakah display sedang memasang logo.
  final bool hasLogo;

  /// Nomor jam pelajaran aktif (1-based); null di luar jam pelajaran.
  final int? jamKeAktif;

  /// Slot aktif saat snapshot dibuat.
  final SlotAktif? slotAktif;

  /// Momen bel berikutnya (jam efektif); null bila tidak ada lagi.
  final DateTime? belBerikutnya;

  /// Detik menuju [belBerikutnya] pada saat snapshot dibuat.
  final int? sisaKeBelDetik;

  /// Ringkasan jadwal termuat; null bila display belum memuat jadwal.
  final RingkasanJadwalSnapshot? jadwal;

  StatusDisplay get status => StatusDisplay.dariString(statusMentah);

  /// Label status yang manusiawi untuk pengguna (Bahasa Indonesia).
  String get labelStatus => switch (status) {
        StatusDisplay.pelajaran =>
          jamKeAktif == null ? 'Pelajaran berlangsung' : 'Pelajaran — Jam ke-$jamKeAktif',
        StatusDisplay.istirahat => 'Istirahat',
        StatusDisplay.isoma => 'ISOMA — Istirahat, Sholat, Makan',
        StatusDisplay.khusus => slotAktif?.label ?? 'Kegiatan khusus',
        StatusDisplay.sebelumMasuk => 'Sebelum masuk',
        StatusDisplay.pulang => 'Sudah pulang',
        StatusDisplay.tidakAdaJadwal => 'Tidak ada jadwal hari ini',
        StatusDisplay.belumSiap => 'Display belum siap',
        StatusDisplay.tidakDikenal => 'Status tidak dikenal ($statusMentah)',
      };

  /// Jam efektif pada waktu lokal [sekarang], bila snapshot ini
  /// diterima pada waktu lokal [diterimaPada]. Jam display berjalan
  /// secepat jam nyata (simulasi hanya menggeser offset), jadi cukup
  /// ditambah selisih waktu lokal sejak snapshot diterima.
  DateTime? jamEfektifPada(DateTime diterimaPada, DateTime sekarang) =>
      jamEfektif?.add(sekarang.difference(diterimaPada));

  /// Sisa detik menuju bel pada waktu lokal [sekarang] (tidak negatif).
  int? sisaKeBelPada(DateTime diterimaPada, DateTime sekarang) {
    final sisa = sisaKeBelDetik;
    if (sisa == null) return null;
    final berjalan = sekarang.difference(diterimaPada).inSeconds;
    final hasil = sisa - berjalan;
    return hasil < 0 ? 0 : hasil;
  }

  factory SnapshotDisplay.fromPayload(Map<String, dynamic> payload) {
    DateTime? parseTanggal(Object? nilai) =>
        nilai is String ? DateTime.tryParse(nilai) : null;
    final slotJson = payload['slotAktif'];
    final jadwalJson = payload['jadwal'];
    return SnapshotDisplay(
      statusMentah: payload['status'] as String? ?? '',
      jamEfektif: parseTanggal(payload['jamEfektif']),
      simulasiAktif: payload['simulasiAktif'] as bool? ?? false,
      mading: payload['mading'] as String? ?? '',
      hasLogo: payload['hasLogo'] as bool? ?? false,
      jamKeAktif: (payload['jamKeAktif'] as num?)?.toInt(),
      slotAktif: slotJson is Map<String, dynamic>
          ? SlotAktif.fromJson(slotJson)
          : null,
      belBerikutnya: parseTanggal(payload['belBerikutnya']),
      sisaKeBelDetik: (payload['sisaKeBelDetik'] as num?)?.toInt(),
      jadwal: jadwalJson is Map<String, dynamic>
          ? RingkasanJadwalSnapshot.fromJson(jadwalJson)
          : null,
    );
  }
}

/// Format sisa detik menjadi `MM:SS`, atau `J:MM:SS` bila ≥ 1 jam.
String formatSisaDetik(int detik) {
  final d = detik < 0 ? 0 : detik;
  final jam = d ~/ 3600;
  final menit = (d % 3600) ~/ 60;
  final sisa = d % 60;
  String dua(int n) => n.toString().padLeft(2, '0');
  return jam > 0 ? '$jam:${dua(menit)}:${dua(sisa)}' : '${dua(menit)}:${dua(sisa)}';
}
