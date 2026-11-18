# Nekios Remote

Remote HP untuk display **nekios-school** — bagian dari ekosistem
**Nekios**. Dari ponsel, guru/panitia pameran mengendalikan TV yang
menayangkan jadwal pelajaran: mengganti teks mading, menyimulasikan
jam (termasuk tombol sakti *lompat ke bel berikutnya*), memasang
logo, dan mengganti jadwal — semuanya lewat WebSocket di jaringan
lokal yang sama.

- **Application ID:** `id.nekios.remote`
- **Protokol:** Nekios v1 (paket
  [`nekios_core`](https://github.com/nyanpoketto-kujira/nekios-core),
  spesifikasi di `docs/PROTOCOL.md` repo tersebut)
- **Port display:** 8920 (tetap), alamat IP dimasukkan manual dan
  IP terakhir tersimpan otomatis.

## Cara pakai singkat

1. Pastikan HP dan TV berada di **Wi-Fi yang sama**, dan aplikasi
   nekios-school sedang berjalan di TV.
2. Tab **Koneksi**: masukkan alamat IP TV (atau ketuk display
   tersimpan) → **Sambungkan**.
3. Tab **Beranda** mencerminkan keadaan TV secara langsung.
4. Kendalikan dari tab **Mading**, **Simulasi**, **Logo**, dan
   **Jadwal**.

Setiap perintah menunggu balasan display: `ack` berarti berhasil
(dan snapshot terbaru menyusul), `error` berarti ditolak — pesannya
ditampilkan apa adanya dari display.

## Enam fitur (R2a)

| Tab | Isi |
| --- | --- |
| Koneksi | Daftar display tersimpan (nama + IP), sambung cepat dengan auto-save IP terakhir, status koneksi |
| Beranda | Cermin `state.snapshot`: status, jam efektif berjalan, hitung mundur bel, badge SIMULASI, mading aktif, ringkasan jadwal, status logo |
| Mading | Editor teks mading; kirim & kosongkan ke sambutan bawaan |
| Simulasi | Lompat ke bel berikutnya, lompat ke jam tertentu, kembali ke jam nyata |
| Logo | Pilih gambar, perkecil maks 512px, kirim/hapus logo TV |
| Jadwal | Editor Jadwal visual (R2b) + kirim berkas JSON langsung: validasi §7 di sisi remote, ringkasan, kirim `schedule.replace` |

## Editor Jadwal visual (R2b)

Dari tab **Jadwal** → **Editor Jadwal Visual**. Pembuatan jadwal
dibagi dua tahap (konsep nyanpo — senyaman mungkin di HP, bukan
tabel Excel):

1. **Master Data** — daftar guru (nama + KG) dan mapel (kode +
   nama panjang + warna aksen) berbentuk kartu ringkas. Relasi
   guru↔mapel **bebas many-to-many**: satu guru bisa mengajar
   banyak mapel, satu mapel bisa diajar banyak guru
   (team-teaching). Relasi diatur lewat checklist saat mengetuk
   guru/mapel, dan hanya menjadi *panduan* saat plotting (yang
   berelasi diutamakan & bertanda bintang), bukan kunci.
2. **Plotting** — TabBar Senin–Jumat + daftar slot vertikal.
   Ketuk slot pelajaran → Bottom Sheet: pilih mapel & guru dari
   master data, atur **rentang 1–4 jam** (mapel produktif langsung
   nge-block beberapa jam berurutan; rentang berhenti di jeda
   istirahat/isoma), terapkan atau kosongkan. Slot non-pelajaran
   tampil redup dan tidak bisa di-assign.

Titik awal sesi: **jadwal bawaan SMKN 1 Ukui** (aset aplikasi —
salinan persis `assets/jadwal-tkj.json` nekios-school; bila jadwal
induk berubah, salin ulang berkas ini) atau **berkas JSON** dari
HP. Satu kelas diedit per sesi aktif; berpindah kelas
mempertahankan master data dan hasil edit kelas lain. Draf
tersimpan **otomatis** di HP per kelas dan bisa dilanjutkan lain
waktu — mengedit tidak butuh koneksi. Tombol **Tinjau & Kirim**
merakit dokumen utuh (kelas lain dipertahankan apa adanya),
menjalankan validator §7, menampilkan ringkasan slot terisi per
hari, lalu mengirim lewat alur yang sama dengan kirim berkas.

## Arsitektur

Berlapis sederhana, meniru pola nekios-school:

```
lib/
  tema.dart            — Material You, seed 0xFF006A60 (sama dengan
                         masjid-you & nekios-school), terang+gelap
                         mengikuti sistem
  model/               — DisplayTersimpan, SnapshotDisplay (parser
                         toleran atas payload snapshot R1)
  domain/              — fungsi murni: validasi_jadwal (§7 atas JSON
                         mentah), perintah (pembangun paket, logika
                         lompat bel), editor_jadwal (model Editor
                         Jadwal R2b: master data, relasi, assign
                         slot/rentang, perakitan dokumen)
  layanan/             — KlienRemote (pembungkus NekiosKlien),
                         PenyimpananDisplay (shared_preferences),
                         PenyimpananDrafEditor (draf editor),
                         olah logo (package:image)
  state/               — RemoteStore (ChangeNotifier): koneksi,
                         snapshot, pola tunggu ack/error + timeout
  ui/                  — enam layar + widget bersama + editor
                         (master data, plotting, tinjau & kirim)
  assets/              — jadwal-bawaan.json: salinan jadwal induk
                         nekios-school untuk titik awal editor
```

Keputusan arsitektur dicatat di [docs/DECISIONS.md](docs/DECISIONS.md).

## Pengembangan

```bash
flutter pub get     # nekios_core diambil dari git (repo publik)
flutter analyze     # harus nol isu
flutter test        # 71 test: validator, perintah, snapshot,
                    # penyimpanan, logo, store, widget, editor
                    # (master data, rentang, draf, plotting)
```

CI (GitHub Actions, `.github/workflows/build.yml`) menjalankan
analyze + test di setiap push/PR, dan membangun APK x86_64 debug
untuk emulator pada PR / dispatch manual — pola yang sama dengan
nekios-school.
