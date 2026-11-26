# مرجع تكامل `zislactl`

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **العربية** | [اللغات الأخرى](../../../README.md)

`zislactl` بروتوكول حالة محلي مشترك لأدوات AI والسكربتات ومهام CI المتكاملة مع zisla. يكتب حالة المهام والاستخدام والإشعارات كبيانات منظمة ويحفظها بمعاملات SQLite لمنع الكتابة الجزئية. يحدد هذا المرجع المزودين والأوامر وقيود الحقول المستقرة.

## مبادئ التصميم

- الحالة محلية ولا تُرفع الطلبات أو الإجابات أو بيانات الدخول.
- تحديثات معرّف المهمة نفسه متماثلة الأثر؛ يرى القارئ حالة قاعدة كاملة مثبتة.
- تقبل أسماء المزودين أسماء توافق بديلة لكنها تُحفظ بقيمها القياسية.

## الحفظ المحلي وحدود JSON

المهام والاستخدام والإشعارات في `~/Library/Application Support/zisla/ai-state.sqlite`. تستخدم الكتابة معاملات SQLite؛ لا يكتب البروتوكول الحالي `ai-state.json`. مسح المهام يبقي تاريخ الاستخدام.

يقبل `zislactl` خيارات الأوامر الموثقة ويطبع `list` نصًا سطريًا. ما تزال التكاملات والإعدادات تستخدم JSON منظمًا، ومنها مدخلات جلسات JSON/JSONL الخارجية وترميز الإعدادات وفق قواعد تحليلها الخاصة. يستخدم CLI ذاته معاملات أوامر وخرجًا نصيًا وحفظ SQLite.

## المزودون

| القيمة | الأسماء البديلة |
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

WorkBuddy وWorkBuddy AI منتجان منفصلان للسوق المحلي والدولي، لا نسختان قديمة وجديدة لعميل واحد. تبقى المزودات والمخازن والأيقونات والروابط العميقة منفصلة. تظل سجلات WorkBuddy القديمة ذات `harness` قابلة للقراءة ولا يعاد تسمية المزود أو ترحيله عالميًا. تفصل معرّفات إشعارات WorkBuddy المزود عن المهمة صراحة بـ`ai-active-workbuddy:<id>` أو `ai-active-workbuddy-ai:<id>` فلا تُخلط مهمة WorkBuddy اليدوية التي تبدأ `ai-` مع WorkBuddy AI.

### الاكتشاف التلقائي لـDelta وOrca وWorkBuddy وWorkBuddy AI

- Delta: يقرأ بيانات الخيوط المتدفقة المفهرسة من `Library/Application Support/Delta/user_*/data.sqlite` ومن القاعدة القديمة الجذرية. يستبعد المؤرشف والخامل والقديم. تأتي الأرقام من سجل `app_model_usage_daily` بما فيه قراءة التخزين المؤقت وكتابته. الإصدار بلا سجل لا يبلغ استخدامًا تلقائيًا ولا يخمن الأعداد من المحادثة.
- Orca: يقرأ لقطات `agent-hooks/last-status.json` وحالة الدور المنظم الحالي من `agent-session-journal.db`، بما فيها أدلة الملفات الشخصية وأدوار v1/v2/v3. يحترم أعلى مراجعات وترتيب الأدوار الأصلي، ويستبعد المكتمل والمنتهي والبعيد وجلسات الهوية فقط. تساهم مسارات التفريغ الموثوقة ومجلدات حسابات Claude/Codex المثبتة في الاستخدام. تحفظ العينات مزود CLI وهوية الحدث فلا يعدها اكتشاف CLI المعتاد ثانية. لا تُستورد ذاكرات Orca على مستوى الجهاز كاستخدام إضافي.
- WorkBuddy: يقرأ `~/.workbuddy/workbuddy.db` الخاص به بمزود `workbuddy` وأيقونة WorkBuddy وروابط `workbuddy://chat/<id>`، ولا يفحص مخزن WorkBuddy AI.
- WorkBuddy AI: يقرأ الحالة والعناوين والنموذج والأوقات من `~/.workbuddy-ai/workbuddy.db` مستقلًا عن `~/.workbuddy/workbuddy.db`. يستبعد المنتهي والمحذوف والقديم؛ الأحدث من `updated_at` و`last_activity_at` يبقي الجلسات الطويلة ظاهرة. يستخدم `workbuddy-ai` وأيقونته وروابط `workbuddy-ai://chat/<id>`. يكتشف الجلسات فقط: `session_usage.used` إشغال سياق، والأرصدة ليست استخدام USD/رموز، فلا يُستورد أي منهما كرموز مفوترة. الأرقام اليدوية عبر `zislactl usage`.
- جميع التكاملات للقراءة فقط وبقدر المتاح؛ المخزن الغائب أو غير المتوافق لا يعيد بيانات. لا تُقرأ أجسام خيوط Delta المكررة أو رسائل يومية Orca. استخدم `zislactl usage` إن لم يعرض الإصدار استخدامًا رقميًا مسجلًا.

## صيغة الخيارات

- اكتب `--key value` أو `--key=value`. لا يتكرر الخيار في أمر واحد؛ التكرار خطأ استخدام برمز 64.
- قد تبدأ القيمة بـ`--` كما في `--detail --verbose`. الاستثناء علم الأمر نفسه: `--failed` لـ`finish` و`--queued` لـ`update` لا يؤخذان كقيمة؛ لذا متغير فارغ بلا اقتباس في `--detail $DETAIL --failed` يظل يعلّم الفشل. مرر القيمة الحرفية بـ`--detail=--failed`.
- `--failed` و`--queued` أعلام. وحدهما true؛ `--failed=false` أو `--failed false` ونظيراهما queued يعطلانها. غير ذلك خطأ استخدام.

## `update`

ينشئ أو يستبدل مهمة بنفس `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- غياب `--progress` يظهر تقدمًا غير محدد.
- `--pid` اختياري ويستخدم عند معرفة عملية المهمة فقط.
- `--status` يبلغ العمل أو الانتظار بالطابور أو إجراء المستخدم أو خطأ أثناء العمل صراحة.
- `--queued` بديل `--status queued`؛ دون حالة صريحة تكون المهمة قيد العمل. `--status` يتقدم على `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

الناجحة 100%؛ الفاشلة تبقي تقدمها الأخير.

## `remove`

```text
zislactl remove --id <id>
```

يخرج 65 إذا لم توجد المهمة.

## `clear`

```text
zislactl clear
```

يمسح المهام ويبقي الاستخدام والإشعارات.

## `list`

```text
zislactl list
```

يطبع الحالة والمزود والعنوان والنسبة سطرًا لكل مهمة.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

يغذي مخطط 12 ساعة وخريطة 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

يظهر الإشعار من الجانب المختار ويتوقف الإخفاء الآلي عند المرور عليه.

## `message`

يرسل رسالة إلى جانبي الجزيرة: الشعار والمرسل يسارًا والنص المتحرك يمينًا.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

مثال:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app` و`--sender` و`--content` مطلوبة؛ `--app-bundle-id` اختياري لحل أيقونة التطبيق المثبت.
- تُدمج الأسطر والفراغات الزائدة ويُختصر النص لنحو 48 حرفًا مع علامة حذف.
- تحفظ معاملة SQLite واحدة سجلي `IslandNotice` دون تغيير `notify`.

## رموز الخروج

| الرمز | المعنى |
| --- | --- |
| `0` | نجاح |
| `64` | معامل أو أمر فرعي غير صالح |
| `65` | خطأ بيانات أو مهمة غائبة أو قاعدة تالفة |
| `70` | خطأ ملفات أو خطأ تشغيل آخر |
