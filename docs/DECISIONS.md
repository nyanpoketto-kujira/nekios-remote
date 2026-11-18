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

## ADR-002: Editor Jadwal visual dua tahap (R2b, 2026-11-18)

**Konteks.** Konsep nyanpo: pembuatan jadwal di HP harus senyaman
mungkin, BUKAN tabel Excel. Dua tahap: (1) Master Data guru & mapel
dengan relasi bebas; (2) Plotting tap-to-assign per hari dengan
opsi rentang jam untuk mapel produktif khas SMK. Hasil editor
adalah dokumen JSON skema nekios-school yang sama dan wajib lolos
validator §7 sebelum dikirim lewat alur R2a.

**Keputusan.**

1. **Relasi many-to-many adalah panduan, bukan kunci.** Master
   data memegang relasi guru↔mapel sebagai himpunan pasangan
   (satu guru banyak mapel; satu mapel banyak guru/team-teaching).
   Relasi hanya memengaruhi URUTAN dan tanda bintang di pemilih
   plotting; assign guru di luar relasi tetap sah — jadwal nyata
   penuh pengecualian dan editor tidak boleh menghalangi. Relasi
   awal sesi DISIMPULKAN dari pemakaian nyata di dokumen yang
   dimuat, lalu bebas diubah di Tahap 1.
2. **Satu kelas per sesi aktif, master data bersama.** Sesi
   memegang dokumen asal utuh + entri hasil edit per kelas yang
   disentuh. Berpindah kelas mempertahankan master data DAN edit
   kelas sebelumnya. Perakitan menimpa hanya entri kelas
   tersentuh; kelas lain, meta, struktur slot, dan field ekstra
   (mis. `terverifikasi`, `statusDecode`) dipertahankan apa
   adanya dari dokumen asal.
3. **Slot kosong = entri dihilangkan, validator yang menjaga.**
   Skema jadwal tidak mengenal entri null dan §7 mewajibkan tepat
   satu entri per kelas di slot pelajaran. Jadi entri kosong di
   editor dihilangkan dari dokumen rakitan; selama masih ada slot
   kosong di kelas tersentuh, validator §7 menolak dan layar
   Tinjau menampilkan hitungan slot kosong per hari. Tidak ada
   representasi "kosong" baru yang diciptakan.
4. **Hapus master data dijaga pemakaian global.** Guru/mapel
   yang masih dipakai entri kelas MANA PUN (bukan hanya kelas
   aktif) tidak bisa dihapus — pesannya menjelaskan alasannya.
   Identitas guru (KG) dan mapel (kode) tidak bisa diubah setelah
   dibuat karena semua entri merujuknya; yang bisa diubah nama,
   nama panjang, dan warna.
5. **Rentang berhenti di jeda.** Assign rentang mengisi slot
   pelajaran berurutan mulai dari slot yang diketuk dan BERHENTI
   di slot non-pelajaran pertama atau akhir hari (blok produktif
   tidak melompati istirahat/isoma). Menimpa isi lama butuh
   konfirmasi eksplisit; pratinjau rentang (target, ada timpa,
   mentok) dihitung murni di domain sebelum UI bertanya.
6. **Draf lokal per kelas, tersimpan otomatis.** Setiap perubahan
   sesi disimpan ke `shared_preferences` (kunci per kelas aktif,
   isi = seluruh sesi). Layar awal editor menawarkan "Lanjutkan
   draf" vs mulai ulang dari titik awal (berkas JSON atau jadwal
   bawaan). Mengedit tidak butuh koneksi; koneksi hanya perlu di
   langkah kirim.
7. **Jadwal bawaan disalin sebagai aset.** Titik awal "jadwal
   bawaan SMKN 1 Ukui" adalah salinan persis
   `assets/jadwal-tkj.json` nekios-school menjadi
   `assets/jadwal-bawaan.json` di aplikasi ini. Bila jadwal induk
   berubah di nekios-school, aset ini perlu disalin ulang manual
   (dicatat di README).
8. **Struktur jam tidak diedit.** Templat slot (jam, tipe, label)
   datang dari dokumen asal dan tidak diubah di R2b — editor
   hanya mengisi entri pelajaran. Mengubah struktur jam adalah
   pekerjaan berkas JSON / fase berikutnya bila dibutuhkan.

**Konsekuensi.** `DokumenEditor` (domain murni) adalah satu-satunya
tempat operasi edit; UI Tahap 1/Tahap 2 hanya memanggilnya dan
menyimpan draf lewat callback perubahan. Alur kirim R2a dipakai
ulang apa adanya dari layar Tinjau (rakit → validasi §7 →
ringkasan per hari → konfirmasi → `schedule.replace`).

## ADR-003: Rute A — dialek masjid-you di remote pusat (tahap A1, 2026-11-18)

**Konteks.** nekios-remote menjadi SATU remote pusat untuk dua
display: nekios-school (protokol nekios-core, WebSocket 8920) dan
tv_display masjid-you. Nyanpo mengunci **Rute A**: TV masjid TIDAK
diubah sama sekali (zero touch, anti-regresi untuk DKM) — remote
yang belajar protokol masjid yang sudah ada. Audit M0
(`audit-masjid-you-sync.md`) memetakan protokol itu: envelope
`SyncPacket {action, payload}` tanpa versi/ack, WebSocket shelf
port 8080 tanpa autentikasi, dan Bluetooth Classic RFCOMM
(plugin kustom `bluetooth_sync`, UUID tetap, framing 4-byte
big-endian + JSON, handshake PIN 4 digit + nonce, chunking 32 KB
untuk payload ≥ 64 KB).

**Keputusan.**

1. **Dialek terpisah di `lib/masjid/`.** Model wire masjid
   (MosqueConfig, RunningTextMessage, MediaBanner, KasTransaction,
   SpecialImage, BackgroundImage, StateSnapshot, PrayerType/Phase)
   dan codec SyncPacket diport PERSIS dari `shared_models`
   masjid-you — paritas `toMap`/`fromMap` adalah kontrak, dibuktikan
   fixture yang dibangun dari serialisasi shared_models asli
   (round-trip identik JSON). Dialek tidak bercampur dengan model
   nekios-core; `MasjidStore` terpisah dari `RemoteStore`. Payload
   `stateUpdate` yang di sumber tidak berkelas dimodelkan sebagai
   `StatusTvMasjid` di sisi dialek.
2. **Kontrak fire-and-forget diakui, bukan dilawan.** Protokol
   masjid tidak punya ack/request-id. Perintah di `MasjidStore`
   menyelesaikan `HasilPerintah` dari BUKTI SUSULAN yang disiarkan
   TV: perintah data menunggu `stateSnapshot` berikutnya, perintah
   kontrol menunggu `stateUpdate`/`stateSnapshot` berikutnya;
   timeout (bawaan 6 detik) = gagal lokal dengan pesan jujur.
   Satu perintah menunggu bukti pada satu waktu (v1, sama seperti
   store sekolah). `triggerBeep` yang mati di sumber TIDAK dikirim
   remote (keputusan hidupkan/hapus menunggu nyanpo).
3. **Bluetooth: plugin lokal, framing di Dart.** masjid-you
   memakai plugin kustom (bukan flutter_bluetooth_serial), jadi
   dibuat plugin lokal `packages/bluetooth_rfcomm`: port separuh
   KLIEN `bluetooth_sync` (kontrak channel, socket bonded →
   fallback insecure refleksi, watchdog 15 detik, alur izin sama),
   TANPA sisi host dan TANPA framing native — plugin hanya pipa
   byte mentah. Framing 4-byte, handshake auth
   (`authChallenge{nonce}` → `authResponse{pin, nonce}`; paket data
   sebelum `authSuccess` dibuang), dan chunking
   (`chunkedData`, ambang 64 KB, potongan 32 KB, satu transfer
   aktif) hidup di Dart murni agar teruji unit; byte di kabel
   identik dengan implementasi masjid-you. Kompresi gambar jalur
   BT diport dari mobile_remote (latar maks 1920px JPEG q80 —
   menghormati opsi tanpa-kompresi; logo maks 512px, alpha→PNG).
   Jalur WebSocket selalu mengirim gambar asli tanpa chunking.
4. **Bluetooth Android saja.** Plugin hanya terdaftar di Android;
   di platform lain transport gagal dengan pesan manusiawi.
   Desktop (Windows/Linux) memang boleh terbatas — keputusan
   transport nyanpo: BT wajib untuk kedua display, target utama
   Android.
5. **Display bertipe.** `DisplayTersimpan` kini membawa
   `tipe` (sekolah|masjid), `transport` (wifi|bluetooth), alamat &
   nama Bluetooth, dan PIN BT (disimpan lokal via pola
   shared_preferences yang ada; TIDAK pernah masuk log). Entri
   lama tanpa field tipe dibaca sebagai sekolah — daftar lama
   pengguna tidak berubah perilaku. PIN berganti tiap TV menyala
   ulang (perilaku sumber); pesan gagal auth mengarahkan pengguna
   memperbaruinya lewat dialog Ubah.
6. **Shell mengikuti tipe display aktif.** Tab Koneksi dipakai
   bersama (daftar satu, ketuk menyambung menurut tipe); shell
   Beranda dkk. mengikuti sambungan yang paling baru mulai
   menyambung. Tahap A1: Beranda masjid (cermin fase + hitung
   mundur lokal, kas, status hasData) + aksi cepat fase
   (skipAdhan/startIqomah/startShalat/finishShalat — wajib dialog
   konfirmasi) dan mode (setMuted/setStandby). Tab Konten/
   Pengaturan/Tes masjid adalah placeholder berlabel tahap
   berikutnya — editor TIDAK dibangun tahap ini.
7. **Bootstrap hasData=false disiapkan, belum diaktifkan.**
   Mekanisme mobile_remote (TV kosong menerima satu dorongan
   `updateConfig` — payload = map config itu sendiri —,
   `updateRunningText`, `updateBanners`, `updateKas`,
   `updateSideImages`, `updateBackgroundImages` per koneksi)
   diimplementasikan di `MasjidStore` lewat penyedia data
   terinjeksi dan diuji dengan penyedia palsu. Bawaan tahap A1:
   tanpa penyedia (remote belum punya dataset lokal masjid),
   Beranda hanya memperingatkan status TV kosong.

**Konsekuensi.** Paritas dialek bergantung pada masjid-you tidak
berubah (repo itu beku menunggu rebrand nekios-mosque); bila
shared_models berubah, fixture + test round-trip di
`test/masjid_model_test.dart` adalah alarm pertamanya. Bagian BT
yang belum bisa dibuktikan tanpa perangkat sungguhan: koneksi
RFCOMM fisik, alur izin Android 12+, dan discovery — logika
protokolnya (framing/auth/chunk/store) teruji unit penuh, dan
transport diuji melawan tautan palsu + server WebSocket lokal.
Verifikasi rig (emulator) adalah tahap M3.
