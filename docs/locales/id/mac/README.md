# zisla untuk macOS

[English](../../../../mac/README.md) | [简体中文](../../../../mac/README.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../../README.md)

Direktori ini berisi implementasi macOS zisla. Arahkan penunjuk ke tengah atas layar untuk membuka pulau; geser menjauh untuk menyembunyikannya. Aplikasi memakai AppKit `NSPanel`, SwiftUI, dan layanan berbasis peristiwa, tanpa jendela transparan permanen untuk area pemicu atau loop frame saat tersembunyi.

Target Swift, ID bundle, direktori data lokal, dan `zislactl` memakai pengenal zisla. Peningkatan memigrasikan data dan preferensi lokal versi sebelumnya secara otomatis.

macOS 14 dan lebih baru didukung. macOS 26 memakai Liquid Glass; macOS 14/15 memakai material sistem native sebagai alternatif.

## Fitur

### 12 modul pulau

| Modul | Kemampuan yang diimplementasikan |
| --- | --- |
| Beranda | Merangkum timer Pomodoro saat ini, tugas AI aktif pertama, unduhan native, dan progres beberapa unduhan peramban sesuai kebutuhan. |
| Suara dan statistik papan ketik | 20 suara bawaan; statistik mengetik lokal dapat diaktifkan terpisah, dengan tren, linimasa aplikasi, dan peta panas per tombol. |
| Serah Terima | Seret berkas, media, atau tautan ke area pemicu atas untuk menyimpannya di baki, menampilkannya di Finder, atau berbagi melalui sistem. Tangkapan tersimpan memakai kartu biru dua kali lebar dan kategori tersendiri, dengan penyalinan gambar, ekspor PNG, dan penghapusan. Kompres berkas dan folder menjadi ZIP, ubah ukuran atau format gambar dengan Alat Gambar dan kembalikan hasil yang berhasil ke baki, atau impor gambar, video, dan audio ke pustaka media rekaman tanpa mengubah proyek dan linimasa saat ini. |
| Papan Klip | Riwayat lokal yang dapat dicari, filter gambar/URL/berkas, dan favorit; riwayat serta deteksi tautan memiliki sakelar terpisah. Gambar baru masuk antrean pengenalan teks di perangkat; cari teks untuk menemukan gambar asal, atau klik kanan untuk mengenali/menyalin teks. Pengenalan yang berjalan dapat dibatalkan; pengenalan latar tidak menyalin teks otomatis. |
| Pemantauan AI | Menggabungkan tugas aktif, status, tren token, peta panas kontribusi, dan pemberitahuan samping dari CLI, aplikasi desktop, serta IDE yang didukung. |
| Unduhan | Memakai `yt-dlp` untuk video dan audio; tanpa `ffmpeg`, AVFoundation membungkus trek yang kompatibel, dan tersedia alternatif Bilibili hanya-baca. |
| Jadwal | Cuaca lokasi saat ini dan hingga enam lokasi tersimpan; melihat, membuat, menghapus acara/pengingat, dan menandai pengingat selesai. Waktu pembaruan daftar cuaca muncul di bagian atas, di sebelah kiri tombol muat ulang. Jika data cuaca belum lengkap, sumber lain melengkapi hasil terlengkap; data yang tersedia tetap digunakan saat sisanya tidak dapat diambil. |
| Surel | Membaca akun Mail.app terpilih untuk melihat kotak masuk, menandai dibaca, membalas, menulis, dan memindahkan pesan ke sampah. |
| Catatan | Apple Notes sebagai satu-satunya sumber data untuk melihat, menyunting, membuat, dan menghapus catatan Markdown, dengan pratinjau langsung serta penyimpanan otomatis. |
| Mixer Volume Aplikasi | macOS 14.4+ mengatur dan membisukan setiap aplikasi yang memutar audio serta mengingat volumenya; memerlukan izin Rekaman Audio Sistem. |
| Utilitas | Timer Pomodoro dengan satu bunyi dan notifikasi lokal saat sesi selesai, mode tetap terjaga, pencegah tidur saat menganggur, pembersihan layar/papan ketik, teleprompter, cermin kamera, dan pengosongan sampah dengan konfirmasi. Nama pengatur waktu hanya berlaku untuk sesi saat ini dan kembali ke nama bawaan saat sesi berakhir atau dibatalkan. Saat island diciutkan, ikon matahari berarti layar tetap menyala, sedangkan ikon laptop berarti Mac tidak akan tertidur saat tidak digunakan. |
| Sistem | CPU, GPU, memori, disk, jaringan, suhu, dan kipas; pelepasan memori dan pemindaian cache/log/data sementara yang aman dihapus; kesehatan baterai dan daya aksesori. |

### Kemampuan lintas modul

- **Sedang Diputar:** MediaRemote menampilkan sampul, judul, progres, lirik bergulir, dan kontrol; Core Audio mengenali sumber audio sesungguhnya sebagai alternatif. Sumber dijeda, berhenti, atau bisu disembunyikan.
- **Unduhan peramban:** Menampilkan sumber dan progres Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, serta Arc di Beranda, keadaan terlipat, dan pemberitahuan samping. Keberadaan berkas `.crdownload` di folder sementara sistem saja tidak memicu tampilan kartu unduhan.
- **Masukan suara:** Pintasan toggle atau tekan-untuk-bicara, pintasan global khusus, pengenalan ucapan sistem, pengolahan transkrip lokal/jarak jauh, dan riwayat rekaman lokal.
- **Tindakan Cepat:** Setelah setiap penyalinan, notifikasi kecil bergaya pulau menampilkan pratinjau kaya dan tindakan sesuai isi: membuka tautan, menampilkan berkas di Finder, mencari dengan mesin pilihan, menerjemahkan, menghitung, membuat acara dari tanggal, serta menyimpan teks panjang atau gambar. Setelah unduhan selesai atau AirDrop diterima, pintasan yang sama membuka folder berkas; sakelar Tindakan Cepat mengendalikannya terpisah dari progres unduhan. Mengenali URL, jalur berkas, surel, nomor telepon, warna CSS dengan contoh langsung, aritmetika, tanggal/waktu, teks bukan bahasa sistem, cuplikan kode, teks dengan hitungan, gambar mini, dan referensi berkas. Pemicu berupa tombol tindakan, pintasan tambahan default Command+N, atau modifier/tombol samping yang diatur. Ada gestur salin “tahan kiri + klik kanan” yang nonaktif secara default, daftar blokir aplikasi, sakelar jenis pengenalan, dan mode pengingat ringan.
- **Pengelolaan CLI dan Skills:** Mendeteksi, memasang, memperbarui, menghapus CLI AI umum, dan mengelola Skills lokal dari Pengaturan.
- **Peliharaan desktop:** Di Pengaturan → Pet, lihat pratinjau peliharaan bawaan dan yang diimpor. Mode Peliharaan tetap menampilkan satu peliharaan. Rotasi acak mengundi dari semua peliharaan kecuali Anda membatasi Daftar undian. Secara bawaan, undian berlangsung pada tengah malam waktu setempat. Pilih Kustom pada Interval pergantian untuk mengatur durasi dari 1 detik hingga 99:59:59. Nilai awalnya 1 jam. Letakkan peliharaan di sisi kiri atau kanan pulau. Saat Anda membuka pulau di satu layar, hewan peliharaan di layar lain tetap di tempatnya.
- **Pembaruan:** Kanal Release atau Preview terpilih mencari kode negara koneksi publik sekali per peluncuran. `CN` memeriksa appcast Gitee bertanda tangan dahulu, lalu mencoba GitHub sekali; negara lain memeriksa GitHub dahulu lalu Gitee sekali. Jika pencarian gagal, Gitee tetap pertama. Sparkle kemudian mengunduh, memverifikasi, memasang, dan meluncurkan ulang. Perubahan kanal berlaku bagi pemeriksaan otomatis maupun manual.
- **Tampilan dan interaksi:** Pengaturan mengikuti tema sistem, terang, atau gelap. Pulau mendukung permukaan transparan atau berkabut, pembukaan yang disematkan, banyak layar, Spaces, serta layar eksternal tanpa notch. Saat browser menggunakan layar penuh, arahkan penunjuk ke pulau untuk membukanya di desktop yang sama.
- **Default:** Pemasangan baru mengaktifkan modul fitur. Fitur, indikator terlipat, pemberitahuan samping, metrik bilah menu, dan perilaku pembaruan dapat diatur sendiri-sendiri; pemasangan lama mempertahankan konfigurasi.
- Saat beberapa layar terhubung, Pengaturan → Umum → Mode Layar memungkinkan Anda memilih mode Dynamic Island (posisi kamera atau kustom), mode notch, atau sembunyikan untuk setiap layar. Dengan satu layar, pengaturan ini disembunyikan dan tampilan global digunakan; menghubungkan kembali memulihkan konfigurasi tersimpan setiap layar. Semua layar yang diaktifkan menampilkan island yang diciutkan secara bersamaan. Memperluas island, tindakan cepat, perekaman, dan pesan sementara hanya mengganti island pada layarnya sendiri; pemilihan layar notifikasi menyaring konten tanpa menyembunyikan island yang sedang tidak aktif.

### Alat mandiri dan alur kerja

- **Studio rekaman:** Buka dari bilah menu atau Pengaturan. Rekam layar, jendela, atau area dengan audio sistem, mikrofon, dan kamera opsional. Sunting video, audio, gambar, dan teks lintas trek, termasuk teks, zoom, animasi, efek potret dan suara; pratinjau sebelum ekspor video, GIF, Live Photo, atau audio. Sebagian format perlu FFmpeg; HDR bergantung dukungan perangkat. Impor gambar, video, dan audio dari rak ke pustaka media sambil mempertahankan proyek dan linimasa saat ini.
- **Alat gambar, audio, dan PDF:** Buka dari Pengaturan. Gambar memiliki 9 operasi lokal dan ekspor batch/ZIP. Audio memiliki 27 operasi termasuk mixing, normalisasi LUFS, dan pengolahan derau serta memerlukan FFmpeg dan ffprobe. PDF memiliki 14 operasi; konversi Office memerlukan LibreOffice atau OpenOffice.
- **Ringkasan harian:** Pilih satu dari 8 templat dan metrik di Pengaturan, pratinjau, lalu ekspor PNG manual atau pada waktu harian. Metrik tidak tersedia tidak ditampilkan sebagai angka nol hasil pengukuran.
- **Pratinjau jendela:** Arahkan ke Dock atau beralih dengan Command+Tab, lalu klik pratinjau untuk mengaktifkan jendela. Kelola fitur dan izin di Pengaturan.
- **Catatan konteks dan rapat:** Tahan pintasan catatan yang diatur lalu goyangkan penunjuk untuk menempelkan catatan ke halaman, jendela, atau desktop. Acara dengan tautan rapat menampilkan hitung mundur 10 menit sebelumnya; bergabung, membuat catatan, atau menautkan catatan lama tersedia. Kelola catatan konteks di rak.
- **Goyang untuk menjatuhkan:** Goyangkan penunjuk ketika menyeret berkas untuk menampilkan target; gestur memiliki sakelar tersendiri.
- **Keluaran audio dan preferensi pemutar:** Pilih perangkat keluaran di area media. Pengaturan memilih sumber otomatis/pemutar utama, tata letak ringkas, dan kondisi penghentian suara latar.
- **Kuota dan reset AI:** Pemantauan AI dan Pengaturan menampilkan kuota akun, waktu sampel/reset, dan peringatan kuota rendah, termasuk jendela 5h/7d yang tersedia dan anggaran Cursor USD. Ini terpisah dari riwayat token lokal. Kuota Gemini dan Claude/GPT Antigravity memiliki pemantauan, tampilan, dan peringatan terpisah. Kuota percakapan Gemini App memakai Cookie web dari akun Google yang sama; Gemini CLI tetap terpisah.

### Urutan papan ketik Tindakan Cepat

Popup memberikan `Command+1` hingga `Command+9`, lalu `Command+0` sesuai urutan tindakan saat ini. Pemicu tambahan default konfigurasi baru adalah `Command+N` untuk tindakan pertama; `Command+Delete` menutup popup. Atur pemicu, tombol samping, dan urutan di Pengaturan. Peningkatan mempertahankan setiap kombinasi tersimpan, termasuk `Command+1` lama, pintasan khusus, dan pemicu kosong. Hanya konfigurasi baru atau kolom pemicu yang tidak ada memakai `Command+N`.

### Lokasi penyimpanan

Pengaturan → Lokasi Simpan memilih folder terpisah untuk unduhan, tangkapan, gambar, rekaman, PDF, Tindakan Cepat, dan ringkasan harian. Konfigurasi baru memakai subfolder `~/Downloads`: `picture` untuk tangkapan/gambar, `video` untuk rekaman, `pdf`, `quick`, dan `daily`. Alat audio memilih berkas/folder melalui dialog ekspor. Berkas rak tetap merujuk aslinya; tangkapan tersimpan dan status catatan konteks dikelola di `~/Library/Application Support/zisla`, proyek rekaman memakai folder rekaman. Teks Catatan Cepat tersimpan di Apple Notes.

[Bantuan dan panduan langkah demi langkah](https://wzz6423.github.io/zisla/help.html?lang=id#help) mencakup sembilan topik: papan klip, tangkapan, rak, rapat, AI, alat media, ringkasan harian, catatan desktop/pratinjau jendela, serta pemutaran/mixing, dengan cuplikan film pendek.

### Pintasan dan penyimpanan tangkapan

Tindakan **Stash** berada antara **Pin** dan **Copy** pada toolbar tangkapan. Hasil gambar akhir, termasuk anotasi dan tangkapan gulir selesai, disimpan ke baki tanpa disalin ke papan klip. PNG dan metadata seperti aplikasi asal serta waktu tangkap disimpan lokal di SQLite dan tetap ada setelah restart. Kategori **Stashed screenshots** hanya menampilkan kartu ini.

**Highlighter** mengikuti **Brush** untuk sorotan transparan; garis ujung dan penanda lingkaran aktif secara default dan dapat dimatikan di menunya. **Extract** mengikuti **Blur** dan mendukung pemisahan subjek/latar macOS serta seleksi bebas. Beberapa lingkaran mempertahankan gabungan area, dengan Select All dan Clear; piksel tak dipilih menjadi transparan dan ekstraksi dapat dibatalkan. Radius sudut default 0. Seret pengatur radius di atas seleksi atau gunakan **Corner radius**; lencana ukuran menampilkan `r`. Ekspor PNG bersudut transparan; reset radius 0 memulihkan piksel sudut asli.

| Konteks | Tindakan | Pintasan default |
| --- | --- | --- |
| Global | Tangkapan layar | `Control+1` |
| Global | Tangkapan gulir | `Control+2` |
| Editor tangkapan | Sematkan | `Control+1` |
| Editor tangkapan | Simpan di baki | `Control+2` |
| Editor tangkapan | Persegi panjang | `Control+3` |
| Editor tangkapan | Elips | `Control+4` |
| Editor tangkapan | Kuas | `Control+5` |
| Editor tangkapan | Penyorot | `Control+6` |
| Editor tangkapan | Panah | `Control+7` |
| Editor tangkapan | Nomor | `Control+8` |
| Editor tangkapan | Teks | `Control+9` |
| Editor tangkapan | Kaburkan | `Control+0` |
| Editor tangkapan | Ekstraksi | `Control+A` |
| Editor tangkapan | Tangkapan gulir | `Control+B` |
| Editor tangkapan | Salin | `Enter` |
| Editor tangkapan | Simpan | `Command+S` |
| Editor tangkapan | Urungkan | `Command+Z` |
| Editor tangkapan | Ulangi | `Command+Shift+Z` |

Pengaturan menampilkan dan merekam pintasan global/editor. Salin, Simpan, Urungkan, dan Ulangi ditampilkan tetapi tidak dapat direkam ulang. Pintasan pengguna dipertahankan saat peningkatan; Pin adalah tindakan editor, bukan pintasan global terpisah, sementara menu tetap tersedia.

Default editor mengikuti toolbar: `Control+1`–`Control+9`, lalu `Control+0`, `Control+A`, `Control+B`, dan huruf berikutnya. Alokasi melewati `Q`, `M`, `N`, `W` karena salah menekan Command dapat keluar, meminimalkan, membuka, atau menutup jendela. Kombinasi pengguna tetap diizinkan.

Saat peningkatan, tata letak lama yang belum diubah, termasuk Pin/Stash sebelumnya, sekali beralih ke default di atas. Jika satu pintasan sudah disesuaikan, tata letak dipertahankan; tindakan baru dengan konflik memilih kombinasi Control kosong dalam urutan aman yang sama. Kombinasi awal juga dapat direkam ulang.

## Mulai cepat

### Lingkungan

- macOS 14+
- Swift 6 / Xcode 16+ (Command Line Tools saja dapat membangun)
- Opsional: `yt-dlp` dan `ffmpeg`; konversi Office ke PDF perlu LibreOffice atau OpenOffice

Dengan Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Menjalankan dari sumber

```bash
swift run zisla
```

Aplikasi berjalan sebagai aksesori bilah menu. Masukkan penunjuk ke area 6 px di tengah atas layar saat ini atau pilih “Show Island” dari ikon bilah menu.

Untuk menguji interval 5 detik pada build debug, jalankan `ZISLA_DEBUG_PET_ROTATION_SECONDS=5 make run` dari direktori utama repositori, aktifkan Rotasi acak dan pilih setidaknya dua peliharaan. Jalankan `make update` tanpa variabel tersebut untuk memulihkan interval yang tersimpan.

### Membangun `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Untuk menyertakan helper `yt-dlp` resmi:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` mengambil berkas standalone macOS resmi dengan versi tetap dan memverifikasinya terhadap `SHA2-256SUMS` resmi sebelum memasang di `Tools/yt-dlp`.

## Integrasi alat AI

### Deteksi otomatis

zisla membaca status sesi lokal publik atau stabil dari alat yang didukung, hanya mengekstrak peristiwa terstruktur dan metadata yang diperlukan untuk status tugas. Prompt dan isi jawaban tidak dibaca.

| Lingkungan | Deteksi otomatis |
| --- | --- |
| OpenAI / Anthropic | Codex CLI dan Desktop, Claude Code, serta lingkungan host-nya |
| GitHub / Google / xAI | GitHub Copilot CLI dan VS Code, Gemini CLI dan Desktop, Grok CLI |
| Alat independen dan regional | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop dan CLI, TRAE, OpenCode, Harnext/Harness, WorkBuddy |

Menunggu persetujuan/jawaban berwarna kuning, kegagalan alat/perintah merah, eksekusi normal hijau; sumber bersamaan dikelompokkan merah, kuning, hijau. Sidecar runtime Qwen hanya dianggap aktif ketika PID hidup agar laporan tidak tersisa setelah keluar.

Aplikasi desktop chat yang tidak menyimpan peristiwa terstruktur tidak memungkinkan pemisahan andal antara terbuka menganggur dan model yang menghasilkan. Alat seperti ChatGPT sebaiknya memakai hook `zislactl` berikut; zisla tidak memalsukan aktivitas dari proses menetap.

### Protokol lokal `zislactl`

`zislactl` menulis status dan riwayat penggunaan ke SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Riwayat bertahan setelah restart, pembaruan pengganti, dan pengosongan tugas. Hanya penghapusan manual data aplikasi menghilangkannya.

Contoh:

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "Refactor index" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "Complete"
```

Penyedia kanonis mencakup `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness`, `doubao`; alias umum dinormalisasi otomatis. Panggil dari hook, pembungkus shell, atau skrip tugas.

Daftar AI dan keadaan terlipat menggunakan logo resmi alat untuk mengenali sumber.

Lihat [referensi integrasi CLI](Docs/cli-reference.md) untuk protokol.

## Progres unduhan peramban

zisla mendengarkan progres berkas publik macOS di Downloads dan menggabungkan ekstensi sementara, atribut tambahan sumber unduhan, serta peramban yang berjalan untuk mengenali sumber. Riwayat peramban tidak dibaca dan jaringan tidak dihubungi untuk mengenali progres; tanda selesai terlihat sekitar tiga detik. Tindakan Cepat memakai sumber yang sama dan menawarkan Open Folder setelah transfer berhasil sampai ke lokasi akhir. Durasi mengikuti pengaturan Tindakan Cepat; pemberitahuan salin/transfer terbaru mengganti sebelumnya.

## Pengunduh

Urutan pencarian executable:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

URL dikirim ke `Process` sebagai nilai argv terpisah tanpa shell. Konfigurasi runtime dan plugin diabaikan, `--exec` dinonaktifkan, batas satu item diterapkan, dan berkas akhir diperiksa tetap di direktori berizin.

Tanpa `ffmpeg`:

- Video memilih trek AVC/MP4 dan M4A, lalu membungkus MP4 dengan AVFoundation; format berkas tunggal dipertahankan.
- Audio memilih M4A atau mempertahankan format asal.
- Jika yt-dlp mendapat HTTP 412, format tidak ditemukan, atau tidak tersedia lokal, Bilibili memakai API hanya-baca untuk memperoleh DASH lalu jalur pembungkus native yang sama, tanpa memasang alat tambahan.

## Catatan

Catatan Markdown pulau hanya memakai Apple Notes sebagai data. Membuat, melihat, menyunting, dan menghapus catatan yang ada didukung, bukan sekadar menambah.

- **Daftar:** Saat masuk, JXA (`osascript -l JavaScript`) membaca judul/tanggal perubahan catatan yang tidak dihapus dan mengurutkan terbaru. Kembali dari Notes memperbarui daftar; Recently Deleted disembunyikan. Pilih catatan untuk menyunting, menyegarkan, membuat, atau menghapus melalui konteks.
- **Lihat dan sunting:** AppleScript membaca `plaintext` catatan sebagai sumber Markdown ke editor. `TextEditor` native menyimpan setelah sekitar 0,8 detik tidak mengetik agar tidak memanggil AppleScript tiap tombol. Catatan baru dibuat dan dipilih di Apple Notes.
- **Pratinjau:** Parser blok merender judul, daftar biasa/bernomor/tugas, kutipan, kode berpagar, garis, tebal, miring, kode sebaris, coret, dan tautan sebagai `AttributedString`.
- **Penyimpanan:** Sumber Markdown disimpan sebagai teks biasa di `body` dengan escaping HTML dan baris kosong. `plaintext` memulihkan sumber; Apple Notes menampilkan teks biasa, tidak merender Markdown.
- **Izin:** Baca/tulis pertama meminta otorisasi otomasi Apple Notes; penolakan memberi pemberitahuan kegagalan daftar/editor.

Modul tidak menyimpan salinan lokal kedua; Apple Notes adalah backend.

## Izin dan privasi

- **Kalender:** Izin Kalender dan Pengingat diminta terpisah saat masuk; data disegarkan setelah pembuatan, penghapusan, penyelesaian.
- **Lokasi:** Cuaca meminta lokasi sekali tanpa melacak terus; lokasi lain dapat dicari, disimpan, dihapus di Pengaturan.
- **Berkas dan unduhan:** Direktori pilihan memakai security-scoped bookmark; serah terima tidak menyalin asal.
- **Papan klip:** Pemasangan baru mengaktifkan riwayat dan tautan terpisah. Tiap `changeCount` mengenali maksimal satu tautan lokal; parameter query tidak dicatat, API clear/declare-type/write tidak dipanggil, sehingga papan klip universal tidak diganti.
- **Tindakan Cepat:** Berjalan lokal pada `changeCount` dan transfer unduhan/AirDrop selesai. Modifier saja/tombol samping dapat memerlukan Pemantauan Masukan; gestur salin opsional juga mengirim ⌘C sintetis dan perlu Accessibility. Pengenalan tidak terhubung jaringan; buka, cari, terjemah, simpan hanya setelah klik/pemicu. Daftar blokir dan sakelar jenis mengatur pemberitahuan salin; sakelar utama juga mengatur transfer.
- **Status AI:** Deteksi membaca hanya peristiwa dan metadata lokal yang diperlukan.
- **Suara:** Mikrofon/pengenalan hanya setelah tindakan eksplisit. Rekaman, transkrip asli, dan teks hasil dikelola lokal; teks dikirim hanya ke model lokal, penyedia jarak jauh, atau profil CLI pilihan, dengan kredensial jarak jauh di basis data privat.
- **Bluetooth dan perangkat:** Daya aksesori dan perangkat seluler Apple tepercaya hanya dibaca saat tampilan baterai di Sistem terbuka.
- **Kamera dan Pemantauan Masukan:** Cermin serta pratinjau/rekaman kamera studio meminta Kamera. Suara, statistik, pembersihan papan ketik, modifier/tombol samping memakai Pemantauan Masukan; statistik lokal dan sakelar terpisah.
- **Layar dan audio sistem:** Tangkapan, rekaman, pratinjau membaca layar dengan Screen Recording. Rekaman menyimpan sumber lokal; mikrofon/kamera hanya diminta bila aktif. Mixer memerlukan macOS 14.4+ dan System Audio Recording dengan tap Core Audio lokal.
- **Unduhan peramban:** Hanya progres sistem publik dan berkas sementara; riwayat dan halaman tidak dibaca.
- **Media:** Metadata MediaRemote dan status keluaran proses Core Audio memastikan pemutaran. MediaRemote adalah framework privat, sehingga build ini tidak cocok untuk pengiriman langsung ke Mac App Store; tanpa metadata tampilkan aplikasi audio aktif.
- **Jaringan:** Prakiraan memakai China Weather, Open-Meteo, dan MET Norway sesuai wilayah, dengan sumber tambahan jika data belum lengkap. Peringatan resmi diambil secara terpisah dari China Weather atau WeatherKit. Kanal memperiksa negara melalui `ipinfo.io/country` sekali: `CN` Gitee lalu GitHub, negara lain sebaliknya, gagal tetap Gitee. Alternatif Bilibili memakai informasi video, URL, CDN hanya-baca; pengenalan tautan tidak menghubungi jaringan. Kuota aktif menghubungi penyedia; terjemahan, edit rekaman AI, dan pembersihan transkrip memakai model/CLI pilihan. Speech dapat memakai Apple sesuai sistem/bahasa. Pemasangan/pembaruan komponen dan CLI, IP publik, dan tindakan jaringan pilihan pengguna juga membuat permintaan.
- **Otomasi:** AppleScript/JXA membaca daftar, melihat, menyunting, membuat, menghapus Apple Notes. Memerlukan izin, tanpa jaringan, data di Apple Notes.

## Tes

Dengan Xcode lengkap:

```bash
swift test
```

Dengan Command Line Tools saja:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Dokumentasi

- [Arsitektur dan kinerja](Docs/architecture.md)
- [Referensi integrasi CLI](Docs/cli-reference.md)
- [Penandatanganan dan rilis](Docs/releasing.md)
- [Dependensi yang disertakan — Inggris](../../../../mac/Vendor/README.md)
- [Pemberitahuan pihak ketiga — Inggris](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Keterbatasan sistem

- macOS tidak memiliki API Dynamic Island publik; notch disimpulkan dari `safeAreaInsets` dan area atas tambahan, layar tanpa notch memakai simulasi overlay yang sama.
- Video DRM, jendela login, layar terkunci, sebagian layar penuh eksklusif mungkin tidak memberi data media atau mengizinkan overlay.
- Aplikasi tanpa integrasi pusat media dapat menampilkan sumber audio tetapi tidak menjamin judul/sampul/progres; video dijeda, berhenti, dan bisu sengaja disembunyikan.
- Persentase memerlukan progres macOS yang dipublikasikan peramban atau berkas sementara Downloads yang dikenal.
- Kesehatan baterai, suhu, daya langsung, aksesori bergantung perangkat, koneksi, data macOS; kolom hilang ditampilkan tidak tersedia.
- Office ke PDF memerlukan LibreOffice/OpenOffice; operasi lain lokal.
- Paket tidak dinotarisasi dan mungkin memerlukan **Open Anyway** pertama. Rilis stabil memakai sertifikat self-signed tetap agar izin bertahan; Sparkle memeriksa EdDSA tiap pembaruan sebelum ekstraksi, penggantian, dan peluncuran ulang.

## Lisensi

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Nonkomersial diizinkan; penjualan atau penggunaan komersial lain tidak diizinkan.
