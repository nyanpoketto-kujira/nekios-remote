import 'package:flutter/material.dart';

import '../state/store_masjid.dart';
import 'layar_banner_masjid.dart';
import 'layar_kas_masjid.dart';
import 'layar_teks_berjalan.dart';
import 'widget_bersama.dart';

/// Tab Konten shell masjid: kerangka enam sub-tab editor —
/// Teks Berjalan, Banner, Kas, Gambar Khusus, Gambar Latar,
/// Logo — mengikuti susunan Konten mobile_remote.
///
/// Teks Berjalan + Banner terisi di A2b, Kas di A2c; gambar &
/// logo menyusul di A2d dan sementara menampilkan penjelasan
/// jujur lewat [LayarTahapBerikut]. Urutan sub-tab tidak
/// berubah antar tahap supaya kebiasaan pengguna tidak
/// bergeser.
class LayarKontenMasjid extends StatelessWidget {
  const LayarKontenMasjid({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
    this.pemilihTanggalKas,
  });

  final MasjidStore store;

  /// Diteruskan ke editor banner (lihat [PemilihGambarMentah]);
  /// null = pemilih galeri bawaan.
  final PemilihGambarMentah? pemilihGambarMentah;

  /// Diteruskan ke editor kas (lihat [PemilihTanggalKas]);
  /// null = pemilih tanggal bawaan.
  final PemilihTanggalKas? pemilihTanggalKas;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Teks Berjalan'),
              Tab(text: 'Banner'),
              Tab(text: 'Kas'),
              Tab(text: 'Gambar Khusus'),
              Tab(text: 'Gambar Latar'),
              Tab(text: 'Logo'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                LayarTeksBerjalan(store: store),
                LayarBannerMasjid(
                  store: store,
                  pemilihGambarMentah: pemilihGambarMentah,
                ),
                LayarKasMasjid(
                  store: store,
                  pemilihTanggal: pemilihTanggalKas,
                ),
                const LayarTahapBerikut(
                  judul: 'Gambar khusus',
                  keterangan:
                      'Fitur untuk mengatur gambar yang tampil '
                      'bergantian di sisi layar TV dari aplikasi '
                      'ini sedang disiapkan.',
                ),
                const LayarTahapBerikut(
                  judul: 'Gambar latar',
                  keterangan:
                      'Fitur untuk mengganti gambar latar layar TV '
                      'dan mengatur pergantiannya dari aplikasi ini '
                      'sedang disiapkan.',
                ),
                const LayarTahapBerikut(
                  judul: 'Logo masjid',
                  keterangan:
                      'Fitur untuk memasang atau mengganti logo '
                      'masjid di layar TV dari aplikasi ini sedang '
                      'disiapkan.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
