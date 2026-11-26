# zisla

**Türkçe** | [Belge dilleri](../README.md)

**zisla, ihtiyaç duyduğunuzda görünen ve ardından geri çekilen, macOS için yerel bir çalışma alanıdır.** İşaretçiyi ekranın üst ortasına götürerek devam eden yapay zekâ işleri, medya, dosya aktarımı, indirmeler ve masaüstü araçları için hafif bir alan açın. Çentiksiz ekranlarda aynı biçimdeki sanal durum alanı kullanılır.

Güncel uygulama: **macOS 14+**. Desteklenen yapılandırma Apple Silicon'dır; Intel sürüm paketleri çalışabilir, ancak uyumluluk garanti edilmez.

[Tüm özelliklerin tanıtımını izleyin — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![zisla tanıtım filmini izleyin](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Müzik: Kevin MacLeod'dan “Funkorama” · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Kaynak](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Neden ekranınızın üstünde yer almalı

- **Gerektiğinde açılır, odağı almaz.** Üst kenardan genişletin, gerektiğinde sabitleyin ve mevcut uygulamada çalışmayı sürdürün.
- **Devam eden işler için tek alan.** Tam bir gösterge paneli açmadan oynatılan medyayı, yapay zekâ görevlerini, indirmeleri, sayaçları, postaları, sistem durumunu ve pil bilgilerini görün.
- **Konuşmalara erişmeden yapay zekâ etkinliği.** zisla yalnızca görev durumunu belirlemek için gereken yapılandırılmış olayları ve yerel etkinlik meta verilerini okur. İstemleri veya yanıtların içeriğini hiçbir zaman okumaz.
- **Denetimler yerel kalır.** Modüller, pano geçmişi ve bağlantı algılama bağımsız anahtarlara sahiptir; izinler yalnızca bir özellik ilk kez kullanıldığında istenir.

## Neler yapabilir

### Masaüstü işlerini akıcı tutun

| Özellik | İşlevi |
| --- | --- |
| Şimdi çalıyor | Kapak, başlık, ilerleme, şarkı sözleri ve oynatma denetimlerini gösterir; meta veriler bulunmadığında Core Audio gerçekten ses üreten uygulamayı belirleyebilir. |
| Aktarım ve paylaşım | Dosyaları, medyayı veya bağlantıları üst tetikleme alanına bırakarak aktarım tepsisinde tutun, Finder'da gösterin veya macOS paylaşım menüsünü açın. Seçilen dosya ve klasörleri ZIP olarak sıkıştırın, Görüntü Araçları'nda seçilen görüntüleri yeniden boyutlandırın veya dönüştürün ve başarılı çıktıları tepsiye geri ekleyin; ya da seçilen görüntü, video ve sesi mevcut proje ile zaman çizelgesini koruyarak kayıt stüdyosunun medya kitaplığına aktarın. |
| Pano ve bildirimler | İsteğe bağlı olarak yerel pano geçmişini kaydeder, yeni bağlantıları yerel olarak tanır ve daraltılmış durumda medya, yapay zekâ etkinliği, tarayıcı indirmeleri, sayaçlar, postalar ve güncellemeleri gösterir. İsteğe bağlı Hızlı İşlemler her kopyalamadan sonra zengin önizleme ve akıllı devam işlemleriyle küçük bir ada bildirimi gösterir: açma, Finder'da gösterme, arama, çeviri, hesaplama ve kaydetme. Tarayıcı indirmesi tamamlandığında veya AirDrop dosyası geldiğinde aynı kısayol ilgili klasörü açabilir. Geçmişe eklenen yeni görüntüler cihaz üzerinde metin tanıma için sıraya alınır; özgün görüntüyü bulmak için metninde arama yapın veya metni tanımak ya da kopyalamak için görüntüye sağ tıklayın. |
| Günlük çalışma alanı | Hava durumu, takvim, anımsatıcılar, Mail.app, Apple Notlar'da tutulan Markdown notları, kilit ekranı bilgileri ve isteğe bağlı masaüstü evcil hayvanlarını içerir. |

### Yapay zekâ çalışmalarını görünür kılın

zisla; Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI ve diğer desteklenen kaynakların yerel etkinliğini izler. Görevleri, durumları, token eğilimlerini, katkı ısı haritalarını ve yan bildirimleri gösterir.

Kararlı bir yerel etkinlik kaynağı olmayan araçlarda `zislactl`, betiklerin, CI işlemlerinin ve araç kancalarının ilerleme, kullanım ve bildirim göndermesini sağlar; protokol durumu bu Mac'te kalır. Ayarlar yaygın yapay zekâ CLI'larını algılayabilir, kurabilir, güncelleyebilir ve kaldırabilir; yerel Skills öğelerini yönetebilir. Sağlayıcılar ve komutlar için [CLI entegrasyon başvurusuna](mac/Docs/cli-reference.md) bakın.

### Yararlı küçük işleri halledin

| Alan | Dahil edilen araçlar |
| --- | --- |
| İndirmeler ve belgeler | `yt-dlp` ile video ve ses indirme; yerel PDF birleştirme, bölme, döndürme, kırpma, dönüştürme, görüntü oluşturma, metin dışa aktarma, filigran, sayfa numarası, şifreleme, kilit açma ve meta veri düzenleme. |
| Odaklanma ve sunum | Oturum bittiğinde bir sesli uyarı ve yerel bildirim veren Pomodoro sayacı, uyanık tutma, boşta uykuya geçmeyi önleme, ekran ve klavye temizliği, teleprompter ve kamera aynası. |
| Sistem ve pil | CPU, GPU, bellek, disk, ağ, fan ve pil bilgileri; güvenle kaldırılabilen önbellekleri ve günlükleri temizleme. |
| Sesli giriş | Kayıt ve yazıya dökme için genel kısayollar, isteğe bağlı yerel veya uzak transkript düzenleme ve yerel ses geçmişi. |

### Güncel giriş noktaları ve iş akışları

Adada 12 modül vardır: Ana Sayfa, Aktarım, Pano, Yapay Zekâ İzleme, Klavye Sesleri, İndirmeler, Ajanda, Posta, Notlar, Uygulama Ses Düzeyi Karıştırıcısı, Araçlar ve Sistem. Pil ayrıntıları Sistem altında bulunur; kilit ekranı sunumu ayrıdır. PDF, görüntü ve ses araçlarını Ayarlar'dan; kayıt stüdyosunu Ayarlar'dan veya menü çubuğundan açın.

- **Kayıt ve üretim:** Ekran, pencere veya bölgeyi isteğe bağlı sistem sesi, mikrofon ve kamerayla kaydedin. Birden çok kanalda altyazıları, yakınlaştırmaları, portre ve ses efektlerini düzenleyin, önizleyin ve video, GIF, Live Photo veya ses dışa aktarın. Görüntü araçlarında 9 yerel işlem, ses araçlarında 27 işlem vardır.
- **Karıştırma ve oynatma:** macOS 14.4+ uygulama başına ses düzeyi ve sessize alma sunar. Ses çıkışını medya alanından, oynatıcı tercihlerini Ayarlar'dan seçin.
- **Masaüstü ve toplantılar:** Dock ve Command+Tab pencere önizlemeleri, web sayfası/pencere/masaüstü bağlam notları, 10 dakikalık toplantı geri sayımı, toplantıya katılma ve bağlı notlar. Raf bırakma hedefini göstermek için dosya sürüklerken işaretçiyi sallayın.
- **Günlük özet:** 8 şablon, önizleme, elle veya zamanlanmış PNG dışa aktarma, seçilen ölçümler ve bağımsız kayıt klasörü.
- **Yapay zekâ hesapları:** Desteklenen hesapların kotalarını, yenilenme zamanlarını, düşük kota bildirimlerini ve örnekleme zamanlarını görün; yerel token geçmişini `.xlsx` olarak dışa aktarın.
- **Hızlı İşlemler:** Açılır penceredeki işlemler sırasıyla `Command+1` ile `Command+0` kullanır. Yeni yapılandırmalarda ilk işlem için ek varsayılan tetikleyici `Command+N`'dir. Yükseltmeler kayıtlı kısayolları ve temizlenmiş tetikleyicileri korur.

[Kullanıcı yardımı](https://wzz6423.github.io/zisla/?lang=tr#help) dokuz adım adım kılavuz sunar: pano, yakalama, raf, toplantılar, yapay zekâ, medya araçları, günlük özetler, masaüstü notları/pencere önizlemeleri ve oynatma/karıştırma. [macOS kılavuzu](mac/README.md) araçların kayıt klasörlerini ve bağımlılıklarını listeler.

## Başlangıç

### Uygulamayı kurun

En yeni DMG'yi [GitHub Releases](https://github.com/wzz6423/zisla/releases) veya [Gitee Releases](https://gitee.com/wzz6423/zisla/releases) üzerinden indirin, bağlayın ve `zisla.app` dosyasını `Applications` klasörüne sürükleyin.

Homebrew ile de kurabilirsiniz:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew çipinize uygun yapıyı getirir; Apple Silicon ve Intel Mac'ler yalnızca kendi mimarilerini indirir. Cask, Homebrew'un kendi cask deposu yerine üçüncü taraf `wzz6423/tap` kaynağından gelir; kurmak bu tap'e güvenmek anlamına gelir.

Başlatınca işaretçiyi geçerli ekranın üst ortasına götürün veya menü çubuğu simgesinden **Adayı Göster** seçeneğini kullanın. Paketler noter onaylı değildir; kurulum yönteminden bağımsız olarak ilk açılışta **Sistem Ayarları > Gizlilik ve Güvenlik** altında **Yine de Aç** gerekir. Alternatif olarak karantina özniteliğini kendiniz kaldırın:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Uygulamayı güncelleyin

zisla, kurulum yönteminden bağımsız olarak Sparkle ile güncellenir. Homebrew için bir ayrıntı vardır: Homebrew 5.1.6 ve sonrası uygulama paketindeki sürümü okuduğundan `brew upgrade`, yalnızca kurulu kopya gerçekten tap sürümünden eskiyse uygulamayı değiştirir. Böylece Sparkle'a engel olmaz ve eski kurulumu da bırakmaz. Cask adını açıkça belirtmek Homebrew kurulum kayıtlarını kullanır; bu nedenle Sparkle ile güncellenmiş uygulamayı tap sürümüne geri döndürebilir:

```bash
brew upgrade --cask zisla
```

Tap yalnızca kararlı sürümleri sunar; Preview yapıları Releases'ta kalır ve `brew upgrade` ön sürüme geçirmez. Preview kullanırken cask adını belirtmek uygulamayı güncel kararlı yapıyla değiştirir. Sparkle sürümü düşürmez; Release'e geri geçince kararlı bir sürüm Preview'ı geçene kadar Preview kurulu kalır. `brew uninstall --cask zisla` uygulamayı; `brew uninstall --zap --cask zisla` yerel verileri de kaldırır.

### Kaynak koddan çalıştırın

Swift 6 / Xcode 16+ gerekir; yalnızca Command Line Tools ile de proje derlenebilir.

```bash
cd mac
swift run zisla
```

İndirici `yt-dlp` gerektirir; `ffmpeg` isteğe bağlıdır. Office'ten PDF'ye dönüştürme LibreOffice veya OpenOffice gerektirir. Derleme, test ve paketleme yönergeleri [macOS geliştirme kılavuzundadır](mac/README.md).

## İşinizi bölmemek için tasarlandı

- Mevcut uygulamayı etkinleştirmeden veya odağını almadan birden çok ekranı, Spaces'ı ve normal tam ekran uygulamalarını destekler.
- Gizli durumda kalıcı saydam tetikleme penceresi veya kare döngüsü yoktur; genel olay izleme ve geometrik denetimler genişlemeyi tetikler.
- Tek sistem malzemesi kullanır; Saydamlığı Azalt açıkken opak arka plana geçer.
- Fiziksel çentiği sistemin güvenli alanından algılar; çentiksiz harici ekranlarda aynı hatlara sahip kaplama kullanır.

Uygulama tercihleri için [mimari ve performans tasarımına](mac/Docs/architecture.md) bakın.

## Gizlilik ve izinler

zisla, etkin bir özelliğin ilk kez ihtiyaç duyduğu anda izin ister. Modülleri Ayarlar'dan kapatabilir ve macOS Sistem Ayarları'nda yetkilendirmeyi istediğiniz zaman kaldırabilirsiniz.

| Kapsam | Sınır |
| --- | --- |
| Yapay zekâ etkinliği | Yalnızca yapılandırılmış olayları ve yerel etkinlik meta verilerini okur. İstemleri ve yanıt içeriklerini okumaz. |
| Pano ve dosyalar | Pano geçmişi, bağlantı algılama ve Hızlı İşlemler ayrı yerel anahtarlardır; Hızlı İşlemler tamamlanan indirmeleri ve AirDrop dosyalarını tarayıcı ilerleme anahtarından bağımsız işler. Tanıma tamamen cihazdadır; bağlantı açma ve işlem çalıştırma yalnızca açık tıklama veya tetikleyici basışıyla olur. Aktarım güvenlik kapsamlı yer imleri kullanır, özgün dosyayı kopyalamaz. |
| Notlar, posta ve ses | Notlar ve Posta, otomasyon izniyle AppleScript/JXA kullanır. Ses yalnızca etkin kullanımda kaydedilir; transkript düzenleme metni yalnızca seçilen yerel modele, uzak sağlayıcıya veya CLI profiline gönderir. |
| Tarayıcı indirmeleri ve medya | macOS'un genel dosya ilerlemesi, MediaRemote meta verileri ve Core Audio çıkış durumu kullanılır. Tarayıcı geçmişi veritabanları okunmaz. Sistem dalga biçimleri ve uygulama karıştırma sesi yerel işler; kayıt yalnızca ilgili kaynak açıkken sesi saklar. |
| Ağ | Hava durumu, genel IP sorgusu, güncelleme aynası seçimi, indirmeler, açık hesap kota denetimleri ve bağımlılık/CLI kurulumu ilgili hizmetlere bağlanır. İsteğe bağlı çeviri, ses temizleme ve yapay zekâ kayıt düzenleme seçilen sağlayıcıyı veya CLI'yı kullanır. Apple konuşma tanıma, sistem ve dil desteğine göre ağı kullanabilir. |

### Özelliğe göre izinler

zisla gerekli yetkiyi ilk kullanımda ister. Önceden erişimi reddettiyseniz **Sistem Ayarları > Gizlilik ve Güvenlik** bölümündeki ilgili öğeden `zisla` uygulamasına izin verin; öğe adları macOS sürümlerine göre değişebilir.

| İzin veya sistem ayarı | Ne zaman gerekir | Yetkilendirilen kapsam |
| --- | --- | --- |
| Aygıt Denetimi ve Veri Erişimi (bazı sürümlerde Erişilebilirlik) | Ses transkriptini geçerli uygulamanın metin alanına otomatik ekleme | Parola olmayan alanları bulur ve Erişilebilirlik API'leri veya `Cmd+V` ile metni aktarır. İzin yoksa transkript yine panoya kopyalanır. |
| Mikrofon | Sesli giriş veya stüdyo mikrofonunu açma | Kayıt ya da etkin izleme için seçilen mikrofonu yakalar. |
| Konuşma Tanıma | Kaydedilen konuşmayı metne dönüştürme | Yalnızca aktif olarak kaydedilmiş konuşmayı işler. Sesli giriş hem Mikrofon hem Konuşma Tanıma izni gerektirir. |
| Tam Disk Erişimi | Mail.app çalışmıyorken posta görüntüleme | Hesapları, gönderenleri, konuları, özetleri, zamanları ve okunma durumunu göstermek için `~/Library/Mail` yerel dizinini okur. Bu Mail dizini erişimi izin gerektirir. |
| Otomasyon | Mail.app iletilerini okuma, oluşturma, yanıtlama, işaretleme veya silme; Apple Notlar okuma/yazma | İlgili sistem uygulamalarını denetlemeye izin verir. Mail ve Notlar izinleri ayrı kaldırılabilir. |
| Takvimler; Anımsatıcılar | Ajanda modülünü kullanma | Etkinlikleri ve anımsatıcıları ayrı izinlerle okur ve yönetir. |
| Konum Servisleri | Geçerli konumun havası | Sürekli izleme yapmadan konumu bir kez ister. Elle eklenen yerler konum erişimi gerektirmez. |
| Kamera | Ayna veya stüdyo kamera önizlemesi/kaydını açma | İlgili özellik etkinken seçilen kamerayı kullanır. |
| Giriş İzleme | Klavye sesleri, yazma istatistikleri, temizlik, yalnızca değiştirici tuş veya fare yan tuş kısayolları | Etkin özelliğin olaylarını izler; istatistikler yereldir. Normal genel kısayollar bu izni gerektirmez. |
| Bluetooth | Sistem → Pil altında aksesuar pillerini görme | Bağlı veya eşlenmiş aygıtların yalnızca genel pil bilgilerini okur. |
| Ekran ve Sistem Sesi Kaydı (eski macOS'ta Ekran Kaydı) | Ekran görüntüleri, pencere önizlemeleri, kayıt, sistem dalga biçimleri ve karıştırıcı | Ekran görüntüleri ve seçilen ses kaynaklarını okur. Kayıt açık kaynakları yerel saklar; karıştırıcı macOS 14.4+ gerektirir. |
| Bildirimler | Pomodoro uyarıları | Sayaç bitince bir sesli uyarı ve yerel bildirim verir. |
| Kullanıcı tarafından seçilen klasörler (elle izin gerektirmez) | Dosya aktarımı, içe/dışa aktarma veya indirme klasörü seçimi | Sistem seçicisi seçilen klasöre erişim verir. Bu özellikler Tam Disk Erişimi gerektirmez. |

İzin kaldırmak yalnızca ilgili özelliği devre dışı bırakır. Bir ayarı değiştirdikten sonra özellik çalışmıyorsa zisla'yı kapatıp yeniden açın ve tekrar deneyin.

[macOS kılavuzu](mac/README.md) tüm izin ve ağ davranışını açıklar.

## Belgeler

| Belge | Amaç |
| --- | --- |
| [macOS geliştirme kılavuzu](mac/README.md) | Modüller, yapay zekâ, bağımlılıklar, derleme, test, izinler ve sistem sınırları. |
| [Web sitesi kılavuzu (İngilizce)](../../../web/README.md) | Yerel geliştirme, üretim derlemeleri ve güncel indirme bağlantıları. |
| [Tanıtım filmi kılavuzu (İngilizce)](../../../promo/README.md) | Remotion önizleme, işleme, kompozisyonlar, müzik ve kaynak lisansları. |
| [Mimari ve performans tasarımı](mac/Docs/architecture.md) | Üst kenar tetikleme, pencereler, eşzamanlılık, medya ve indirme güvenliği. |
| [CLI entegrasyon başvurusu](mac/Docs/cli-reference.md) | `zislactl` sağlayıcıları, komutları, alanları ve çıkış kodları. |
| [İmzalama ve sürüm tasarımı](mac/Docs/releasing.md) | İmzalama, noter onayı, DMG'ler, kanallar ve sürüm kabul denetimleri. |
| [Katkı kılavuzu](CONTRIBUTING.md) | Geliştirme ortamı, dallar, commit'ler ve pull request gereksinimleri. |

## Katkıda bulunun

Issue ve pull request'ler kabul edilir. Önce [katkı kılavuzunu](CONTRIBUTING.md) okuyun. Güvenlik sorunlarını genel issue yerine [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) üzerinden özel olarak bildirin.

## Lisans

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Ticari olmayan kullanım serbesttir; bu yazılımın satışı veya diğer ticari kullanımı yasaktır.
