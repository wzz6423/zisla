# Desain penandatanganan dan rilis

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../../../README.md)

Proses rilis lengkap, dua kanal pembaruan, dan sinkronisasi aset GitHub/Gitee dikelola oleh [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Halaman ini hanya menjelaskan batas desain penandatanganan, notarisasi, dan paket pembaruan; ikuti skill tersebut ketika menerbitkan rilis.

Kedua kanal terpilih memakai Sparkle untuk memverifikasi ZIP dan appcast bertanda tangan sebelum mengganti dan meluncurkan ulang aplikasi. Kode negara koneksi publik dicari sekali per peluncuran: `CN` memeriksa Gitee dahulu lalu mencoba GitHub tepat sekali; negara lain memeriksa GitHub dahulu lalu Gitee sekali. Pencarian gagal tetap mendahulukan Gitee. `package-release.sh` memerlukan `SPARKLE_GENERATE_APPCAST` menunjuk `generate_appcast` Sparkle 2.9.4 dan menulis `appcast-gitee.xml` serta `appcast-github.xml` di samping ZIP/DMG. Setiap appcast ditandatangani sendiri dan menunjuk ZIP dari eksekusi yang sama di situsnya sendiri. `build-package.sh` menjalankan skrip per arsitektur sehingga ada tiga pasangan: universal sebagai `appcast.xml` untuk aplikasi sebelum pembaruan per arsitektur, serta `appcast-arm64.xml` dan `appcast-x86_64.xml`. Pemasangan satu arsitektur mengubah URL feed Info.plist sesuai slice yang berjalan; x86_64 terjemahan meminta `arm64`, sehingga tetap pada arsitekturnya, bukan bertambah menjadi universal. Universal menghitung slice sendiri, mempertahankan nama bersama, dan tetap universal. Gitee memakai feed permanen `update-release` (Release) dan `preview` (Preview); GitHub memakai `latest` untuk Release dan prarilis permanen `preview`. Untuk publikasi noninteraktif, atur `SPARKLE_ED_KEY_FILE` ke kunci privat EdDSA yang diamankan, atau kosongkan untuk akun `zisla-update-ed25519` di login keychain. Kunci privat tidak boleh masuk repositori. Rilis stabil default memakai satu sertifikat self-signed agar designated requirement tetap dan izin macOS bertahan setelah pembaruan; rilis ini tetap tidak dinotarisasi. Paket Developer ID sebaiknya dinotarisasi; pratinjau ad-hoc gratis juga tidak dapat dinotarisasi.

## Prasyarat

- Identitas `zisla Release Signing` dalam keychain rilis khusus atau sertifikat Developer ID Application
- Kredensial notarisasi Apple ketika memakai Developer ID
- Helper `yt-dlp` resmi telah diambil dan diverifikasi melalui `Scripts/fetch-yt-dlp.sh`

## 1. Membangun aplikasi bertanda tangan

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Rilis stabil default memakai `RELEASE_SIGNING_MODE=selfsigned`, membaca `zisla Release Signing` dari `~/Library/Keychains/zisla-release-signing.keychain-db`, dan membukanya melalui item `dev.wzz.zisla.release-signing-keychain` dalam login keychain. Ini tidak menghilangkan peringatan peluncuran pertama Gatekeeper, tetapi mempertahankan designated requirement berbasis sertifikat, bukan cdhash setiap build.

Dengan Developer ID, pilih jalur yang dapat dinotarisasi secara eksplisit:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Keluaran:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Distribusi pratinjau gratis

Tanpa Apple Developer Program, buat pratinjau bertanda tangan ad-hoc:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Paket ini tidak dinotarisasi dan tidak memiliki entitlement WeatherKit. Setelah appcast bertanda tangan diterbitkan ke feed Preview permanen, Sparkle memeriksa, mengunduh, memverifikasi, memasang, dan meluncurkan ulang pembaruan Preview. Peluncuran pertama mungkin masih memerlukan **System Settings > Privacy & Security > Open Anyway**. Developer ID dan notarisasi tetap disarankan untuk distribusi tanpa peringatan keamanan.

## 2. Notarisasi

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# Repackage the stapled app so both the ZIP and DMG contain the final artifact.
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 3. Publikasi dan verifikasi

Unggah ZIP, DMG, checksum, dan appcast GitHub ke tag versi GitHub yang sama dengan nama `appcast.xml` (universal), `appcast-arm64.xml`, dan `appcast-x86_64.xml`. Unggah aset yang cocok dan appcast Gitee dengan nama yang sama ke tag Gitee yang sama. Rilis stabil tidak boleh ditandai prarilis. Salin tiga appcast Gitee ke `update-release` permanen; appcast Preview ke `preview` permanen pada kedua situs. Kanal memilih Gitee lalu GitHub bagi `CN` dan urutan sebaliknya untuk negara lain.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Rilis rutin mempertahankan pemeriksaan aset lokal, tanda tangan, checksum, tata letak paket, appcast, aset dua situs, feed permanen, dan metadata rilis. Mengunduh ulang paket, memeriksa pemasangan, dan menerima peningkatan Sparkle nyata hanya dilakukan atas permintaan eksplisit.

Untuk penerimaan pembaruan yang diminta, gunakan aplikasi versi lama untuk memeriksa rilis baru. Pastikan pemeriksaan otomatis dan manual dari koneksi publik `CN` memakai feed Gitee terpilih dahulu dan mencoba GitHub sekali; koneksi lain memakai GitHub dahulu lalu Gitee sekali. Verifikasi Sparkle memasang dan meluncurkan ulang ZIP arsitektur berjalan, dengan pemasangan satu arsitektur tetap satu. Uji Release→Preview, Preview→Release, serta pembaruan kanal yang sama. Pemeriksaan tidak diminta dicatat `Not verified` dan bukan prasyarat menyelesaikan rilis.

## 4. Sinkronisasi cask Homebrew

Rilis stabil berakhir di Homebrew. Preview berhenti sebelum langkah ini: tap hanya menyediakan versi stabil, sehingga `brew upgrade` tidak memindahkan pengguna ke prarilis.

Dari root repositori setelah aset diterbitkan:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Skrip menulis ulang `version` dan dua nilai `sha256` dalam `Casks/zisla.rb`. Digest dibaca dari `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` dan pasangan `x86_64` jika tersedia; jika tidak, dari aset GitHub terbitan. Cask memilih `#{arch}` per mesin agar Apple Silicon/Intel hanya mengambil slice sendiri; verifikasi menolak penggunaan satu digest untuk keduanya. Cask yang gagal `homebrew-cask.rb verify` tidak ditulis, lalu berkas dicerminkan ke `wzz6423/homebrew-tap`. Tanpa `PUBLISH_TAP`, dry run hanya memperbarui cask repositori.

Cask memiliki `auto_updates true` karena Sparkle mengelola pembaruan: `brew upgrade` hanya mengganti ketika bundle terpasang benar-benar lebih lama dari tap, yang ditentukan Homebrew 5.1.6+ dari versi di dalam aplikasi. `brew upgrade --cask zisla` dan `--greedy` memakai catatan Homebrew sehingga dapat mengembalikan versi tap dan membatalkan pembaruan Sparkle. Commit cask bersama kenaikan `latestRelease` situs; CI gagal jika versinya berbeda. Validasi dari root:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Penerimaan unduhan, pemasangan, peningkatan, dan `livecheck` Homebrew dilakukan hanya jika diminta eksplisit. Contoh penerimaan pemasangan:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Pemeriksaan Homebrew yang tidak diminta dicatat `Not verified` dan bukan syarat penyelesaian rilis.
