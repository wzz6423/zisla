# Mimari ve performans tasarımı

**Türkçe** | [Belge dilleri](../../../README.md)

## Üst kenardan tetikleme

Gizli durumda saydam pencere bulunmaz. `PointerEdgeMonitor`, fare hareketleri ve sürükleme olayları için genel ve yerel `NSEvent` izleyicileri kurar. `ScreenLayoutEngine`, işaretçinin her ekranın üst ortasındaki 6 px alana girip girmediğini yalnızca geometriyle belirler.

Her ekran, `NSScreenNumber` ile `CGDirectDisplayID` eşleştirilerek kararlı bir kimlik alır. Düzen `screen.frame.maxY` noktasına bağlıdır; böylece negatif koordinatlar, dikey dizilmiş ekranlar ve çentiksiz harici ekranlar desteklenir.

## Pencere

Ana ada tek bir `.borderless + .nonactivatingPanel` kullanır:

- `.statusBar` düzeyindedir ve sistem kilit ekranını ya da sistem menüsünü örtmez.
- `.canJoinAllSpaces + .fullScreenAuxiliary`, Spaces ve normal tam ekran uygulamalarını destekler.
- İşaretçiyle genişleme hiçbir zaman `NSApp.activate` çağırmaz; geçerli uygulamanın odağını almaz.
- Gizli durumda `orderOut` kullanılır; menü çubuğu alanını saydam bir pencere işgal etmez.

Sol ve sağ bildirim panelleri gerektiğinde oluşturulur ve kuyrukları boşalır boşalmaz gizlenir.

## Durum ve eşzamanlılık

- AppKit, SwiftUI durumu ve pencere denetimi `MainActor` üzerinde kalır.
- İndirmeler, hava durumu ve GitHub istekleri actors kullanır.
- Kancaların yazdığı yapay zekâ durumu, dizinin dosya sistemi olayları üzerinden izlenir. Her yapay zekâ oturum kaynağı, en son yerel oturum veya etkinlik dosyasının değişiklik zamanını ve boyutunu karşılaştırır. Hiçbir şey değişmediyse ayrıştırma önbelleğini yeniden kullanır.
- Otomatik algılama yalnızca görev durumunu belirlemek için gereken yapılandırılmış olayları, sabit durum işaretlerini ve etkinlik meta verilerini okur. İstem veya yanıt içeriklerini okumaz; bir sağlayıcının ayrıştırma hatası diğer sağlayıcıları engellemez.
- Yapay zekâ hesap kotaları her sağlayıcıdan ayrı alınır. Antigravity Gemini ve Claude/GPT kotaları ayrı yenilenme pencerelerini ve uyarılarını korur. Gemini App normal sohbet kotası aynı Google hesabının kayıtlı web Cookie bilgisiyle sorgulanır; Gemini CLI yerel OAuth kaynağını korur. Eksik kotalar tahmin edilmez.
- Daraltma gecikmeleri iptal edilebilir `Task` nesneleri ve nesil belirteci kullanır; eski bir görev yeniden açılmış adayı gizleyemez.
- Gizli durumda `TimelineView`, 60 Hz sayaç veya sürekli animasyon gönderimi bulunmaz.

## Medya algılama

MediaRemote başlık, kapak, ilerleme ve oynatma denetimlerini sağlar. Core Audio 14.4+ süreç nesnesi özellikleri, uygulamanın etkin bir çıkış akışı olduğunu doğrular ve meta veri yoksa alternatif kaynak uygulamayı belirler. Süreç listeleri ve çıkış durumu, özellik dinleyicileri ile sınırlandırılmış periyodik doğrulamayı birlikte kullanır. Ses içeriği hiçbir zaman yakalanmaz; Ekran Kaydı veya Erişilebilirlik izni istenmez. Duraklatılmış, durdurulmuş ve sessize alınmış kaynaklar medya alanında tutulmaz.

## Kayıt ve uygulama karıştırma

Ekran kaydı ve uygulama ses düzeyi karıştırıcısı, meta veri algılamadan ayrıdır. Kayıt, Ekran Kaydı ve açık mikrofon/kamera kaynaklarının izinlerini ister, seçilen medyayı yerel olarak saklar ve projeleri seçilen kayıt klasöründe yönetir. Uygulama karıştırıcısı macOS 14.4+ üzerinde Core Audio taps kullanır ve Sistem Sesi Kaydı izni gerektirir.

## Malzemeler

macOS 26 tek katmanlı SwiftUI `glassEffect`; macOS 14/15 tek katmanlı `NSVisualEffectView` kullanır. Saydamlığı Azalt, opak arka plana geçer. Ada birden fazla bulanıklık veya malzeme katmanını üst üste koymaz.

## İndirme güvenlik sınırı

Swift, `yt-dlp` aracını `Process.executableURL` ve argüman dizisiyle başlatır. URL her zaman `--` sonrasında ayrı bir argv değeridir. Çalışma yapılandırması, eklentiler ve exec kapalıdır; çıktı kanalları eşzamanlı boşaltılır ve ilerleme bir JSON işaretçisi üzerinden ayrıştırılır.

Bir görev yalnızca çıkış kodu 0 ise, çıktı yolu mevcutsa ve çözümlenen yol yetkilendirilmiş dizin içinde kalıyorsa başarılıdır. Her görev yalnızca UUID ile adlandırılmış kendi geçici dizinini temizler.

## Güncelleme denetimleri ve indirmeler

Seçilen güncelleme kanalı, her uygulama çalışmasında genel ağ çıkışının ülke kodunu bir kez çözümler. Ardından Sparkle, kurulu yapı için imzalı appcast'i alır, belirtilen ZIP'i HTTPS üzerinden indirir, çıkarmadan önce arşiv ve akışın EdDSA imzalarını doğrular, uygulamayı değiştirir ve yeniden başlatır. `CN`, Gitee ile başlar: Release için `update-release`, Preview için `preview`. Sonra eşleşen GitHub akışını bir kez dener. Diğer ülke kodları GitHub ile başlar ve Gitee'yi bir kez dener. Ülke sorgusu kullanılamıyorsa Gitee önceliği korunur; her akış kendi sunucusundaki imzalı ZIP'e işaret eder. Bir sürüm, ortak `appcast.xml` yanında her mimari için ayrı appcast yayımlar. Tek mimarili kurulum kendi dilimine uygun akışı ister; çeviri altında çalışan x86_64 dilimi `arm64` ister. Böylece evrensel yapıyla değiştirilmez. Evrensel kurulum kendi çalıştırılabilir dosyasındaki dilimleri sayar ve `appcast.xml` kullanmayı sürdürür; bu akış, mimariye özgü güncellemelerden önce yayımlanan uygulamalara da hizmet verir. Ayarı değiştirmek otomatik ve elle denetimleri etkiler, Sparkle'ın sonraki güncelleme döngüsünü sıfırlar. Gömülü açık anahtar hesap bilgisi içermez; özel imzalama anahtarı sürüm sorumlusunun macOS Anahtar Zinciri'nde veya ayrıca korunan özel anahtar dosyasında kalır.
