# zisla

[English](../../../README.md) | [简体中文](../../../README.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../README.md)

**zisla adalah ruang kerja macOS native yang muncul saat dibutuhkan, lalu memberi ruang untuk pekerjaan Anda.** Arahkan penunjuk ke tengah atas layar untuk membuka satu tempat ringan bagi pekerjaan AI aktif, media, serah terima, unduhan, dan utilitas desktop. Layar tanpa notch memakai area status simulasi dengan bentuk yang sama.

Implementasi saat ini: **macOS 14+**. Apple Silicon adalah konfigurasi yang didukung; paket Intel mungkin berfungsi, tetapi kompatibilitas tidak dijamin.

[Tonton tur fitur lengkap — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Tonton film peluncuran zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Musik: “Funkorama” oleh Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Sumber](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Mengapa cocok di bagian atas layar

- **Sesuai kebutuhan, tanpa mengambil fokus.** Buka dari tepi atas, sematkan bila perlu, dan lanjutkan pekerjaan di aplikasi saat ini.
- **Satu tempat untuk pekerjaan aktif.** Lihat media yang diputar, tugas AI, unduhan, timer, surel, status sistem, dan baterai tanpa membuka dasbor penuh.
- **Aktivitas AI tanpa akses percakapan.** zisla hanya membaca peristiwa terstruktur dan metadata aktivitas lokal yang diperlukan untuk menentukan status tugas. Isi prompt dan jawaban tidak dibaca.
- **Kendali tetap lokal.** Modul, riwayat papan klip, dan deteksi tautan memiliki sakelar terpisah; izin diminta saat fitur pertama kali digunakan.

## Kemampuannya

### Menjaga pekerjaan desktop berjalan

| Kemampuan | Fungsinya |
| --- | --- |
| Sedang Diputar | Menampilkan sampul, judul, progres, lirik, dan kontrol pemutaran; Core Audio dapat mengenali aplikasi yang benar-benar mengeluarkan audio ketika metadata tidak tersedia. |
| Serah terima dan berbagi | Jatuhkan berkas, media, atau tautan pada area pemicu atas untuk menyimpannya di baki, menampilkannya di Finder, atau membuka menu berbagi macOS. Kompres berkas dan folder terpilih menjadi ZIP, ubah ukuran atau format gambar melalui Alat Gambar dan kembalikan hasil yang berhasil ke baki, atau impor gambar, video, dan audio ke pustaka media rekaman sambil mempertahankan proyek dan linimasa saat ini. |
| Papan klip dan notifikasi | Secara opsional menyimpan riwayat papan klip lokal, mengenali tautan baru di perangkat, dan menampilkan media, aktivitas AI, unduhan peramban, timer, surel, serta pembaruan dalam keadaan terlipat. Tindakan Cepat opsional menampilkan notifikasi pulau kecil setelah setiap penyalinan, dengan pratinjau kaya dan tindakan sesuai isi: buka, tampilkan di Finder, cari, terjemahkan, hitung, simpan. Setelah unduhan selesai atau berkas AirDrop tiba, pintasan yang sama dapat membuka foldernya. Gambar riwayat baru masuk antrean pengenalan teks di perangkat; cari teksnya untuk menemukan gambar asal, atau klik kanan gambar untuk mengenali atau menyalin teksnya. |
| Ruang kerja sehari-hari | Cuaca, kalender, pengingat, Mail.app, catatan Markdown dengan Apple Notes sebagai penyimpanan, informasi layar terkunci, dan peliharaan desktop opsional. Lihat pratinjau peliharaan dan pilih satu untuk ditampilkan terus, atau izinkan zisla mengundi dari daftar Anda setiap tengah malam waktu setempat atau pada interval khusus. Jika data cuaca belum lengkap, sumber lain melengkapi hasil terlengkap; data yang tersedia tetap digunakan saat sisanya tidak dapat diambil. |

### Membuat pekerjaan AI terlihat

zisla memantau aktivitas lokal Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI, dan sumber lain yang didukung. Tugas, status, tren token, peta panas kontribusi, dan pemberitahuan samping ditampilkan.

Untuk alat tanpa sumber aktivitas lokal yang stabil, `zislactl` memungkinkan skrip, CI, dan hook alat melaporkan progres, penggunaan, dan notifikasi dengan status protokol tetap di Mac ini. Pengaturan juga dapat mendeteksi, memasang, memperbarui, dan menghapus CLI AI umum serta mengelola Skills lokal. Lihat [referensi integrasi CLI](mac/Docs/cli-reference.md) untuk penyedia dan perintah.

### Menangani hal kecil yang berguna

| Bidang | Alat yang tersedia |
| --- | --- |
| Unduhan dan dokumen | Unduhan video dan audio melalui `yt-dlp`; penggabungan, pemisahan, rotasi, pemotongan, konversi, rendering, ekspor teks, tanda air, nomor halaman, enkripsi, pembukaan kunci, dan penyuntingan metadata PDF secara lokal. |
| Fokus dan presentasi | Timer Pomodoro dengan satu bunyi dan notifikasi lokal ketika sesi berakhir, mode tetap terjaga, pencegah tidur saat menganggur, pembersihan layar dan papan ketik, teleprompter, dan cermin kamera. Nama pengatur waktu hanya berlaku untuk sesi saat ini dan kembali ke nama bawaan saat sesi berakhir atau dibatalkan. Saat island diciutkan, ikon matahari berarti layar tetap menyala, sedangkan ikon laptop berarti Mac tidak akan tertidur saat tidak digunakan. |
| Sistem dan baterai | Informasi CPU, GPU, memori, disk, jaringan, kipas, dan baterai, serta pembersihan cache dan log yang aman dihapus. |
| Masukan suara | Pintasan global untuk merekam dan mentranskripsikan, pengolahan transkrip lokal atau jarak jauh opsional, dan riwayat suara lokal. |

### Titik masuk dan alur kerja saat ini

Pulau memiliki 12 modul: Beranda, Serah Terima, Papan Klip, Pemantauan AI, Suara Papan Ketik, Unduhan, Jadwal, Surel, Catatan, Mixer Volume Aplikasi, Utilitas, dan Sistem. Detail baterai berada di Sistem; tampilan layar terkunci terpisah. Buka alat PDF, gambar, dan audio dari Pengaturan; buka studio rekaman dari Pengaturan atau bilah menu.

- **Perekaman dan pembuatan:** Rekam layar, jendela, atau area dengan audio sistem, mikrofon, dan kamera opsional. Sunting teks, zoom, efek potret dan suara di berbagai trek, pratinjau, lalu ekspor video, GIF, Live Photo, atau audio. Alat gambar menyediakan 9 operasi lokal; audio menyediakan 27.
- **Mixing dan pemutaran:** macOS 14.4+ mendukung volume dan bisu per aplikasi. Pilih keluaran audio di area media dan preferensi pemutar di Pengaturan.
- **Desktop dan rapat:** Pratinjau jendela Dock dan Command+Tab, catatan konteks halaman/jendela/desktop, hitung mundur rapat 10 menit, bergabung, dan catatan terkait. Goyangkan penunjuk saat menyeret berkas untuk menampilkan target jatuh di rak.
- **Ringkasan harian:** 8 templat, pratinjau, ekspor PNG manual atau terjadwal, metrik pilihan, dan folder simpan terpisah.
- **Akun AI:** Lihat kuota akun yang didukung, waktu reset, pemberitahuan kuota rendah, dan waktu pengambilan sampel; ekspor riwayat token lokal sebagai `.xlsx`. Kuota Gemini dan Claude/GPT Antigravity memiliki pemantauan, tampilan, dan peringatan terpisah. Kuota percakapan Gemini App memakai Cookie web dari akun Google yang sama; Gemini CLI tetap terpisah.
- **Tindakan Cepat:** Tindakan popup memakai `Command+1` sampai `Command+0` secara berurutan. Pemicu tambahan default untuk konfigurasi baru adalah `Command+N` bagi tindakan pertama. Peningkatan mempertahankan pintasan tersimpan dan pemicu yang dikosongkan.

[Bantuan pengguna](https://wzz6423.github.io/zisla/help.html?lang=id#help) menyediakan sembilan panduan langkah demi langkah: papan klip, tangkapan, rak, rapat, AI, alat media, ringkasan harian, catatan desktop/pratinjau jendela, serta pemutaran/mixing. [Panduan macOS](mac/README.md) mencantumkan folder simpan dan dependensi alat.

## Mulai menggunakan

### Memasang aplikasi

Unduh DMG terbaru dari [GitHub Releases](https://github.com/wzz6423/zisla/releases) atau [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), pasang image, lalu seret `zisla.app` ke `Applications`.

Pilihan lainnya adalah Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew mengambil build yang sesuai dengan chip, sehingga Mac Apple Silicon atau Intel hanya mengunduh arsitekturnya sendiri. Cask berasal dari tap pihak ketiga `wzz6423/tap`, bukan repositori cask Homebrew sendiri; pemasangannya berarti mempercayai tap ini.

Setelah aplikasi berjalan, arahkan penunjuk ke tengah atas layar saat ini atau pilih **Show Island** dari ikon bilah menu. Paket belum dinotarisasi, sehingga peluncuran pertama dengan metode pemasangan apa pun memerlukan **Open Anyway** di **System Settings > Privacy & Security**, atau hapus atribut karantina sendiri:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Memperbarui aplikasi

zisla memperbarui diri melalui Sparkle dengan metode pemasangan apa pun. Untuk Homebrew, `brew upgrade` hanya mengganti aplikasi jika salinan terpasang benar-benar lebih lama daripada versi tap, karena Homebrew 5.1.6 dan lebih baru membaca versi di dalam bundle aplikasi. Ini memberi ruang bagi Sparkle tanpa menyisakan pemasangan usang. Menyebut nama cask memakai catatan pemasangan Homebrew dan dapat mengembalikan aplikasi yang sudah diperbarui Sparkle ke versi tap:

```bash
brew upgrade --cask zisla
```

Tap hanya menyediakan rilis stabil; build pratinjau tetap di Releases sehingga `brew upgrade` tidak beralih ke prarilis. Menyebut nama cask ketika memakai pratinjau menggantinya dengan build stabil saat ini. Sparkle tidak menurunkan versi, sehingga kembali ke Release mempertahankan pratinjau hingga rilis stabil melampauinya. `brew uninstall --cask zisla` menghapus aplikasi; `brew uninstall --zap --cask zisla` juga membuang data lokal.

### Menjalankan dari sumber

Diperlukan Swift 6 / Xcode 16+; Command Line Tools saja juga dapat membangun proyek.

```bash
cd mac
swift run zisla
```

Pengunduh memerlukan `yt-dlp`; `ffmpeg` opsional. Konversi Office ke PDF memerlukan LibreOffice atau OpenOffice. Petunjuk build, tes, dan pengemasan ada di [panduan pengembangan macOS](mac/README.md).

## Dirancang agar tidak mengganggu

- Mendukung banyak layar, Spaces, dan aplikasi layar penuh biasa tanpa mengaktifkan atau mengambil fokus dari aplikasi saat ini.
- Saat beberapa layar terhubung, Pengaturan → Umum → Mode Layar memungkinkan Anda memilih mode Dynamic Island (posisi kamera atau kustom), mode notch, atau sembunyikan untuk setiap layar. Dengan satu layar, pengaturan ini disembunyikan dan tampilan global digunakan; menghubungkan kembali memulihkan konfigurasi tersimpan setiap layar. Semua layar yang diaktifkan menampilkan island yang diciutkan secara bersamaan. Memperluas island, tindakan cepat, perekaman, dan pesan sementara hanya mengganti island pada layarnya sendiri; pemilihan layar notifikasi menyaring konten tanpa menyembunyikan island yang sedang tidak aktif.
- Keadaan tersembunyi tidak memiliki jendela transparan permanen sebagai area sentuh dan tidak menjalankan loop frame; pemantauan peristiwa global dan pemeriksaan geometri memicu pembukaan.
- Memakai satu material sistem dan beralih ke latar buram ketika Reduce Transparency aktif.
- Mendeteksi notch fisik dari area aman sistem; layar eksternal tanpa notch memakai overlay dengan bentuk yang sama.

Lihat [desain arsitektur dan kinerja](mac/Docs/architecture.md) untuk pertimbangan implementasinya.

## Privasi dan izin

zisla meminta izin hanya ketika fitur yang aktif pertama kali memerlukannya. Modul dapat dimatikan di Pengaturan dan otorisasi dicabut di Pengaturan Sistem macOS kapan saja.

| Lingkup | Batas |
| --- | --- |
| Aktivitas AI | Hanya peristiwa terstruktur dan metadata aktivitas lokal. Prompt dan isi jawaban tidak pernah dibaca. |
| Papan klip dan berkas | Riwayat, deteksi tautan, dan Tindakan Cepat adalah sakelar lokal terpisah. Tindakan Cepat menangani unduhan selesai dan berkas AirDrop secara independen dari sakelar progres unduhan peramban. Pengenalan sepenuhnya di perangkat; tautan dan tindakan hanya berjalan setelah klik atau tekanan pemicu eksplisit. Serah terima memakai security-scoped bookmark tanpa menyalin berkas asal. |
| Catatan, surel, suara | Catatan dan surel memakai AppleScript/JXA dengan izin otomasi. Suara direkam hanya saat aktif; pengolahan transkrip mengirim teks hanya ke model lokal, penyedia jarak jauh, atau profil CLI terpilih. |
| Unduhan peramban dan media | Memakai progres berkas publik macOS, metadata MediaRemote, dan status keluaran Core Audio. Basis data riwayat peramban tidak dibaca. Bentuk gelombang sistem dan mixing aplikasi memproses audio lokal; perekaman menyimpan audio hanya jika sumber terkait diaktifkan. |
| Jaringan | Cuaca, IP publik, pemilihan mirror pembaruan, unduhan, pemeriksaan kuota AI aktif, dan pemasangan dependensi/CLI menghubungi layanannya. Terjemahan, pengolahan suara, dan penyuntingan rekaman AI opsional memakai penyedia atau CLI terpilih. Pengenalan suara Apple dapat memakai jaringan sesuai dukungan sistem dan bahasa. |

### Izin menurut fitur

Izin diminta saat pertama memakai fitur. Jika sebelumnya menolak, buka bagian yang sesuai di **System Settings > Privacy & Security** lalu izinkan `zisla`; nama bagian dapat berbeda antarversi macOS.

| Izin atau pengaturan sistem | Kapan diperlukan | Akses yang diizinkan |
| --- | --- | --- |
| Kendali Perangkat dan Akses Data (Accessibility pada sebagian versi) | Memasukkan transkrip otomatis ke kolom teks aplikasi saat ini | Membaca dan mencari kolom nonkata sandi, kemudian mengirim transkrip melalui API Accessibility atau `Cmd+V`. Tanpa izin, transkrip tetap disalin ke papan klip. |
| Mikrofon | Masukan suara atau mikrofon studio aktif | Menangkap mikrofon terpilih untuk merekam atau pemantauan aktif. |
| Pengenalan Ucapan | Mengubah ucapan rekaman menjadi teks | Hanya memproses ucapan yang aktif direkam. Masukan suara perlu izin Mikrofon dan Pengenalan Ucapan. |
| Akses Disk Penuh | Melihat surel ketika Mail.app tidak berjalan | Membaca indeks lokal `~/Library/Mail` untuk akun, pengirim, subjek, ringkasan, waktu, dan status baca. Jalur akses indeks ini memerlukan otorisasi. |
| Otomasi | Membaca, menulis, membalas, menandai, atau menghapus Mail.app; membaca dan menulis Apple Notes | Mengizinkan kendali atas aplikasi sistem terkait. Izin Mail dan Notes dapat dicabut terpisah. |
| Kalender; Pengingat | Modul jadwal | Membaca dan mengelola acara dan pengingat dengan izin terpisah. |
| Layanan Lokasi | Cuaca lokasi saat ini | Meminta lokasi sekali tanpa pelacakan terus-menerus. Lokasi manual tidak memerlukan izin lokasi. |
| Kamera | Cermin atau pratinjau/perekaman kamera studio | Menggunakan kamera terpilih selama fitur aktif. |
| Pemantauan Masukan | Suara, statistik mengetik, pembersihan papan ketik, serta pintasan modifier saja/tombol samping | Mengamati peristiwa fitur aktif; statistik tetap lokal. Pintasan global biasa tidak memerlukan izin ini. |
| Bluetooth | Baterai aksesori di Sistem → Baterai | Membaca informasi baterai publik dari perangkat terhubung atau berpasangan saja. |
| Rekaman Layar & Audio Sistem (Screen Recording pada macOS lama) | Tangkapan, pratinjau, rekaman, bentuk gelombang, mixer aplikasi | Membaca gambar layar dan sumber audio terpilih. Rekaman menyimpan sumber aktif secara lokal; mixer memerlukan macOS 14.4+. |
| Notifikasi | Peringatan Pomodoro | Satu bunyi dan notifikasi lokal saat timer berakhir. |
| Folder pilihan pengguna (tanpa otorisasi manual) | Serah terima, impor/ekspor, folder unduhan | Pemilih berkas sistem memberi akses direktori terpilih. Fitur ini tidak memerlukan Akses Disk Penuh. |

Pencabutan izin hanya mematikan fitur terkait. Jika fitur masih tidak tersedia setelah perubahan, tutup dan buka kembali zisla, lalu coba lagi.

[Panduan macOS](mac/README.md) mendokumentasikan seluruh perilaku izin dan jaringan.

## Dokumentasi

| Dokumen | Tujuan |
| --- | --- |
| [Panduan pengembangan macOS](mac/README.md) | Modul, integrasi AI, dependensi, build, tes, izin, keterbatasan sistem. |
| [Panduan situs — Inggris](../../../web/README.md) | Pengembangan lokal, build produksi, tautan unduhan saat ini. |
| [Panduan film peluncuran — Inggris](../../../promo/README.md) | Pratinjau Remotion, rendering, komposisi, musik, lisensi aset. |
| [Desain arsitektur dan kinerja](mac/Docs/architecture.md) | Pemicu tepi atas, perilaku jendela, konkurensi, media, keamanan unduhan. |
| [Referensi integrasi CLI](mac/Docs/cli-reference.md) | Penyedia, perintah, kolom, kode keluar `zislactl`. |
| [Desain penandatanganan dan rilis](mac/Docs/releasing.md) | Tanda tangan, notarisasi, DMG, kanal pembaruan, penerimaan rilis. |
| [Panduan kontribusi](CONTRIBUTING.md) | Lingkungan pengembangan, branch, commit, persyaratan pull request. |

## Kontribusi

Issue dan pull request dipersilakan. Baca [panduan kontribusi](CONTRIBUTING.md) dahulu. Laporkan keamanan secara pribadi melalui [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), bukan issue publik.

## Lisensi

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Penggunaan nonkomersial diizinkan; penjualan perangkat lunak atau penggunaan komersial lainnya tidak diizinkan.
