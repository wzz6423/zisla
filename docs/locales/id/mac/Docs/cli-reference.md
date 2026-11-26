# Referensi integrasi `zislactl`

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **Bahasa Indonesia** | [Bahasa lain](../../../README.md)

`zislactl` adalah protokol status lokal bersama untuk alat AI, skrip, dan tugas CI yang terintegrasi dengan zisla. Status tugas, penggunaan, dan notifikasi ditulis sebagai data terstruktur dalam transaksi SQLite agar tidak ada status yang tertulis sebagian. Dokumen ini menetapkan penyedia, perintah, dan batas kolom yang stabil.

## Prinsip desain

- Status ditulis lokal; prompt, isi jawaban, dan kredensial tidak diunggah.
- Pembaruan ID tugas yang sama idempoten; pembaca melihat status basis data yang sudah dikomit lengkap.
- Nama penyedia menerima alias kompatibilitas, tetapi disimpan memakai nilai kanonis.

## Penyimpanan lokal dan batas JSON

Tugas, penggunaan, dan pemberitahuan berada di `~/Library/Application Support/zisla/ai-state.sqlite`. Penulisan memakai transaksi SQLite; protokol saat ini tidak menulis `ai-state.json`. Mengosongkan tugas mempertahankan riwayat penggunaan.

`zislactl` menerima opsi baris perintah yang didokumentasikan, dan `list` menampilkan teks per baris. Integrasi dan konfigurasi tetap memakai JSON terstruktur, termasuk masukan sesi JSON/JSONL alat luar serta pengodean/dekode pengaturan, mengikuti aturan parser masing-masing. CLI sendiri memakai argumen, keluaran teks, dan penyimpanan SQLite.

## Penyedia

| Nilai | Alias |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy dan WorkBuddy AI adalah produk berbeda untuk pasar domestik/internasional, bukan versi lama/baru satu klien. Penyedia kanonis, penyimpanan, ikon, dan deep link harus tetap terpisah. Catatan WorkBuddy historis dengan `harness` tetap terbaca; penyedia itu tidak diganti nama atau dimigrasikan secara global. ID pemberitahuan aktivitas memiliki batas penyedia/tugas eksplisit (`ai-active-workbuddy:<id>` atau `ai-active-workbuddy-ai:<id>`), sehingga tugas manual WorkBuddy dengan ID berawalan `ai-` tidak disalahartikan sebagai WorkBuddy AI.

### Deteksi otomatis Delta, Orca, WorkBuddy, dan WorkBuddy AI

- Delta membaca metadata thread streaming terindeks dari `Library/Application Support/Delta/user_*/data.sqlite` serta basis data root lama. Thread diarsipkan, menganggur, atau usang dikecualikan. Penggunaan angka berasal dari buku besar `app_model_usage_daily` termasuk baca/tulis cache. Rilis tanpa buku besar ini tidak melaporkan penggunaan otomatis dan tidak menebak dari isi percakapan.
- Orca membaca snapshot lokal `agent-hooks/last-status.json` dan status giliran chat terstruktur saat ini dari `agent-session-journal.db`, termasuk direktori profil dan catatan v1/v2/v3. Revisi tertinggi dan urutan giliran asli dihormati. Sesi selesai, kedaluwarsa, jarak jauh, atau identitas saja dikecualikan. Jalur transkrip otoritatif dan direktori akun Claude/Codex yang disematkan juga menyumbang token. Sampel mempertahankan penyedia CLI dan identitas peristiwa sehingga detektor CLI biasa tidak menghitungnya ulang. Cache penggunaan seluruh mesin Orca sengaja tidak diimpor sebagai penggunaan tambahan.
- WorkBuddy membaca `~/.workbuddy/workbuddy.db` sendiri dengan penyedia `workbuddy`, ikon WorkBuddy, dan tautan `workbuddy://chat/<id>`. Penyimpanan WorkBuddy AI tidak diperiksa.
- WorkBuddy AI membaca status, judul, model, dan waktu sesi di `~/.workbuddy-ai/workbuddy.db`, independen dari `~/.workbuddy/workbuddy.db`. Sesi selesai, dihapus, dan usang dikecualikan; nilai lebih baru antara `updated_at` dan `last_activity_at` menjaga sesi panjang tetap terlihat. Tugas memakai `workbuddy-ai`, ikon WorkBuddy AI, serta `workbuddy-ai://chat/<id>`. Integrasi ini hanya mendeteksi sesi: `session_usage.used` adalah okupansi konteks dan kredit bukan USD/token, sehingga keduanya tidak diimpor sebagai token yang ditagih. Angka manual dapat dikirim lewat `zislactl usage`.
- Semua integrasi hanya-baca dan berusaha sesuai data yang tersedia; penyimpanan hilang/tidak kompatibel menghasilkan tanpa data. Isi thread Delta yang direplikasi dan isi pesan jurnal Orca tidak dibaca. Gunakan `zislactl usage` untuk alat/versi yang tidak menyediakan penggunaan angka tercatat.

## Sintaks opsi

- Tulis `--key value` atau `--key=value`. Opsi hanya boleh muncul sekali per perintah; pengulangan adalah kesalahan penggunaan, kode keluar 64.
- Nilai dapat dimulai `--` seperti `--detail --verbose`. Pengecualian adalah flag perintah yang sama: `--failed` untuk `finish` dan `--queued` untuk `update` tidak diperlakukan sebagai nilai. Variabel kosong tanpa kutip dalam `--detail $DETAIL --failed` tetap menandai tugas gagal. Kirim nilai literal seperti itu dengan `--detail=--failed`.
- `--failed` dan `--queued` adalah flag. Sendiri berarti true; `--failed=false` atau `--failed false` serta padanannya untuk queued mematikannya. Nilai lain adalah kesalahan penggunaan.

## `update`

Membuat atau mengganti tugas dengan `id` sama.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Tanpa `--progress`, UI menampilkan progres tak tentu.
- `--pid` opsional, hanya diberikan jika pemanggil dapat menentukan proses tugas.
- `--status` melaporkan sedang berjalan, antre, menunggu tindakan pengguna, atau kesalahan saat berjalan secara eksplisit.
- `--queued` adalah alias `--status queued`; tanpa status eksplisit tugas berjalan. `--status` eksplisit lebih utama daripada `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Tugas berhasil menjadi 100%; tugas gagal mempertahankan progres terakhir.

## `remove`

```text
zislactl remove --id <id>
```

Keluar dengan kode 65 jika tugas tidak ada.

## `clear`

```text
zislactl clear
```

Mengosongkan tugas tanpa menghapus riwayat penggunaan dan notifikasi.

## `list`

```text
zislactl list
```

Menampilkan status, penyedia, judul, dan persentase tugas, satu per baris.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Penggunaan mengisi grafik 12 jam dan peta panas 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

Notifikasi muncul dari sisi terpilih, dan penutupan otomatis berhenti sementara saat disorot penunjuk.

## `message`

Mengirim satu notifikasi ke kedua sisi pulau: logo aplikasi dan pengirim di kiri, isi bergulir di kanan.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Contoh:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`, `--content` wajib; `--app-bundle-id` opsional untuk mencari ikon aplikasi terpasang.
- Baris baru dan spasi berlebih digabung; isi dipotong sekitar 48 karakter dengan elipsis.
- Satu transaksi SQLite menyimpan dua entri `IslandNotice` tanpa mengubah perilaku `notify` yang ada.

## Kode keluar

| Kode | Arti |
| --- | --- |
| `0` | Berhasil |
| `64` | Argumen atau subperintah tidak valid |
| `65` | Kesalahan data, tugas hilang, basis data rusak |
| `70` | Kesalahan sistem berkas atau runtime lain |
