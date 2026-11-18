/// Model domain Editor Jadwal visual (R2b) — logika MURNI tanpa UI
/// dan tanpa IO, supaya semua operasi master data, relasi, assign
/// slot/rentang, dan perakitan dokumen bisa diuji langsung.
///
/// Konsep nyanpo: pembuatan jadwal di HP dibagi dua tahap —
/// (1) Master Data guru & mapel dengan relasi BEBAS many-to-many
/// (satu guru banyak mapel; satu mapel banyak guru / team-teaching),
/// (2) Plotting: tap slot → pilih mapel & guru, dengan opsi rentang
/// 3–4 jam untuk mapel produktif.
///
/// Sumber kebenaran format: skema JSON jadwal nekios-school
/// (meta/kelas/guru/mapel/hari[].slots[].entri). [DokumenEditor]
/// memegang dokumen asal utuh; yang diedit hanya entri SATU kelas
/// aktif (kelas lain dipertahankan apa adanya saat perakitan) plus
/// tabel guru/mapel. Hasil [DokumenEditor.rakitDokumen] wajib lolos
/// validator §7 (`validasi_jadwal.dart`) sebelum dikirim.
///
/// Catatan representasi "slot kosong": skema jadwal tidak mengenal
/// entri null — validator §7 mewajibkan slot pelajaran punya tepat
/// satu entri per kelas. Jadi entri kosong di editor DIHILANGKAN
/// dari dokumen rakitan, dan validator akan menolak pengiriman
/// selama masih ada slot pelajaran kelas aktif yang kosong. Itu
/// memang penjaga yang diinginkan: jadwal setengah kosong tidak
/// boleh terkirim tanpa disadari.
library;

import 'dart:convert';

/// Hasil operasi editor: [sukses] + [pesan] manusiawi bila gagal
/// (atau keterangan hasil bila sukses dan layak tampil).
class HasilOperasi {
  const HasilOperasi.berhasil([this.pesan]) : sukses = true;
  const HasilOperasi.gagal(this.pesan) : sukses = false;

  final bool sukses;
  final String? pesan;
}

/// Satu guru di master data. [kg] adalah identitas (kode guru di
/// jadwal cetak) — tidak bisa diubah setelah dibuat karena semua
/// entri merujuknya; yang bisa diubah adalah [nama]. Field JSON lain
/// (mis. `terverifikasi`) dipertahankan apa adanya lewat [mentah].
class GuruMaster {
  GuruMaster({
    required this.kg,
    required this.nama,
    Map<String, dynamic>? mentah,
  }) : mentah = mentah ?? <String, dynamic>{};

  final int kg;
  String nama;

  /// Field JSON asal selain kg/nama, dipertahankan saat perakitan.
  final Map<String, dynamic> mentah;

  factory GuruMaster.dariJson(Map<String, dynamic> json) {
    final sisa = Map<String, dynamic>.from(json)
      ..remove('kg')
      ..remove('nama');
    return GuruMaster(
      kg: json['kg'] as int,
      nama: json['nama'] as String,
      mentah: sisa,
    );
  }

  Map<String, dynamic> toJson() => {'kg': kg, 'nama': nama, ...mentah};
}

/// Satu mapel di master data. [kode] adalah identitas (dirujuk semua
/// entri) — tidak bisa diubah; [namaPanjang] dan [warna] bisa.
class MapelMaster {
  MapelMaster({
    required this.kode,
    required this.namaPanjang,
    required this.warna,
    Map<String, dynamic>? mentah,
  }) : mentah = mentah ?? <String, dynamic>{};

  final String kode;
  String namaPanjang;

  /// Warna aksen mapel format #RRGGBB (data dari jadwal cetak —
  /// wajib ada menurut aturan §7 nomor 5).
  String warna;

  /// Field JSON asal selain kode/namaPanjang/warna.
  final Map<String, dynamic> mentah;

  factory MapelMaster.dariJson(Map<String, dynamic> json) {
    final sisa = Map<String, dynamic>.from(json)
      ..remove('kode')
      ..remove('namaPanjang')
      ..remove('warna');
    return MapelMaster(
      kode: json['kode'] as String,
      namaPanjang: json['namaPanjang'] as String,
      warna: json['warna'] as String,
      mentah: sisa,
    );
  }

  Map<String, dynamic> toJson() => {
    'kode': kode,
    'namaPanjang': namaPanjang,
    'warna': warna,
    ...mentah,
  };
}

/// Pilihan warna bawaan untuk mapel BARU (validator §7 mewajibkan
/// warna #RRGGBB; nilai-nilai ini data aksen dari jadwal cetak,
/// bukan warna UI).
const List<String> kPaletWarnaMapel = [
  '#8FC48F',
  '#F0A868',
  '#9FC6E8',
  '#A79BC8',
  '#D9A097',
  '#B9CFE4',
  '#E8B04B',
  '#7FA8C9',
];

/// Master data: daftar guru, daftar mapel, dan relasi many-to-many
/// di antara keduanya.
///
/// Relasi adalah PANDUAN pemilih di layar plotting (yang berelasi
/// diutamakan/ditandai), BUKAN kunci: assign guru ke mapel di luar
/// relasi tetap sah. Lihat ADR-002.
class MasterData {
  MasterData({
    List<GuruMaster>? guru,
    List<MapelMaster>? mapel,
    Map<int, Set<String>>? relasi,
  }) : guru = guru ?? [],
       mapel = mapel ?? [],
       relasi = relasi ?? {};

  final List<GuruMaster> guru;
  final List<MapelMaster> mapel;

  /// kg guru → himpunan kode mapel yang diajarnya.
  final Map<int, Set<String>> relasi;

  GuruMaster? guruDariKg(int kg) {
    for (final g in guru) {
      if (g.kg == kg) return g;
    }
    return null;
  }

  MapelMaster? mapelDariKode(String kode) {
    for (final m in mapel) {
      if (m.kode == kode) return m;
    }
    return null;
  }

  /// Kode mapel yang diajar guru [kg] (kosong bila belum berelasi).
  Set<String> mapelUntukGuru(int kg) => relasi[kg] ?? const {};

  /// Semua guru yang mengajar mapel [kode] — bisa lebih dari satu
  /// (team-teaching).
  List<GuruMaster> guruUntukMapel(String kode) =>
      guru.where((g) => mapelUntukGuru(g.kg).contains(kode)).toList();

  /// Guru yang berelasi dengan mapel [kode] dulu, lalu sisanya —
  /// urutan tampil pemilih di plotting.
  List<GuruMaster> guruDiurutkanUntukMapel(String? kode) {
    if (kode == null) return List.of(guru);
    final berelasi = guruUntukMapel(kode);
    final lain = guru.where((g) => !berelasi.contains(g)).toList();
    return [...berelasi, ...lain];
  }

  /// Mapel yang berelasi dengan guru [kg] dulu, lalu sisanya.
  List<MapelMaster> mapelDiurutkanUntukGuru(int? kg) {
    if (kg == null) return List.of(mapel);
    final berelasiKode = mapelUntukGuru(kg);
    final berelasi = mapel.where((m) => berelasiKode.contains(m.kode)).toList();
    final lain = mapel.where((m) => !berelasiKode.contains(m.kode)).toList();
    return [...berelasi, ...lain];
  }

  HasilOperasi tambahGuru(int kg, String nama) {
    if (nama.trim().isEmpty) {
      return const HasilOperasi.gagal('Nama guru tidak boleh kosong.');
    }
    if (kg <= 0) {
      return const HasilOperasi.gagal('Kode guru (KG) harus angka positif.');
    }
    if (guruDariKg(kg) != null) {
      return HasilOperasi.gagal('KG $kg sudah dipakai guru lain.');
    }
    guru.add(GuruMaster(kg: kg, nama: nama.trim()));
    guru.sort((a, b) => a.kg.compareTo(b.kg));
    return const HasilOperasi.berhasil();
  }

  HasilOperasi ubahNamaGuru(int kg, String namaBaru) {
    final g = guruDariKg(kg);
    if (g == null) return HasilOperasi.gagal('Guru KG $kg tidak ditemukan.');
    if (namaBaru.trim().isEmpty) {
      return const HasilOperasi.gagal('Nama guru tidak boleh kosong.');
    }
    g.nama = namaBaru.trim();
    return const HasilOperasi.berhasil();
  }

  HasilOperasi tambahMapel(String kode, String namaPanjang, String warna) {
    final kodeBersih = kode.trim();
    if (kodeBersih.isEmpty) {
      return const HasilOperasi.gagal('Kode mapel tidak boleh kosong.');
    }
    if (namaPanjang.trim().isEmpty) {
      return const HasilOperasi.gagal('Nama panjang mapel tidak boleh kosong.');
    }
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(warna)) {
      return const HasilOperasi.gagal('Warna mapel harus format #RRGGBB.');
    }
    if (mapelDariKode(kodeBersih) != null) {
      return HasilOperasi.gagal('Kode mapel "$kodeBersih" sudah ada.');
    }
    mapel.add(
      MapelMaster(
        kode: kodeBersih,
        namaPanjang: namaPanjang.trim(),
        warna: warna,
      ),
    );
    return const HasilOperasi.berhasil();
  }

  HasilOperasi ubahMapel(String kode, {String? namaPanjang, String? warna}) {
    final m = mapelDariKode(kode);
    if (m == null) return HasilOperasi.gagal('Mapel "$kode" tidak ditemukan.');
    if (namaPanjang != null) {
      if (namaPanjang.trim().isEmpty) {
        return const HasilOperasi.gagal(
          'Nama panjang mapel tidak boleh kosong.',
        );
      }
      m.namaPanjang = namaPanjang.trim();
    }
    if (warna != null) {
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(warna)) {
        return const HasilOperasi.gagal('Warna mapel harus format #RRGGBB.');
      }
      m.warna = warna;
    }
    return const HasilOperasi.berhasil();
  }

  /// Atur ulang seluruh relasi satu guru (checklist di Tahap 1).
  void aturRelasiGuru(int kg, Set<String> kodeMapel) {
    relasi[kg] = kodeMapel.where((k) => mapelDariKode(k) != null).toSet();
  }

  /// Atur ulang seluruh pengajar satu mapel (checklist di Tahap 1).
  void aturRelasiMapel(String kode, Set<int> daftarKg) {
    for (final g in guru) {
      final himpunan = relasi.putIfAbsent(g.kg, () => <String>{});
      if (daftarKg.contains(g.kg)) {
        himpunan.add(kode);
      } else {
        himpunan.remove(kode);
      }
    }
  }

  /// Hapus guru dari master data + relasinya. Penjaga "masih
  /// terpakai di entri" ada di [DokumenEditor.hapusGuru] karena
  /// hanya dokumen yang tahu pemakaiannya.
  void hapusGuruMentah(int kg) {
    guru.removeWhere((g) => g.kg == kg);
    relasi.remove(kg);
  }

  /// Hapus mapel dari master data + semua relasinya.
  void hapusMapelMentah(String kode) {
    mapel.removeWhere((m) => m.kode == kode);
    for (final himpunan in relasi.values) {
      himpunan.remove(kode);
    }
  }

  Map<String, dynamic> toJson() => {
    'guru': guru.map((g) => g.toJson()).toList(),
    'mapel': mapel.map((m) => m.toJson()).toList(),
    'relasi': {
      for (final e in relasi.entries) '${e.key}': e.value.toList()..sort(),
    },
  };

  factory MasterData.dariJson(Map<String, dynamic> json) {
    final relasiMentah = json['relasi'] as Map<String, dynamic>? ?? const {};
    return MasterData(
      guru: (json['guru'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GuruMaster.dariJson)
          .toList(),
      mapel: (json['mapel'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MapelMaster.dariJson)
          .toList(),
      relasi: {
        for (final e in relasiMentah.entries)
          int.parse(e.key): (e.value as List).map((v) => v as String).toSet(),
      },
    );
  }
}

/// Isi satu sel jadwal di editor: pasangan mapel + guru.
/// null (bukan EntriSlot) berarti slot kosong.
class EntriSlot {
  const EntriSlot({required this.kodeMapel, required this.kg});

  final String kodeMapel;
  final int kg;

  Map<String, dynamic> toJson() => {'mapel': kodeMapel, 'kg': kg};

  factory EntriSlot.dariJson(Map<String, dynamic> json) =>
      EntriSlot(kodeMapel: json['mapel'] as String, kg: json['kg'] as int);

  @override
  bool operator ==(Object other) =>
      other is EntriSlot && other.kodeMapel == kodeMapel && other.kg == kg;

  @override
  int get hashCode => Object.hash(kodeMapel, kg);

  @override
  String toString() => 'EntriSlot($kodeMapel, KG $kg)';
}

/// Templat satu slot dari dokumen asal (jam + tipe + label).
/// Templat TIDAK diedit di R2b — struktur jam datang dari berkas.
class SlotTemplat {
  const SlotTemplat({
    required this.mulai,
    required this.selesai,
    required this.tipe,
    this.label,
  });

  final String mulai;
  final String selesai;
  final String tipe;
  final String? label;

  bool get adalahPelajaran => tipe == 'pelajaran';

  factory SlotTemplat.dariJson(Map<String, dynamic> json) => SlotTemplat(
    mulai: json['mulai'] as String,
    selesai: json['selesai'] as String,
    tipe: json['tipe'] as String,
    label: json['label'] as String?,
  );
}

/// Pratinjau assign rentang: slot mana saja yang akan terisi,
/// apakah ada yang menimpa isi lama, dan apakah rentang terpotong
/// (mentok slot non-pelajaran / akhir hari).
class PratinjauRentang {
  const PratinjauRentang({
    required this.indeksSlot,
    required this.adaTimpa,
    required this.mentok,
  });

  /// Indeks slot (dalam hari itu) yang akan terisi, berurutan.
  final List<int> indeksSlot;

  /// True bila ada target yang sudah terisi (perlu konfirmasi).
  final bool adaTimpa;

  /// True bila jumlah target < yang diminta (terhalang slot
  /// non-pelajaran atau akhir hari).
  final bool mentok;
}

/// Ringkasan keterisian satu hari untuk kelas aktif.
class RingkasanHariEditor {
  const RingkasanHariEditor({
    required this.namaHari,
    required this.terisi,
    required this.totalPelajaran,
  });

  final String namaHari;
  final int terisi;
  final int totalPelajaran;

  int get kosong => totalPelajaran - terisi;
}

/// Salinan dalam (deep copy) lewat JSON — dokumen jadwal murni
/// data JSON sehingga ini aman dan sederhana.
Map<String, dynamic> _salinDokumen(Map<String, dynamic> asal) =>
    jsonDecode(jsonEncode(asal)) as Map<String, dynamic>;

/// Satu sesi pengeditan jadwal.
///
/// Memegang dokumen asal utuh (untuk mempertahankan kelas lain +
/// field ekstra apa adanya), master data bersama, templat slot per
/// hari, dan entri hasil edit per kelas yang pernah disentuh sesi
/// ini. Berpindah kelas mempertahankan master data DAN edit kelas
/// sebelumnya.
class DokumenEditor {
  DokumenEditor._({
    required this.dokumenAsal,
    required this.labelSumber,
    required this.master,
    required this.daftarKelas,
    required this.templatHari,
    required this.kelasAktif,
    required this._entriPerKelas,
  });

  /// Dokumen asal (sudah disalin dalam) — basis perakitan.
  final Map<String, dynamic> dokumenAsal;

  /// Label asal sesi: nama berkas atau "Jadwal bawaan SMKN 1 Ukui".
  final String labelSumber;

  final MasterData master;

  /// Daftar kelas dari dokumen: pasangan (id, nama) terurut urutan.
  final List<({String id, String nama})> daftarKelas;

  /// Templat slot per hari, sejajar dengan `hari` di dokumen asal.
  final List<({String nama, List<SlotTemplat> slots})> templatHari;

  /// Kelas yang sedang diedit.
  String kelasAktif;

  /// Entri hasil edit: kelasId → per indeks hari → per indeks slot.
  final Map<String, List<List<EntriSlot?>>> _entriPerKelas;

  /// Kelas yang entrinya sudah dimuat ke sesi (pernah diedit/dilihat).
  Iterable<String> get kelasTersentuh => _entriPerKelas.keys;

  /// Buat sesi dari dokumen jadwal utuh (berkas / bawaan).
  /// Relasi master data DISIMPULKAN dari pemakaian nyata di dokumen
  /// (semua kelas): pasangan (kg, mapel) yang muncul di entri mana
  /// pun menjadi relasi awal — titik awal yang masuk akal untuk
  /// diedit lebih lanjut di Tahap 1.
  factory DokumenEditor.dariDokumen(
    Map<String, dynamic> dokumen, {
    required String labelSumber,
    String? kelasAwal,
  }) {
    final salinan = _salinDokumen(dokumen);
    final master = MasterData(
      guru: (salinan['guru'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GuruMaster.dariJson)
          .toList(),
      mapel: (salinan['mapel'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MapelMaster.dariJson)
          .toList(),
    );
    final kelas = (salinan['kelas'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((k) => (id: k['id'] as String, nama: k['nama'] as String))
        .toList();
    final hariMentah = (salinan['hari'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final templat = hariMentah
        .map(
          (h) => (
            nama: h['nama'] as String,
            slots: (h['slots'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(SlotTemplat.dariJson)
                .toList(),
          ),
        )
        .toList();

    // Simpulkan relasi dari seluruh entri dokumen.
    final relasi = <int, Set<String>>{};
    for (final h in hariMentah) {
      for (final s in (h['slots'] as List? ?? const [])) {
        if (s is! Map<String, dynamic>) continue;
        final entri = s['entri'];
        if (entri is! Map<String, dynamic>) continue;
        for (final nilai in entri.values) {
          if (nilai is Map<String, dynamic> &&
              nilai['kg'] is int &&
              nilai['mapel'] is String) {
            relasi
                .putIfAbsent(nilai['kg'] as int, () => <String>{})
                .add(nilai['mapel'] as String);
          }
        }
      }
    }
    master.relasi.addAll(relasi);

    final editor = DokumenEditor._(
      dokumenAsal: salinan,
      labelSumber: labelSumber,
      master: master,
      daftarKelas: kelas,
      templatHari: templat,
      kelasAktif: kelasAwal ?? (kelas.isEmpty ? '' : kelas.first.id),
      entriPerKelas: {},
    );
    if (editor.kelasAktif.isNotEmpty) editor._muatKelas(editor.kelasAktif);
    return editor;
  }

  /// Muat entri satu kelas dari dokumen asal ke sesi (sekali saja;
  /// panggilan berikutnya mempertahankan hasil edit sesi).
  void _muatKelas(String kelasId) {
    if (_entriPerKelas.containsKey(kelasId)) return;
    final perHari = <List<EntriSlot?>>[];
    final hariMentah = (dokumenAsal['hari'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    for (var i = 0; i < templatHari.length; i++) {
      final slotsMentah = i < hariMentah.length
          ? (hariMentah[i]['slots'] as List? ?? const [])
          : const [];
      final baris = <EntriSlot?>[];
      for (var j = 0; j < templatHari[i].slots.length; j++) {
        EntriSlot? entri;
        if (j < slotsMentah.length && slotsMentah[j] is Map<String, dynamic>) {
          final entriMentah = (slotsMentah[j] as Map<String, dynamic>)['entri'];
          if (entriMentah is Map<String, dynamic>) {
            final nilai = entriMentah[kelasId];
            if (nilai is Map<String, dynamic> &&
                nilai['mapel'] is String &&
                nilai['kg'] is int) {
              entri = EntriSlot.dariJson(nilai);
            }
          }
        }
        baris.add(entri);
      }
      perHari.add(baris);
    }
    _entriPerKelas[kelasId] = perHari;
  }

  /// Pindah kelas aktif. Master data bersama; edit kelas lain
  /// dipertahankan di sesi.
  void pilihKelas(String kelasId) {
    if (!daftarKelas.any((k) => k.id == kelasId)) return;
    kelasAktif = kelasId;
    _muatKelas(kelasId);
  }

  /// Entri kelas [kelasId] pada hari [indeksHari], slot [indeksSlot];
  /// null = kosong / bukan slot pelajaran.
  EntriSlot? entriDi(String kelasId, int indeksHari, int indeksSlot) {
    _muatKelas(kelasId);
    return _entriPerKelas[kelasId]![indeksHari][indeksSlot];
  }

  EntriSlot? entriAktif(int indeksHari, int indeksSlot) =>
      entriDi(kelasAktif, indeksHari, indeksSlot);

  bool _slotBisaDiisi(int indeksHari, int indeksSlot) =>
      indeksHari >= 0 &&
      indeksHari < templatHari.length &&
      indeksSlot >= 0 &&
      indeksSlot < templatHari[indeksHari].slots.length &&
      templatHari[indeksHari].slots[indeksSlot].adalahPelajaran;

  /// Assign satu slot kelas aktif.
  HasilOperasi assignSlot(
    int indeksHari,
    int indeksSlot, {
    required String kodeMapel,
    required int kg,
  }) {
    if (!_slotBisaDiisi(indeksHari, indeksSlot)) {
      return const HasilOperasi.gagal('Slot itu bukan slot pelajaran.');
    }
    if (master.mapelDariKode(kodeMapel) == null) {
      return HasilOperasi.gagal('Mapel "$kodeMapel" tidak ada di master data.');
    }
    if (master.guruDariKg(kg) == null) {
      return HasilOperasi.gagal('Guru KG $kg tidak ada di master data.');
    }
    _muatKelas(kelasAktif);
    _entriPerKelas[kelasAktif]![indeksHari][indeksSlot] = EntriSlot(
      kodeMapel: kodeMapel,
      kg: kg,
    );
    return const HasilOperasi.berhasil();
  }

  /// Hitung target assign rentang TANPA mengubah apa pun: mulai
  /// dari slot awal, kumpulkan slot PELAJARAN berurutan; berhenti
  /// di slot non-pelajaran pertama atau akhir hari (rentang tidak
  /// melompati istirahat/isoma — blok produktif berhenti di jeda).
  PratinjauRentang pratinjauRentang(
    int indeksHari,
    int indeksSlotAwal,
    int jumlahJam,
  ) {
    final target = <int>[];
    if (indeksHari < 0 || indeksHari >= templatHari.length) {
      return const PratinjauRentang(
        indeksSlot: [],
        adaTimpa: false,
        mentok: true,
      );
    }
    final slots = templatHari[indeksHari].slots;
    var i = indeksSlotAwal;
    while (i < slots.length && target.length < jumlahJam) {
      if (!slots[i].adalahPelajaran) break;
      target.add(i);
      i++;
    }
    _muatKelas(kelasAktif);
    final baris = _entriPerKelas[kelasAktif]![indeksHari];
    return PratinjauRentang(
      indeksSlot: target,
      adaTimpa: target.any((idx) => baris[idx] != null),
      mentok: target.length < jumlahJam,
    );
  }

  /// Assign rentang: mapel+guru yang sama ke slot-slot target
  /// [pratinjauRentang]. Menimpa isi lama hanya bila [izinkanTimpa]
  /// — UI wajib konfirmasi dulu saat pratinjau menunjukkan timpa.
  HasilOperasi assignRentang(
    int indeksHari,
    int indeksSlotAwal, {
    required String kodeMapel,
    required int kg,
    required int jumlahJam,
    bool izinkanTimpa = false,
  }) {
    if (jumlahJam < 1) {
      return const HasilOperasi.gagal('Rentang minimal 1 jam.');
    }
    if (!_slotBisaDiisi(indeksHari, indeksSlotAwal)) {
      return const HasilOperasi.gagal('Slot awal bukan slot pelajaran.');
    }
    if (master.mapelDariKode(kodeMapel) == null) {
      return HasilOperasi.gagal('Mapel "$kodeMapel" tidak ada di master data.');
    }
    if (master.guruDariKg(kg) == null) {
      return HasilOperasi.gagal('Guru KG $kg tidak ada di master data.');
    }
    final pratinjau = pratinjauRentang(indeksHari, indeksSlotAwal, jumlahJam);
    if (pratinjau.adaTimpa && !izinkanTimpa) {
      return const HasilOperasi.gagal(
        'Sebagian slot rentang sudah terisi — konfirmasi penimpaan dulu.',
      );
    }
    _muatKelas(kelasAktif);
    final baris = _entriPerKelas[kelasAktif]![indeksHari];
    for (final idx in pratinjau.indeksSlot) {
      baris[idx] = EntriSlot(kodeMapel: kodeMapel, kg: kg);
    }
    return HasilOperasi.berhasil(
      pratinjau.mentok
          ? 'Terisi ${pratinjau.indeksSlot.length} jam (rentang terpotong '
                'jeda/akhir hari).'
          : 'Terisi ${pratinjau.indeksSlot.length} jam.',
    );
  }

  /// Kosongkan satu slot kelas aktif.
  HasilOperasi kosongkanSlot(int indeksHari, int indeksSlot) {
    if (!_slotBisaDiisi(indeksHari, indeksSlot)) {
      return const HasilOperasi.gagal('Slot itu bukan slot pelajaran.');
    }
    _muatKelas(kelasAktif);
    _entriPerKelas[kelasAktif]![indeksHari][indeksSlot] = null;
    return const HasilOperasi.berhasil();
  }

  /// Semua KG yang sedang dipakai entri mana pun di dokumen hasil
  /// edit (kelas tersentuh memakai entri sesi; kelas lain memakai
  /// dokumen asal).
  Set<int> kgTerpakai() {
    final hasil = <int>{};
    for (final kelas in daftarKelas) {
      for (var h = 0; h < templatHari.length; h++) {
        for (var s = 0; s < templatHari[h].slots.length; s++) {
          final e = entriDi(kelas.id, h, s);
          if (e != null) hasil.add(e.kg);
        }
      }
    }
    return hasil;
  }

  /// Semua kode mapel yang sedang dipakai entri mana pun.
  Set<String> mapelTerpakai() {
    final hasil = <String>{};
    for (final kelas in daftarKelas) {
      for (var h = 0; h < templatHari.length; h++) {
        for (var s = 0; s < templatHari[h].slots.length; s++) {
          final e = entriDi(kelas.id, h, s);
          if (e != null) hasil.add(e.kodeMapel);
        }
      }
    }
    return hasil;
  }

  /// Hapus guru — DITOLAK bila KG-nya masih dipakai entri mana pun
  /// (kelas mana pun), karena dokumen rakitan akan gagal §7.
  HasilOperasi hapusGuru(int kg) {
    if (master.guruDariKg(kg) == null) {
      return HasilOperasi.gagal('Guru KG $kg tidak ditemukan.');
    }
    if (kgTerpakai().contains(kg)) {
      return HasilOperasi.gagal(
        'KG $kg masih dipakai di jadwal (kelas mana pun). Kosongkan '
        'atau ganti dulu semua slotnya sebelum menghapus guru ini.',
      );
    }
    master.hapusGuruMentah(kg);
    return const HasilOperasi.berhasil();
  }

  /// Hapus mapel — DITOLAK bila kodenya masih dipakai entri mana pun.
  HasilOperasi hapusMapel(String kode) {
    if (master.mapelDariKode(kode) == null) {
      return HasilOperasi.gagal('Mapel "$kode" tidak ditemukan.');
    }
    if (mapelTerpakai().contains(kode)) {
      return HasilOperasi.gagal(
        'Mapel "$kode" masih dipakai di jadwal (kelas mana pun). '
        'Kosongkan atau ganti dulu semua slotnya sebelum menghapus.',
      );
    }
    master.hapusMapelMentah(kode);
    return const HasilOperasi.berhasil();
  }

  /// Ringkasan keterisian per hari untuk [kelasId].
  List<RingkasanHariEditor> ringkasanKelas(String kelasId) {
    _muatKelas(kelasId);
    return [
      for (var h = 0; h < templatHari.length; h++)
        RingkasanHariEditor(
          namaHari: templatHari[h].nama,
          terisi: [
            for (var s = 0; s < templatHari[h].slots.length; s++)
              if (templatHari[h].slots[s].adalahPelajaran &&
                  _entriPerKelas[kelasId]![h][s] != null)
                s,
          ].length,
          totalPelajaran: templatHari[h].slots
              .where((s) => s.adalahPelajaran)
              .length,
        ),
    ];
  }

  /// Rakit dokumen jadwal utuh siap validasi §7 + kirim:
  /// - meta & struktur hari/slot & kelas: dari dokumen asal apa adanya;
  /// - guru & mapel: dari master data hasil edit;
  /// - entri: kelas tersentuh diganti dari sesi (slot kosong =
  ///   entri kelas itu dihilangkan); kelas lain apa adanya.
  Map<String, dynamic> rakitDokumen() {
    final hasil = _salinDokumen(dokumenAsal);
    hasil['guru'] = master.guru.map((g) => g.toJson()).toList();
    hasil['mapel'] = master.mapel.map((m) => m.toJson()).toList();
    final hariHasil = (hasil['hari'] as List).cast<Map<String, dynamic>>();
    for (final kelasId in _entriPerKelas.keys) {
      for (var h = 0; h < templatHari.length && h < hariHasil.length; h++) {
        final slotsHasil = (hariHasil[h]['slots'] as List)
            .cast<Map<String, dynamic>>();
        for (
          var s = 0;
          s < templatHari[h].slots.length && s < slotsHasil.length;
          s++
        ) {
          if (!templatHari[h].slots[s].adalahPelajaran) continue;
          final entri = _entriPerKelas[kelasId]![h][s];
          final entriMentah = slotsHasil[s]['entri'];
          final Map<String, dynamic> wadah = entriMentah is Map<String, dynamic>
              ? entriMentah
              : <String, dynamic>{};
          if (entri == null) {
            wadah.remove(kelasId);
          } else {
            wadah[kelasId] = entri.toJson();
          }
          slotsHasil[s]['entri'] = wadah;
        }
      }
    }
    return hasil;
  }

  // --- Serialisasi draf -------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'versi': 1,
    'labelSumber': labelSumber,
    'dokumenAsal': dokumenAsal,
    'master': master.toJson(),
    'kelasAktif': kelasAktif,
    'entriPerKelas': {
      for (final e in _entriPerKelas.entries)
        e.key: [
          for (final baris in e.value)
            [for (final entri in baris) entri?.toJson()],
        ],
    },
  };

  factory DokumenEditor.dariJsonDraf(Map<String, dynamic> json) {
    // Bangun ulang lewat dokumen asal (templat & daftar kelas sama),
    // lalu timpa master + entri dengan isi draf.
    final editor = DokumenEditor.dariDokumen(
      (json['dokumenAsal'] as Map).cast<String, dynamic>(),
      labelSumber: json['labelSumber'] as String? ?? 'Draf',
      kelasAwal: json['kelasAktif'] as String?,
    );
    final masterDraf = MasterData.dariJson(
      (json['master'] as Map).cast<String, dynamic>(),
    );
    editor.master.guru
      ..clear()
      ..addAll(masterDraf.guru);
    editor.master.mapel
      ..clear()
      ..addAll(masterDraf.mapel);
    editor.master.relasi
      ..clear()
      ..addAll(masterDraf.relasi);
    final entriMentah =
        (json['entriPerKelas'] as Map?)?.cast<String, dynamic>() ?? const {};
    editor._entriPerKelas.clear();
    for (final e in entriMentah.entries) {
      editor._entriPerKelas[e.key] = [
        for (final baris in (e.value as List))
          [
            for (final nilai in (baris as List))
              nilai == null
                  ? null
                  : EntriSlot.dariJson((nilai as Map).cast<String, dynamic>()),
          ],
      ];
    }
    if (!editor._entriPerKelas.containsKey(editor.kelasAktif)) {
      editor._muatKelas(editor.kelasAktif);
    }
    return editor;
  }
}
