# Berkontribusi pada zisla

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../README.md)

Terima kasih telah berkontribusi pada zisla.

## Laporan masalah

Terima kasih telah membuka issue. Cari Issues dan Discussions yang ada dahulu agar laporan tidak berulang.

- Gunakan `[Bug] Short problem description` untuk bug, misalnya `[Bug] Voice input is not written to the current text field`. Sertakan versi zisla, macOS dan perangkat, metode pemasangan, langkah reproduksi, perilaku yang diharapkan dan yang terjadi.
- Gunakan `[Feature] Short request description` untuk fitur, misalnya `[Feature] Support custom voice-organization prompts`. Jelaskan masalah, solusi yang diusulkan, dan alternatif yang dipertimbangkan.
- Pilih satu **Area** wajib pada formulir. Ini menentukan label `area:*`: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation`, atau `Community & Discussion`. Formulir Tionghoa Sederhana menyediakan pilihan dan pemetaan label yang sama.
- Hapus token, detail akun, jalur lokal, dan informasi sensitif lain dari log, tangkapan, serta rekaman.
- Laporkan kerentanan secara privat melalui [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), bukan issue publik.
- Otomasi memberikan `bug` atau `enhancement` serta `area:*` terkait, tanpa mengubah label lain. Jika awalan judul atau kolom wajib tidak sesuai, `needs-more-info` ditambahkan dan satu komentar menjelaskan kekurangan; penyuntingan issue memperbarui komentar tersebut.

## Pengembangan

Implementasi macOS saat ini berada di `mac/` dan memerlukan macOS 14+ dengan Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Hapus binary tes, build, dan pengemasan sebelum commit.

Sebelum setiap commit atau amend, jalankan `make format` dari root dengan SwiftFormat 0.64.7 yang sama seperti CI. Tinjau diff dan pertahankan hanya format yang diperlukan tugas saat ini.

## Branch dan commit

- Buat branch dari `main` terbaru dengan awalan sesuai jenis PR: `feat/` (atau `feature/`), `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`. Contoh: `fix/download-timeout` atau `ci/skip-directive-timing`.
- Gunakan [Conventional Commits](https://www.conventionalcommits.org/) berbahasa Inggris, seperti `type(scope): description` atau `fix(ui): resolve layout issue in notch area`.
- Satu branch dan satu PR fokus pada satu tujuan jelas; hindari perubahan format saja serta refaktor yang tidak terkait.
- Branch `publish-v*` khusus pemeliharaan rilis. Kontribusi lain ditujukan ke `main`.

## Permintaan penggabungan

Terima kasih telah membuka PR. Periksa persyaratan ini ketika menunggu review.

- **Judul PR** harus berupa subjek Conventional Commit berbahasa Inggris, misalnya:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Jenis yang diizinkan: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`, `revert`.

- **Isi PR** harus berbahasa Inggris dan memiliki bagian `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` dari `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` mempertahankan `- Project: zisla Development`. `Project Automation` membacanya untuk menempatkan PR di board bersama.
  - `Start date` dan `Target date` wajib dalam `GitHub Project`, masing-masing tepat sekali sebagai tanggal valid `YYYY-MM-DD`; target harus sama atau sesudah awal. Tanggal hilang, kosong, dikomentari, berulang, atau tidak valid menggagalkan `PR Quality`. `Submitted date` otomatis memakai tanggal pembuatan UTC+08:00; `End date` terisi saat merge. Keduanya tidak perlu diisi manual.
  - `PR Type` berisi tepat satu `- Type:` yang cocok dengan tipe judul. Judul memakai tipe kanonis; isi menerima nama label dan alias: `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` semuanya menjadi `fix`. `PR Automation` mengubah tipe menjadi label, misalnya fix menjadi bug.
  - `Project Automation` memilih `Status` dari pemetaan label, termasuk jenis PR, dan mengaturnya `Done` saat ditutup/merge. Jangan memasukkan Status manual.
  - `Summary` menjelaskan perubahan; `Risk and Rollback` wajib tepat satu kolom `Risk` dan satu `Rollback` yang tidak kosong.
  - Setiap entri `Validation` dimulai `- Status:` miliknya dengan nilai tepat `passed`, `failed`, atau `not run`. passed/failed perlu `Command` dan `Result` sendiri yang tidak kosong; not run perlu `Reason` sendiri. Kolom entri lain tidak memenuhi syarat. Laporkan kegagalan sebagai failed dengan jujur.
  - `Related Issue` menutup issue lewat kata seperti `Closes #123`, juga memberi `development`, atau berisi tepat `None`.
  - `AI Attribution` memiliki tepat satu `- Agent:` tidak kosong. Agent selain `None` memerlukan `- Co-authored-by: Name <email>` yang sama sebagai trailer setidaknya satu commit dan memberi `ai-assisted`.

  Contoh judul: `fix(ci): validate every PR metadata entry`

  Contoh isi (catat validasi yang benar-benar dilakukan):

  ```markdown
  ## Summary
  - Validate every PR metadata field and each Validation entry independently.
  - Keep contributor welcome replies aligned with the current PR template.

  ## GitHub Project
  - Project: zisla Development
  - Start date: 2026-10-05
  - Target date: 2026-10-12
  <!--
  Automatic Project fields (illustration only; not PR body inputs):
  - Submitted date: 2026-10-05 (PR creation date in UTC+08:00)
  - End date: 2026-10-12 (assumed merge date in UTC+08:00; blank before merge)
  Automation updates Project date fields and the PR Timeline; it does not fill these comment lines.
  -->

  ## PR Type
  - Type: fix

  ## Validation
  - Status: passed
  - Command: ruby .github/scripts/pr-metadata-test.rb
  - Result: All PR metadata contract tests passed.

  - Status: passed
  - Command: ruby .github/scripts/contributor-welcome-test.rb
  - Result: Both documented examples pass PR validation and the welcome reply preserves the complete example.

  - Status: passed
  - Command: actionlint .github/workflows/*.yml
  - Result: All workflow files passed actionlint.

  - Status: not run
  - Reason: Local macOS tests were not run because this change only affects PR metadata and contributor guidance. Platform checks still run in CI.

  ## Risk and Rollback
  - Risk: Stricter metadata checks may reject incomplete PR descriptions; no application behavior changes.
  - Rollback: Revert this pull request to restore the previous metadata checks and guidance.

  ## Related Issue
  None

  ## AI Attribution
  - Agent: Codex
  - Co-authored-by: Codex <noreply@openai.com>
  ```

  Contoh tanggal: PR dibuat 2026-10-05 dan merge 2026-10-12 (UTC+08:00). Kolom otomatis dalam komentar kode menggambarkan nilai Project, bukan masukan. Otomasi memperbarui GitHub Project dan PR Timeline, bukan komentar contoh.

  | Tanggal | Saat pembuatan (2026-10-05) | Setelah merge (2026-10-12) | Sumber |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Masukan wajib |
  | `Target date` | 2026-10-12 | 2026-10-12 | Masukan wajib |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Tanggal pembuatan otomatis |
  | `End date` | Kosong | 2026-10-12 | Tanggal merge otomatis |

- `PR Quality` memvalidasi format; PR tidak dapat merge selama gagal. `PR Automation` kemudian memberikan label dan penugasan.
- Jalankan `cd mac && swift test` untuk kode macOS; jelaskan hasil manual dalam teks untuk perubahan UI.
- Isi PR dan catatan rilis dapat berupa teks saja; gambar, tangkapan, dan sampul tidak wajib.
- Perbarui dokumentasi resmi dan bantuan situs dalam patch yang sama saat mengubah fitur, perilaku, default, instruksi build, atau rilis. Teks situs mencakup 17 bahasa; gunakan struktur bantuan dan direktori lokal yang ada.
- Jangan commit `.build`, `dist`, unduhan, log, token, bahan penandatanganan, atau data pribadi.
- `main` dan `publish-v*` dilindungi dan hanya diubah melalui PR yang direview serta lulus pemeriksaan.

## Melewati CI

Maintainer dan reviewer yang diminta dapat melewati pemeriksaan yang tidak terpengaruh, misalnya perbaikan dokumen saja. Tulis direktif pada baris sendiri dalam komentar PR:

| Direktif | Efek |
| --- | --- |
| `skip-all` | Melewati semua workflow dalam `.github/ci-skip.json`. |
| `skip-<workflow>` | Melewati satu workflow menurut nama, berkas, atau alias, seperti `skip-swift`, `skip-web-ci`, `skip-Web CI`. |
| `unskip-all` | Menghapus semua direktif skip. |
| `unskip-<workflow>` | Memulihkan satu workflow. |

- Teks bebas boleh mengikuti, misalnya `skip-all: documentation only change`.
- Nama boleh sesuai tampilan GitHub termasuk spasi; `skip-CI Lint` dan `skip-lint` setara. Kecocokan nama terpanjang menang; sisanya menjadi catatan.
- Hanya direktif pemilik, anggota organisasi, kolaborator, atau reviewer yang diminta dihormati. Komentar bot diabaikan.
- `CI Skip` membatalkan run aktif, melaporkan skip berhasil agar syarat terpenuhi, memberi `skip-ci`, dan menyunting satu komentar ringkasan keputusan.
- Seluruh thread diputar ulang tiap komentar, sehingga direktif terbaru menang.
- Direktif kedaluwarsa segera setelah commit baru didorong: hanya berlaku pada kode yang dilihat penulisnya, agar status berhasil tidak mengizinkan merge kode baru tanpa build. Setiap push `CI Skip` menghapus label dan memulihkan pemeriksaan, serta menyebut direktif yang kedaluwarsa. Komentari lagi untuk commit baru.
- Maintainer dapat menerapkan keputusan kembali lewat **Actions -> CI Skip -> Run workflow** dengan nomor PR, tanpa komentar baru.
- `.github/ci-skip.json` memetakan workflow ke nama check. Ketidaksesuaian dengan berkas workflow menggagalkan `CI Checks`.

## Pemeriksaan menurut path

Workflow platform menjalankan pemeriksaan hanya bila PR menyentuh berkas yang dibangunnya. Perubahan dokumentasi dinilai menurut lokasinya:

| Workflow | Path yang memicu |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- Lingkup diatur `paths` dalam `.github/ci-skip.json`; workflow tanpa lingkup selalu berjalan. `CI Lint`, `PR Quality Gates`, `CodeQL`, `Dependency Review` berjalan pada semua PR. Kebersihan repositori dan validasi skill bagian `CI Checks`; alias lama `hygiene` dan `skills` tidak digunakan.
- Perubahan `.github/` menjalankan semuanya agar perubahan CI dibuktikan pada semua platform.
- Job dilewati memakai kondisi job, bukan filter workflow `paths:`, sehingga required check melaporkan sukses, bukan selamanya pending.
- Nama berkas yang berubah diperiksa pada path lama dan baru, tanpa membedakan huruf besar/kecil.
