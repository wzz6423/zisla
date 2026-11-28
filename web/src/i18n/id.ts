import { createCatalog } from './createCatalog';

export const id = createCatalog({
  meta: {
    documentTitle: 'zisla · Ruang kerja dinamis',
    description:
      'zisla adalah ruang kerja macOS native untuk tugas AI, ringkasan harian dan edit rekaman, dengan hewan kustom, tangkapan layar dan izin di satu tempat.',
    ogTitle: 'zisla · Letakkan apa yang terjadi di tempat yang dapat Anda lihat',
    ogDescription:
      'Lihat tugas AI dan kegiatan harian, rekam dan edit di Mac, impor hewan sendiri dan kelola izin di satu tempat.',
  },
  tagline: 'Ruang kerja dinamis native untuk macOS',
  header: {
    navAriaLabel: 'Navigasi utama',
    brandHomeAriaLabel: 'Beranda zisla',
    menuOpenLabel: 'Buka menu navigasi',
    menuCloseLabel: 'Tutup navigasi',
    menuButtonTitle: 'Buka navigasi',
    navItems: {
      help: "Bantuan",
      showcase: 'Fitur',
      ai: 'Alur kerja AI',
      download: 'Unduh',
      changelog: 'Catatan perubahan',
      faq: 'Pertanyaan umum',
      developers: 'Pengembang',
    },
    downloadCta: 'Unduh',
    downloadCtaAriaLabel: 'Buka bagian unduhan',
    languageLabel: 'Bahasa antarmuka',
    themeLabel: 'Tampilan',
    themeModes: { auto: 'Otomatis (sistem)', light: 'Mode terang', dark: 'Mode gelap' },
  },
  hero: {
    eyebrow: 'RUANG KERJA MACOS NATIVE',
    title: 'zisla<br><em>Letakkan yang terjadi<br>tepat di tempat yang dapat Anda lihat.</em>',
    lede:
      'Kumpulkan tugas AI, media, berkas, dan agenda di bagian atas layar. Setelah menyalin sesuatu, bilah tindakan cepat terpisah menampilkan pratinjau dan menyarankan langkah berikutnya. Muncul saat dibutuhkan lalu menyingkir setelah selesai.',
    downloadCta: 'Unduh',
    downloadCtaAriaLabel: 'Unduh',
    sourceCta: 'Lihat kode sumber',
    sourceCtaAriaLabel: 'Lihat kode sumber zisla di GitHub',
    hints: [
      'Gerakkan penunjuk ke bagian atas layar untuk membuka, tanpa klik',
      'Setelah menyalin, tekan Command+N untuk langkah cerdas berikutnya',
      'Menutup sendiri tanpa mengganggu pekerjaan',
    ],
  },
  proof: {
    ariaLabel: 'Ringkasan produk',
    items: {
      modules: { title: '{count} modul di bagian atas', desc: 'Aktifkan alur kerja yang Anda perlukan' },
      os: { title: 'macOS 14+', desc: 'Pengalaman desktop native' },
      displays: { title: 'Banyak layar', desc: 'Bekerja pada layar ber-notch dan eksternal' },
      local: { title: 'Lokal terlebih dahulu', desc: 'Status AI tidak pernah membaca percakapan' },
    },
  },
  showcase: {
    eyebrow: 'SATU TITIK MASUK / ALUR KERJA HARIAN',
    title: 'Alur kerja harian, <span>di bagian atas layar.</span>',
    lede:
      'Dari tugas AI hingga clipboard, agenda, dan status sistem, zisla mengumpulkan alur kerja desktop yang tersebar di satu titik masuk.',
    ariaLabel: 'Katalog fitur zisla',
    summaryMono: '{modules} MODUL / {groups} ALUR KERJA',
    summaryLede: 'Dari alur kerja atas layar hingga alat lokal, setiap tugas yang dapat diselesaikan dijelaskan di sini.',
    summaryNote: '{modules} modul di bagian atas dan {features} kemampuan mandiri, dari pratinjau jendela dan tangkapan layar hingga pengelolaan AI dan aplikasi rekomendasi.',
    groupNames: {
      island: 'Alur kerja atas layar',
      ai: 'Alur kerja AI',
      daily: 'Informasi harian',
      tools: 'Utilitas',
    },
    groupCount: '{count} modul',
    pointsAriaLabel: 'Sorotan {name}',
    modules: {
      dashboard: { name: 'Beranda', caption: 'Kartu dinamis hanya muncul saat sesi fokus, tugas AI, atau unduhan berlangsung; saat tidak ada aktivitas, tidak ada ruang yang terpakai. Halaman utama mengelompokkan tugas AI yang berjalan menurut aplikasi.', points: ['Muncul sesuai kebutuhan', 'Progres langsung', 'Tata letak menyesuaikan'] },
      shelf: { name: 'Rak', caption: "Simpan berkas di rak untuk mencari, memilih, dan berbagi. Buat ZIP atau PDF, ubah ukuran atau format gambar, lalu kirim media ke catatan atau studio.", points: ['Pencarian dan tindakan massal', 'Gambar ke PDF dan Catatan cepat', 'Edit video di studio'] },
      clipboard: { name: 'Clipboard', caption: "Cari riwayat lokal dan teks dalam gambar. Filter menurut jenis atau aplikasi, simpan favorit, dan kirim entri ke Catatan Cepat.", points: ['Riwayat di dalam pulau', 'Filter berdasarkan jenis', 'Catatan cepat dan favorit'] },
      aiMonitor: { name: 'Monitor AI', caption: 'Menggabungkan tugas dan status dari CLI AI, aplikasi desktop, dan IDE. Angka pemakaian yang andal menghasilkan tren token dan peta aktivitas; pilih tanggal untuk melihat token masukan, keluaran, dan total menurut penyedia serta model. Lihat riwayat, ekspor seluruhnya sebagai .xlsx, atau hapus di Pengaturan. Menampilkan sisa kuota akun yang sebenarnya, waktu reset, dan peringatan kuota rendah, termasuk periode 5h/7d serta anggaran Cursor dalam dolar jika tersedia. Tidak membaca teks prompt atau balasan. Tata letak ringkas juga menampilkan sisa kuota dalam bentuk cincin. Pilih wilayah akun secara terpisah; catatan penggunaan harian dan warna sisa kuota tetap konsisten di semua tata letak. Kuota Gemini dan Claude/GPT Antigravity memiliki pemantauan, tampilan, dan peringatan terpisah. Kuota percakapan Gemini App memakai Cookie web dari akun Google yang sama; Gemini CLI tetap terpisah.', points: ['Tugas dari berbagai alat AI', 'Riwayat model dan ekspor .xlsx', 'Kuota akun dan waktu reset'] },
      keyboardSound: { name: 'Suara keyboard', caption: 'Memutar 20 suara keyboard mekanis bawaan untuk penekanan tombol global, dengan volume dan variasi nada yang dapat diatur. Aktifkan statistik mengetik lokal untuk melihat ringkasan, tren, riwayat, lini masa aplikasi, dan peta tombol F1-F12. Total suara, durasi dikte, kecepatan dan waktu yang dihemat juga ada di dasbor keyboard. Konfigurasi baru mengaktifkan suara dan statistik, yang bisa dimatikan terpisah.', points: ['20 suara bawaan', 'Suara lepas dan variasi nada', 'Statistik bisa diubah terpisah'] },
      download: { name: 'Pengunduh', caption: 'Tempel tautan atau biarkan zisla mengenali tautan dari clipboard setelah diaktifkan. Pilih video atau audio dan unduh ke folder default atau folder pilihan. Tautan yang didukung menampilkan sumber, progres langsung, dan status selesai. Pilih folder unduhan di Pengaturan → Lokasi Penyimpanan, terpisah dari tangkapan layar dan rekaman. Tautan Bilibili mengunduh bagian yang dipilih. Kelola komponen di Pengaturan → Komponen yang diperlukan, dengan pilihan pembaruan harian untuk komponen yang sudah terpasang.', points: ['Mode video / audio', 'Folder default atau khusus', 'Sumber dan progres langsung'] },
      agenda: { name: 'Agenda dan cuaca', caption: 'Menampilkan cuaca lokasi Anda dan hingga enam tempat pilihan. Lihat, tambah, atau hapus acara serta pengingat, lalu tandai pengingat sebagai selesai. Acara dengan tautan rapat menampilkan hitung mundur 10 menit sebelum mulai dan dapat diikuti dengan satu klik. Buat catatan rapat atau tautkan dan lepaskan catatan kontekstual yang sudah ada. Waktu pembaruan daftar cuaca muncul di bagian atas, di sebelah kiri tombol muat ulang. Jika data cuaca belum lengkap, sumber lain melengkapi hasil terlengkap; data yang tersedia tetap digunakan saat sisanya tidak dapat diambil.', points: ['Cuaca dan kalender', 'Hitung mundur 10 menit', 'Ikuti rapat dan tautkan catatan'] },
      mail: { name: 'Mail', caption: 'Membaca akun yang diaktifkan di Mail. Lihat kotak masuk, tandai satu pesan atau semua pesan masuk sebagai dibaca, balas, tulis, dan pindahkan pesan ke Sampah dari pulau. Pilih lampiran saat menulis; panduan yang jelas ditampilkan jika izin belum ada.', points: ['Akun Mail', 'Balas dan tulis di dalam pulau', 'Panduan izin transparan'] },
      quickNotes: { name: 'Catatan cepat', caption: 'Menggunakan aplikasi Catatan sistem untuk melihat, mengedit, membuat, dan menghapus catatan dengan pratinjau Markdown langsung, serta melompat langsung ke sembilan catatan pertama dengan Command+1 hingga 9. Draf ditulis kembali secara otomatis. Pratinjau lampiran tulisan tangan dan edit teks sebelum atau sesudahnya sambil mempertahankan aslinya. Gunakan Command dan tombol panah untuk berpindah antarcatatan. Teks yang ditempel mengikuti tipografi asli teks utama.', points: ['Data berada di Catatan', 'Editor Markdown', 'Draf tersimpan otomatis'] },
      volumeMixer: {
        name: 'Mixer volume per aplikasi',
        caption: 'Atur volume dan bisukan secara terpisah untuk aplikasi yang memutar audio. Memerlukan macOS 14.4 atau lebih baru dan izin perekaman audio sistem. Pengaturan volume diingat per aplikasi, dan sumber audio lama hilang saat pemutaran berhenti.',
        points: ['Volume per aplikasi', 'Bisukan terpisah', 'macOS 14.4+'],
      },
      toolbox: { name: 'Utilitas', caption: 'Pengatur waktu fokus, layar tetap menyala, pembersihan layar dan keyboard yang memblokir tombol termasuk F1-F12, teleprompter, cermin, dan Sampah dalam satu halaman. Jeda, lanjutkan, atau reset Pomodoro dan lihat progresnya dalam tata letak ringkas horizontal maupun vertikal. Mulai pembersihan berkas yang tidak diperlukan dari utilitas dengan pengaturan pembersihan sistem, lalu pantau progres dan hasilnya di island. Nama pengatur waktu hanya berlaku untuk sesi saat ini dan kembali ke nama bawaan saat sesi berakhir atau dibatalkan. Saat island diciutkan, ikon matahari berarti layar tetap menyala, sedangkan ikon laptop berarti Mac tidak akan tertidur saat tidak digunakan.', points: ['Penghitung fokus', 'Blokir F1-F12 saat membersihkan', 'Teleprompter dan cermin'] },
      system: { name: 'Status sistem', caption: 'Memantau CPU, GPU, memori, disk, jaringan, kipas, dan suhu NVMe SMART yang tersedia. Lihat riwayat per menit pada rentang tanggal, ekspor .xlsx, atau hapus di Pengaturan. Periksa kesehatan, siklus, suhu, kapasitas baterai, daya perangkat sekitar, dan IPv4/IPv6 publik. Pilih mode daya otomatis saat tersambung listrik atau memakai baterai, dengan opsi hemat daya pada 20% atau kurang. Isi segera hingga 100% ketika macOS mengizinkannya. Tinjau cache, log, sisa preferensi, dan ruang kerja AI yang terlantar sebelum memindahkannya ke Sampah; pembersihan opsional dapat berjalan setiap 7, 15, atau 30 hari. Pembersihan terjadwal mati secara bawaan; pilih hanya item tepercaya atau semua item yang dapat diproses, termasuk yang perlu ditinjau. Jalankan pembersihan di latar belakang dengan progres dan hasil di pulau. Temukan instalasi aplikasi duplikat dan sisa pembaruan aplikasi.', points: ['Pemantauan tingkat chip', 'Grafik riwayat dan ekspor .xlsx', 'Tinjau sebelum memindahkan ke Sampah'] },
    },
  },
  extensions: {
    eyebrow: 'DI DALAM DAN DI LUAR PULAU',
    title: 'Di luar pulau, <span>tetap menjadi alat desktop.</span>',
    lede: 'Tangkapan layar, alat gambar dan audio, dikte, media, unduhan browser, serta pengelolaan AI hadir di tempat yang mudah dijangkau.',
    ariaLabel: 'Kemampuan desktop mandiri',
    summaryMono: 'MELAMPAUI PULAU',
    summaryLede: 'Kemampuan yang sering dipakai, masing-masing di tempat yang alami.',
    summaryNote: 'Pratinjau jendela, tangkapan layar, dan Tindakan Cepat mudah dijangkau; aplikasi rekomendasi membantu Anda menemukan lebih banyak alat desktop.',
    features: {
      floatingIsland: {
        title: 'Pulau mengambang yang menyesuaikan tata letak',
        description: 'Gunakan posisi kamera atau pilih posisi sendiri di tepi layar. Posisi kustom diingat saat berganti mode. Tata letak ringkas horizontal dan vertikal menyesuaikan panjang berdasarkan ikon status, tugas AI, unduhan dan media, dengan opsi menampilkan lebih banyak informasi. Atur urutan modul dengan menyeretnya di Pengaturan → Tata Letak Dynamic Island, atau pulihkan urutan bawaan. Prioritas informasi status ringkas juga dapat diatur di halaman yang sama. Saat beberapa layar terhubung, Pengaturan → Umum → Mode Layar memungkinkan Anda memilih mode Dynamic Island (posisi kamera atau kustom), mode notch, atau sembunyikan untuk setiap layar. Dengan satu layar, pengaturan ini disembunyikan dan tampilan global digunakan; menghubungkan kembali memulihkan konfigurasi tersimpan setiap layar. Semua layar yang diaktifkan menampilkan island yang diciutkan secara bersamaan. Memperluas island, tindakan cepat, perekaman, dan pesan sementara hanya mengganti island pada layarnya sendiri; pemilihan layar notifikasi menyaring konten tanpa menyembunyikan island yang sedang tidak aktif.',
        detail: 'Posisi kustom · Ikon status tetap · Informasi adaptif',
      },
      dailyBriefing: {
        title: 'Hari Anda dalam ringkasan harian',
        description: "Pilih dari delapan templat, tentukan data penggunaan, pengetikan, sistem dan aktivitas zisla, lalu lihat pratinjau. Ekspor PNG secara manual atau pada waktu harian pilihan. Riwayat Durasi Layar dipakai saat aktif dan tersedia. Pilih folder ekspor terpisah di Pengaturan → Lokasi Penyimpanan. Anda juga dapat menyertakan sisa kuota akun yang sebenarnya dan waktu pengambilannya.",
        detail: '8 templat · Pilih isi · Pratinjau dan ekspor PNG terjadwal',
      },
      userCare: {
        title: 'Pengingat saat bekerja',
        description: 'Atur interval untuk istirahat, minum, bergerak dan mengistirahatkan mata. Pesan menyesuaikan waktu. Jeda alami, kunci layar dan tidur mereset waktu. Selesai fokus dan tindakan catatan bisa menampilkan umpan balik singkat. Aktifkan atau matikan di Pengaturan.',
        detail: 'Interval dapat diatur · Pesan sesuai waktu · Menghormati jeda dan tidur',
      },
      contextNotes: {
        title: 'Catatan yang terikat tempat',
        description: 'Simpan catatan yang bisa diedit untuk halaman web, jendela aplikasi atau desktop dan lihat saat kembali. Lampirkan tangkapan jendela, kelola catatan di rak, dan atur pengingat berulang dari satu jam hingga tiga hari atau matikan.',
        detail: 'Catatan lokasi · Tangkapan jendela · Pengingat berulang',
      },
      recording: {
        title: 'Rekam dan edit di studio',
        description: "Rekam layar, jendela, atau area, edit trek, takarir serta efek potret/suara, lalu ekspor. Mendukung HDR pada perangkat yang sesuai dan impor dari rak.",
        detail: 'Efek potret dan suara · Jejak kursor berwarna · Pemutaran dan ekspor multitrek',
      },
      permissions: {
        title: 'Izin sistem di satu tempat',
        description: "Tinjau status di Pengaturan → Izin, mulai permintaan yang didukung atau buka halaman sistem terkait. Status izin diperbarui setelah akses diberikan. Bantuan menyeret aplikasi mempermudah izin yang mengharuskan penambahan aplikasi.",
        detail: "Status izin · Permintaan dan tautan",
      },
      imageTools: {
        title: 'Alat Gambar',
        description: 'Sembilan alat lokal di Pengaturan: kompresi; konversi PNG, JPEG, WebP, AVIF, dan JPEG XL; ubah ukuran dan potong; bandingkan format terkecil; putar dan cerminkan; tanda air; mosaik dan buram; kenali teks serta tabel; hapus latar belakang. Ekspor massal atau ZIP, dengan folder tersendiri di Pengaturan → Lokasi Penyimpanan.',
        detail: '9 alat lokal · Lima format · Ekspor massal dan ZIP',
      },
      audioTools: {
        title: 'Alat audio',
        description: '27 operasi lokal di Pengaturan, termasuk konversi, kompresi, potong, pisah, sambung dan campur, ekstraksi audio dari video, normalisasi LUFS, fade, kecepatan dan nada, pengurangan derau dan penghapusan hening, EQ, dinamika, kanal, serta tag. Memerlukan FFmpeg dan ffprobe; pilih berkas atau folder untuk ekspor.',
        detail: '27 operasi lokal · Edit dan campur · FFmpeg dan ffprobe',
      },
      pdf: {
        title: 'Alat PDF',
        description: "Tersedia di Pengaturan. Empat belas operasi di perangkat: gabungkan, pisahkan, putar, pangkas, konversi gambar dan Office, render ke gambar, ekstrak teks, tambahkan watermark dan nomor halaman, enkripsi, hapus kata sandi, dan edit metadata.",
        detail: '14 alat di perangkat · Gabungkan sesuai urutan Anda · Tidak ada yang meninggalkan Mac',
      },

      windowPreviews: {
        title: 'Lihat jendela, klik untuk beralih',
        description:
          'Pratinjau jendela dari Dock atau dengan Command-Tab, lalu klik kartu untuk mengaktifkan jendela. Konfigurasi baru mengaktifkan fitur ini; kelola fitur dan izinnya di Pengaturan. Jendela tertutup dan duplikat disaring, dan pratinjau Dock tetap tersembunyi selama menu konteks terbuka.',
        detail: 'Dock dan Command-Tab · Klik untuk beralih · Dapat diatur',
      },
      capture: { title: 'Tangkapan, tangkapan gulir, dan pin', description: 'Tangkap, sematkan atau gabungkan tangkapan bergulir dengan pintasan yang dapat disesuaikan. Sorot area, ekstrak bagian gambar, bulatkan sudut dan pertahankan anotasi saat ekspor. Kenali dan salin teks, terjemahkan lalu salin hasilnya, atau ekspor tabel ke .xlsx. Simpan tangkapan di rak. Pengaturan memeriksa konflik dengan suara dan Tindakan Cepat. Dialog simpan terbuka di folder tangkapan layar dari Pengaturan → Lokasi Penyimpanan. Tangkapan yang disematkan tetap ada saat mengambil lagi. Gunakan gulir otomatis lambat untuk tangkapan panjang, dan tangkap HDR pada perangkat yang mendukung. Penyesuaian area tangkapan ke jendela juga mencakup jendela pengaturan. Gambar yang disematkan mengikuti ukuran bingkainya saat diperbesar lewat bilah alat atau trackpad, atau saat sudutnya diseret.', detail: 'Sorot dan ekstrak · Pengenalan, terjemahan dan salin · Sudut bulat dan .xlsx' },
      voice: { title: 'Input suara dan pembersihan', description: 'Tekan tombol untuk beralih atau tahan untuk berbicara dengan pengenalan suara sistem, kosakata khusus bidang, dan kata khusus Anda. Jika diinginkan, gunakan Ollama, LM Studio, atau model jarak jauh untuk mengoreksi transkrip tanpa mengubah maknanya dan memformat hal-hal yang disebutkan sebagai daftar secara jelas. Pengaturan → Monitor Sistem dan Pembersihan dapat menghapus audio yang berumur lebih dari 7, 15, atau 30 hari sambil menyimpan transkrip; pembersihan otomatis nonaktif secara default.', detail: 'Dua mode rekaman · Kosakata dan kata khusus · Pembersihan opsional' },
      media: { title: 'Media dan suara latar sistem', description: 'Kendalikan pemutaran dari bagian atas pulau atau pilih suara latar macOS. Suara dapat berhenti saat layar terkunci, screensaver dimulai, atau layar tidur. Pilih gelombang suara atau cahaya sampul; progres pemutaran juga muncul dalam tata letak ringkas dan mengambang.', detail: 'Kontrol pemutaran · Lirik tersinkron · Berhenti otomatis' },
      browserDownloads: { title: 'Progres unduhan browser', description: 'Mendeteksi unduhan Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, dan Arc, lalu menampilkan sumber serta progres langsung di atas. Progres menampilkan nama berkas tujuan yang sebenarnya jika disediakan browser. Keberadaan berkas .crdownload di folder sementara sistem saja tidak memicu tampilan kartu unduhan.', detail: '8 browser · Deteksi sumber · Pemberitahuan selesai' },
      copyAssistant: { title: 'Tindakan Cepat dan langkah berikutnya', description: 'Setelah diaktifkan, teks, tautan, berkas, atau gambar yang disalin dipratinjau di bilah terpisah dengan saran buka, tampilkan di Finder, cari, terjemahkan, hitung, atau simpan—hanya setelah Anda mengonfirmasi. Buka folder berkas melalui Tindakan Cepat setelah unduhan browser atau transfer AirDrop. Mendukung folder unduhan bawaan dan pilihan di Chrome, dengan sakelar terpisah dari tampilan progres unduhan. Alamat IP memiliki tindakan pencarian dan membuka tautan terpisah. Konversi mengenali satuan mata uang kecil; katalog mencakup Emoji 18.0. Teks dan gambar yang disimpan memakai folder Tindakan Cepat terpisah di Pengaturan → Lokasi Penyimpanan. Jika aplikasi tidak dapat dibuka, Tindakan Cepat memeriksa integritas, tanda tangan, dan kebijakan keamanan macOS, lalu menghapus atribut karantina dan membukanya setelah pemeriksaan berhasil. Atur urutan tindakan per jenis yang dikenali di Pengaturan → Tindakan Cepat. Jumlah uang mendukung simbol regional dan kode mata uang dengan prefiks. Deteksi perintah mendukung here-document.', detail: 'Sakelar opsional · Pengenalan lokal · Command+N sebagai default' },
      aiManagement: { title: 'Pengelolaan CLI AI dan Skills', description: 'Deteksi, pasang, perbarui, dan hapus CLI AI dari Pengaturan, serta tinjau dan kelola Skills lokal agar lebih jarang berpindah terminal.', detail: 'Deteksi dan pasang · Perbarui dan hapus · Skills lokal' },
      pet: { title: 'Hewan peliharaan pulau', description: 'Pilih dari katalog hewan dan karakter yang diperluas, atau impor gambar, animasi atau video yang didukung dan beri nama. Lihat pratinjau peliharaan dan pilih satu untuk ditampilkan terus, atau izinkan zisla mengundi dari daftar Anda setiap tengah malam waktu setempat atau pada interval khusus. Letakkan di salah satu sisi pulau dan hapus hewan impor di Pengaturan. Animasi maksimal 30 detik, berkas maksimal 100 MB. Saat Anda membuka pulau di satu layar, hewan peliharaan di layar lain tetap di tempatnya.', detail: 'Pratinjau dan rotasi acak · Impor gambar dan video · Hapus hewan kustom' },
      lockScreen: { title: 'Informasi layar terkunci', description: "Tampilkan tanggal, status, dan media yang sedang diputar di layar terkunci macOS secara opsional.", detail: "Pilihan pengguna · Tidak mengambil fokus" },
      recommendedTools: {
        title: 'Aplikasi rekomendasi',
        description:
          'Temukan OpenScreen untuk rekaman dan edit video, DockDoor untuk pratinjau jendela dan pergantian aplikasi, serta Zshell sebagai ruang kerja terminal native macOS. Aplikasi pihak ketiga ini dipasang terpisah.',
        detail: 'Temukan alat desktop · Aplikasi pihak ketiga · Instalasi terpisah',
      },
    },
  },
  ai: {
    eyebrow: "ALUR AI",
    title: "Pantau tugas AI, <span>penggunaan dan kuota.</span>",
    lede: "Lihat tugas per aplikasi, penggunaan model per tanggal, dan sisa kuota akun.",
    summaryMono: "TUGAS / PENGGUNAAN / KUOTA",
    summaryLede: "Tugas AI, penggunaan, dan kuota di satu tempat.",
    toolsHeading: 'Alat AI yang didukung',
    toolsLede: "Mendeteksi tugas dari CLI, aplikasi desktop, dan IDE yang didukung.",
    toolsAriaLabel: 'Alat AI yang didukung',
    boundariesHeading: "Privasi",
    privacyPoints: [
      "Status tugas dan penggunaan disimpan di Mac",
      "Teks prompt dan balasan tidak dibaca",
      "Percakapan tidak diunggah",
    ],
    bridgeHeading: 'Hubungkan tugas Anda sendiri',
    bridgeLede: "Gunakan zislactl untuk menampilkan skrip dan tugas build di bilah status.",
    zislactlTaskTitle: 'Build dan rilis',
    copyZislactlAriaLabel: 'Salin perintah zislactl',
  },
  flow: {
    eyebrow: 'IRAMA INTERAKSI',
    title: 'Naikkan, <span>lihat, lalu lepaskan.</span>',
    lede: 'Tidak pernah mengambil fokus dan menutup saat Anda selesai melihat.',
    ariaLabel: 'Irama interaksi di bagian atas',
    summaryMono: 'BILAH STATUS / 3 LANGKAH',
    summaryLede: 'Membuka saat diperlukan dan menutup setelah selesai.',
    summaryNote: 'Dipicu posisi penunjuk, tidak memakan ruang saat kosong, dan tidak mengambil fokus.',
    steps: {
      trigger: { phase: 'Picu', title: 'Gerakkan penunjuk ke tengah atas', desc: "Dapat digunakan di layar berponi dan layar eksternal." },
      review: { phase: 'Tinjau', title: 'Lihat status saat ini sekilas', desc: 'Media, berkas, AI, agenda, dan alat sistem berada di tempat yang sama.' },
      dismiss: { phase: 'Tutup', title: 'Kembali ke pekerjaan', desc: 'Jauhkan penunjuk dan panel menutup; membuka tidak mengaktifkan aplikasi atau mengambil fokus.' },
    },
  },
  help: {
    "title": "Mulai memakai zisla",
    "lede": "Pilih tugas lalu ikuti pintu masuk, langkah, izin, dan tempat penyimpanan.",
    "labels": {
      "entry": "Pintu masuk",
      "shortcuts": "Pintasan",
      "permissions": "Izin",
      "output": "Hasil dan penyimpanan"
    },
    "guides": {
      "clipboard": {
        "title": "Gunakan kembali yang disalin",
        "summary": "Cari riwayat atau pilih tindakan setelah menyalin.",
        "entry": "Pulau → Papan klip; Pengaturan → Tindakan cepat.",
        "steps": [
          "Aktifkan riwayat atau tindakan cepat lalu salin teks atau tautan contoh.",
          "Buka papan klip, saring atau cari, lalu salin item.",
          "Salin gambar contoh dengan teks yang jelas, tunggu pengenalan lokal di latar belakang, lalu cari kata dari gambar untuk menemukan gambar asli.",
          "Klik kanan gambar untuk mengenali atau menyalin teksnya; batalkan saat pengenalan berlangsung jika perlu. Pengenalan di latar belakang tidak menyalin teks otomatis.",
          "Tempel di aplikasi tujuan; untuk salinan baru, pilih langkah berikutnya di jendela tindakan cepat."
        ],
        "shortcuts": "Command+1…9 lalu Command+0 mengikuti urutan tindakan. Konfigurasi baru juga memakai Command+N untuk tindakan pertama; Command+Delete menutup. Pintasan yang disimpan atau dikosongkan tetap dipertahankan.",
        "permissions": "Riwayat dan pengenalan lokal. Pemicu tombol pengubah/mouse perlu Pemantauan Input; gestur salin opsional perlu Aksesibilitas. Terjemahan memakai layanan pilihan.",
        "output": "Riwayat dalam data aplikasi lokal. Simpan teks/gambar memakai Pengaturan → Lokasi penyimpanan → Tindakan cepat; default baru ~/Downloads/quick."
      },
      "capture": {
        "title": "Tangkap dan edit layar",
        "summary": "Edit tangkapan atau rekaman lalu ekspor hasilnya.",
        "entry": "Bilah menu → Tangkapan/Rekaman; Pengaturan → Rekaman → Studio.",
        "steps": [
          "Tangkap area atau jendela; edit, salin, simpan, atau taruh di rak.",
          "Pilih layar, jendela, atau area dan aktifkan hanya sumber audio/kamera yang perlu.",
          "Hentikan, edit dan pratinjau di studio, lalu ekspor format pilihan."
        ],
        "shortcuts": "Control+1 tangkapan; Control+2 tangkapan panjang. Control+Shift+1/2/3 merekam layar/jendela/area; Control+Shift+6 membuka studio. Dapat diubah di pengaturan.",
        "permissions": "Perlu Perekaman Layar. Mikrofon dan kamera perlu izin masing-masing, termasuk pratinjau kamera.",
        "output": "Default baru: ~/Downloads/picture untuk gambar, ~/Downloads/video untuk rekaman/proyek. Folder diatur terpisah. Beberapa ekspor perlu FFmpeg."
      },
      "shelf": {
        "title": "Teruskan file lewat rak",
        "summary": "Siapkan file untuk aplikasi lain tanpa menyalin aslinya.",
        "entry": "Pulau → Rak; seret ke pemicu atas.",
        "steps": [
          "Seret file contoh ke atas atau goyangkan saat menyeret bila gesturnya aktif.",
          "Buka rak dan pilih kategori atau item yang diperlukan.",
          "Seret ke tujuan, tampilkan di Finder, atau bagikan; tangkapan yang disimpan dapat diekspor sebagai PNG.",
          "Pilih berkas atau folder dan pilih kompresi ZIP di menu konteks; arsip kembali ke rak.",
          "Pilih gambar di rak lalu ubah ukuran atau format; jalankan alat gambar dan hasil yang berhasil kembali ke rak.",
          "Pilih gambar, video, atau audio lalu impor ke pustaka media studio rekaman; proyek dan linimasa saat ini tetap dipertahankan."
        ],
        "shortcuts": "Seret dengan penunjuk. Gestur goyang diatur terpisah; tidak perlu pintasan tetap.",
        "permissions": "Pemilih file dan bookmark aman memberi akses ke file pilihan. Tangkapan perlu Perekaman Layar.",
        "output": "File asli tetap di tempatnya. Referensi dan tangkapan disimpan lokal; PNG memakai tujuan pilihan. Arsip ZIP dan hasil gambar yang berhasil kembali ke rak; media impor ditambahkan ke pustaka proyek rekaman."
      },
      "weather": {
        "title": "Lihat cuaca terlengkap yang tersedia",
        "summary": "Periksa cuaca lokasi saat ini atau lokasi tersimpan dan lengkapi data yang belum tersedia.",
        "entry": "Island → Jadwal; Pengaturan → Cuaca.",
        "steps": [
          "Aktifkan Cuaca di Pengaturan → Fitur; cari dan simpan tempat lain di pengaturan cuaca.",
          "Buka Jadwal atau segarkan cuaca. Jika data belum lengkap, sumber lain mengisi bagian yang hilang berdasarkan hasil terlengkap.",
          "Jika sumber tambahan tidak tersedia, pertahankan informasi yang ada dan jangan tampilkan metrik yang belum diperoleh.",
          "Periksa sumber yang digunakan lewat tautan di bawah daftar cuaca; peringatan resmi diambil terpisah."
        ],
        "shortcuts": "Gunakan tombol penyegaran di Jadwal; tidak ada pintasan global tetap.",
        "permissions": "Lokasi saat ini memerlukan izin lokasi; tempat yang ditambahkan manual tidak. Cuaca dan peringatan memakai jaringan.",
        "output": "Cuaca disimpan dalam memori dan tempat tersimpan tetap lokal. Data parsial ditampilkan jika tidak dapat dilengkapi; prakiraan lebih lama dari satu jam disembunyikan."
      },
      "meeting": {
        "title": "Ikuti rapat dan simpan catatan",
        "summary": "Hubungkan rapat kalender dengan catatan konteks.",
        "entry": "Pulau → Agenda; aktifkan kalender dan catatan konteks di Pengaturan.",
        "steps": [
          "Buat atau buka acara dengan tautan rapat yang didukung dan waktu awal/akhir valid.",
          "Klik Gabung; hitung mundur muncul 10 menit sebelumnya.",
          "Buat, simpan, atau tautkan catatan dari acara; buka kembali lewat agenda atau rak."
        ],
        "shortcuts": "Gabung dan catatan memakai tombol. Di lokasi lain tahan tombol yang diatur lalu goyangkan; default Command.",
        "permissions": "Perlu akses kalender. Catatan jendela mungkin perlu Aksesibilitas; tangkapan terlampir perlu Perekaman Layar.",
        "output": "Catatan rapat ada dalam data rak lokal. Catatan cepat adalah fitur terpisah memakai Apple Notes."
      },
      "ai": {
        "title": "Hubungkan AI dan cek kuota",
        "summary": "Pantau tugas, pemakaian tercatat, dan kuota akun.",
        "entry": "Pengaturan → AI; pulau → Monitor AI.",
        "steps": [
          "Aktifkan alat lokal yang didukung atau laporkan tugas dengan zislactl sesuai referensi CLI.",
          "Aktifkan pemantauan penyedia pilihan dan pilih pemantauan serta tampilan Gemini dan Claude/GPT Antigravity secara terpisah. Untuk Gemini App, masuk ke akun Google yang sama di gemini.google.com/usage dan simpan Cookie di kredensial kuota web; pilih Gemini CLI secara terpisah.",
          "Lihat waktu sampel/reset dan peringatan; buka riwayat atau ekspor .xlsx."
        ],
        "shortcuts": "Pakai monitor atau Pengaturan, tanpa pintasan global tetap. zislactl memakai argumen yang terdokumentasi.",
        "permissions": "Deteksi lokal membaca status terstruktur. Kuota menghubungi penyedia; edit AI opsional memakai model atau CLI pilihan.",
        "output": "Tugas/pemakaian: ~/Library/Application Support/zisla/ai-state.sqlite. Kuota berasal dari penyedia, bukan perkiraan token; data hilang tetap tidak tersedia."
      },
      "media-tools": {
        "title": "Proses gambar, audio, dan PDF",
        "summary": "Gunakan alat lokal mandiri pada file contoh.",
        "entry": "Pengaturan → Alat Gambar / Audio / PDF.",
        "steps": [
          "Tambahkan gambar, pilih operasi dan opsi, jalankan lalu ekspor hasil atau ZIP.",
          "Pilih gambar di rak lalu ubah ukuran atau format; jalankan alat gambar dan hasil yang berhasil kembali ke rak.",
          "Pasang FFmpeg dan ffprobe di komponen, tambahkan audio, pilih potong atau campur lalu file atau folder keluaran.",
          "Tambahkan PDF sesuai urutan, jalankan dan simpan. Konversi Office perlu LibreOffice atau OpenOffice lokal."
        ],
        "shortcuts": "Tombol alat; tanpa pintasan global tetap.",
        "permissions": "Pemilih file memberi akses ke file dan folder pilihan. Proses lokal; memasang komponen mengunduhnya.",
        "output": "Default baru: gambar ~/Downloads/picture, PDF ~/Downloads/pdf, diatur terpisah. Audio memakai dialog ekspor."
      },
      "daily-briefing": {
        "title": "Buat ringkasan harian",
        "summary": "Pratinjau statistik sebelum ekspor PNG.",
        "entry": "Pengaturan → Ringkasan harian.",
        "steps": [
          "Pilih templat dan statistik.",
          "Buka pratinjau, periksa data tersedia dan folder keluaran.",
          "Ekspor hari ini atau aktifkan ekspor harian dan waktunya."
        ],
        "shortcuts": "Tombol Pratinjau dan Ekspor; tanpa pintasan tetap.",
        "permissions": "Aktifkan fitur statistik terkait. Riwayat Durasi Layar mungkin perlu Akses Disk Penuh; kuota menghubungi penyedia.",
        "output": "PNG di folder ringkasan; default baru ~/Downloads/daily. Data hilang bukan nol terukur."
      },
      "desktop": {
        "title": "Pratinjau jendela dan buat catatan konteks",
        "summary": "Pindah ke jendela lalu tinggalkan catatan lokasinya.",
        "entry": "Pengaturan → Pratinjau jendela / Catatan konteks; Dock, Command+Tab dan rak.",
        "steps": [
          "Aktifkan pratinjau dan izin, arahkan ke aplikasi Dock atau pakai Command+Tab lalu klik kartu.",
          "Di halaman, jendela atau desktop contoh, tahan tombol pilihan dan goyangkan; tulis lalu simpan.",
          "Kembali ke lokasi atau buka dari rak; tambah pengingat berkala atau tangkapan jendela bila perlu."
        ],
        "shortcuts": "Command+Tab beralih aplikasi. Catatan default menahan Command, bisa diubah.",
        "permissions": "Pratinjau perlu Aksesibilitas dan Perekaman Layar. Deteksi jendela memakai Aksesibilitas; tangkapan lampiran Perekaman Layar.",
        "output": "Catatan dan gambar dalam data rak lokal di ~/Library/Application Support/zisla."
      },
      "playback": {
        "title": "Pilih pemutaran dan campur volume aplikasi",
        "summary": "Pilih keluaran dan atur aplikasi yang berbunyi.",
        "entry": "Area media → Perangkat keluaran; Pengaturan → Sumber media; pulau → Mixer.",
        "steps": [
          "Putar audio contoh dan pilih keluaran tersedia.",
          "Pilih sumber otomatis atau pemutar favorit lalu uji kontrol.",
          "Di macOS 14.4+, buka mixer, izinkan Perekaman Audio Sistem lalu atur atau bisukan aplikasi."
        ],
        "shortcuts": "Tombol dan penggeser; tanpa pintasan tetap.",
        "permissions": "Mixer perlu macOS 14.4+ dan Perekaman Audio Sistem. Perangkat tergantung koneksi; Bluetooth mungkin perlu izin.",
        "output": "Keluaran adalah pilihan sistem. Volume aplikasi diingat lokal; tidak mengekspor file."
      }
    },
    "workflowsTitle": "Demo alur singkat",
    "workflows": {
      "copy-next": {
        "title": "Cari, salin, dan gunakan lagi",
        "steps": [
          "Cari kata contoh “brew” dalam riwayat.",
          "Salin item yang cocok.",
          "Tempel di aplikasi tujuan. Cuplikan memperlihatkan pencarian dan penyalinan; salinan baru punya tindakan cepat terpisah."
        ]
      },
      "drop-output": {
        "title": "Taruh file dan siapkan keluaran",
        "steps": [
          "Seret gambar contoh dari Finder ke rak atas.",
          "Buka rak dan pilih gambar.",
          "Seret ke tujuan atau simpan tangkapan sebagai PNG. Cuplikan memperlihatkan penempatan ke rak."
        ]
      },
      "meeting-note": {
        "title": "Dari rapat ke catatan",
        "steps": [
          "Buka rapat dengan tautan gabungnya.",
          "Pilih Catatan rapat baru atau Tautkan catatan lama.",
          "Simpan dan buka kembali dari acara atau rak. Cuplikan memperlihatkan pembuatan dan penautan."
        ]
      }
    },
    "excerptLabel": "Putar cuplikan",
    "guideLinkLabel": "Baca panduan",
    "videoNotice": "Cuplikan dari tur fitur yang sudah ada dengan data demo. Teks dalam video berbahasa Inggris; langkah di sini memakai bahasa pilihan. Tur lengkap 2:40 dan kredit musik ada di bawah.",
    "preferencesTitle": "Preferensi berguna",
    "preferences": [
      "Di Pengaturan → Pet, lihat pratinjau peliharaan bawaan dan yang diimpor. Mode Peliharaan tetap menampilkan satu peliharaan. Rotasi acak mengundi dari semua peliharaan kecuali Anda membatasi Daftar undian. Secara bawaan, undian berlangsung pada tengah malam waktu setempat. Pilih Kustom pada Interval pergantian untuk mengatur durasi dari 1 detik hingga 99:59:59. Nilai awalnya 1 jam.",
      "Aktifkan goyang saat menyeret untuk menampilkan rak. Catatan konteks memakai tombol tahan tersendiri.",
      "Pilih keluaran audio di area media dan sumber otomatis atau pemutar favorit di Pengaturan. Ini tidak membagi perangkat berbeda per aplikasi.",
      "Suara tombol dan statistik ketikan berdiri sendiri dan memakai Pemantauan Input. Mixer aplikasi perlu macOS 14.4+ dan Perekaman Audio Sistem.",
      "Ringkasan harian menawarkan 8 templat, pratinjau, serta ekspor PNG manual atau harian dengan folder terpisah."
    ]
  },
  download: {
    eyebrow: 'SIAP SAAT ANDA SIAP',
    title: 'Unduh zisla',
    copy: 'Untuk Mac Apple Silicon. Versi, arsitektur lain, dan checksum tersedia di halaman rilis. Setelah memasang, Sparkle memverifikasi tanda tangan terlebih dahulu, lalu mengunduh, memasang, dan memulai ulang sesuai pengaturan Anda; pembaruan mempertahankan izin yang sudah diberikan. Jika ada rilis yang tidak Anda butuhkan, lewati saja dan tidak akan diingatkan lagi. Baca catatan rilis sebelum pemasangan dan setelah mulai ulang.',
    primaryCta: 'Unduh',
    primaryCtaAriaLabel: 'Unduh zisla',
    releaseCta: 'Lihat rilis',
    releaseCtaAriaLabel: 'Lihat detail rilis di GitHub',
    brewMono: 'HOMEBREW / SATU PERINTAH',
    brewNote: 'Sparkle memperbarui zisla sendiri, jadi brew upgrade hanya mengganti aplikasi bila salinan terpasang benar-benar lebih lama daripada versi di tap — sejak Homebrew 5.1.6 yang dibaca adalah versi di dalam aplikasi itu sendiri. Menyebut cask secara eksplisit, seperti brew upgrade --cask zisla, berpatokan pada catatan pemasangan Homebrew dan bisa mengembalikanmu ke versi tap setelah pembaruan lewat Sparkle. Tap hanya menyediakan versi stabil. Tap ini milik pihak ketiga dan aplikasinya belum dinotarisasi, jadi peluncuran pertama perlu memilih "Buka Saja" di Pengaturan Sistem → Privasi & Keamanan.',
    copyBrewCommandAriaLabel: 'Salin perintah pemasangan Homebrew',
    notes: {
      system: { term: 'Sistem', value: 'macOS 14 atau lebih baru · Konfigurasi yang didukung: Mac Apple Silicon' },
      install: { term: 'Pasang', value: 'Pasang DMG lalu seret ke Applications' },
      package: { term: 'Paket', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Arsitektur lain', value: 'Halaman rilis' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.25': [
        'Mulai pembersihan berkas yang tidak diperlukan dari utilitas dengan pengaturan yang sudah ada. Progres dan hasil muncul di island; pesan hasil AI tetap terbaca sebelum informasi pembersihan kembali ditampilkan.',
        'Isi tangkapan layar yang disematkan mengikuti ukuran bingkainya saat menggunakan bilah alat, trackpad, atau sudut gambar, termasuk gambar HDR.',
        'Daftar cuaca menampilkan satu waktu pembaruan dan mengelompokkan sumber tanpa entri berulang.',
        'Statistik pengetikan kembali menampilkan bilah gulir vertikal dan dasbor tetap berada dalam area yang terlihat.',
        'Alat audio menyesuaikan area pengaturan yang terlihat, dengan pengguliran terpisah untuk daftar operasi dan panel penyuntingan.',
        'Mixer volume aplikasi menyembunyikan sumber audio yang tidak aktif, mempertahankan kontrol volume dan bisu yang tersimpan, serta memungkinkan percobaan ulang jika deteksi audio gagal.',
      ],
      'v0.1.24': [
        'Riwayat Clipboard dapat mencari dan mengelompokkan entri berdasarkan aplikasi sumber. Tindakan Cepat mengenali perintah yang berisi here-document.',
        'Pembersihan sistem dapat berjalan di latar belakang dengan progres dan hasil di pulau. Pembersihan Disk menemukan instalasi aplikasi duplikat dan sisa pembaruan aplikasi.',
        'Lokasi Penyimpanan dapat memulihkan semua folder keluaran ke lokasi bawaan. Kelompok pengaturan dan urutan halaman ditata ulang.',
        'Rekam HDR pada perangkat yang didukung. Pengenalan teks, terjemahan, dan pratinjau HDR tangkapan layar dipulihkan; penyesuaian tangkapan ke jendela juga mencakup jendela pengaturan.',
        'Catatan cepat mendukung navigasi dengan Command dan tombol panah. Teks yang ditempel mempertahankan tipografi asli teks utama.',
        'Pengaturan kuota AI mendukung wilayah terpisah. Riwayat penggunaan harian dan warna sisa kuota tetap konsisten pada kartu yang diperluas dan pemberitahuan ringkas. Giliran Kimi yang dibatalkan menghapus kesalahan, dan penyegaran langganan dibatalkan sebelum membaca kredensial.',
        'Pratinjau jendela menyaring jendela tertutup dan duplikat, mengikuti identitas jendela saat memakai jalur cadangan, dan tetap tersembunyi selama menu konteks Dock terbuka.',
        'Pemantauan media menyegarkan sumber lama dan mengakhiri aktivitas audio setelah sampel berhenti. Pengaturan volume aplikasi disimpan; fade audio mengikuti waktu sampel yang didekode. Audio keyboard dan statistik menangani pemutaran yang tidak tersedia dan data kosong.',
        'Perubahan izin diperbarui setelah akses diberikan, dengan bantuan menyeret aplikasi saat pengaturan. Kesalahan alat yang direkomendasikan tetap mudah dibaca.',
      ],
      'v0.1.23': [
        'Alat gambar menambah sembilan operasi lokal: kompresi, konversi lima format, ukuran dan pemotongan, perbandingan format terkecil, rotasi dan pencerminan, tanda air, mosaik dan blur, pengenalan teks dan tabel, serta penghapusan latar. Ekspor batch dan ZIP tersedia, dengan folder penyimpanan terpisah untuk alat PDF dan gambar.',
        'Alat audio menambah 27 operasi lokal untuk konversi, penyuntingan, pemisahan, penggabungan, pencampuran, ekstraksi audio, normalisasi LUFS, efek, kanal, dan tag. Memerlukan FFmpeg dan ffprobe; pilih berkas atau folder ekspor.',
        'Pemantauan akun AI menampilkan cincin sisa kuota, waktu reset, dan peringatan kuota rendah di tata letak island, termasuk jendela 5h/7d dan anggaran Cursor dalam USD jika tersedia. Ringkasan harian dapat menyertakan kuota nyata dan waktu pengambilan datanya.',
        'Pilih tanggal pada tren penggunaan AI atau peta panas untuk melihat token masukan, keluaran, dan total per penyedia dan model. Lihat, ekspor seluruh riwayat sebagai .xlsx, atau hapus di Pengaturan. Beranda mengelompokkan pekerjaan AI per aplikasi dan menampilkan hasil ekspor ringkasan di island.',
        'Acara kalender dengan tautan rapat menampilkan hitung mundur mulai 10 menit sebelum acara dan tombol bergabung sekali klik. Buat catatan rapat atau hubungkan dan putuskan catatan kontekstual. Mail dapat menandai seluruh kotak masuk sebagai telah dibaca.',
        'Rak menambah pencarian, filter, dan pilihan jamak untuk menyalin, berbagi, atau mengirim ke Catatan Cepat. Konversi gambar ke PDF, kenali teks gambar untuk catatan, dan buka video terpilih di studio rekaman.',
        'Pilih mode daya otomatis untuk adaptor dan baterai, dengan opsi tetap hemat daya saat 20% atau kurang. Isi hingga 100% segera jika macOS menyediakan tindakan itu. Pengaturan menyediakan riwayat sistem, ekspor .xlsx, dan penghapusan.',
        'Tata letak Pomodoro ringkas horizontal dan vertikal menambah progres, jeda, lanjutkan, dan reset. Menyorot kontrol mempertahankan island dalam keadaan tertutup, termasuk tata letak vertikal dengan informasi tambahan.',
        'Tangkapan layar panjang menambah gulir otomatis lambat untuk jendela terpilih. Tangkapan HDR tersedia pada perangkat yang mendukung; penyuntingan mempertahankan pengaturan rendering dan ekspor gambar.',
        'Tindakan Cepat dapat memperbaiki aplikasi yang tidak terbuka setelah memeriksa integritas, tanda tangan, dan kebijakan keamanan macOS. Atur urutan per jenis, lihat contoh tambahan, dan gunakan simbol mata uang regional atau kode dengan prefiks. Pencarian penerbangan, kereta, dan paket diprioritaskan.',
        'Pengaturan memisahkan Tata Letak Dynamic Island, Ringkasan Harian, Notifikasi dan Perhatian, serta Alur Kerja ke halaman masing-masing. Atur prioritas status ringkas dan pilih pembaruan harian komponen terpasang. Pembersihan rekaman berpindah ke Monitor Sistem dan Pembersihan dengan transkrip tetap disimpan.',
        'Unduhan browser menampilkan nama berkas tujuan yang nyata jika tersedia. Rendering saat diam, pemindaian AI, pemuatan riwayat sistem, dan pemutaran studio memakai lebih sedikit sumber daya. Logo AI ringkas, kartu kuota, dan animasi hasil diperbaiki, bersama gulir cuaca, drop rak, penulisan Mail, dan penyimpanan riwayat clipboard.',
        'Beranda menambah tur fitur 160 detik yang dimulai dengan klik dan tautan video asli. Situs tetap dapat dipakai tanpa WebGL, dan rekomendasi aplikasi kini mencakup ruang kerja terminal Zshell.',
      ],
      'v0.1.22': [
        'Studio menambahkan penghalusan kulit, kecerahan, perampingan wajah dan tubuh, preset suara yang bisa diatur serta pemantauan mikrofon opsional. Efek dapat diatur sebelum merekam dan saat mengedit.',
        'Warna jejak kursor halus dapat dipilih. Pemutaran studio menampilkan hasil edit beserta trek, efek dan audio.',
        'Pengaturan → Lokasi Penyimpanan memisahkan unduhan, tangkapan layar, rekaman, Tindakan Cepat dan ringkasan harian. Pembaruan mempertahankan lokasi sebelumnya, lalu setiap folder dapat diubah sendiri.',
        'Pembersihan sistem opsional memindahkan item ke Sampah setiap 7, 15 atau 30 hari. Pilih item tepercaya atau semua item yang dapat diproses, termasuk yang perlu ditinjau; nonaktif secara default. Pembersihan disk menambahkan tinjauan folder kerja AI tanpa sesi tersimpan, melindungi sesi yang disimpan dan folder baru.',
        'Riwayat clipboard dapat menghapus item lebih lama dari 7, 15 atau 30 hari otomatis sambil mempertahankan favorit. Penghapusan otomatis nonaktif secara default.',
        'Catatan Cepat menampilkan lampiran tulisan tangan dan mendukung edit teks sebelum atau sesudahnya melalui Catatan, dengan lampiran asli tetap dipertahankan.',
        'Monitor AI menyembunyikan sisa kuota langganan, mempertahankan penggunaan harian dan memperbaiki pengguliran grafik serta label bulan. Pengaturan baterai digabung ke Status sistem.',
        'Quiet.md hadir sebagai aplikasi rekomendasi untuk catatan lokal, dengan pemasangan dan pengelolaan di Pengaturan.',
        'Bilibili mengunduh bagian video yang dipilih dan menangani lebih banyak format tautan. Penghapusan kalender menyasar kejadian berulang yang dipilih. Tangkapan yang disematkan tetap terlihat saat mengambil lagi, dengan label alat lebih jelas dan penanda ukuran lebih andal.',
      ],
      'v0.1.21': [
        'Pemantauan sistem menyimpan seluruh riwayat per menit yang ada maupun baru secara default hingga Anda menghapusnya. Grafik untuk rentang waktu apa pun dan ekspor .xlsx tetap tersedia.',
        'Unduhan, rekaman, dan tangkapan layar berbagi satu lokasi penyimpanan. Dialog simpan tangkapan layar terbuka di folder unduhan saat ini; pengaturan lokasi rekaman yang duplikat dihapus.',
        'Lokasi tampilan indikator status dan entri pencariannya hanya muncul untuk tata letak kapsul dengan posisi kustom. Baris disembunyikan pada tata letak notch atau kapsul di kamera saat hanya dapat memakai bilah menu.',
        'Hitung mundur Tindakan Cepat memakai bilah progres bawah pada tata letak notch. Tata letak kapsul tetap menampilkan progres di seluruh kelilingnya.',
      ],
      'v0.1.20': [
        'Pilih dari delapan templat, tentukan data penggunaan, pengetikan, sistem dan aktivitas zisla, lalu lihat pratinjau. Ekspor PNG secara manual atau pada waktu harian pilihan. Riwayat Durasi Layar dipakai saat aktif dan tersedia; data yang hilang tidak dianggap nol terukur.',
        'Atur interval untuk istirahat, minum, bergerak dan mengistirahatkan mata. Pesan menyesuaikan waktu. Jeda alami, kunci layar dan tidur mereset waktu. Selesai fokus dan tindakan catatan bisa menampilkan umpan balik singkat. Aktifkan atau matikan di Pengaturan. Simpan catatan yang bisa diedit untuk halaman web, jendela aplikasi atau desktop dan lihat saat kembali. Lampirkan tangkapan jendela, kelola catatan di rak, dan atur pengingat berulang dari satu jam hingga tiga hari atau matikan.',
        'Gunakan posisi kamera atau pilih posisi sendiri di tepi layar. Posisi kustom diingat saat berganti mode. Tata letak ringkas horizontal dan vertikal menyesuaikan panjang berdasarkan ikon status, tugas AI, unduhan dan media, dengan opsi menampilkan lebih banyak informasi. Pilih gelombang suara atau cahaya sampul; progres pemutaran juga muncul dalam tata letak ringkas dan mengambang.',
        'Pilih dari katalog hewan dan karakter yang diperluas, atau impor gambar, animasi atau video yang didukung dan beri nama. Letakkan di salah satu sisi pulau dan hapus hewan impor di Pengaturan. Animasi maksimal 30 detik, berkas maksimal 100 MB.',
        'Rekam layar, jendela atau area dengan audio sistem, mikrofon dan kamera opsional. Edit video, audio, gambar dan teks di banyak trek, tambahkan animasi, zoom dan subtitle serta lihat pratinjau tajam. Pilih rasio asli, 16:9, 9:16, 1:1 atau 4:3. Ekspor video, GIF, Live Photo atau audio; beberapa format memerlukan FFmpeg. Usulan AI opsional dipratinjau sebelum diterapkan.',
        'Tangkap, sematkan atau gabungkan tangkapan bergulir dengan pintasan yang dapat disesuaikan. Sorot area, ekstrak bagian gambar, bulatkan sudut dan pertahankan anotasi saat ekspor. Kenali dan salin teks, terjemahkan lalu salin hasilnya, atau ekspor tabel ke .xlsx. Simpan tangkapan di rak. Pengaturan memeriksa konflik dengan suara dan Tindakan Cepat.',
        'Deteksi tugas Cursor ditambahkan bersama penggunaan numerik dan kuota langganan yang tersedia untuk Cursor dan Muse Code. Tugas Cursor tetap terlihat selama alat berjalan lama. Alamat IP memiliki tindakan pencarian dan membuka tautan terpisah. Konversi mengenali satuan mata uang kecil; katalog mencakup Emoji 18.0.',
        'Atur volume dan bisukan secara terpisah untuk aplikasi yang memutar audio. Memerlukan macOS 14.4 atau lebih baru dan izin perekaman audio sistem. Tersedia di Pengaturan, di luar karusel modul pulau. Tinjau status di Pengaturan → Izin, mulai permintaan yang didukung atau buka halaman sistem terkait. Sambutan pertama memakai daftar yang sama dan menandai izin yang harus diatur manual. Total suara, durasi dikte, kecepatan dan waktu yang dihemat juga ada di dasbor keyboard. Konfigurasi baru mengaktifkan suara dan statistik, yang bisa dimatikan terpisah. Pilih berkas saat menulis untuk dilampirkan ke pesan. Baca catatan rilis sebelum pemasangan dan setelah mulai ulang.',
      ],
    },
    eyebrow: 'Catatan perubahan',
    title: 'Perubahan di setiap rilis zisla: fitur baru, peningkatan, dan perbaikan.',
    lede: 'Perubahan di setiap rilis zisla: fitur baru, peningkatan, dan perbaikan.',
    ariaLabel: 'riwayat rilis zisla',
    releaseCountLabel: 'rilis',
    latestLabel: 'terbaru',
    shippedLabel: 'dirilis',
    latestBadge: 'Terbaru',
    noteLabel: 'rilis',
    pagerAriaLabel: 'Halaman changelog',
    pageLabel: 'Halaman {page}',
    prevPageLabel: 'Sebelumnya',
    nextPageLabel: 'Berikutnya',
  },
  faq: {
    eyebrow: 'JAWABAN YANG JELAS',
    title: 'Pertanyaan umum.',
    lede: 'Izin, privasi, dan kompatibilitas.',
    items: {
      audience: { question: 'Untuk siapa zisla?', answer: 'Untuk pengguna Mac yang ingin AI, media, berkas, dan agenda di satu tempat. Layar tanpa notch juga didukung.' },
      aiPrivacy: { question: 'Apakah zisla membaca percakapan AI saya?', answer: 'Tidak. Pemantauan status AI hanya membaca status tugas, bukan teks prompt atau balasan.' },
      copyAssistant: { question: 'Apakah tindakan cepat membuka atau mengunggah yang saya salin?', answer: 'Tidak. Pengenalan dan pratinjau terjadi di Mac, dan langkah berikutnya dijalankan hanya setelah konfirmasi Anda.' },
      permissions: {
        question: 'Izin sistem apa yang diperlukan zisla?',
        answer: '<p>Pengaturan → Izin menyatukan status, permintaan dan tautan ke Pengaturan Sistem. Beberapa izin harus diatur manual. Anda memilih permintaan yang dimulai; layar sambutan pertama juga menyediakan kontrol yang sama.</p><p>Perekaman layar dan audio sistem, mikrofon serta kamera dipakai untuk tangkapan, rekaman, mixer dan cermin sesuai fitur. Dikte juga memakai pengenalan ucapan. Kalender, Pengingat, Lokasi, Bluetooth dan Otomatisasi mendukung fitur terkait. Menambah kota cuaca manual tidak memerlukan lokasi.</p><p>Konfigurasi baru mengaktifkan suara keyboard dan statistik, yang bisa dimatikan terpisah. Kejadian tombol global memerlukan pemantauan input. Statistik menyimpan jumlah, kode tombol, waktu dan nama aplikasi, bukan teks yang diketik. Aksesibilitas dipakai untuk penyisipan, gestur, pembersihan dan kontrol jendela.</p><p>Akses Disk Penuh mungkin diperlukan untuk indeks surel lokal dan riwayat Durasi Layar dalam ringkasan harian. Pemilih berkas memberi akses ke folder yang dipilih. Matikan fitur di zisla atau cabut izin di Pengaturan Sistem → Privasi &amp; Keamanan.</p>',
      },
      localVoice: {
        question: 'Bagaimana cara memakai model lokal untuk merapikan transkrip suara?',
        answer: `
      <p>Ollama, LM Studio, dan layanan lokal lain yang kompatibel dengan OpenAI didukung.</p>
      <ol>
        <li>Unduh atau muat model yang diinginkan di aplikasi model lokal, lalu jalankan layanannya.</li>
        <li>Buka Pengaturan → Suara → Model Lokal, tambahkan dan aktifkan konfigurasi, pilih Ollama atau LM Studio, lalu masukkan URL layanan. Untuk layanan lain yang kompatibel dengan OpenAI, pilih LM Studio juga. Biarkan API Key kosong jika layanan tidak memerlukan autentikasi.</li>
        <li>Pilih model yang ditemukan secara otomatis, lalu pilih konfigurasi tersebut di Model Organisasi Suara → Gunakan Model.</li>
      </ol>
      <p>zisla menyarankan model Gemma 4 QAT berdasarkan chip dan total RAM. Model yang disarankan tidak diunduh atau dimuat secara otomatis.</p>
    `.trim(),
      },
      network: { question: 'Apakah zisla terhubung ke internet?', answer: 'Cuaca, pemeriksaan pembaruan bertanda tangan, unduhan yang Anda mulai, dan pembersihan suara jarak jauh opsional menggunakan jaringan sesuai kebutuhan. Deteksi tautan clipboard berjalan lokal. Model lokal merapikan teks setelah transkripsi; pengenalan suara Apple masih dapat menggunakan jaringan, bergantung pada bahasa dan dukungan sistem. Pemantauan kuota akun AI yang aktif juga menghubungi layanan penyedia yang dipilih.' },
      multiDisplay: { question: 'Apakah zisla mendukung banyak layar?', answer: 'Ya: banyak layar, Spaces, dan aplikasi layar penuh biasa; membuka tidak mengambil fokus. Saat browser menggunakan layar penuh, arahkan penunjuk ke pulau untuk membukanya di desktop yang sama. Saat beberapa layar terhubung, Pengaturan → Umum → Mode Layar memungkinkan Anda memilih mode Dynamic Island (posisi kamera atau kustom), mode notch, atau sembunyikan untuk setiap layar. Dengan satu layar, pengaturan ini disembunyikan dan tampilan global digunakan; menghubungkan kembali memulihkan konfigurasi tersimpan setiap layar. Semua layar yang diaktifkan menampilkan island yang diciutkan secara bersamaan. Memperluas island, tindakan cepat, perekaman, dan pesan sementara hanya mengganti island pada layarnya sendiri; pemilihan layar notifikasi menyaring konten tanpa menyembunyikan island yang sedang tidak aktif.' },
      intel: { question: 'Bisakah digunakan di Mac Intel?', answer: 'Build Intel mungkin tersedia, tetapi kompatibilitas tidak dijamin. Konfigurasi yang didukung saat ini adalah Apple Silicon.' },
      storage: { question: 'Di mana zisla menyimpan data?', answer: 'Data lokal berada di ~/Library/Application Support/zisla/. Statistik mengetik disimpan terpisah di ~/Library/Application Support/zisla/typing-stats.sqlite3. Catatan cepat memakai aplikasi Catatan sistem. Pengaturan → Lokasi Penyimpanan menyediakan folder terpisah untuk unduhan, alat PDF, alat gambar, tangkapan layar, rekaman, Tindakan Cepat, dan ringkasan harian. Pembaruan mempertahankan lokasi yang telah dipilih; setiap folder kemudian dapat diubah sendiri. Pulihkan semua folder penyimpanan ke lokasi bawaan dalam satu tindakan.' },
    },
  },
  developers: {
    eyebrow: 'OPEN SOURCE SEBAGAI DEFAULT',
    title: 'Sumber daya pengembang.',
    lede: 'Berlisensi PolyForm Noncommercial 1.0.0—hanya untuk penggunaan nonkomersial, apa adanya atau di-build dari kode sumber.',
    docs: {
      macos: { title: 'Panduan pengembangan macOS', description: 'Fitur, build, pengujian, dan batas sistem' },
      architecture: { title: 'Arsitektur dan performa', description: 'Pemicu atas layar, jendela, dan desain performa' },
      cli: { title: 'Integrasi CLI', description: 'Perintah dan bidang zislactl' },
      releasing: { title: 'Penandatanganan dan rilis', description: 'Tanda tangan, notarization, dan proses rilis' },
      contributing: { title: 'Panduan kontribusi', description: 'Lingkungan, branch, commit, dan persyaratan pull request' },
    },
    quickStartMono: 'MULAI CEPAT / SUMBER',
    quickStartHeading: 'Jalankan dari sumber atau hubungkan tugas Anda sendiri.',
    copyRunCommandAriaLabel: 'Salin perintah untuk menjalankan dari sumber',
    githubRepoLabel: 'Repositori GitHub',
    giteeRepoLabel: 'Repositori Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Mendukung banyak layar, Spaces, dan aplikasi layar penuh biasa; membuka tidak mengaktifkan aplikasi atau mengambil fokus',
      "Menggunakan latar buram saat Kurangi Transparansi aktif",
      'Liquid Glass di macOS 26+, dengan fallback otomatis ke material native di macOS 14 dan 15',
    ],
  },
  film: {
    title: "Video pengenalan",
    videoAriaLabel: "Video pengenalan zisla",
    openVideoLabel: "Buka video",
    playbackError: "Video tidak dapat diputar.",
    musicLabel: "Musik",
    excerptLabel: "Cuplikan",
  },
  footer: {
    brandHomeAriaLabel: 'Kembali ke beranda zisla',
    previewChannelLabel: 'Saluran Preview',
    tagline: 'Open source, native, dan berada dalam kendali Anda.',
  },
  common: { copyCommandTitle: 'Salin perintah', copiedAriaLabel: 'Tersalin' },
  toast: { runCommandCopied: 'Perintah menjalankan sumber disalin', zislactlCopied: 'Perintah zislactl disalin', brewCommandCopied: 'Perintah pemasangan Homebrew disalin' },
});
