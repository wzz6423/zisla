import { createCatalog } from './createCatalog';

export const id = createCatalog({
  meta: {
    documentTitle: 'zisla · Ruang kerja dinamis',
    description:
      'zisla adalah ruang kerja dinamis native untuk macOS. Satukan tugas AI, media, berkas, dan agenda, lengkap dengan suara keyboard, statistik mengetik, anotasi tangkapan layar, dan asisten salin.',
    ogTitle: 'zisla · Letakkan apa yang terjadi di tempat yang dapat Anda lihat',
    ogDescription:
      'Dari tugas AI dan media hingga suara keyboard, statistik mengetik, asisten salin, anotasi tangkapan layar, dan alat desktop: ruang kerja macOS native yang muncul saat diperlukan.',
  },
  tagline: 'Ruang kerja dinamis native untuk macOS',
  header: {
    navAriaLabel: 'Navigasi utama',
    brandHomeAriaLabel: 'Beranda zisla',
    menuOpenLabel: 'Buka menu navigasi',
    menuCloseLabel: 'Tutup navigasi',
    menuButtonTitle: 'Buka navigasi',
    navItems: {
      showcase: 'Fitur',
      ai: 'Alur kerja AI',
      download: 'Unduh',
      faq: 'Pertanyaan umum',
      developers: 'Pengembang',
    },
    downloadCta: 'Unduh',
    downloadCtaAriaLabel: 'Buka bagian unduhan',
    languageLabel: 'Bahasa antarmuka',
  },
  hero: {
    eyebrow: 'RUANG KERJA MACOS NATIVE',
    title: 'zisla<br><em>Letakkan yang terjadi<br>tepat di tempat<br class="hero-mobile-break"> yang dapat Anda lihat.</em>',
    lede:
      'Kumpulkan tugas AI, media, berkas, dan agenda di bagian atas layar. Setelah menyalin sesuatu, bilah asisten terpisah menampilkan pratinjau dan menyarankan langkah berikutnya. Muncul saat dibutuhkan lalu menyingkir setelah selesai.',
    downloadCta: 'Unduh',
    downloadCtaAriaLabel: 'Unduh',
    sourceCta: 'Lihat kode sumber',
    sourceCtaAriaLabel: 'Lihat kode sumber zisla di GitHub',
    hints: [
      'Gerakkan penunjuk ke bagian atas layar untuk membuka, tanpa klik',
      'Setelah menyalin, tekan Command+N untuk langkah cerdas berikutnya',
      'Menutup sendiri tanpa mengganggu pekerjaan',
    ],
    identityCaption: 'Bagian atas layar',
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
    summaryNote: '{modules} modul atas dan {features} kemampuan mandiri untuk tangkapan layar, suara, media, unduhan, asisten salin, pengelolaan AI, hewan peliharaan, dan layar terkunci.',
    groupNames: {
      island: 'Alur kerja atas layar',
      ai: 'Alur kerja AI',
      daily: 'Informasi harian',
      tools: 'Utilitas',
    },
    groupCount: '{count} modul',
    pointsAriaLabel: 'Sorotan {name}',
    modules: {
      dashboard: { name: 'Beranda', caption: 'Kartu dinamis hanya muncul saat sesi fokus, tugas AI, atau unduhan berlangsung; saat tidak ada aktivitas, tidak ada ruang yang terpakai.', points: ['Muncul sesuai kebutuhan', 'Progres langsung', 'Tata letak menyesuaikan'] },
      shelf: { name: 'Rak', caption: 'Seret berkas, audio, video, atau tautan ke bilah atas untuk menyimpannya di rak, menampilkannya di Finder, atau membuka menu Bagikan macOS.', points: ['Seret ke atas untuk menyimpan', 'Tampilkan di Finder', 'Menu Bagikan sistem'] },
      clipboard: { name: 'Clipboard', caption: 'Jelajahi riwayat clipboard di dalam pulau dan filter berdasarkan gambar, URL, jalur, atau jenis berkas. Kirim item ke Catatan cepat, jadikan favorit, atau hapus.', points: ['Riwayat di dalam pulau', 'Filter berdasarkan jenis', 'Catatan cepat dan favorit'] },
      aiMonitor: { name: 'Monitor AI', caption: 'Mendeteksi aktivitas CLI, aplikasi desktop, dan IDE yang didukung, termasuk thread Zed Agent, lalu menampilkan tugas, status, tren token, dan peta kontribusi. Hanya peristiwa terstruktur yang dianalisis; isi percakapan tidak dibaca.', points: ['Tugas dari berbagai alat', 'Tren pemakaian token', 'Tidak membaca prompt atau balasan'] },
      keyboardSound: { name: 'Suara keyboard', caption: 'Memutar 20 suara keyboard mekanis bawaan untuk penekanan tombol global, dengan volume dan variasi nada yang dapat diatur. Aktifkan statistik mengetik lokal untuk melihat ringkasan, tren, riwayat, lini masa aplikasi, dan peta tombol F1-F12.', points: ['20 suara bawaan', 'Suara lepas dan variasi nada', 'Statistik opsional'] },
      download: { name: 'Pengunduh', caption: 'Tempel tautan atau biarkan zisla mengenali tautan dari clipboard setelah diaktifkan. Pilih video atau audio dan unduh ke folder default atau folder pilihan. Tautan yang didukung menampilkan sumber, progres langsung, dan status selesai.', points: ['Mode video / audio', 'Folder default atau khusus', 'Sumber dan progres langsung'] },
      agenda: { name: 'Agenda dan cuaca', caption: 'Menampilkan cuaca di lokasi Anda dan hingga enam tempat pilihan. Lihat, tambah, dan hapus acara kalender serta pengingat, lalu tandai pengingat sebagai selesai.', points: ['Kartu cuaca beberapa tempat', 'Kalender dan tugas', 'Selesaikan pengingat sekali ketuk'] },
      mail: { name: 'Mail', caption: 'Membaca akun Mail yang diaktifkan, menampilkan kotak masuk, dan memungkinkan Anda menandai, membalas, menulis, serta memindahkan pesan ke Sampah di dalam pulau, dengan panduan jelas jika izin belum tersedia.', points: ['Akun Mail', 'Balas dan tulis di dalam pulau', 'Panduan izin transparan'] },
      quickNotes: { name: 'Catatan cepat', caption: 'Menggunakan aplikasi Catatan sistem untuk melihat, mengedit, membuat, dan menghapus catatan dengan pratinjau Markdown langsung. Draf ditulis kembali secara otomatis.', points: ['Data berada di Catatan', 'Editor Markdown', 'Draf tersimpan otomatis'] },
      pdf: { name: 'Alat PDF', caption: 'Empat belas operasi di perangkat: gabungkan, pisahkan, putar, pangkas, konversi gambar dan Office, render ke gambar, ekstrak teks, tambahkan watermark dan nomor halaman, enkripsi, hapus kata sandi, dan edit metadata.', points: ['14 alat di perangkat', 'Gabungkan sesuai urutan Anda', 'Tidak ada yang meninggalkan Mac'] },
      toolbox: { name: 'Utilitas', caption: 'Penghitung fokus, menjaga layar tetap aktif, pembersihan layar dan keyboard (termasuk memblokir F1-F12), alarm, teleprompter, cermin, dan Sampah dalam satu halaman.', points: ['Penghitung fokus', 'Blokir F1-F12 saat membersihkan', 'Teleprompter dan cermin'] },
      system: { name: 'Status sistem', caption: 'Periksa CPU, GPU, memori, disk, jaringan, dan kipas; baca suhu NVMe SMART jika didukung perangkat keras dan bersihkan cache serta log yang aman dihapus.', points: ['Pemantauan tingkat chip', 'Suhu NVMe jika didukung', 'Bersihkan cache sekali ketuk'] },
      battery: { name: 'Baterai', caption: 'Lihat pengisian, kesehatan, siklus, suhu, dan kapasitas Mac ini, serta tingkat baterai perangkat sekitar yang dibagikan sistem.', points: ['Metrik kesehatan Mac', 'Sisa waktu', 'Baterai perangkat sekitar'] },
    },
  },
  extensions: {
    eyebrow: 'DI DALAM DAN DI LUAR PULAU',
    title: 'Di luar pulau, <span>tetap menjadi alat desktop.</span>',
    lede: 'Tangkapan layar, suara, media, unduhan browser, dan pengelolaan AI muncul di tempat yang paling mudah dijangkau.',
    ariaLabel: 'Kemampuan desktop mandiri',
    summaryMono: 'MELAMPAUI PULAU',
    summaryLede: 'Kemampuan yang sering dipakai, masing-masing di tempat yang alami.',
    summaryNote: 'Tangkapan, rekaman, media, unduhan browser, asisten salin, pengelolaan AI, hewan peliharaan, dan layar terkunci ditampilkan terpisah.',
    features: {
      capture: { title: 'Tangkapan, tangkapan gulir, dan pin', description: 'Tangkap atau pin bagian layar dengan pintasan global, beri anotasi, gabungkan tangkapan gulir, serta kenali atau ekspor tabel. Anotasi teks yang masih diedit tetap tersimpan saat ekspor.', detail: 'Pintasan global · Anotasi dan urungkan · Perubahan dipertahankan saat ekspor' },
      voice: { title: 'Input suara dan pembersihan', description: 'Beralih dengan tombol atau tahan untuk berbicara memakai pengenal suara sistem. Tambahkan kosakata, kata khusus, format terstruktur, atau pembersihan oleh model lokal maupun jarak jauh.', detail: 'Dua mode rekaman · Kosakata dan kata khusus · Pembersihan opsional' },
      media: { title: 'Media dan suara latar sistem', description: 'Kendalikan pemutaran dari bagian atas pulau atau pilih suara latar macOS. Suara dapat berhenti saat layar terkunci, screensaver dimulai, atau layar tidur.', detail: 'Kontrol pemutaran · Lirik tersinkron · Berhenti otomatis' },
      browserDownloads: { title: 'Progres unduhan browser', description: 'Mendeteksi unduhan Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, dan Arc, lalu menampilkan sumber serta progres langsung di atas.', detail: '8 browser · Deteksi sumber · Pemberitahuan selesai' },
      copyAssistant: { title: 'Asisten salin dan langkah berikutnya', description: 'Setelah diaktifkan, teks, tautan, berkas, atau gambar yang disalin dipratinjau di bilah terpisah dengan saran buka, tampilkan di Finder, cari, terjemahkan, hitung, atau simpan—hanya setelah Anda mengonfirmasi.', detail: 'Sakelar opsional · Pengenalan lokal · Command+N sebagai default' },
      aiManagement: { title: 'Pengelolaan CLI AI dan Skills', description: 'Deteksi, pasang, perbarui, dan hapus CLI AI dari Pengaturan, serta tinjau dan kelola Skills lokal agar lebih jarang berpindah terminal.', detail: 'Deteksi dan pasang · Perbarui dan hapus · Skills lokal' },
      pet: { title: 'Hewan peliharaan pulau', description: 'Pilih hewan bawaan dan letakkan di sisi kiri atau kanan pulau. Matikan kapan saja.', detail: 'Karakter bawaan · Kiri atau kanan · Aktif sesuai kebutuhan' },
      lockScreen: { title: 'Informasi layar terkunci', description: 'Tampilkan tanggal, status, dan media yang sedang diputar di layar terkunci macOS secara opsional. Ini adalah overlay terpisah dan tidak muncul di daftar atau karusel modul pulau.', detail: 'Overlay terpisah · Pilihan pengguna · Tidak mengambil fokus' },
    },
  },
  ai: {
    eyebrow: 'AI TANPA KOTAK HITAM',
    title: 'Lihat status AI <span>tanpa membaca percakapan.</span>',
    lede: 'Tugas, status, dan tren token tetap di Mac Anda. Halaman ini menjelaskan fitur tanpa mensimulasikan tugas yang sedang berjalan.',
    summaryMono: 'STATUS LOKAL / BATAS JELAS',
    summaryLede: 'Hubungkan alat AI yang Anda gunakan sambil menjaga batas konteks yang diperlukan.',
    summaryNote: 'Halaman ini hanya menjelaskan cakupan deteksi, batas data, dan cara menghubungkan; sesi langsung tidak disimulasikan.',
    toolsHeading: 'Alat AI yang didukung',
    toolsLede: 'Mendeteksi aktivitas CLI, aplikasi desktop, dan IDE yang didukung, lalu menggabungkan status tugas.',
    toolsAriaLabel: 'Alat AI yang didukung',
    doubaoName: 'Doubao',
    boundariesHeading: 'Hanya batas status yang dicatat',
    privacyPoints: ['Hanya menganalisis jenis peristiwa, status, waktu, model, dan ID sesi dari peristiwa terstruktur', 'Tidak pernah membaca teks prompt atau balasan', 'Protokol dan status disimpan di Mac'],
    bridgeHeading: 'Hubungkan tugas Anda sendiri',
    bridgeLede: 'Gunakan zislactl untuk mengirim status terstruktur tugas eksternal ke bilah status.',
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
      trigger: { phase: 'Picu', title: 'Gerakkan penunjuk ke tengah atas', desc: 'Layar ber-notch dan eksternal memakai pemicu yang sama; saat tersembunyi tidak ada loop frame.' },
      review: { phase: 'Tinjau', title: 'Lihat status saat ini sekilas', desc: 'Media, berkas, AI, agenda, dan alat sistem berada di tempat yang sama.' },
      dismiss: { phase: 'Tutup', title: 'Kembali ke pekerjaan', desc: 'Jauhkan penunjuk dan panel menutup; membuka tidak mengaktifkan aplikasi atau mengambil fokus.' },
    },
  },
  download: {
    eyebrow: 'SIAP SAAT ANDA SIAP',
    title: 'Unduh zisla',
    copy: 'Untuk Mac Apple Silicon. Versi, arsitektur lain, dan checksum tersedia di halaman rilis. Setelah memasang, Sparkle memverifikasi tanda tangan terlebih dahulu, lalu mengunduh, memasang, dan memulai ulang sesuai pengaturan Anda.',
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
  faq: {
    eyebrow: 'JAWABAN YANG JELAS',
    title: 'Pertanyaan umum.',
    lede: 'Izin, privasi, dan kompatibilitas.',
    items: {
      audience: { question: 'Untuk siapa zisla?', answer: 'Untuk pengguna Mac yang ingin AI, media, berkas, dan agenda di satu tempat. Layar tanpa notch juga didukung.' },
      aiPrivacy: { question: 'Apakah zisla membaca percakapan AI saya?', answer: 'Tidak. Pemantauan status AI hanya membaca status tugas, bukan teks prompt atau balasan.' },
      copyAssistant: { question: 'Apakah asisten salin membuka atau mengunggah yang saya salin?', answer: 'Tidak. Pengenalan dan pratinjau terjadi di Mac, dan langkah berikutnya dijalankan hanya setelah konfirmasi Anda.' },
      permissions: {
        question: 'Izin sistem apa yang diperlukan zisla?',
        answer: `
      <p>zisla tidak meminta semua izin saat pertama kali dijalankan. macOS hanya menampilkan setiap permintaan ketika Anda mengaktifkan dan benar-benar menggunakan fitur yang sesuai:</p>
      <ul>
        <li><strong>Kalender dan Pengingat:</strong> diminta secara terpisah saat Anda membuka modul agenda, untuk membaca, membuat, dan mengelola acara kalender serta pengingat bertanggal.</li>
        <li><strong>Layanan Lokasi:</strong> diminta saat Anda memilih cuaca untuk lokasi saat ini. zisla mengambil lokasi satu kali dan tidak melacak Anda terus-menerus. Menambahkan kota secara manual tidak memerlukan izin lokasi.</li>
        <li><strong>Mikrofon dan Pengenalan Ucapan:</strong> diminta saat Anda memulai input suara. Audio hanya direkam selama Anda aktif merekam, dan hanya rekaman itu yang ditranskripsikan.</li>
        <li><strong>Aksesibilitas:</strong> diperlukan untuk memasukkan transkrip secara otomatis ke aplikasi yang sedang digunakan, menyalin dengan cepat melalui gestur mouse, membersihkan keyboard, dan mengendalikan pemutar yang didukung. Izin ini digunakan untuk menemukan kolom input yang bukan kolom kata sandi atau mengirim tombol sistem yang diperlukan.</li>
        <li><strong>Pemantauan Input:</strong> digunakan untuk suara keyboard, statistik pengetikan lokal opsional, dan pemicu global seperti satu tombol pengubah atau tombol samping mouse. Hanya peristiwa global yang diperlukan fitur tersebut yang dipantau; pintasan global biasa tidak memerlukannya.</li>
        <li><strong>Perekaman Layar dan Perekaman Audio Sistem:</strong> diperlukan untuk tangkapan layar, pengeditan tangkapan layar, dan bentuk gelombang audio sistem yang sedang diputar. Tangkapan layar membaca gambar layar; bentuk gelombang hanya menganalisis tingkat audio sistem saat ini dan tidak pernah menyimpan atau mengunggah audio.</li>
        <li><strong>Kamera:</strong> digunakan hanya saat jendela cermin terbuka.</li>
        <li><strong>Bluetooth:</strong> digunakan hanya saat modul baterai terbuka, untuk membaca tingkat baterai yang diumumkan perangkat yang terhubung atau dipasangkan.</li>
        <li><strong>Otomasi:</strong> saat pertama kali menggunakan Catatan Cepat, Mail, pembersihan desktop, atau kendali langsung atas pemutar yang didukung, macOS bertanya secara terpisah apakah zisla boleh mengendalikan Catatan, Mail, Finder, atau aplikasi tersebut. Catatan Cepat membaca dan menulis di Catatan; Mail dapat membaca, menulis, membalas, menandai, dan menghapus pesan.</li>
        <li><strong>Akses Disk Penuh:</strong> hanya diperlukan ketika Mail tidak sedang berjalan dan zisla tetap perlu membaca indeks mail lokal untuk menampilkan akun, pengirim, subjek, pratinjau, waktu, dan status telah dibaca.</li>
        <li><strong>Pemberitahuan:</strong> diminta saat Anda mengaktifkan timer Pomodoro atau alarm, semata-mata untuk menampilkan pemberitahuan lokal ketika timer selesai atau alarm berbunyi.</li>
      </ul>
      <p><strong>Folder bukan Akses Disk Penuh:</strong> untuk folder rak, impor/ekspor, atau unduhan yang Anda pilih di pemilih file sistem, zisla hanya mendapat akses ke folder tersebut, bukan hak membaca seluruh disk.</p>
      <p><strong>Suara keyboard dan statistik pengetikan:</strong> keduanya nonaktif secara default, dan peristiwa keyboard global hanya dipantau setelah salah satunya diaktifkan. Saat suara keyboard aktif, peristiwa tombol hanya digunakan untuk memutar suara; saat statistik pengetikan aktif, yang disimpan hanya data agregat — jumlah karakter, kode tombol fisik, waktu, dan aplikasi terdepan — bukan apa yang Anda ketik. Anda dapat menonaktifkan masing-masing fitur di Pengaturan; setelah itu tidak ada data baru yang dicatat. Data yang sudah tersimpan tetap berada dalam file basis data lokal yang dapat Anda hapus sendiri.</p>
      <p>Anda dapat menonaktifkan fitur di pengaturan aplikasi, atau mencabut izin kapan saja melalui Pengaturan Sistem → Privasi &amp; Keamanan. Mencabut satu izin hanya menonaktifkan fitur terkait dan tidak memengaruhi modul lain. Nama item dapat sedikit berbeda di berbagai versi macOS.</p>
    `.trim(),
      },
      network: { question: 'Apakah zisla terhubung ke internet?', answer: 'Cuaca, pemeriksaan pembaruan bertanda tangan, unduhan yang Anda mulai, dan pembersihan suara jarak jauh opsional menggunakan jaringan sesuai kebutuhan. Deteksi tautan clipboard berjalan lokal.' },
      multiDisplay: { question: 'Apakah zisla mendukung banyak layar?', answer: 'Ya: banyak layar, Spaces, dan aplikasi layar penuh biasa; membuka tidak mengambil fokus.' },
      intel: { question: 'Bisakah digunakan di Mac Intel?', answer: 'Build Intel mungkin tersedia, tetapi kompatibilitas tidak dijamin. Konfigurasi yang didukung saat ini adalah Apple Silicon.' },
      storage: { question: 'Di mana zisla menyimpan data?', answer: 'Data lokal berada di ~/Library/Application Support/zisla/. Statistik mengetik disimpan terpisah di ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Catatan cepat memakai aplikasi Catatan sistem.' },
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
      'Saat tersembunyi tidak membuat jendela hotspot transparan permanen dan tidak menjalankan loop frame; ekspansi memakai event global dan geometri',
      'Menggunakan satu lapisan material sistem dan beralih ke latar buram saat Kurangi Transparansi aktif',
      'Liquid Glass di macOS 26+, dengan fallback otomatis ke material native di macOS 14 dan 15',
      'Notch fisik disimpulkan dari area aman sistem; layar eksternal tanpa notch mendapat bilah status simulasi dalam overlay khusus',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Kembali ke beranda zisla',
    previewChannelLabel: 'Saluran Preview',
    tagline: 'Open source, native, dan berada dalam kendali Anda.',
  },
  common: { copyCommandTitle: 'Salin perintah', copiedAriaLabel: 'Tersalin' },
  toast: { runCommandCopied: 'Perintah menjalankan sumber disalin', zislactlCopied: 'Perintah zislactl disalin', brewCommandCopied: 'Perintah pemasangan Homebrew disalin' },
});
