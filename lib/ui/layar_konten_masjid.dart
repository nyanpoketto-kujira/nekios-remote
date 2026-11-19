import 'package:flutter/material.dart';

import '../state/store_masjid.dart';
import 'layar_banner_masjid.dart';
import 'layar_gambar_khusus.dart';
import 'layar_gambar_latar.dart';
import 'layar_kas_masjid.dart';
import 'layar_logo_masjid.dart';
import 'layar_teks_berjalan.dart';

/// Tab Konten shell masjid: kerangka enam sub-tab editor —
/// Teks Berjalan, Banner, Kas, Gambar Khusus, Gambar Latar,
/// Logo — mengikuti susunan Konten mobile_remote.
///
/// Keenam editor terisi bertahap: Teks Berjalan + Banner di
/// A2b, Kas di A2c, Gambar Khusus + Gambar Latar + Logo di
/// A2d. Urutan sub-tab tidak berubah antar tahap supaya
/// kebiasaan pengguna tidak bergeser.
class LayarKontenMasjid extends StatelessWidget {
  const LayarKontenMasjid({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
    this.pemilihTanggalKas,
  });

  final MasjidStore store;

  /// Diteruskan ke editor banner, gambar khusus, gambar latar,
  /// dan logo (lihat [PemilihGambarMentah]); null = pemilih
  /// galeri bawaan.
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
                LayarGambarKhusus(
                  store: store,
                  pemilihGambarMentah: pemilihGambarMentah,
                ),
                LayarGambarLatar(
                  store: store,
                  pemilihGambarMentah: pemilihGambarMentah,
                ),
                LayarLogoMasjid(
                  store: store,
                  pemilihGambarMentah: pemilihGambarMentah,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
