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

## ADR-004: Gateway, auto-detect & shell dinamis (koreksi arsitektur, 2026-11-18)

**Konteks.** ADR-003 butir 6 membuat tab Koneksi dipakai bersama dan
shell mengikuti sambungan terakhir — pengguna tetap harus memilih
jenis display (Sekolah/Masjid) saat menambah display, dan tab
dashboard tampil walau belum terhubung. Pemilik produk mengoreksi
empat hal mendasar (meniru alur gateway mobile_remote masjid-you
yang sudah teruji): dashboard tidak boleh bisa dicapai sebelum
koneksi sukses; pengguna tidak boleh disuruh berpikir jenis
display; shell harus khusus per jenis display; Bluetooth adalah
jalur penyelamat yang wajib setara Wi-Fi.

**Keputusan.**
1. **Connection guard / Gateway sebagai akar.** `LayarUtama`
   memilih secara keras: tidak ada store terhubung →
   `LayarGateway`; `RemoteStore` terhubung → shell sekolah;
   `MasjidStore` terhubung → shell masjid. Tab Koneksi DIHAPUS;
   urusan koneksi di dalam shell menyusut menjadi strip status
   (nama display + jalur) dengan tombol Putuskan. Putus — sengaja
   maupun tak terduga — otomatis kembali ke gateway.
2. **Auto-detect via probing paralel.** Menyambung lewat IP hanya
   meminta alamat IP. `PendekteksiDisplay` (`layanan/penyelidik.dart`)
   menyelidiki DUA protokol bersamaan: nekios-core `ping` →
   `state.snapshot` di 8920 dan warisan masjid `getInitialState` →
   `stateSnapshot` di 8080. Jawaban valid pertama menentukan
   identitas; nama display diambil dari payload identitas itu
   (nama sekolah pada ringkasan jadwal / nama masjid pada
   konfigurasi). Keduanya senyap → kegagalan jujur di gateway.
   Penyelidikan memakai koneksi sekali-pakai yang selalu ditutup;
   sesi sungguhan dibuka store seperti biasa.
3. **Riwayat lahir dari bukti, bukan formulir.** Dialog tambah
   display (dengan pemilih tipe/transport) dihapus. Entri
   `DisplayTersimpan` dibuat/diupdate `SesiRemote` hanya setelah
   deteksi terbukti DAN store berhasil terhubung, atau setelah
   koneksi Bluetooth lolos. Field `tipe` kini berarti "hasil
   deteksi terakhir", bukan pilihan pengguna. IP yang sudah
   tersimpan disambung langsung tanpa deteksi ulang (jalur cepat,
   setara "Perangkat Dikenal" mobile_remote). Dialog Ubah hanya
   menyunting nama/IP/PIN.
4. **Orkestrasi sesi tunggal.** Kelas baru `SesiRemote`
   (`state/sesi.dart`) adalah satu-satunya pemanggil sambung/putus
   dari UI: ia menjalankan deteksi, memilih store menurut hasil,
   menyimpan riwayat, mengubah putus tak terduga menjadi
   pemberitahuan gateway + tombol sambungkan-ulang (pola
   `_handleTransportDisconnected` mobile_remote), dan menjaga
   invariant satu sesi (store lawan diputuskan senyap bila perlu).
   Kedua store mempertahankan kontrak ADR-001/003 apa adanya.
5. **Dual transport di gateway.** Kartu Bluetooth berisi perangkat
   dikenal (entri BT tersimpan, 1 ketuk, PIN tersimpan) dan
   pencarian perangkat (discovery → dialog PIN → auth). Kanal BT
   yang lolos auth hari ini selalu masjid — satu-satunya host
   RFCOMM yang ada; bila host BT sekolah (nekios-core di dalam
   RFCOMM) tiba, klasifikasi dilakukan dengan probing protokol
   yang sama di dalam kanal, tanpa mengubah gateway.

**Konsekuensi.** ADR-003 butir 6 (tab Koneksi bersama + pemilih
tipe manual) DICABUT. `LayarKoneksi` dihapus; cakupan testnya
pindah ke `gateway_widget_test.dart`, ditambah `deteksi_test.dart`
(probing paralel) dan `sesi_test.dart` (orkestrasi). Sesi paralel
dua display sekaligus (yang dulu mungkin lewat tab Koneksi) tidak
lagi didukung — sesuai model gateway satu-display-aktif.

## ADR-005: Deteksi dijamin selesai — penutupan probe tidak ditunggu + tenggat total (perbaikan bug, 2026-11-18)

**Konteks.** Pada verifikasi rig laptop (M3, 18 Nov 2026 malam),
gateway terjebak di "Mendeteksi..." selamanya ketika alamat yang
diketik tidak lengkap ("10.0.2."). Penyelidikan: kedua penyelidik
di `layanan/penyelidik.dart` menutup koneksi cobanya dengan
`await ...putus()` di blok `finally`. `putus()` bermuara ke
`sink.close()` pada kanal WebSocket yang koneksinya macet di
tengah handshake (alamat tak terjangkau di balik firewall DROP,
misalnya) — dan `close()` itu tidak pernah selesai. Akibatnya
penyelidik tidak pernah kembali, `deteksi()` tidak pernah
selesai, dan `SesiRemote` terjebak sibuk sampai aplikasi
dimatikan paksa. Keluarga bug yang sama dengan kebuntuan
`putuskan` MasjidStore di A1.

**Keputusan.**

1. **Penutupan probe tidak pernah ditunggu.** Kedua penyelidik
   menutup koneksi cobanya lewat `_tutupDiamDiam(...)`:
   penutupan ditembakkan (unawaited), errornya ditelan. Tidak
   ada tindakan pemulihan yang mungkin di titik itu, dan sesi
   sungguhan selalu membuka koneksi baru sendiri.
2. **`deteksi()` memakai tenggat total** (bawaan 8 detik):
   penyelidik yang tidak kunjung kembali dihitung senyap dan
   hasil menjadi `TidakTerdeteksi`. Pertahanan berlapis di atas
   batas per-penyelidik (3 detik) dan perbaikan butir 1.
3. **Penyelidik dapat diinjeksi jalur palsu** (`buatKlien` /
   `buatTransport`) supaya kondisi macet dapat direproduksi di
   test: klien/transport yang sambungannya menggantung dan
   penutupannya tidak pernah selesai.

**Konsekuensi.** Gateway selalu pulih dari alamat rusak/tak
terjangkau dalam waktu terbatas dan menampilkan keadaan
tidak-terdeteksi seperti biasa. Kontrak ADR-004 tidak berubah;
`deteksi_test.dart` bertambah grup regresi ADR-005 (4 test).
Penutupan sesi sungguhan di store TIDAK diubah — di sana
menunggu penutupan tetap benar.

## ADR-006: Pola editor masjid A2 — salinan kerja, kirim-seketika vs draf-simpan, triggerBeep mati (2026-11-18)

**Konteks.** Tahap A2 mengubah tab Konten/Pengaturan/Tes di shell
masjid menjadi editor sungguhan dengan paritas fitur mobile_remote.
Rencana tahap ini (`plan-a2-editor-masjid.md`) membawa 12 keputusan
yang dikunci nyanpo 2026-11-18; ADR ini mengabadikan pola yang
mengikat semua tahap A2a–A2e, dan A2a meletakkan fondasinya:
metode data typed di `MasjidStore`, getter `sedangMengirim`,
dan tab Tes sebagai konsumen pertama.

**Keputusan.**

1. **Salinan kerja per layar, TV tetap trust source.** Setiap
   editor membuka salinan kerja yang di-seed dari
   `store.snapshot`; mutasi mengirim daftar/config PENUH terbaru
   (semua perintah `update*` bersifat full-replace). Snapshot
   bukti yang tiba setelah perintah berhasil menjadi seed baru —
   UI tidak pernah menebak keadaan TV dari input lokal.
2. **Konten = kirim seketika; Pengaturan = draf + Simpan.**
   Editor daftar di Konten (teks berjalan, banner, kas, gambar,
   logo) mengirim pada setiap mutasi, persis perilaku
   mobile_remote. Pengaturan adalah satu-satunya pola draf:
   form menampung draf `MosqueConfig`, status dirty dihitung dari
   `draf != snapshot.config` (model punya `==` penuh), dan satu
   tombol Simpan mengirim config utuh. Selama sebuah perintah
   menunggu bukti (`store.sedangMengirim`), kontrol editor
   dinonaktifkan — store memang menolak perintah kedua.
3. **`triggerBeep` dinyatakan MATI.** Nilai enum-nya
   dipertahankan di `SyncAction` demi paritas decode dengan
   tv_display, tetapi remote TIDAK PERNAH mengirimnya — tidak
   sebagai kontrol Tes, tidak di tempat lain. Menghidupkannya
   membutuhkan handler baru di tv_display, yang melanggar
   aturan zero-touch Rute A (ADR-003). Menghidupkan beep adalah
   keputusan terpisah di repo masjid-you, bukan di remote.
4. **Fondasi A2a.** `MasjidStore` mendapat metode typed per
   perintah data — `perbaruiConfig`, `perbaruiRunningText`,
   `perbaruiBanners`, `perbaruiKas`, `perbaruiSideImages`,
   `perbaruiBackgroundImages`, `perbaruiLogo` — dengan payload
   identik jalur bootstrap yang sudah terbukti, semuanya lewat
   kontrak bukti `kirimData`; plus `paksaFase` lewat
   `kirimKontrol` (payload `{'phase': phase.name}`) dan getter
   `sedangMengirim` yang ber-notify pada transisi tunggu/selesai.
   Tab Tes: kartu status dari `statusTv`, tombol paksa fase
   berkelompok Hari Biasa / Hari Jumat seperti mobile_remote,
   konfirmasi sebelum menembak SEMUA fase kecuali Normal (jalan
   pulang tanpa gesekan), dan Khutbah nonaktif + keterangan bila
   `config.hasFridayPrayer == false`.
5. **Tahapan A2 (rekap).** A2a fondasi store + Tes; A2b kerangka
   Konten + Teks Berjalan + Banner; A2c Kas; A2d Gambar Khusus +
   Gambar Latar + Logo; A2e Pengaturan penuh (termasuk GPS via
   geolocator, durasi iqamah dapat diedit, `utcOffsetHours`
   tetap read-only). Preview Simulasi Jadwal dilewati; backup
   export/import menjadi tahap terpisah setelah A2 (jalur
   migrasi data DKM menuju M4).

**Konsekuensi.** Semua editor A2 dibangun di atas satu pola
yang sama, jadi perilaku kirim/bukti/gagal konsisten di semua
tab dan teruji sekali di fondasi. `triggerBeep` tidak akan
muncul lagi sebagai pertanyaan desain di tahap A2 mana pun.
Tidak ada perubahan di tv_display maupun di kontrak ADR-003/
004/005.

## ADR-007: A2b — kerangka Konten enam sub-tab dan pola editor daftar (2026-11-18)

**Konteks.** Tahap A2b mengisi tab Konten shell masjid untuk
pertama kalinya: kerangka sub-tab plus dua editor daftar murni
(Teks Berjalan dan Banner) yang membuktikan pola salinan kerja
ADR-006 pada perintah data `update*` full-replace. Empat sub-tab
lainnya (Kas, Gambar Khusus, Gambar Latar, Logo) menyusul di
A2c/A2d.

**Keputusan.**

1. **Kerangka Konten = enam sub-tab tetap sejak awal.**
   `LayarKontenMasjid` memasang `DefaultTabController` dengan
   urutan Teks Berjalan, Banner, Kas, Gambar Khusus, Gambar
   Latar, Logo — persis susunan Konten mobile_remote. Sub-tab
   yang belum dibangun menampilkan `LayarTahapBerikut` dengan
   penjelasan ramah pengguna (tanpa istilah tahap/pengembangan);
   urutan tidak berubah antar tahap supaya kebiasaan pengguna
   tidak bergeser.
2. **Pola editor daftar (berlaku untuk semua editor Konten).**
   Salinan kerja di-seed dari `store.snapshot` dan di-seed
   ULANG setiap kali objek snapshot berganti — snapshot bukti
   susulan adalah seed baru, bukan tebakan lokal. Selama
   `store.sedangMengirim`, SEMUA kontrol daftar membeku (baris,
   sakelar, tombol, tambah, seret) karena store menolak perintah
   kedua. Kirim yang gagal menahan salinan kerja apa adanya
   (tidak di-rollback) dan melapor lewat SnackBar jujur;
   pengguna bisa langsung mencoba lagi. Selama snapshot belum
   pernah tiba (`store.snapshot == null`), editor menahan diri
   di keadaan "Belum ada data dari TV" — tidak pernah mengarang
   daftar kosong, karena perintah `update*` bersifat
   full-replace dan daftar kosong karangan bisa menghapus isi
   TV. Daftar kosong hanya sah sebagai HASIL mutasi pengguna
   atas data TV yang nyata (mis. menghapus item terakhir).
3. **Hapus + urungkan = kirim, lalu kirim ulang.** Penghapusan
   langsung dikirim sebagai daftar penuh terbaru (paritas
   kirim-seketika); SnackBar keberhasilannya menawarkan
   "Urungkan", yang mengembalikan item ke indeks asalnya dan
   MENGIRIM ULANG daftar yang dipulihkan sebagai perintah baru
   dengan kontrak bukti yang sama. Tidak ada penahanan kirim di
   sisi UI: keadaan TV selalu sama dengan yang terakhir
   dilaporkan remote.
4. **Sakelar `isActive` teks berjalan DITAMPILKAN** (keputusan
   #11): baris nonaktif diberi penanda "Nonaktif". Ini
   menyimpang dari mobile_remote yang tidak pernah menampilkan
   field ini, tetapi modelnya memang mendukung dan DKM
   membutuhkannya untuk mematikan teks musiman tanpa
   menghapusnya.
5. **Gambar banner diperkecil di sisi editor saat dipilih.**
   Helper `perkecilUntukBanner` (layanan/gambar_banner.dart):
   decode, perkecil agar muat 1920×1080 (hanya mengecilkan,
   rasio dipertahankan), encode JPEG kualitas 85; bytes yang
   tidak terbaca sebagai gambar dikembalikan apa adanya dan
   DITOLAK oleh dialog (bukan dikirim ke TV). Ini terpisah dari
   kompresi transport Bluetooth (ADR-003): editor menyimpan
   hasil perkecil sebagai base64 banner, transport tetap bebas
   mengompresi lagi untuk jalur BT. Pemilih gambar dialog
   terinjeksi (`PemilihGambarMentah`) supaya test bisa memakai
   bytes contoh kecil tanpa plugin galeri.
6. **Validasi simpan banner:** sah bila judul ATAU isi ATAU
   gambar terisi (paritas mobile_remote); selain itu tombol
   Simpan nonaktif dengan petunjuk eksplisit. Teks berjalan
   lebih ketat: isi wajib tidak kosong setelah trim. Tambah/
   ubah keduanya lewat dialog layar penuh; item baru memakai id
   `millisecondsSinceEpoch` dan masuk dalam keadaan aktif.

**Konsekuensi.** Pola daftar di butir 2–3 menjadi cetakan untuk
Kas (A2c) dan kedua editor gambar (A2d): cukup mengganti model,
metode typed store, dan isi baris/dialog. Bukti pola ini
diuji per editor — seed tampil, tambah/ubah/sakelar/seret
menghasilkan SATU paket `update*` berisi daftar penuh terbaru,
hapus + urungkan pulang-pergi, kontrol membeku selama menunggu
bukti, dan snapshot bukti menjadi seed baru. Tidak ada
perubahan di tv_display, store, maupun kontrak ADR-003–006.

## ADR-008: A2c — editor Kas: paritas tanpa-sunting, pemilih tanggal, ringkasan dari salinan kerja (2026-11-19)

**Konteks.** Sub-tab Kas adalah editor ketiga pola daftar
ADR-007 dan data paling sensitif di TV: `updateKas` bersifat
full-replace atas catatan uang masjid. Keputusan A2 #10 sudah
mengunci pemilih tanggal untuk tahap ini.

**Keputusan.**

1. **Pola ADR-007 utuh.** Salinan kerja di-seed dari snapshot,
   tambah/hapus langsung mengirim daftar penuh lewat
   `perbaruiKas`, kontrol membeku selama `sedangMengirim`,
   hapus + urungkan = kirim ulang daftar pulih ke indeks asal,
   kirim gagal menahan salinan apa adanya. Selama snapshot
   belum tiba editor menahan diri ("belum ada data dari TV") —
   editor kas tidak pernah mengirim daftar kosong hasil seed
   yang gagal.
2. **Tidak ada sunting transaksi (paritas mobile_remote).**
   Mengoreksi catatan = hapus lalu tambah ulang. Dialog hanya
   punya mode tambah.
3. **Pemilih tanggal (keputusan #10).** Tanggal transaksi
   dipilih lewat pemilih tanggal Material: bawaan hari ini,
   boleh mundur (mencatat infaq yang baru disetor), tidak
   boleh masa depan. Jam transaksi = jam saat menyimpan,
   supaya urutan jam dalam satu hari tetap masuk akal.
   Pemilih terinjeksi (`PemilihTanggalKas`) demi tes.
4. **Urutan = urutan TV apa adanya.** Daftar tampil dan
   terkirim persis urutan snapshot; transaksi baru ditambahkan
   di AKHIR daftar, sama seperti mobile_remote (`.add`). Editor
   tidak mengurutkan ulang — mengurutkan diam-diam akan
   mengubah daftar TV pada mutasi yang tidak berkaitan.
5. **Ringkasan dihitung dari salinan kerja**
   (`KasSummary.fromTransactions`), bukan dari snapshot, supaya
   kartu Saldo/Pemasukan/Pengeluaran selalu konsisten dengan
   daftar yang sedang tampil — termasuk selagi menunggu bukti.
   Format rupiah memakai `formatRupiah` Beranda; format tanggal
   `d MMM yyyy, HH:mm` ditulis manual (repo tidak memakai
   intl), nama bulan Indonesia disingkat (Jan, Feb, …, Agu).

**Konsekuensi.** Tinggal dua sub-tab gambar + logo (A2d) yang
mengikuti pola yang sama sebelum Pengaturan (A2e). Tidak ada
perubahan di tv_display, store, maupun kontrak ADR-003–007.

## ADR-009: A2d — editor gambar & logo: pipa base64 bersama, interval satu-field, sakelar tanpa-kompresi diteruskan ke transport (2026-11-19)

**Konteks.** Tiga sub-tab Konten terakhir (Gambar Khusus,
Gambar Latar, Logo) berbagi pipa gambar base64 besar.
Keputusan A2 yang terkunci untuk tahap ini: #4 logo tinggal
di Konten, #5 interval slideshow dikirim sebagai satu
`updateConfig` dari layar Gambar Latar, #9 sakelar "kirim
tanpa kompresi" (Bluetooth) ikut dibangun — padahal preferensi
itu sebelumnya `final` dari konstruktor transport dan pabrik
di main.dart selalu memakai bawaan.

**Keputusan.**

1. **Pola ADR-007 utuh** untuk kedua editor daftar (salinan
   kerja, kirim seketika, beku selama `sedangMengirim`, hapus
   + urungkan, tahan diri selama snapshot belum tiba).
2. **Gambar Khusus diperkecil saat dipilih** memakai helper
   banner (muat 1920×1080, JPEG q85 — "maks 1080p" rencana
   §3a); berkas yang tidak terbaca sebagai gambar ditolak
   (helper mengembalikan bytes apa adanya → pemanggil
   membandingkannya). Keterangan opsional diisi lewat dialog
   sesudah memilih dan tidak bisa disunting setelah tersimpan
   (paritas mobile_remote: koreksi = hapus + tambah ulang).
3. **Gambar Latar disimpan apa adanya.** Base64 yang terkirim
   adalah berkas pilihan persis — perkecilan adalah urusan
   transport Bluetooth saat mengirim, dan Wi-Fi selalu
   mengirim asli. Tes mengunci ini (base64 terkirim == base64
   berkas pilihan).
4. **Interval slideshow = satu field config (keputusan #5).**
   Stepper 5–300 detik langkah 5 mengirim `perbaruiConfig`
   berisi config snapshot saat itu dengan hanya
   `backgroundSlideSeconds` diganti (model meng-clamp).
   Bukti snapshot menjadi nilai tampil berikutnya.
5. **Sakelar tanpa-kompresi diteruskan, bukan dititipkan
   diam-diam (keputusan #9).** Antarmuka `TransportMasjid`
   mendapat `aturKirimTanpaKompresiLatar(bool)`: Bluetooth
   mengubah flag-nya yang kini bisa diubah saat hidup,
   WebSocket tidak melakukan apa-apa (selalu asli).
   `MasjidStore` memegang nilai preferensi, meneruskannya ke
   transport aktif setiap berubah, dan menerapkannya ke
   setiap transport baru saat menyambung. Persistensi lokal
   HP (SharedPreferences `remote.kirimLatarTanpaKompresi.v1`)
   ditambatkan dari main.dart lewat nilai awal + callback —
   store sendiri tidak tahu-menahu soal SharedPreferences.
6. **Logo berlaku seketika** lewat `perbaruiLogo` (bukan
   bagian dari Simpan config): pilih → `olahLogoKeBase64`
   (maks 512px, helper yang sama dengan layar Logo sekolah)
   → kirim; hapus meminta konfirmasi lalu mengirim
   `logoBase64: null`. Pratinjau membaca `snapshot.mosqueLogo`
   apa adanya.
