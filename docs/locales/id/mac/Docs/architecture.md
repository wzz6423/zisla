# Desain arsitektur dan kinerja

[English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../../../README.md)

## Pemicu tepi atas

Keadaan tersembunyi tidak mempunyai jendela transparan. `PointerEdgeMonitor` memasang pemantau `NSEvent` global dan lokal untuk gerakan serta seretan mouse; `ScreenLayoutEngine` hanya memakai geometri untuk menentukan masuknya penunjuk ke area 6 px di tengah atas setiap layar.

Identitas tiap layar stabil melalui pasangan `NSScreenNumber` dan `CGDirectDisplayID`. Tata letak bertumpu pada `screen.frame.maxY` sehingga koordinat negatif, layar bertumpuk vertikal, dan layar eksternal tanpa notch didukung.

Saat beberapa layar terhubung, Pengaturan → Umum → Mode Layar memungkinkan Anda memilih mode Dynamic Island (posisi kamera atau kustom), mode notch, atau sembunyikan untuk setiap layar. Dengan satu layar, pengaturan ini disembunyikan dan tampilan global digunakan; menghubungkan kembali memulihkan konfigurasi tersimpan setiap layar. Semua layar yang diaktifkan menampilkan island yang diciutkan secara bersamaan. Memperluas island, tindakan cepat, perekaman, dan pesan sementara hanya mengganti island pada layarnya sendiri; pemilihan layar notifikasi menyaring konten tanpa menyembunyikan island yang sedang tidak aktif.

## Jendela

Pulau utama mempertahankan satu `.borderless + .nonactivatingPanel`:

- Memakai level `.statusBar` tanpa menutupi layar terkunci atau menu sistem.
- `.canJoinAllSpaces + .fullScreenAuxiliary` mendukung Spaces dan aplikasi layar penuh biasa.
- Pembukaan hover tidak memanggil `NSApp.activate` sehingga fokus aplikasi saat ini tetap.
- Keadaan tersembunyi memakai `orderOut` sehingga jendela transparan tidak mengambil area bilah menu.

Panel notifikasi kiri/kanan dibuat sesuai kebutuhan dan disembunyikan begitu antreannya kosong.

## Status dan konkurensi

- AppKit, status SwiftUI, dan kontrol jendela tetap pada `MainActor`.
- Unduhan, cuaca, dan permintaan GitHub memakai actor.
- Status AI dari hook dipantau lewat peristiwa sistem berkas direktori. Tiap sumber sesi membandingkan mtime dan ukuran berkas sesi/aktivitas lokal terbaru, lalu menggunakan ulang cache parser jika tidak berubah.
- Deteksi otomatis hanya membaca peristiwa terstruktur, penanda status tetap, dan metadata yang perlu untuk status tugas. Isi prompt/jawaban tidak dibaca; kegagalan parser satu penyedia tidak memblokir lainnya.
- Kuota akun AI diperoleh secara terpisah dari setiap penyedia. Kuota Gemini dan Claude/GPT Antigravity memiliki jendela reset dan peringatan sendiri. Kuota percakapan biasa Gemini App memakai Cookie web tersimpan dari akun Google yang sama; Gemini CLI mempertahankan OAuth lokal. Kuota yang tidak tersedia tidak diperkirakan.
- Penundaan lipat memakai `Task` yang dapat dibatalkan dan token generasi sehingga tugas lama tidak menyembunyikan pulau yang dibuka kembali.
- Keadaan tersembunyi tidak memiliki `TimelineView`, timer 60 Hz, atau pengiriman animasi terus-menerus.

## Deteksi media

MediaRemote memberi judul, sampul, progres, dan kontrol. Properti objek proses Core Audio 14.4+ memastikan aliran output aktif dan menyediakan aplikasi sumber alternatif ketika metadata hilang. Daftar proses dan status output memakai listener properti serta verifikasi periodik terbatas. Konten audio tidak pernah ditangkap; izin Screen Recording maupun Accessibility tidak diminta. Sumber dijeda, berhenti, atau bisu tidak dipertahankan di area media.

## Perekaman dan mixing aplikasi

Perekaman layar dan mixer volume terpisah dari deteksi metadata. Rekaman meminta Screen Recording serta izin mikrofon/kamera yang aktif, menyimpan media pilihan lokal, dan mengelola proyek di folder rekaman terpilih. Mixer menggunakan tap Core Audio pada macOS 14.4+ dan memerlukan System Audio Recording.

## Material

macOS 26 memakai SwiftUI `glassEffect` satu lapis; macOS 14/15 memakai `NSVisualEffectView` satu lapis. Reduce Transparency mengubah latar menjadi buram. Pulau tidak menumpuk beberapa lapisan blur/material.

## Batas keamanan unduhan

Swift memulai `yt-dlp` dengan `Process.executableURL` dan larik argumen; URL selalu merupakan nilai argv terpisah setelah `--`. Konfigurasi runtime, plugin, dan exec dinonaktifkan; pipa keluaran dikuras bersamaan, progres diuraikan dengan penanda JSON.

Tugas berhasil hanya jika kode keluar 0, jalur output ada, dan jalur yang diresolusikan tetap di direktori berizin. Tiap tugas hanya membersihkan direktori sementara UUID-nya sendiri.

## Pemeriksaan dan unduhan pembaruan

Kanal terpilih mencari negara koneksi publik sekali per peluncuran. Sparkle mengambil appcast bertanda tangan bagi build terpasang, mengunduh ZIP melalui HTTPS, memeriksa tanda tangan EdDSA arsip/feed sebelum ekstraksi, mengganti aplikasi, dan membuka kembali. `CN` mulai Gitee (`update-release` untuk Release, `preview` untuk Preview) lalu mencoba feed GitHub yang sama sekali; negara lain mulai GitHub lalu Gitee sekali. Kegagalan pencarian mempertahankan Gitee pertama; setiap feed menunjuk ZIP bertanda tangan pada host-nya sendiri. Rilis menerbitkan appcast per arsitektur di samping `appcast.xml` bersama. Pemasangan satu arsitektur meminta slice-nya sendiri (x86_64 terjemahan meminta `arm64`) sehingga tidak diganti universal. Pemasangan universal menghitung slice dalam executable sendiri dan tetap memakai `appcast.xml`, juga melayani versi sebelum pembaruan per arsitektur. Perubahan pengaturan memengaruhi pemeriksaan otomatis/manual dan mereset siklus Sparkle berikutnya. Kunci publik tertanam tidak mengandung informasi akun; kunci privat tetap di macOS Keychain pengelola rilis atau berkas privat lain yang diamankan.
