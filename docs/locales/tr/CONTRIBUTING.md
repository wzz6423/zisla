# zisla'ya katkıda bulunma

**Türkçe** | [Belge dilleri](../README.md)

zisla'ya katkıda bulunduğunuz için teşekkür ederiz.

## Issue

Issue açtığınız için teşekkür ederiz. Aynı raporu tekrar göndermemek için önce mevcut Issues ve Discussions içinde arama yapın.

- Hata raporunda `[Bug] Short problem description` kullanın; örneğin `[Bug] Voice input is not written to the current text field`. zisla sürümünü, macOS sürümünü ve aygıtı, kurulum yöntemini, yeniden oluşturma adımlarını, beklenen ve gerçek davranışı ekleyin.
- Özellik isteğinde `[Feature] Short request description` kullanın; örneğin `[Feature] Support custom voice-organization prompts`. Sorunu, önerilen çözümü ve düşündüğünüz alternatifleri açıklayın.
- Formda bir **Area** seçin. Zorunludur ve `area:*` etiketini belirler: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` veya `Community & Discussion`. Basitleştirilmiş Çince formlar aynı seçenekleri ve etiketleri kullanır.
- Günlük, görüntü ve kayıtlardan token, hesap bilgisi, yerel yol ve diğer hassas bilgileri çıkarın.
- Güvenlik açıklarını genel issue yerine [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) üzerinden özel bildirin.
- Otomasyon, eşleşen `area:*` ile birlikte `bug` veya `enhancement` ekler; diğer etiketleri değiştirmez. Başlık öneki veya zorunlu alan forma uymuyorsa `needs-more-info` ekler ve eksikleri tek yorumda listeler. Issue düzenlenince yorum kendini günceller.

## Geliştirme

Mevcut macOS uygulaması `mac/` içindedir; macOS 14+ ve Swift 6 / Xcode 16+ gerektirir.

```bash
cd mac
swift test
```

Commit öncesinde test, derleme ve paketleme ikili dosyalarını kaldırın.

Her commit veya amend öncesinde, CI ile aynı SwiftFormat 0.64.7 sürümüyle depo kökünde `make format` çalıştırın. Farkı inceleyin; yalnızca mevcut görev için gereken biçimlendirmeyi koruyun.

## Dallar ve commit'ler

- En yeni `main` üzerinden dal oluşturun ve pull request'in bildireceği tür önekini kullanın: `feat/` veya `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`. Örnekler `fix/download-timeout` ve `ci/skip-directive-timing`.
- İngilizce [Conventional Commits](https://www.conventionalcommits.org/) biçimini kullanın; örneğin `type(scope): description` veya `fix(ui): resolve layout issue in notch area`.
- Bir dal ve pull request'i tek açık hedefe odaklayın; yalnızca biçimlendirme veya ilgisiz yeniden düzenleme eklemeyin.
- `publish-v*` dalları yayın bakımına ayrılmıştır. Diğer katkıları `main` dalına gönderin.

## Pull request

Pull request açtığınız için teşekkür ederiz. İncelemeyi beklerken bu gereksinimleri denetleyin.

- **PR başlığı** İngilizce Conventional Commit konusu olmalıdır; örneğin:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  İzin verilen türler `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` ve `revert`.

- **PR gövdesi** İngilizce olmalı ve `.github/PULL_REQUEST_TEMPLATE.md` içindeki `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` bölümlerini içermelidir.
  - `GitHub Project`, şablondaki `- Project: zisla Development` değerini korur. `Project Automation` PR'yi ortak panoya yerleştirmek için bu değeri okur.
  - `GitHub Project` içinde `Start date` ve `Target date` zorunludur. Her birini gerçek takvim tarihiyle `YYYY-MM-DD` biçiminde tam bir kez yazın; `Target date`, `Start date` ile aynı veya sonra olmalıdır. Eksik, boş, yorumda, yinelenmiş veya geçersiz tarihler `PR Quality` hatası verir. `Submitted date` UTC+08:00 oluşturma tarihidir; `End date` birleşmede otomatik doldurulur. İkisi de elle girilmez.
  - `PR Type` tam bir `- Type:` değeri bildirir; başlıktaki türe çözümlenmelidir. Başlıklar kanonik tür kullanır; gövde etiket adlarını ve ayarlı takma adları kabul eder. `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` değerlerinin tümü `fix` olur. `PR Automation` bunu etikete dönüştürür; örneğin `fix` → `bug`.
  - `Project Automation`, PR tür etiketi dahil yapılandırılmış eşlemeyle `Status` seçer; PR kapanınca veya birleşince `Done` yapar. `Status` elle girilmez.
  - `Summary` değişimi açıklamalı; `Risk and Rollback` tam bir dolu `Risk` ve bir dolu `Rollback` alanı içermelidir.
  - Her `Validation` girdisi kendi `- Status:` satırında tam `passed`, `failed` veya `not run` bildirir. Her `passed`/`failed` girdisinin kendi dolu `Command` ve `Result` alanı; her `not run` girdisinin kendi dolu `Reason` alanı olmalıdır. Başka girdinin alanları yeterli değildir. Hataları dürüstçe `failed` bildirin.
  - `Related Issue`, `Closes #123` gibi anahtar sözcükle issue kapatmalı, böylece `development` etiketi de eklenir; veya tam `None` olmalıdır.
  - `AI Attribution` tam bir dolu `- Agent:` alanı bildirmelidir. `None` dışındaki agent, eşleşen `- Co-authored-by: Name <email>` satırı gerektirir; en az bir commit'in trailer'ında da bulunmalı ve `ai-assisted` etiketi eklenmelidir.

  Örnek başlık: `fix(ci): validate every PR metadata entry`

  Örnek gövde; gerçek doğrulama sonuçlarınızı yazın:

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

  Tarih örneği: PR 2026-10-05 oluşturulup 2026-10-12 birleşsin, UTC+08:00. Kod yorumundaki otomatik alanlar Project değerlerini örnekler; girdi değildir. Otomasyon GitHub Project ve PR Timeline'ı günceller, bu örnek yorumları değil.

  | Tarih | Oluşturmada (2026-10-05) | Birleşmeden sonra (2026-10-12) | Kaynak |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Zorunlu girdi |
  | `Target date` | 2026-10-12 | 2026-10-12 | Zorunlu girdi |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Otomatik oluşturma tarihi |
  | `End date` | Boş | 2026-10-12 | Otomatik birleşme tarihi |

- `PR Quality` biçimi doğrular; başarısızken PR birleştirilemez. Ardından `PR Automation` etiketleri ekler ve PR'yi atar.
- macOS kod değişiminde `cd mac && swift test` çalıştırın; arayüz değişiminde elle doğrulama sonuçlarını metinle yazın.
- PR gövdeleri ve yayın notları yalnızca metin olabilir; görüntü, ekran görüntüsü veya kapak gerekmez.
- Özellik, davranış, varsayılan, derleme veya yayın değişiminde aynı yamada resmî belgeleri ve web yardımını güncelleyin. Kullanıcıya yönelik web metinleri 17 dili kapsar; mevcut yardım ve yerelleştirilmiş belge dizinini kullanın.
- `.build`, `dist`, indirilmiş dosya, günlük, token, imzalama malzemesi veya kişisel veri commit etmeyin.
- `main` ve `publish-v*` korunur; yalnızca incelemeden geçen ve kontrolleri başarılı PR ile güncellenir.

## CI denetimlerini atlama

Bakımcılar ve istenen inceleyiciler, yalnızca belge düzeltmesi gibi değişimin etkileyemeyeceği denetimleri atlayabilir. PR yorumunda direktifi ayrı satırda yazın:

| Direktif | Etkisi |
| --- | --- |
| `skip-all` | `.github/ci-skip.json` içindeki tüm iş akışlarını atlar. |
| `skip-<workflow>` | Ad, dosya veya takma adla tek akışı atlar; `skip-swift`, `skip-web-ci`, `skip-Web CI` gibi. |
| `unskip-all` | Tüm atlama direktiflerini temizler. |
| `unskip-<workflow>` | Bir akışı geri açar. |

- Ardından serbest metin gelebilir; örneğin `skip-all: documentation only change`.
- Akış GitHub'daki boşluklu adıyla yazılabilir; `skip-CI Lint` ve `skip-lint` aynıdır. En uzun eşleşen ad seçilir, kalan sözcükler not olur.
- Yalnızca depo sahibi, kuruluş üyesi, işbirlikçi veya istenen inceleyicinin direktifi kabul edilir. Bot yorumları yok sayılır.
- `CI Skip` çalışan işleri iptal eder, gerekli kontrolleri karşılamak için atlananları başarılı bildirir, `skip-ci` ekler ve tek özet yorumunu günceller.
- Her yorumda tüm yorum dizisi yeniden değerlendirilir; en son direktif geçerlidir.
- Yeni commit gönderilince direktif sona erer; yalnızca yazarın gördüğü kodu kapsar, yoksa başarılı denetim yeni commit'i derlenmeden birleştirirdi. `CI Skip` her push'ta `skip-ci` kaldırır ve kontrolleri açar; özet sona eren direktifleri listeler. Yeni commit için yeniden yorum yazın.
- Bakımcı yeni yorum olmadan **Actions -> CI Skip -> Run workflow** üzerinden PR numarasıyla mevcut kararı yeniden uygular.
- `.github/ci-skip.json`, akışları yayımladıkları kontrol adlarına eşler. Dosyalarla manifest farklıysa `CI Checks` başarısızdır.

## Yola bağlı kontroller

Platform akışı yalnızca PR derlediği dosyalara dokunursa çalışır; belge değişimleri bulunduğu yola göre denetlenir:

| İş akışı | PR şu yolları değiştirince çalışır |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- Kapsamı `.github/ci-skip.json` içindeki `paths` belirler; belirtmeyen akış daima çalışır. `CI Lint`, `PR Quality Gates`, `CodeQL`, `Dependency Review` her PR'de çalışır. Depo temizliği ve skill doğrulaması `CI Checks` içindedir; eski `hygiene` ve `skills` takma adları kullanılmaz.
- `.github/` altındaki her değişim tümünü çalıştırır; CI değişimi tüm platformlarda doğrulanmalıdır.
- Atlama akış `paths:` filtresi yerine job koşuluyla yapılır; gerekli kontrol sürekli beklemek yerine başarı bildirir.
- Yeniden adlandırılan dosya eski ve yeni yolla eşleşir; büyük/küçük harf farkı yok sayılır.
