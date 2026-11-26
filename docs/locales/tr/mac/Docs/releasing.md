# İmzalama ve sürüm tasarımı

**Türkçe** | [Belge dilleri](../../../README.md)

Tüm yayın süreci, iki güncelleme kanalı ve GitHub/Gitee dosya eşitlemesi [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md) tarafından yönetilir. Bu sayfa yalnızca imzalama, noter onayı ve güncelleme paketlerinin tasarım kısıtlarını açıklar; sürüm yayımlarken skill yönergelerini izleyin.

Her iki güncelleme kanalı, uygulamayı değiştirmeden ve yeniden başlatmadan önce Sparkle ile imzalı ZIP ve appcast'i doğrular. Uygulama genel ağ çıkışının ülke kodunu her çalışmada bir kez çözer: `CN` önce Gitee'yi, sonra tam bir kez GitHub'ı dener; diğer ülke kodları GitHub'dan başlayıp Gitee'yi bir kez dener. Sorgu yoksa Gitee önceliği korunur. `package-release.sh`, `SPARKLE_GENERATE_APPCAST` değerinin Sparkle 2.9.4 içindeki `generate_appcast` aracına işaret etmesini ister ve ZIP/DMG yanında `appcast-gitee.xml` ile `appcast-github.xml` yazar. Her appcast ayrı imzalanmalı ve aynı çalışmada üretilen, kendi sitesinde barındırılan ZIP'e işaret etmelidir. `build-package.sh` betiği her mimari için çalıştırır; böylece sürüm üç çift taşır. Evrensel çift, mimari güncellemelerinden önce çıkan uygulamaların hâlâ istediği `appcast.xml` adıyla; tek mimarili çiftler `appcast-arm64.xml` ve `appcast-x86_64.xml` olarak yüklenir. Tek mimarili kurulum, Info.plist akış adresini çalışan dilimin appcast'ine çevirir; çeviri altında x86_64 dilimi `arm64` ister. Bu yüzden evrensel yapıya büyümeden kendi mimarisiyle güncellenir. Evrensel kurulum dilimlerini sayar, ortak adı korur ve evrensel kalır. Gitee kalıcı `update-release` ve `preview` akışlarını; GitHub Release için `latest`, Preview için kalıcı ön sürüm `preview` kullanır. Etkileşimsiz yayında `SPARKLE_ED_KEY_FILE` değerini özel saklanan EdDSA anahtar dosyasına ayarlayın veya giriş anahtar zinciri hesabı `zisla-update-ed25519` kullanılması için boş bırakın. Özel anahtar depoya asla girmemelidir. Kararlı sürümler aynı kendinden imzalı sertifikayı kullanır; tanımlanmış gereksinim sabit kalır ve macOS izinleri güncellemelerde korunur. Bunlar yine noter onaylı değildir. Developer ID paketleri noter onayı almalıdır; ücretsiz ad hoc Preview paketleri de noter onayı alamaz.

## Ön koşullar

- Ayrı yayın anahtar zincirinde `zisla Release Signing` kimliği veya Developer ID Application sertifikası
- Developer ID kullanırken Apple noter onayı kimlik bilgileri
- `Scripts/fetch-yt-dlp.sh` ile alınmış ve doğrulanmış resmî `yt-dlp` yardımcı aracı

## 1. İmzalı uygulamayı derleyin

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Kararlı sürümde betik varsayılan `RELEASE_SIGNING_MODE=selfsigned` kullanır, `~/Library/Keychains/zisla-release-signing.keychain-db` içinden `zisla Release Signing` okur ve giriş zincirindeki `dev.wzz.zisla.release-signing-keychain` öğesiyle zinciri açar. Gatekeeper ilk açılış uyarısını kaldırmaz; ancak derlemeye özel cdhash yerine sertifika tabanlı tanımlanmış gereksinimi korur.

Developer ID sertifikasıyla noter onayına uygun yolu açıkça seçin:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Çıktı:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Ücretsiz Preview dağıtımı

Apple Developer Program olmadan ad hoc imzalı önizleme derleyin:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Bu paket noter onaylı değildir ve WeatherKit yetkisi içermez. İmzalı appcast kalıcı Preview akışına yüklendikten sonra Sparkle Preview güncellemelerini denetler, indirir, doğrular, kurar ve yeniden başlatır. İlk açılışta yine **Sistem Ayarları > Gizlilik ve Güvenlik > Yine de Aç** gerekebilir. Güvenlik istemleri olmadan dağıtım için Developer ID imzası ve noter onayı önerilmeye devam eder.

## 2. Noter onayı alın

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

## 3. Yayımlayın ve doğrulayın

ZIP'leri, DMG'leri, sağlama toplamlarını ve GitHub appcast'lerini aynı sürüm etiketine yükleyin; adlar evrensel için `appcast.xml`, ayrıca `appcast-arm64.xml` ve `appcast-x86_64.xml` olmalıdır. Eşleşen dosyaları ve Gitee appcast'lerini aynı üç adla aynı Gitee etiketine yükleyin. Kararlı sürüm ön sürüm olarak işaretlenmemelidir. Üç Gitee appcast'ini kalıcı `update-release` akışına; Preview appcast'lerini her iki sitedeki kalıcı `preview` akışına kopyalayın. Seçili kanal `CN` için Gitee ardından GitHub, diğerleri için GitHub ardından Gitee denetler.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Normal yayınlarda yerel dosya, imza, sağlama toplamı, paket düzeni ve appcast denetimleri; iki sitedeki dosya ve kalıcı akış doğrulamaları ile yayın meta verisi doğrulaması korunur. Paketleri tekrar indirme, kurulum denetimleri ve gerçek Sparkle yükseltme kabulü yalnızca açıkça istendiğinde yapılır.

Yükseltme kabulü istendiğinde yeni sürümü eski uygulamayla denetleyin. `CN` genel çıkışındaki otomatik ve elle denetimlerin önce seçili Gitee akışını, sonra bir kez GitHub'ı; diğer çıkışların GitHub sonra bir kez Gitee'yi kullandığını doğrulayın. Sparkle'ın çalışan mimari ZIP'ini kurup yeniden başlattığını ve tek mimarili kurulumun tek mimarili kaldığını doğrulayın. Release→Preview, Preview→Release ve aynı kanal yükseltmelerini sınayın. İstenmeyen denetimler `Not verified` olarak kaydedilir ve yayını tamamlamanın ön koşulu değildir.

## 4. Homebrew cask'i eşitleyin

Kararlı yayın Homebrew'da tamamlanır. Preview bu adımdan önce durur: tap yalnızca kararlı sürüm sunduğundan `brew upgrade` kullanıcıyı ön sürüme geçirmez.

Yayın dosyaları yüklendikten sonra depo kökünden çalıştırın:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Betik `Casks/zisla.rb` içinde `version` ve iki `sha256` değerini yeniden yazar. Varsa özetleri `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` ve `x86_64` eşinden, yoksa yayımlanmış GitHub dosyalarından alır. Cask her makine için `#{arch}` çözer; Apple Silicon ve Intel yalnızca kendi dilimini indirir. Doğrulama iki mimaride aynı özeti kullanan cask'i reddeder. `homebrew-cask.rb verify` başarısızsa dosya yazılmaz; başarılıysa `wzz6423/homebrew-tap` deposuna aynalanır. Yalnızca depo içi cask'i güncelleyen deneme için `PUBLISH_TAP` değerini vermeyin.

Cask `auto_updates true` taşır çünkü güncellemeyi Sparkle yönetir. `brew upgrade`, kurulu paket gerçekten tap'ten eskiyse değiştirir; Homebrew 5.1.6 ve sonrası paket içindeki sürümü okuyarak karar verir. `brew upgrade --cask zisla` ve `--greedy` ise Homebrew kurulum kayıtlarını kullanır ve tap sürümünü geri koyarak Sparkle güncellemesini geri alabilir. Cask değişimini sitenin `latestRelease` artışıyla birlikte commit edin; sürümler farklıysa CI başarısız olur. Depo kökünden cask ve site meta verilerini doğrulayın:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew indirme, kurulum, yükseltme ve `livecheck` kabulü yalnızca açık istekle yapılır. Kurulum kabulü örneği:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

İstenmeyen Homebrew kabul denetimleri `Not verified` olarak kaydedilir; yayını tamamlamak için ön koşul değildir.
