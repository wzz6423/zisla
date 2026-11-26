# `zislactl` entegrasyon başvurusu

**Türkçe** | [Belge dilleri](../../../README.md)

`zislactl`, zisla ile bütünleşen yapay zekâ araçları, betikler ve CI görevleri için ortak yerel durum protokolüdür. Görev durumunu, kullanımı ve bildirimleri yapılandırılmış veri olarak yazar; kısmi durum yazılmasını önlemek için SQLite işlemleriyle kalıcılaştırır. Bu belge kararlı sağlayıcıları, komutları ve alan kısıtlarını tanımlar.

## Tasarım ilkeleri

- Durum yerel olarak yazılır; istemler, yanıt içerikleri veya kimlik bilgileri hiçbir zaman yüklenmez.
- Aynı görev kimliğine yapılan güncellemeler idempotenttir; okuyucular veritabanının tam ve onaylanmış durumunu görür.
- Sağlayıcı adları uyumluluk takma adlarını kabul eder, ancak kanonik değerle saklanır.

## Yerel kalıcılık ve JSON sınırları

Görevler, kullanım ve bildirimler `~/Library/Application Support/zisla/ai-state.sqlite` içinde tutulur. Yazma SQLite işlemleri kullanır; mevcut protokol `ai-state.json` yazmaz. Görevleri temizlemek kullanım geçmişini korur.

`zislactl` belgelenen komut satırı seçeneklerini kabul eder; `list` satır tabanlı metin yazdırır. Entegrasyonlar ve yapılandırma kendi ayrıştırma kurallarıyla yapılandırılmış JSON kullanmayı sürdürür; dış araçların JSON/JSONL oturum girdileri ve ayarların JSON kodlama/kod çözmesi buna dahildir. CLI ise argümanlar, metin çıktısı ve SQLite kalıcılığı kullanır.

## Sağlayıcılar

| Değer | Takma adlar |
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

WorkBuddy ve WorkBuddy AI, ulusal/uluslararası pazarlar için ayrı ürünlerdir;
aynı istemcinin eski/yeni sürümleri değildir. Kanonik sağlayıcıları, depoları, simgeleri ve derin bağlantıları
ayrı kalmalıdır. `harness` kullanan geçmiş WorkBuddy kayıtları okunabilir kalır;
bu sağlayıcı genel olarak yeniden adlandırılmaz veya taşınmaz. WorkBuddy etkinlik bildirimi kimlikleri açık
sağlayıcı/görev sınırı kullanır: `ai-active-workbuddy:<id>` veya `ai-active-workbuddy-ai:<id>`.
Böylece kimliği `ai-` ile başlayan elle oluşturulmuş WorkBuddy görevi WorkBuddy AI ile karıştırılmaz.

### Delta, Orca, WorkBuddy ve WorkBuddy AI otomatik algılama

- Delta, dizinlenmiş akış iş parçacığı meta verilerini `Library/Application Support/Delta/user_*/data.sqlite`
  ve eski kök veritabanından okur. Arşivlenmiş, boşta ve eski iş parçacıkları dışlanır. Sayısal kullanım
  Delta'nın `app_model_usage_daily` defterinden, önbellek okumaları ve yazmaları dahil alınır. Bu defteri içermeyen
  sürüm otomatik kullanım bildirmez; konuşma içeriğinden sayı tahmin etmez.
- Orca, yerel `agent-hooks/last-status.json` anlık görüntülerini ve mevcut yapılandırılmış sohbet turu durumunu
  `agent-session-journal.db` üzerinden okur; profil dizinleri ve v1/v2/v3 tur kayıtları dahildir.
  En yüksek revizyon ve özgün tur sırası korunur. Bitmiş, süresi dolmuş, uzak ve
  yalnızca kimlik içeren oturumlar dışlanır. Yetkili transkript yolları ve sabitlenmiş Claude/Codex
  hesap ana dizinleri de token kullanımına katkı yapar. Örnekler alttaki CLI sağlayıcısını ve
  olay kimliğini korur; normal CLI algılayıcısı yeniden sayamaz. Orca'nın makine genelindeki kullanım
  önbellekleri ek kullanım olarak bilerek içe aktarılmaz.
- WorkBuddy, kendi `~/.workbuddy/workbuddy.db` deposunu `workbuddy` sağlayıcısı,
  WorkBuddy simgesi ve `workbuddy://chat/<id>` bağlantılarıyla okur. WorkBuddy AI deposunu incelemez.
- WorkBuddy AI, oturum durumunu, başlığı, modeli ve zamanları
  `~/.workbuddy-ai/workbuddy.db` üzerinden, WorkBuddy'nin `~/.workbuddy/workbuddy.db` deposundan bağımsız okur.
  Bitmiş, silinmiş ve eski oturumlar dışlanır. `updated_at` ve
  `last_activity_at` değerlerinden yenisi uzun süren oturumları görünür tutar. Görevler `workbuddy-ai` sağlayıcısı,
  WorkBuddy AI simgesi ve `workbuddy-ai://chat/<id>` bağlantısını kullanır. Entegrasyon yalnızca oturumları algılar:
  `session_usage.used` bağlam doluluğudur ve krediler USD/token kullanımı değildir; bu yüzden ikisi de
  faturalanmış token olarak alınmaz. Elle sayısal kullanım `zislactl usage` ile bildirilebilir.
- Tüm entegrasyonlar salt okunur ve mevcut verilere göre çalışır; eksik veya uyumsuz depolar veri döndürmez.
  Delta'nın çoğaltılmış konuşma içerikleri veya Orca günlük iletileri sorgulanmaz. Sayısal kullanım kaydı sunmayan
  araçlar veya sürümler için `zislactl usage` kullanın.

## Seçenek sözdizimi

- Seçeneği `--key value` veya `--key=value` olarak yazın. Her seçenek komutta yalnızca bir kez olabilir; tekrar kullanım hatasıdır, çıkış kodu 64.
- Değer `--` ile başlayabilir, örneğin `--detail --verbose`. Aynı komutun bayrağı istisnadır: `finish` için `--failed`, `update` için `--queued` hiçbir zaman değer sayılmaz. Bu yüzden `--detail $DETAIL --failed` içindeki tırnaksız boş değişken görevi yine başarısız işaretler. Böyle bir gerçek değeri `--detail=--failed` olarak verin.
- `--failed` ve `--queued` bayraktır. Tek başlarına doğru demektir; `--failed=false` veya `--failed false`, aynı şekilde `--queued`, bayrağı kapatır. Diğer değerler kullanım hatasıdır.

## `update`

Aynı `id` ile görev oluşturur veya değiştirir.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- `--progress` verilmezse arayüz belirsiz ilerleme gösterir.
- `--pid` isteğe bağlıdır; yalnızca çağıran görev sürecini belirleyebiliyorsa verilmelidir.
- `--status`, çalışma, kuyruk, kullanıcı eylemi bekleme veya çalışma sırasında hata durumunu açıkça bildirir.
- `--queued`, `--status queued` takma adıdır; açık durum yoksa görev çalışır. Açık `--status`, `--queued` değerinden önceliklidir.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Başarılı görevler %100'e ayarlanır; başarısızlar son ilerlemeyi korur.

## `remove`

```text
zislactl remove --id <id>
```

Görev yoksa 65 koduyla çıkar.

## `clear`

```text
zislactl clear
```

Kullanım geçmişi ve bildirimleri koruyarak görevleri temizler.

## `list`

```text
zislactl list
```

Güncel görev durumunu, sağlayıcıyı, başlığı ve yüzdeyi satır satır yazdırır.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Kullanım 12 saatlik grafiği ve 7x24 ısı haritasını besler.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

Yeni bildirim seçilen yandan görünür; üzerinde beklenirken otomatik kapanma durur.

## `message`

Adanın iki yanına bir ileti bildirimi gönderir: solda uygulama logosu ve gönderen, sağda kayan içerik görünür.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Örnek:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender` ve `--content` gereklidir; `--app-bundle-id` isteğe bağlıdır ve kurulu uygulama simgesini belirlemeye yardımcı olur.
- Satır sonları ve fazla boşluklar birleştirilir; içerik yaklaşık 48 karaktere kısaltılıp üç nokta eklenir.
- Tek SQLite işlemi iki `IslandNotice` kaydını da saklar; mevcut `notify` davranışını değiştirmez.

## Çıkış kodları

| Kod | Anlam |
| --- | --- |
| `0` | Başarı |
| `64` | Geçersiz argüman veya alt komut |
| `65` | Veri hatası, eksik görev veya bozuk veritabanı |
| `70` | Dosya sistemi veya başka çalışma hatası |
