# macOS için zisla

**Türkçe** | [Belge dilleri](../../README.md)

Bu dizin zisla'nın macOS uygulamasını içerir. Adayı genişletmek için işaretçiyi ekranın üst ortasına götürün; gizlemek için uzaklaştırın. AppKit `NSPanel`, SwiftUI ve olay güdümlü hizmetler kullanılır. Gizliyken kalıcı saydam tetikleme penceresi veya kare döngüsü bulunmaz.

Swift hedefleri, paket kimliği, yerel veri dizini ve `zislactl`, zisla adını kullanır. Yükseltmeler eski sürümlerin verilerini ve tercihlerini otomatik taşır.

macOS 14 ve sonrası desteklenir. macOS 26 Liquid Glass kullanır; macOS 14/15 yerel sistem malzemesine döner.

## Özellikler

### Adanın 12 modülü

| Modül | Uygulanan işlevler |
| --- | --- |
| Ana Sayfa | Geçerli Pomodoro'yu, ilk etkin yapay zekâ görevini, yerel indirmeleri ve birden çok tarayıcı indirmesinin ilerlemesini gerektiğinde özetler. |
| Klavye sesleri ve istatistikler | 20 yerleşik klavye sesi; yerel yazma istatistikleri, eğilimler, uygulama zaman çizelgesi ve tuş bazlı ısı haritası bağımsız açılır. |
| Aktarım | Dosya, medya veya bağlantıları üst alana sürükleyerek tepside tutun, Finder'da gösterin veya paylaşın. Saklanan ekran görüntüleri mavi çift genişlikli kartlar ve ayrı kategori kullanır; görüntü kopyalama, PNG dışa aktarma ve silme sunar. Seçilen dosya ve klasörleri ZIP'e sıkıştırın, Görüntü Araçları'nda seçilen görüntüleri boyutlandırın veya dönüştürün ve başarılı çıktıları tepsiye geri alın; ya da görüntü, video ve sesi mevcut proje ve zaman çizelgesini koruyarak kayıt medya kitaplığına aktarın. |
| Pano | Aranabilir yerel geçmiş tutar, görüntü/URL/dosya filtreleri ve favoriler sunar; geçmiş ve bağlantı algılama ayrıdır. Yeni geçmiş görüntüleri cihazda metin tanımaya alınır; metinle özgün görüntüyü bulun veya sağ tıklayarak tanıyın ya da kopyalayın. Devam eden tanıma iptal edilebilir; arka plan tanıma metni otomatik kopyalamaz. |
| Yapay Zekâ İzleme | Desteklenen CLI, masaüstü uygulaması ve IDE'lerden görevleri, durumları, token eğilimlerini, katkı haritalarını ve yan bildirimleri toplar. |
| İndirmeler | Video ve ses için `yt-dlp`; `ffmpeg` yoksa AVFoundation uyumlu kanalları paketler ve Bilibili salt okunur alternatif sunar. |
| Ajanda | Geçerli konum ve en fazla altı kayıtlı yer için hava durumu; etkinlik ve anımsatıcıları görüntüleme, oluşturma, silme ve anımsatıcı tamamlama. Hava durumu listesinin güncelleme zamanı, başlık satırında yenileme düğmesinin solunda görünür. Hava durumu verileri eksikse diğer kaynaklar en kapsamlı sonucu tamamlar; kalan veriler alınamazsa mevcut veriler korunur. |
| Posta | Seçilen Mail.app hesaplarının gelen kutularını okur; okundu işareti, yanıt, yeni posta ve çöp kutusuna taşıma sunar. |
| Notlar | Markdown notlarını görüntüleme, düzenleme, oluşturma ve silmede tek kaynak Apple Notlar'dır; canlı önizleme ve otomatik yazma sunar. |
| Uygulama ses düzeyi karıştırıcısı | macOS 14.4+ üzerinde ses üreten her uygulamanın düzeyini ve sessizliğini ayarlayıp hatırlar; Sistem Sesi Kaydı izni gerekir. |
| Araçlar | Oturum sonunda bir sesli uyarı ve yerel bildirim veren Pomodoro, uyanık tutma, boşta uyku önleme, ekran/klavye temizliği, teleprompter, kamera aynası ve onaylı çöp boşaltma. Zamanlayıcı adı yalnızca geçerli oturum için kullanılır ve oturum bittiğinde veya iptal edildiğinde varsayılan ada döner. Ada daraltıldığında güneş simgesi ekranın açık kaldığını, dizüstü bilgisayar simgesi ise Mac’in boşta kaldığında uyumasının engellendiğini gösterir. |
| Sistem | CPU, GPU, bellek, disk, ağ, sıcaklık ve fan; belleği boşaltma, güvenli önbellek/günlük/geçici veri tarama, pil sağlığı ve aksesuar düzeyleri. |

### Modüller arası işlevler

- **Şimdi çalıyor:** MediaRemote kapak, başlık, ilerleme, kayan şarkı sözleri ve denetimler sağlar; Core Audio gerçek ses kaynağını alternatif olarak belirler. Duraklatılan, durdurulan ve sessiz kaynaklar gizlenir.
- **Tarayıcı indirmeleri:** Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera ve Arc kaynak ve ilerlemesini ana sayfada, daraltılmış durumda ve yan bildirimlerde gösterir.
- **Sesli giriş:** Aç/kapat veya bas-konuş kısayolları, özel genel kısayollar, sistem konuşma tanıma, yerel/uzak transkript düzenleme ve yerel kayıt geçmişi.
- **Hızlı İşlemler:** Her kopyalamadan sonra zengin önizlemeli küçük bildirim gösterir: bağlantı açma, Finder'da dosya gösterme, seçilebilir arama motoru, çeviri, hesaplama, tanınan tarihlerden etkinlik oluşturma ve uzun metin/görüntü kaydetme. İndirme veya AirDrop tamamlanınca aynı kısayol klasörü açar; Hızlı İşlemler bunu tarayıcı ilerlemesinden bağımsız denetler. URL, dosya yolu, e-posta, telefon, canlı örnekli CSS rengi, aritmetik, tarih/saat, sistemden farklı dilde metin, kod, sayımlı düz metin, küçük resimli görüntü ve dosya başvurularını tanır. Düğmeler, ek varsayılan Command+N veya ayarlı değiştirici/fare yan tuşu tetikler. Sol tuşu tutup sağ tıklama hızlı kopya hareketi varsayılan kapalıdır; uygulama engel listesi, tür anahtarları ve hafif anımsatma modu da vardır.
- **CLI ve Skills yönetimi:** Ayarlar'da yaygın yapay zekâ CLI'larını algılar, kurar, günceller, kaldırır ve yerel Skills öğelerini yönetir.
- **Masaüstü evcil hayvanları:** Ayarlar → Evcil Hayvan bölümünde yerleşik ve içe aktarılmış hayvanların önizlemesine bakabilirsiniz. “Sabit evcil hayvan” seçtiğiniz hayvanı gösterir. “Rastgele değişim” varsayılan olarak yerel saatle gece yarısında tüm hayvanlar arasından seçim yapar. Adayları “Rastgele seçim listesi” ile sınırlandırabilirsiniz. “Değişim aralığı” altında “Özel” seçeneğiyle 1 saniye ile 99:59:59 arasında bir süre belirleyebilirsiniz. Başlangıç değeri 1 saattir. Evcil hayvanı adanın soluna veya sağına yerleştirin. Adayı bir ekranda genişlettiğinizde diğer ekranlardaki evcil hayvanlar yerinde kalır.
- **Güncellemeler:** Seçilen Release veya Preview kanalı genel çıkış ülkesini her çalışmada bir kez çözer. `CN` önce imzalı Gitee appcast'ini, sonra bir kez GitHub'ı dener; diğerleri GitHub sonra bir kez Gitee. Sorgu yoksa Gitee önceliği korunur. Sparkle indirir, doğrular, kurar ve yeniden başlatır. Kanal değişimi otomatik ve elle denetimi etkiler.
- **Görünüm ve etkileşim:** Ayarlar sistem/açık/koyu görünümü seçer. Ada saydam veya buzlu yüzey, sabit genişleme, çoklu ekran, Spaces ve çentiksiz harici ekran sunar.
- **Varsayılanlar:** Yeni kurulumlarda modüller açıktır. Her özellik, daraltılmış gösterge, yan bildirim, menü ölçümü ve güncelleme davranışı ayrıdır; mevcut kurulumlar ayarlarını korur.
- Birden çok ekran bağlıyken Ayarlar → Genel → Ekran Modları bölümünde her ekran için Dynamic Island modu (kamera veya özel konum), çentik modu ya da gizleme seçilebilir. Tek ekranda bu ayar gizlenir ve genel görünüm kullanılır; yeniden bağlanınca her ekranın kayıtlı yapılandırması geri yüklenir. Görünür tüm ekranlarda daraltılmış ada aynı anda görünür kalır. Genişletme, hızlı işlemler, kayıt ve geçici mesajlar yalnızca kendi ekranlarındaki adanın yerini alır; bildirim ekranı seçimi boşta duran adayı gizlemeden içeriği filtreler.

### Bağımsız araçlar ve iş akışları

- **Kayıt stüdyosu:** Menü çubuğu veya Ayarlar'dan açın. Ekran, pencere veya bölgeyi sistem sesi, mikrofon ve kamerayla isteğe bağlı kaydedin. Video, ses, görüntü ve metni altyazı, zoom, animasyon, portre ve ses efektleriyle kanallarda düzenleyin; video, GIF, Live Photo veya ses aktarımından önce önizleyin. Bazı biçimler FFmpeg gerektirir; HDR cihaz desteğine bağlıdır. Raftan görüntü, video ve sesi mevcut proje ve zaman çizelgesini koruyarak medya kitaplığına aktarın.
- **Görüntü, ses ve PDF:** Ayarlar'dan açın. Görüntüde 9 yerel işlem ve toplu/ZIP aktarım; seste karıştırma, LUFS normalleştirme ve gürültü dahil 27 işlem vardır, FFmpeg/ffprobe gerekir. PDF'de 14 işlem; Office dönüşümü LibreOffice/OpenOffice gerektirir.
- **Günlük özet:** 8 şablon ve Ayarlar'dan ölçüm seçin, önizleyin, PNG'yi elle veya günlük saatte aktarın. Eksik ölçümler ölçülmüş sıfır olarak sunulmaz.
- **Pencere önizlemeleri:** Dock üzerinde bekleyin veya Command+Tab ile değiştirin, önizlemeye tıklayarak pencereyi etkinleştirin. İşlev ve izinleri Ayarlar'da yönetin.
- **Bağlam notları ve toplantılar:** Not kısayolunu tutup işaretçiyi sallayarak sayfa/pencere/masaüstüne not bağlayın. Toplantı bağlantılı etkinlikler başlamadan 10 dakika önce geri sayar; katılın, not oluşturun veya mevcut not bağlayın. Notları rafta yönetin.
- **Sallayarak bırakma:** Dosya sürüklerken işaretçiyi sallayarak hedefi gösterin; bu hareketi ayrı açıp kapatın.
- **Ses çıkışı ve oynatıcı tercihleri:** Medya alanında aygıt seçin. Ayarlar otomatik kaynak/tercih edilen oynatıcı, kompakt düzen ve ortam sesi durma koşullarını seçer.
- **Yapay zekâ kotası ve yenilenme:** İzleme ve Ayarlar kota, örnekleme ve yenilenme saatleri ile düşük kota uyarılarını gösterir; mevcut 5h/7d pencereleri ve Cursor USD bütçeleri dahildir. Yerel token geçmişinden ayrıdır. Antigravity Gemini ve Claude/GPT kotalarının izleme, gösterim ve uyarıları ayrıdır. Gemini App sohbet kotası aynı Google hesabının web Cookie bilgisiyle sorgulanır; Gemini CLI ayrı izlenir.

### Hızlı İşlemler klavye sırası

Açılır pencere işlem sırasına göre `Command+1` ile `Command+9`, ardından `Command+0` atar. Yeni yapılandırmanın ek varsayılan tetikleyicisi ilk işlem için `Command+N`; `Command+Delete` pencereyi kapatır. Tetikleyici, fare yan tuşu ve sırayı Ayarlar'dan belirleyin. Yükseltmeler eski `Command+1`, özel kombinasyonlar ve temizlenmiş tetikleyiciler dahil açıkça kaydedilen her ayarı korur; yalnızca yeni yapılandırmalar veya eksik alan `Command+N` kullanır.

### Kayıt konumları

Ayarlar → Kayıt Konumu; indirme, ekran görüntüsü, görüntü araçları, kayıt, PDF, Hızlı İşlemler ve günlük özet için ayrı klasör seçer. Yeni ayarlar `~/Downloads` altındaki `picture` görüntüleri, `video` kayıtları, `pdf`, `quick` ve `daily` kullanır. Ses araçları dosya/klasör aktarım penceresi kullanır. Raf dosyaları özgünlere başvurur; saklanan görüntüler ve bağlam notu durumu `~/Library/Application Support/zisla` altında, kayıt projeleri kayıt klasöründe yönetilir. Hızlı Notlar metni Apple Notlar'dadır.

[Kullanıcı yardımı ve adım adım kılavuzlar](https://wzz6423.github.io/zisla/help.html?lang=tr#help) dokuz konuyu kapsar: pano, yakalama, raf, toplantılar, yapay zekâ, medya araçları, günlük özetler, masaüstü notları/pencere önizlemeleri ve oynatma/karıştırma; kısa film parçaları içerir.

### Ekran görüntüsü kısayolları ve saklama

Araç çubuğundaki **Sakla**, **Sabitle** ile **Kopyala** arasındadır. Açıklamalar ve tamamlanan kaydırmalı yakalamalar dahil son görüntüyü panoya kopyalamadan aktarım tepsisine koyar. PNG ve özgün uygulama/zaman dahil meta veriler yerel SQLite'ta tutulur, yeniden başlatmada kalır. **Saklanan ekran görüntüleri** sadece bu kartları gösterir.

**Vurgulayıcı**, **Fırça** sonrasında yarı saydam işaret çizer; uç çizgiler ve daireler varsayılan korunur, menüde kapatılır. **Çıkar**, **Bulanıklaştır** sonrasındadır; macOS konu/arka plan çıkarma ve serbest seçim sunar. Birden çok döngü birleşik alanı korur; Tümünü Seç/Temizle vardır, seçilmeyen pikseller saydamlaşır, işlem geri alınır. Köşe yarıçapı varsayılan 0'dır. Seçim üstündeki tutamacı veya **Köşe yarıçapı** sürgüsünü kullanın; boyut etiketi `r` gösterir. PNG köşeleri saydamdır; 0'a dönmek özgün pikselleri geri getirir.

| Bağlam | İşlem | Varsayılan kısayol |
| --- | --- | --- |
| Genel | Ekran görüntüsü | `Control+1` |
| Genel | Kaydırmalı ekran görüntüsü | `Control+2` |
| Görüntü düzenleyicisi | Sabitle | `Control+1` |
| Görüntü düzenleyicisi | Sakla | `Control+2` |
| Görüntü düzenleyicisi | Dikdörtgen | `Control+3` |
| Görüntü düzenleyicisi | Elips | `Control+4` |
| Görüntü düzenleyicisi | Fırça | `Control+5` |
| Görüntü düzenleyicisi | Vurgulayıcı | `Control+6` |
| Görüntü düzenleyicisi | Ok | `Control+7` |
| Görüntü düzenleyicisi | Numara | `Control+8` |
| Görüntü düzenleyicisi | Metin | `Control+9` |
| Görüntü düzenleyicisi | Bulanıklaştır | `Control+0` |
| Görüntü düzenleyicisi | Çıkarma | `Control+A` |
| Görüntü düzenleyicisi | Kaydırmalı yakalama | `Control+B` |
| Görüntü düzenleyicisi | Kopyala | `Enter` |
| Görüntü düzenleyicisi | Kaydet | `Command+S` |
| Görüntü düzenleyicisi | Geri al | `Command+Z` |
| Görüntü düzenleyicisi | Yinele | `Command+Shift+Z` |

Ayarlar genel ve düzenleyici kısayollarını gösterir ve kaydeder. Kopyala, Kaydet, Geri Al ve Yinele görünür ancak yeniden kaydedilemez. Kullanıcı kısayolları korunur; Sabitle ayrı genel kısayol değil düzenleyici işlemidir, menü girişi sürer.

Düzenleyici varsayılanları araç sırasını izler: `Control+1`–`Control+9`, `Control+0`, `Control+A`, `Control+B` ve sonraki harfler. `Q`, `M`, `N`, `W` atlanır; yanlışlıkla Command uygulamayı kapatabilir, pencere küçültebilir/açabilir/kapatabilir. Kullanıcı kombinasyonları yine kabul edilir.

Yükseltmede değiştirilmemiş eski düzenler, önceki Sabitle/Sakla dahil, bir kez bu varsayılanlara geçer. Herhangi bir kısayol özelleştirildiyse düzen korunur; yeni işlemler çakışmada aynı güvenli sırada boş Control kombinasyonu seçer. İlk kombinasyonlar yeniden kaydedilebilir.

## Hızlı başlangıç

### Ortam

- macOS 14+
- Swift 6 / Xcode 16+ (yalnızca Command Line Tools ile de derlenir)
- İsteğe bağlı: `yt-dlp` ve `ffmpeg`; Office'ten PDF ayrıca LibreOffice/OpenOffice gerektirir

Homebrew ile:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Kaynak koddan çalıştırma

```bash
swift run zisla
```

Uygulama menü çubuğu aksesuarı olarak açılır. Üst ortadaki 6 px alana işaretçiyi götürün veya menü simgesinden “Adayı Göster” seçin.

Hata ayıklama derlemesinde 5 saniyelik aralığı denemek için depo kökünde `ZISLA_DEBUG_PET_ROTATION_SECONDS=5 make run` komutunu çalıştırın. “Rastgele değişim” modunu açın ve en az iki hayvan seçin. Kayıtlı aralığa dönmek için `make update` komutunu değişkeni belirtmeden çalıştırın.

### `.app` derleme

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Resmî `yt-dlp` yardımcı aracını paketlemek için:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh`, sabit sürümlü resmî bağımsız macOS dosyasını indirir, resmî `SHA2-256SUMS` ile doğrular ve `Tools/yt-dlp` altına kurar.

## Yapay zekâ araç entegrasyonu

### Otomatik algılama

zisla desteklenen araçların genel veya kararlı yerel oturum durumunu okur, yalnızca görev durumuna gereken olay ve meta verileri çıkarır. İstem ve yanıt içeriklerini okumaz.

| Ortam | Otomatik algılama |
| --- | --- |
| OpenAI / Anthropic | Codex CLI ve Desktop, Claude Code ve ana ortamları |
| GitHub / Google / xAI | GitHub Copilot CLI ve VS Code, Gemini CLI ve Desktop, Grok CLI |
| Bağımsız ve bölgesel araçlar | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop ve CLI, TRAE, OpenCode, Harnext/Harness ve WorkBuddy |

Onay/yanıt bekleme sarı, araç/komut hatası kırmızı, normal çalışma yeşildir; eşzamanlı kaynaklar kırmızı-sarı-yeşil sıralanır. Qwen yan hizmeti PID yaşadığı sürece aktiftir; çıkıştan sonra eski rapor bırakmaz.

Sohbet uygulaması yapılandırılmış olay saklamıyorsa açık boş uygulamayla üreten model güvenilir ayırt edilemez. ChatGPT dahil bunlar aşağıdaki `zislactl` kancasını kullanmalıdır; zisla yerleşik süreçle sahte etkinlik göstermez.

### Yerel `zislactl` protokolü

`zislactl` görev durumu ve kullanım geçmişini SQLite'a yazar:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Geçmiş yeniden başlatma, değiştiren güncelleme ve görev temizleme sonrasında korunur. Yalnızca veriler kullanıcı tarafından elle silinirse kaybolur.

Örnek:

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

Kanonik sağlayıcılar `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness`, `doubao` içerir; yaygın takma adlar otomatik normalleştirilir. Araç kancası, shell sarmalayıcı veya görev betiğinden çağırın.

Çalışma listesi ve daraltılmış durum kaynak için resmî araç logosunu kullanır.

Protokol için [CLI entegrasyon başvurusuna](Docs/cli-reference.md) bakın.

## Tarayıcı indirme ilerlemesi

zisla İndirilenler'de genel macOS dosya ilerlemesini dinler; geçici uzantı, kaynak özniteliği ve çalışan tarayıcı bilgisini birleştirir. Geçmiş veritabanı okumaz veya ilerleme için ağ isteği yapmaz; tamamlanma işareti yaklaşık üç saniye kalır. Hızlı İşlemler aynı kaynaktan başarılı aktarım son konuma varınca Klasörü Aç sunar. Süre Hızlı İşlemler ayarını izler; en yeni kopya/aktarım bildirimi eskisini değiştirir.

## İndirici

Çalıştırılabilir dosyalar şu sırayla bulunur:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

URL shell yerine ayrı argv olarak `Process`'e verilir. Çalışma ayarları ve eklentiler yok sayılır, `--exec` kapalıdır, tek öğe sınırı uygulanır ve son dosyanın izinli klasörde kaldığı doğrulanır.

`ffmpeg` olmadan:

- Video AVC/MP4 ve M4A kanallarını tercih eder, AVFoundation ile MP4 paketler; tek dosyalı biçim değişmez.
- Ses M4A'yı tercih eder, aksi halde özgün biçimi korur.
- yt-dlp HTTP 412 alırsa, biçim bulamazsa veya yoksa Bilibili salt okunur API ile DASH alır, başka araç kurmadan aynı yerel paketlemeyi kullanır.

## Notlar

Markdown notlarında tek kaynak Apple Notlar'dır. Mevcut notları oluşturabilir, görüntüleyebilir, düzenleyebilir ve silebilirsiniz; yalnızca yenilerini eklemekle sınırlı değildir.

- **Liste:** Girişte JXA (`osascript -l JavaScript`) silinmemiş notların başlık ve değişiklik tarihlerini okur, en yeniye göre sıralar. Geri dönüş listeyi yeniler; Son Silinenler gizlidir. Düzenlemek için seçin, yenileyin, oluşturun veya bağlam menüsünden silin.
- **Görüntüle ve düzenle:** AppleScript seçilen notun `plaintext` Markdown kaynağını okur. Yerel `TextEditor`, her tuşta çağrı yapmamak için yaklaşık 0,8 saniye boşta kaldıktan sonra yazar. Yeni notlar Apple Notlar'da oluşturulur ve seçilir.
- **Önizleme:** Yerleşik ayrıştırıcı başlık, sırasız/sıralı/görev listesi, alıntı, kod bloğu, çizgi, kalın, italik, satır içi kod, üstü çizili ve bağlantıları `AttributedString` olarak işler.
- **Saklama:** Kaynak notun `body` alanında HTML kaçışı ve boş satırlarla normal metindir. `plaintext` kaynağı geri getirir; Apple Notlar Markdown değil düz metin gösterir.
- **İzinler:** İlk okuma/yazma Apple Notlar otomasyonunu ister; ret liste veya düzenleyicide hata bildirir.

İkinci yerel kopya tutulmaz; depolama Apple Notlar'dır.

## İzinler ve gizlilik

- **Takvim:** Takvim/Anımsatıcı ilk girişte ayrı izin ister, ekleme/silme/tamamlama sonrası yenilenir.
- **Konum:** Hava bir kez konum ister, sürekli izlemez; diğer yerler Ayarlar'da aranır, kaydedilir, silinir.
- **Dosya ve indirmeler:** Seçilen klasörler güvenlik kapsamlı yer imi kullanır; aktarım özgünleri kopyalamaz.
- **Pano:** Yeni kurulumlarda geçmiş ve bağlantı ayrı açıktır. Her `changeCount` en fazla bir yerel bağlantı tanır; sorgu parametresi kaydedilmez ve temizleme/tür bildirme/yazma API'si çağrılmaz, evrensel pano değiştirilmez.
- **Hızlı İşlemler:** Açıkken her `changeCount` yerel çalışır, biten indirme/AirDrop da işlenir. Değiştirici ve fare yan tuşu Giriş İzleme gerektirebilir; hızlı kopya sentetik ⌘C gönderir, Erişilebilirlik ister. Tanıma ağı kullanmaz; açma, arama, çeviri, kaydetme açık eylem gerektirir. Engel listesi/türler kopya bildirimlerini; anahtar tamamlanmış aktarımı da denetler.
- **Yapay zekâ durumu:** Yalnızca gereken yapılandırılmış olay ve yerel meta veriler okunur.
- **Ses:** Mikrofon/tanıma açık kullanıcı eyleminden sonra açılır. Kayıt, ham ve düzenlenmiş metin yereldir; düzenlenmiş metin yalnızca seçili model/sağlayıcı/CLI profiline gider, uzak kimlik bilgileri özel veritabanındadır.
- **Bluetooth ve aygıtlar:** Aksesuar ve güvenilen Apple mobil aygıtlarının pili yalnızca Sistem altındaki Pil görünümü açıkken okunur.
- **Kamera ve Giriş İzleme:** Ayna ve stüdyo önizleme/kayıt kamerayı ister. Klavye sesi, istatistik, temizlik ve değiştirici/yan tuş tetikleyicileri Giriş İzleme kullanır; yerel istatistik ve ayrı anahtarlar vardır.
- **Ekran ve sistem sesi:** Görüntü, kayıt ve önizleme Ekran Kaydı izniyle içerik okur. Seçilen kaynaklar yerel kaydedilir; mikrofon/kamera ancak açık kaynaklara istenir. Karıştırıcı macOS 14.4+, Sistem Sesi Kaydı ve yerel Core Audio taps kullanır.
- **Tarayıcı indirmeleri:** Yalnızca genel ilerleme/geçici dosyalar incelenir; geçmiş ve sayfalar okunmaz.
- **Medya:** MediaRemote meta verisi ve Core Audio çıkışı oynatmayı doğrular. Özel framework olduğundan mevcut yapı doğrudan Mac App Store gönderimine uygun değildir; eksik metaveri aktif ses uygulamasına döner.
- **Ağ:** Tahminler bölgeye göre China Weather, Open-Meteo ve MET Norway kaynaklarını sorgular ve eksik veriler için diğer kaynaklara başvurur. Resmî uyarılar China Weather veya WeatherKit üzerinden ayrı olarak alınır. Kanal `ipinfo.io/country` ile çıkış ülkesini bir kez çözer: `CN` Gitee→GitHub, diğerleri GitHub→Gitee, yoksa Gitee ilk. Bilibili salt okunur video bilgisi, URL ve CDN kullanır; bağlantı tanıma bağlanmaz. Kota denetimi sağlayıcılara; isteğe bağlı çeviri, kayıt düzenleme ve transkript temizliği seçili model/CLI'ya gider. Tanıma sistem/dile göre Apple hizmeti kullanabilir. Bağımlılık/CLI kurma-güncelleme, genel IP ve açık ağ eylemleri de istek yapar.
- **Otomasyon:** Notlar AppleScript/JXA ile Apple Notlar'ı listeler, okur, düzenler, oluşturur, siler. Otomasyon izni ister, ağ kullanmaz, veri Apple Notlar'da kalır.

## Testler

Tam Xcode kurulumunda:

```bash
swift test
```

Yalnızca Command Line Tools ile:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Belgeler

- [Mimari ve performans tasarımı](Docs/architecture.md)
- [CLI entegrasyon başvurusu](Docs/cli-reference.md)
- [İmzalama ve sürüm tasarımı](Docs/releasing.md)
- [Depoya dahil edilen bağımlılıklar (İngilizce)](../../../../mac/Vendor/README.md)
- [Üçüncü taraf bildirimleri (İngilizce)](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Sistem sınırları

- macOS genel Dynamic Island API sunmaz; çentik `safeAreaInsets` ve üst yardımcı alandan anlaşılır, çentiksiz ekranlar aynı özel kaplamayı kullanır.
- DRM video, oturum açma, kilit ekranı ve bazı özel tam ekran uygulamalar medya verisi veya kaplama izni vermeyebilir.
- Sistem medyasına entegre olmayanlar ses kaynağı sunabilir, başlık/kapak/ilerleme garanti etmez; duraklayan, duran ve sessiz video gizlenir.
- Yüzde için tarayıcı genel ilerleme veya İndirilenler'de tanınan geçici dosya sunmalıdır.
- Pil sağlığı, sıcaklık, anlık güç ve aksesuar bilgisi donanım, bağlantı ve macOS'a bağlıdır; eksik alanlar kullanılamaz görünür.
- Office PDF dönüşümü LibreOffice/OpenOffice ister; diğer PDF işlemleri yereldir.
- Paketler noter onaylı değildir; ilk açılış **Yine de Aç** gerektirebilir. Kararlı sürümler izinleri korumak için aynı kendinden imzalı sertifikayı kullanır; Sparkle açmadan, değiştirmeden, başlatmadan önce EdDSA açık anahtarıyla ayrıca doğrular.

## Lisans

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Ticari olmayan kullanım serbest; satış veya ticari kullanım yasaktır.
