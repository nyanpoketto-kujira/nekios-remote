# Keputusan Arsitektur (ADR) — nekios-remote

## ADR-001: Arsitektur aplikasi & kontrak balasan display (R2a, 2026-11-18)

**Konteks.** nekios-remote adalah pengendali HP untuk nekios-school.
Sisi display (R1, PR nekios-school #8) sudah jadi lebih dulu dan
menetapkan kontrak balasan: perintah sukses → `ack` (payload
`ofType`) lalu satu `state.snapshot` susulan; perintah gagal →
`error` dengan `payload.message` Bahasa Indonesia. Enam fitur
terkunci nyanpo: koneksi (IP manual + auto-save IP terakhir, port
tetap 8920, tanpa PIN), cermin status, mading, simulasi jam
(terutama *lompat ke bel berikutnya*), logo, dan kirim jadwal.

**Keputusan.**

1. **Satu store pusat.** `RemoteStore` (ChangeNotifier) memegang
   daftar display, keadaan koneksi, dan snapshot terakhir. UI hanya
   membaca store lewat `ListenableBuilder`; tidak ada logika jaringan
   di widget.
2. **Perintah menunggu balasan.** Metode `kirimPerintah` menunggu
   `ack`/`error` yang cocok (dipetakan lewat `ofType`) dengan
   timeout 6 detik, mengembalikan `HasilPerintah`. UI menampilkan
   hasil jujur dari display, bukan sekadar "terkirim". `ping`
   dikecualikan (tidak ditunggu; snapshotnya tiba sebagai paket
   biasa) dan dikirim berkala tiap 15 detik selama terhubung
   sebagai penyegar snapshot + deteksi putus.
3. **Detak lokal di antara snapshot.** Jam efektif dan hitung
   mundur bel tidak menunggu snapshot baru: snapshot menyimpan
   waktu terima lokal, tampilan menambahkan selisih waktu nyata
   (jam display berjalan secepat jam nyata; simulasi hanya
   menggeser offset). Lihat `SnapshotDisplay.jamEfektifPada`.
4. **Lompat ke bel berikutnya = `clock.simulate {at}`** dengan
   `at` diambil dari `belBerikutnya` snapshot — remote tidak
   menghitung jadwal sendiri. Tombol nonaktif bila snapshot tidak
   punya bel berikutnya.
5. **Validasi jadwal digandakan di remote.** Validator §7 ditulis
   ulang atas JSON mentah (remote tidak memuat model nekios-school)
   dengan semantik yang sama seperti `validasiJadwal` display,
   ditambah pemeriksaan struktur (field hilang/tipe salah/format
   jam) karena berkas rusak harus tertolak sebelum dikirim, dengan
   pesan yang layak tampil. Display tetap memvalidasi ulang —
   remote bukan garis pertahanan terakhir.
6. **Logo diperkecil di remote** ke sisi terpanjang maks 512px
   (pola masjid-you) sebelum base64: PNG bila berkanal alfa, JPEG
   q88 bila tidak. Paket tetap ringan; header TV menampilkannya
   kecil.
7. **Penyimpanan lokal** memakai `shared_preferences`: daftar
   display (JSON) + IP terakhir (auto-save setiap upaya sambung).
8. **Tema Material You**: `ColorScheme.fromSeed` dengan seed
   0xFF006A60 — sama persis dengan masjid-you & nekios-school —
   mode terang & gelap mengikuti sistem. Tidak ada warna hex
   hardcode di UI selain seed.
9. **`nekios_core` via git HTTPS** (ref `main`), meniru pola
   nekios-school; repo core publik sehingga CI resolve tanpa
   kredensial.

**Konsekuensi.** Remote bergantung pada kontrak snapshot R1; bila
bentuk snapshot berubah, `SnapshotDisplay.fromPayload` (parser
toleran: field hilang jatuh ke nilai aman) dan test kontrak di
`test/snapshot_test.dart` adalah titik sesuaikan pertama. Reconnect
otomatis sengaja belum dibuat (mengikuti TODO di `NekiosKlien`
nekios_core) — putus terdeteksi dari ping berkala dan pengguna
menyambung ulang dengan satu ketukan dari daftar tersimpan.
