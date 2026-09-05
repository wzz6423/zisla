import { createCatalog } from './createCatalog';

export const tr = createCatalog({
  meta: {
    documentTitle: 'zisla · Dinamik çalışma alanı',
    description:
      'zisla, macOS için yerel ve dinamik bir çalışma alanıdır. AI görevlerini, medyayı, dosyaları ve gündeminizi klavye sesleri, yazma istatistikleri, ekran görüntüsü açıklamaları ve kopyalama yardımcısıyla tek yerde tutar.',
    ogTitle: 'zisla · Olan biteni görebileceğiniz yere taşıyın',
    ogDescription:
      'AI görevlerinden ve medya oynatmadan klavye seslerine, yazma istatistiklerine, kopyalama yardımcısına, ekran görüntüsü açıklamalarına ve masaüstü araçlarına kadar — yalnızca gerektiğinde görünen yerel bir macOS çalışma alanı.',
  },
  tagline: 'Yerel macOS dinamik çalışma alanı',
  header: {
    navAriaLabel: 'Ana gezinme',
    brandHomeAriaLabel: 'zisla ana sayfası',
    menuOpenLabel: 'Gezinme menüsünü aç',
    menuCloseLabel: 'Gezinmeyi kapat',
    menuButtonTitle: 'Gezinmeyi aç',
    navItems: {
      showcase: 'Özellikler',
      ai: 'AI iş akışı',
      download: 'İndir',
      faq: 'SSS',
      developers: 'Geliştiriciler',
    },
    downloadCta: 'İndir',
    downloadCtaAriaLabel: 'İndirme bölümüne git',
    languageLabel: 'Arayüz dili',
  },
  hero: {
    eyebrow: 'YEREL MACOS ÇALIŞMA ALANI',
    title: 'zisla<br><em>Olan biteni,<br>tam da<br class="hero-mobile-break"> görebileceğiniz yerde.</em>',
    lede:
      'AI görevlerini, medyayı, dosyaları ve gündeminizi ekranın üst kısmında toplayın. Bir şeyi kopyaladıktan sonra ayrı bir yardımcı çubuğu içeriği orada önizler ve sonraki adımı önerir. Gerektiğinde görünür, işiniz bittiğinde kenara çekilir.',
    downloadCta: 'İndir',
    downloadCtaAriaLabel: 'zisla indir',
    sourceCta: 'Kaynak kodunu görüntüle',
    sourceCtaAriaLabel: 'zisla kaynak kodunu GitHub üzerinde görüntüle',
    hints: [
      'Genişletmek için ekranın üstüne gelin — tıklama gerekmez',
      'Kopyaladıktan sonra akıllı sonraki adım için Command+N tuşlarına basın',
      'İşinizi bölmeden kendiliğinden kapanır',
    ],
    identityCaption: 'Ekranın üst kısmı',
  },
  proof: {
    ariaLabel: 'Ürün özeti',
    items: {
      modules: { title: '{count} ekran üstü modül', desc: 'İhtiyacınız olan iş akışlarını etkinleştirin' },
      os: { title: 'macOS 14+', desc: 'Yerel masaüstü deneyimi' },
      displays: { title: 'Çoklu ekran', desc: 'Çentikli ve harici ekranlarla çalışır' },
      local: { title: 'Önce yerel', desc: 'AI durumu konuşmalarınızı asla okumaz' },
    },
  },
  showcase: {
    eyebrow: 'TEK GİRİŞ NOKTASI / GÜNLÜK İŞ AKIŞLARI',
    title: 'Günlük iş akışları, <span>ekranın üstünde.</span>',
    lede:
      'AI görevlerinden panoya, gündeminize ve sistem durumuna kadar zisla, dağınık masaüstü iş akışlarını tek bir giriş noktasında toplar.',
    ariaLabel: 'zisla özellik kataloğu',
    summaryMono: '{modules} MODÜL / {groups} İŞ AKIŞI',
    summaryLede: 'Ekran üstü iş akışlarından yerel araçlara kadar tamamlayabileceğiniz her görev burada açıklanır.',
    summaryNote:
      'Ekran üstü {modules} modül ve ekran görüntüleri, ses, medya, indirmeler, kopyalama yardımcısı, AI yönetimi, evcil hayvan ve kilit ekranını kapsayan {features} bağımsız özellik.',
    groupNames: {
      island: 'Ekran üstü iş akışları',
      ai: 'AI iş akışı',
      daily: 'Günlük bilgiler',
      tools: 'Yardımcı araçlar',
    },
    groupCount: '{count} modül',
    pointsAriaLabel: '{name} öne çıkanları',
    modules: {
      dashboard: { name: 'Ana sayfa', caption: 'Canlı kartlar yalnızca odak oturumu, AI görevi veya indirme çalışırken görünür; hiçbir şey olmadığında yer kaplamaz.', points: ['İhtiyaç olduğunda görünür', 'Canlı ilerleme', 'Düzen otomatik uyarlanır'] },
      shelf: { name: 'Raf', caption: 'Dosyaları, sesleri, videoları veya bağlantıları ekranın üstündeki tetikleme şeridine sürükleyerek rafa bırakın, Finder\'da gösterin ya da macOS paylaşım menüsünü açın.', points: ['Saklamak için üste sürükleyin', 'Finder\'da göster', 'Sistem paylaşım menüsü'] },
      clipboard: { name: 'Pano', caption: 'Pano geçmişine ada içinden göz atın ve görüntü, URL, yol veya dosya türüne göre filtreleyin. Bir öğeyi Hızlı Notlar\'a gönderin, favorilere ekleyin ya da silin.', points: ['Ada içinde geçmiş', 'Türe göre filtreleme', 'Hızlı Notlar ve favoriler'] },
      aiMonitor: { name: 'AI izleyici', caption: 'Zed Agent iş parçacıkları da dahil olmak üzere desteklenen AI CLI\'larının, masaüstü uygulamalarının ve IDE\'lerin etkinliğini otomatik olarak algılar; görevleri, durumu, toplam token eğilimlerini ve katkı ısı haritasını gösterir. Yalnızca yapılandırılmış olayları işler, konuşma metnini okumaz.', points: ['Araçlar arası görev özeti', 'Token kullanım eğilimleri', 'İstemleri veya yanıtları okumaz'] },
      keyboardSound: { name: 'Klavye sesleri', caption: 'Global tuş vuruşları için ayarlanabilir ses ve doğal perde değişimiyle 20 yerleşik mekanik klavye sesi çalar; destekleyen seslerde tuş bırakma sesleri de bulunur. Yerel yazma istatistiklerini açarak bugünün özetini, eğilimleri, geçmişi, uygulama zaman çizelgesini ve F1-F12 tuşlarını içeren tuş ısı haritasını görün.', points: ['20 yerleşik ses', 'Tuş bırakma sesleri ve perde değişimi', 'Yazma istatistikleri isteğe bağlı'] },
      download: { name: 'İndirici', caption: 'Bir bağlantı yapıştırın veya etkinleştirdikten sonra zisla\'nın panodan bağlantıları almasına izin verin. Video ya da ses seçip varsayılan klasöre veya istediğiniz bir klasöre indirin. Desteklenen bağlantılar kaynak simgesini, canlı ilerlemeyi ve tamamlanma durumunu gösterir.', points: ['Video / ses modları', 'Varsayılan veya özel klasör', 'Kaynak simgesi ve canlı ilerleme'] },
      agenda: { name: 'Gündem ve hava durumu', caption: 'Mevcut konumunuzun yanı sıra seçtiğiniz en fazla altı yerin hava durumunu gösterir. Takvim etkinliklerini ve anımsatıcıları görüntüleyin, ekleyin, silin ve anımsatıcıları tamamlandı olarak işaretleyin.', points: ['Birden çok yer için hava durumu kartları', 'Takvim ve yapılacaklar', 'Anımsatıcıyı tek dokunuşla tamamlayın'] },
      mail: { name: 'Mail', caption: 'Mail\'de etkinleştirdiğiniz hesapları okur. Gelen kutusunu kontrol edin, iletileri okundu olarak işaretleyin, yanıtlayın, yazın ve adanın içinden Çöp Sepeti\'ne taşıyın; izin eksikse açık yönlendirme gösterir.', points: ['Mail hesapları', 'Ada içinde yanıtla ve yaz', 'Açık izin yönlendirmesi'] },
      quickNotes: { name: 'Hızlı Notlar', caption: 'Sistem Notlar uygulamasını temel alır: notları canlı Markdown önizlemesiyle görüntüleyin, düzenleyin, oluşturun ve silin. Taslaklar otomatik olarak Notlar\'a geri yazılır.', points: ['Veriler Notlar\'da', 'Markdown düzenleyici', 'Taslaklar otomatik kaydedilir'] },
      pdf: { name: 'PDF araçları', caption: 'Mac\'inizde çalışan on dört işlem: birleştirme, bölme, döndürme, kırpma, görüntü ve Office dosyalarını dönüştürme, görüntü olarak oluşturma, metin çıkarma, metin veya görüntü filigranı ekleme, sayfa numarası ekleme, şifreleme, parolayı kaldırma ve meta verileri düzenleme.', points: ['Cihazda çalışan 14 araç', 'Kendi sıranızla birleştirin', 'Hiçbir şey Mac\'inizden çıkmaz'] },
      toolbox: { name: 'Yardımcı araçlar', caption: 'Odak sayacı, ekranı uyanık tutma, ekran temizleme, çalışırken F1-F12 dahil tuşları engelleyen klavye temizleme, alarmlar, teleprompter, ayna ve Çöp Sepeti tek sayfada.', points: ['Odak sayacı', 'Temizleme sırasında F1-F12 engellenir', 'Teleprompter ve ayna'] },
      system: { name: 'Sistem durumu', caption: 'CPU, GPU, bellek, disk, ağ ve fan durumunu kontrol edin; donanım bildirdiğinde NVMe SMART sıcaklığını okuyun ve güvenle silinebilecek önbellekleri ve günlükleri temizleyin.', points: ['Çip düzeyinde izleme', 'Desteklenen donanımda NVMe sıcaklığı', 'Önbelleği tek dokunuşla temizleyin'] },
      battery: { name: 'Pil', caption: 'Bu Mac\'in şarj, sağlık, döngü sayısı, sıcaklık ve kapasite gibi ayrıntılı ölçümlerini ve sistemin bildirdiği yakındaki cihazların pil seviyelerini görün.', points: ['Bu Mac için sağlık ölçümleri', 'Kalan süre', 'Yakındaki cihazların pili'] },
    },
  },
  extensions: {
    eyebrow: 'ADA İÇİNDE VE DIŞINDA',
    title: 'Adadan uzakta da <span>masaüstü aracıdır.</span>',
    lede: 'Ekran görüntüleri, ses, medya, tarayıcı indirmeleri ve AI yönetimi ulaşılması en kolay yerde görünür.',
    ariaLabel: 'Bağımsız masaüstü özellikleri',
    summaryMono: 'ADANIN ÖTESİNDE',
    summaryLede: 'Sık kullanılan özellikler, her biri doğal yerinde.',
    summaryNote: 'Ekran görüntüleri, kayıt, medya, tarayıcı indirmeleri, kopyalama yardımcısı, AI yönetimi, evcil hayvan ve kilit ekranı ayrı ayrı sunulur.',
    features: {
      capture: { title: 'Ekran görüntüleri, kaydırmalı yakalama ve sabitleme', description: 'Global bir kısayolla ekranın bir bölümünü yakalayın veya sabitleyin; açıklama ekleyin, kaydırmalı görüntüyü birleştirin ve tabloları tanıyıp dışa aktarın. Hâlâ düzenlediğiniz metin açıklamaları dışa aktarırken korunur.', detail: 'Global kısayol · Açıklama ve geri alma · Düzenlemeler dışa aktarımda korunur' },
      voice: { title: 'Sesli giriş ve temizleme', description: 'Bir tuşla geçiş yapın veya konuşmak için basılı tutun; sistemin konuşma tanıyıcısını kullanır. Gerektiğinde alan sözlükleri, özel etkin sözcükler, yapılandırılmış biçimlendirme ya da yerel veya uzak modelle temizleme ekleyin.', detail: 'İki kayıt modu · Sözlükler ve etkin sözcükler · İsteğe bağlı model temizleme' },
      media: { title: 'Medya ve sistem ortam sesleri', description: 'Çalan içeriği adanın üstünden kontrol edin veya bir macOS sistem ortam sesi seçin. Ekran kilitlendiğinde, ekran koruyucu başladığında ya da ekran uykuya geçtiğinde otomatik olarak durabilir.', detail: 'Oynatma denetimi · Eşzamanlı şarkı sözleri · Ortam sesi otomatik durur' },
      browserDownloads: { title: 'Tarayıcı indirme ilerlemesi', description: 'Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera ve Arc indirmelerini algılar; kaynaklarını ve canlı ilerlemeyi ekranın üstünde gösterir.', detail: '8 tarayıcı · Kaynak algılama · Tamamlanma bildirimi' },
      copyAssistant: { title: 'Kopyalama yardımcısı ve akıllı sonraki adımlar', description: 'Etkinleştirildiğinde kopyalanan metin, bağlantı, dosya veya görüntü ayrı bir üst çubukta önizlenir; açma, Finder\'da gösterme, arama, çevirme, hesaplama veya kaydetme gibi sonraki adımlar yalnızca onayınızdan sonra gerçekleştirilir.', detail: 'İsteğe bağlı anahtar · Cihazda tanıma · Varsayılan Command+N' },
      aiManagement: { title: 'AI CLI ve Skills yönetimi', description: 'Ayarlar\'dan popüler AI CLI\'larını algılayın, kurun, güncelleyin ve kaldırın; yerel Skills\'leri inceleyip yönetin, böylece terminaller ve araçlar arasında daha az geçiş yapın.', detail: 'Algıla ve kur · Güncelle ve kaldır · Yerel Skills' },
      pet: { title: 'Ada evcil hayvanı', description: 'Yerleşik evcil hayvanlardan birini seçin ve adanın soluna veya sağına yerleştirin. İstediğiniz zaman kapatın.', detail: 'Yerleşik karakterler · Sol veya sağ · İstediğinizde açın' },
      lockScreen: { title: 'Kilit ekranı bilgileri', description: 'Tarihi, durumu ve çalan içeriği isteğe bağlı olarak macOS kilit ekranında gösterin. Bu ayrı bir kilit ekranı katmanıdır; ada modül listesinde veya döngüsünde görünmez.', detail: 'Ayrı kilit ekranı katmanı · İsteğe bağlı · Odağı almaz' },
    },
  },
  ai: {
    eyebrow: 'KARA KUTU OLMAYAN AI',
    title: 'AI durumunu görün <span>konuşmayı okumadan.</span>',
    lede: 'Görevler, durum ve token eğilimleri Mac\'inizde kalır. Bu sayfa özelliği açıklar; çalışan bir görevin ekran görüntüsünü uydurmaz.',
    summaryMono: 'CİHAZDA DURUM / NET SINIRLAR',
    summaryLede: 'Kullandığınız AI araçlarını bağlayın ve işinizin gerektirdiği bağlam sınırlarını koruyun.',
    summaryNote: 'Bu sayfa yalnızca algılama kapsamını, veri sınırını ve bağlantı yöntemini açıklar; canlı bir oturumu taklit etmez.',
    toolsHeading: 'Desteklenen AI araçları',
    toolsLede: 'Desteklenen CLI\'ların, masaüstü uygulamalarının ve IDE\'lerin etkinliğini algılar ve görev durumunu toplar.',
    toolsAriaLabel: 'Desteklenen AI araçları',
    doubaoName: 'Doubao',
    boundariesHeading: 'Yalnızca durum sınırları kaydedilir',
    privacyPoints: [
      'Yapılandırılmış olaylardan yalnızca olay türünü, durumu, zaman damgasını, modeli ve oturum kimliğini ayrıştırır',
      'İstem veya yanıt metnini asla okumaz',
      'Protokol ve durum Mac\'inizde saklanır',
    ],
    bridgeHeading: 'Kendi görevlerinizi bağlayın',
    bridgeLede: 'Harici görevlerin yapılandırılmış durumunu durum çubuğuna göndermek için zislactl kullanın.',
    zislactlTaskTitle: 'Derleme ve yayınlama',
    copyZislactlAriaLabel: 'zislactl komutunu kopyala',
  },
  flow: {
    eyebrow: 'ETKİLEŞİM RİTMİ',
    title: 'Yukarı gelin, <span>bakın, sonra bırakın.</span>',
    lede: 'Odağı asla almaz ve baktığınızda yeniden kapanır.',
    ariaLabel: 'Ekran üstü etkileşim ritmi',
    summaryMono: 'DURUM ÇUBUĞU / 3 ADIM',
    summaryLede: 'İhtiyaç duyduğunuzda genişler, okumanız bitince geri çekilir.',
    summaryNote: 'İşaretçi konumuyla tetiklenir. İçerik yokken yer kaplamaz ve kullandığınız uygulamanın odağını asla çalmaz.',
    steps: {
      trigger: { phase: 'Tetikle', title: 'İşaretçiyi ekranın üst orta kısmına taşıyın', desc: 'Çentikli ve harici ekranlar aynı tetikleyiciyi kullanır; gizliyken kare döngüsü çalışmaz.' },
      review: { phase: 'İncele', title: 'Mevcut duruma göz atın', desc: 'Medya, dosyalar, AI, gündem ve sistem araçları aynı yerde bulunur.' },
      dismiss: { phase: 'Kapat', title: 'Yaptığınız işe dönün', desc: 'İşaretçiyi uzaklaştırdığınızda kapanır; genişletme uygulamayı etkinleştirmez ve odağı almaz.' },
    },
  },
  download: {
    eyebrow: 'SİZ HAZIR OLDUĞUNUZDA HAZIR',
    title: 'zisla indir',
    copy: 'Apple Silicon Mac\'ler içindir. Sürümler, diğer mimariler ve sağlama toplamları sürüm sayfasındadır. Kurulumdan sonra zisla, seçtiğiniz güncelleme kanalında yeni sürümleri kontrol edebilir: Sparkle önce imzayı doğrular, ardından ayarlarınıza göre elle veya otomatik olarak indirir, kurar ve yeniden başlatır.',
    primaryCta: 'İndir',
    primaryCtaAriaLabel: 'zisla indir',
    releaseCta: 'Sürümü görüntüle',
    releaseCtaAriaLabel: 'Sürüm ayrıntılarını GitHub\'da görüntüle',
    brewMono: 'HOMEBREW / TEK KOMUT',
    brewNote: 'zisla güncellemelerini Sparkle üstlenir; bu yüzden sade bir brew upgrade uygulamaya dokunmaz. Değişimi Homebrew yapsın istiyorsan brew upgrade --cask zisla komutunu çalıştır. Tap yalnızca kararlı sürümleri sunar.',
    copyBrewCommandAriaLabel: 'Homebrew kurulum komutunu kopyala',
    notes: {
      system: { term: 'Sistem', value: 'macOS 14 veya sonrası · Bugün desteklenen yapılandırma Apple Silicon Mac\'lerdir' },
      install: { term: 'Kurulum', value: 'DMG\'yi bağlayın ve Applications klasörüne sürükleyin' },
      package: { term: 'Paket', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Diğer mimariler', value: 'Sürüm sayfası' },
      mirror: { term: 'Ayna', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: 'BİRKAÇ NET YANIT',
    title: 'Sık sorulan sorular.',
    lede: 'İzinler, gizlilik ve uyumluluk.',
    items: {
      audience: { question: 'zisla kimler için?', answer: 'AI, medya, dosyalar ve gündemini tek yerde görmek isteyen Mac kullanıcıları için. Çentiksiz ekranlar da desteklenir.' },
      aiPrivacy: { question: 'zisla AI konuşmalarımı okur mu?', answer: 'Hayır. AI durum izleyicisi yalnızca görev durumunu okur; istem veya yanıt metnini okumaz.' },
      copyAssistant: { question: 'Kopyalama yardımcısı kopyaladıklarımı açar veya yükler mi?', answer: 'Hayır. Etkinleştirildiğinde tanıma ve önizleme tamamen Mac\'inizde gerçekleşir; zisla sonraki adımı yalnızca tıkladığınızda veya hızlı kısayola bastığınızda yürütür.' },
      permissions: {
        question: 'zisla hangi sistem izinlerine ihtiyaç duyar?',
        answer: `
      <p>zisla ilk açılışta tüm izinleri birden istemez. macOS her isteği yalnızca ilgili özelliği açıp gerçekten kullandığınızda gösterir:</p>
      <ul>
        <li><strong>Takvimler ve Anımsatıcılar:</strong> gündem modülünü açtığınızda ayrı ayrı istenir; takvim etkinliklerini ve tarihli anımsatıcıları okumak, oluşturmak ve yönetmek için kullanılır.</li>
        <li><strong>Konum Servisleri:</strong> mevcut konumunuzun hava durumunu seçtiğinizde istenir. zisla konumu bir kez alır, sürekli takip etmez. Şehri elle eklemek konum izni gerektirmez.</li>
        <li><strong>Mikrofon ve Konuşma Tanıma:</strong> sesli girişi başlattığınızda istenir. Ses yalnızca etkin kayıt sırasında alınır ve yalnızca o kayıt yazıya dökülür.</li>
        <li><strong>Erişilebilirlik:</strong> dökümü etkin uygulamaya eklemek, fare hareketiyle hızlı kopyalama, klavye temizleme ve desteklenen bazı oynatıcıları denetlemek için gereklidir.</li>
        <li><strong>Girdi İzleme:</strong> klavye sesleri, isteğe bağlı yerel yazma istatistikleri ve tek başına değiştirici tuş veya fare yan düğmesi gibi global tetikleyiciler için kullanılır.</li>
        <li><strong>Ekran Kaydı ve Sistem Sesi Kaydı:</strong> ekran görüntüleri, ekran görüntüsü düzenleme ve sistem sesi dalga biçimi için gereklidir. Dalga biçimi yalnızca anlık ses seviyesini analiz eder; ses kaydetmez veya yüklemez.</li>
        <li><strong>Kamera:</strong> yalnızca ayna penceresi açıkken kullanılır.</li>
        <li><strong>Bluetooth:</strong> yalnızca pil modülü açıkken bağlı veya eşleştirilmiş cihazların bildirdiği pil seviyesini okumak için kullanılır.</li>
        <li><strong>Otomasyon:</strong> Hızlı Notlar, Mail, masaüstü düzenleme veya desteklenen bir oynatıcıyı doğrudan denetleme ilk kez kullanıldığında macOS ayrı ayrı sorar.</li>
        <li><strong>Tam Disk Erişimi:</strong> yalnızca Mail çalışmıyorken yerel posta dizinini okumak gerektiğinde kullanılır.</li>
        <li><strong>Bildirimler:</strong> Pomodoro sayacını veya alarmları açtığınızda istenir ve yalnızca yerel bildirim göstermek için kullanılır.</li>
      </ul>
      <p><strong>Klasörler Tam Disk Erişimi değildir:</strong> sistem dosya seçicisinden seçtiğiniz raf, içe/dışa aktarma veya indirme klasörleri için zisla yalnızca o klasöre erişir.</p>
      <p><strong>Klavye sesleri ve yazma istatistikleri:</strong> ikisi de varsayılan olarak kapalıdır. Açıldığında yalnızca gereken global olaylar izlenir; yazdığınız metin hiçbir zaman saklanmaz. Ayarlardan iki özelliği ayrı ayrı kapatabilirsiniz.</p>
      <p>İlgili özelliği uygulama ayarlarından kapatabilir veya izni istediğiniz zaman Sistem Ayarları → Gizlilik ve Güvenlik bölümünden iptal edebilirsiniz. Bir izni iptal etmek yalnızca ilgili özelliği devre dışı bırakır.</p>
    `.trim(),
      },
      network: { question: 'zisla internete bağlanır mı?', answer: 'Hava durumu, imzalı güncelleme kontrolleri, başlattığınız indirmeler ve isteğe bağlı uzak ses temizleme gerektiğinde ağı kullanır. Pano bağlantısı algılama tamamen Mac\'inizde çalışır.' },
      multiDisplay: { question: 'zisla birden çok ekranı destekler mi?', answer: 'Evet: birden çok ekran, Spaces ve normal tam ekran uygulamaları desteklenir; genişletme odağı almaz.' },
      intel: { question: 'Intel Mac\'te kullanabilir miyim?', answer: 'Intel makineler için bir derleme bulunabilir ancak uyumluluk garanti edilmez. Günümüzde desteklenen yapılandırma Apple Silicon Mac\'lerdir.' },
      storage: { question: 'zisla verilerini nereye kaydeder?', answer: 'Yerel veriler ~/Library/Application Support/zisla/ konumundadır. Yazma istatistikleri ayrı olarak ~/Library/Application Support/SimuBoard/typing-stats.sqlite3 konumunda tutulur. Hızlı Notlar sistem Notlar uygulamasını kullanır.' },
    },
  },
  developers: {
    eyebrow: 'VARSAYILAN OLARAK AÇIK KAYNAK',
    title: 'Geliştirici kaynakları.',
    lede: 'PolyForm Noncommercial 1.0.0 lisanslıdır — yalnızca ticari olmayan kullanım için; olduğu gibi kullanın veya kaynak koddan derleyin.',
    docs: {
      macos: { title: 'macOS geliştirme kılavuzu', description: 'Özellikler, derleme, testler ve sistem sınırları' },
      architecture: { title: 'Mimari ve performans', description: 'Ekran üstü tetikleme, pencereler ve performans tasarımı' },
      cli: { title: 'CLI entegrasyonu', description: 'zislactl komutları ve alanları' },
      releasing: { title: 'İmzalama ve yayınlama', description: 'İmzalama, noterleme ve yayın süreci' },
      contributing: { title: 'Katkı kılavuzu', description: 'Ortam, dallar, commit\'ler ve pull request beklentileri' },
    },
    quickStartMono: 'HIZLI BAŞLANGIÇ / KAYNAK',
    quickStartHeading: 'Kaynak koddan çalıştırın veya kendi görevlerinizi bağlayın.',
    copyRunCommandAriaLabel: 'Kaynak koddan çalıştırma komutunu kopyala',
    githubRepoLabel: 'GitHub deposu',
    giteeRepoLabel: 'Gitee deposu',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Birden çok ekranı, Spaces\'i ve normal tam ekran uygulamalarını destekler; genişletme uygulamayı etkinleştirmez veya odağı almaz',
      'Gizliyken kalıcı şeffaf sıcak bölge penceresi oluşturmaz ve kare döngüsü çalıştırmaz; genişletme global olay izleme ve geometri kontrolleriyle tetiklenir',
      'Tek bir sistem malzemesi katmanı kullanır; Şeffaflığı Azalt etkin olduğunda opak arka plana geçer',
      'macOS 26+ üzerinde Liquid Glass kullanır; macOS 14 ve 15\'te yerel sistem malzemelerine otomatik olarak geri döner',
      'Fiziksel çentik sistemin güvenli alanından çıkarılır; çentiksiz harici ekranlarda özel katmanda benzetilmiş durum çubuğu gösterilir',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'zisla ana sayfasına dön',
    previewChannelLabel: 'Preview kanalı',
    tagline: 'Açık kaynak, yerel ve kontrol sizin elinizde.',
  },
  common: { copyCommandTitle: 'Komutu kopyala', copiedAriaLabel: 'Kopyalandı' },
  toast: { runCommandCopied: 'Kaynak çalıştırma komutu kopyalandı', zislactlCopied: 'zislactl komutu kopyalandı', brewCommandCopied: 'Homebrew kurulum komutu kopyalandı' },
});
