# المساهمة في zisla

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **العربية** | [اللغات الأخرى](../README.md)

شكرًا لمساهمتك في zisla.

## المسائل

شكرًا لفتح مسألة. ابحث أولًا في Issues وDiscussions لمنع تكرار التقارير.

- بلاغ الخلل بعنوان `[Bug] Short problem description` مثل `[Bug] Voice input is not written to the current text field`. اذكر نسخة zisla وmacOS والجهاز وطريقة التثبيت وخطوات التكرار والمتوقع والفعلي.
- طلب الميزة بعنوان `[Feature] Short request description` مثل `[Feature] Support custom voice-organization prompts`. صف المشكلة والحل والبدائل المدروسة.
- اختر **Area** واحدًا إلزاميًا يحدد `area:*`: `Feature Development` أو `Bug Fix` أو `CI & Build` أو `Documentation` أو `Community & Discussion`. النموذج الصيني المبسط يقدم الخيارات والوسوم نفسها.
- أزل الرموز السرية والحسابات والمسارات المحلية وسائر الحساس من السجلات واللقطات والتسجيلات.
- أبلغ الثغرات سرًا عبر [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) لا مسألة عامة.
- تضيف الأتمتة `bug` أو `enhancement` مع `area:*` المطابق وتبقي الباقي. عدم اتباع بادئة العنوان أو الحقل المطلوب يضيف `needs-more-info` وتعليقًا واحدًا للنواقص؛ تعديل المسألة يحدثه.

## التطوير

تنفيذ macOS في `mac/` ويتطلب macOS 14+ وSwift 6 / Xcode 16+.

```bash
cd mac
swift test
```

أزل ثنائيات الاختبار والبناء والتغليف قبل الإيداع.

قبل كل إيداع أو amend نفّذ `make format` من الجذر باستخدام SwiftFormat 0.64.7 المطابق لـCI. راجع الفرق وأبقِ التنسيق اللازم للمهمة فقط.

## الفروع والإيداعات

- أنشئ من أحدث `main` ببادئة نوع PR: `feat/` أو `feature/`، `fix/`، `docs/`، `style/`، `refactor/`، `perf/`، `test/`، `chore/`، `build/`، `ci/`، `revert/`؛ مثل `fix/download-timeout` أو `ci/skip-directive-timing`.
- استخدم [Conventional Commits](https://www.conventionalcommits.org/) بالإنجليزية مثل `type(scope): description` أو `fix(ui): resolve layout issue in notch area`.
- ركز فرعًا وPR على هدف واضح واحد دون تنسيق فقط أو إعادة هيكلة غير مرتبطة.
- `publish-v*` لصيانة الإصدار؛ سائر المساهمات إلى `main`.

## طلب السحب

شكرًا لفتح PR. تحقق من المتطلبات أثناء انتظار المراجعة.

- **عنوان PR** بصيغة Conventional Commit إنجليزية مثل:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  الأنواع المسموحة `feat` و`fix` و`docs` و`style` و`refactor` و`perf` و`test` و`chore` و`build` و`ci` و`revert`.

- **متن PR** بالإنجليزية وبأقسام `Summary` و`GitHub Project` و`PR Type` و`Validation` و`Risk and Rollback` و`Related Issue` و`AI Attribution` في `.github/PULL_REQUEST_TEMPLATE.md`.
  - يحتفظ `GitHub Project` بـ`- Project: zisla Development`؛ تقرؤه `Project Automation` لوضع الطلب باللوحة المشتركة.
  - `Start date` و`Target date` مطلوبان مرة واحدة لكل منهما بتواريخ تقويم حقيقية `YYYY-MM-DD`؛ الهدف لا يسبق البداية. الغائب والفارغ والمعلق والمكرر وغير الصالح يفشل `PR Quality`. `Submitted date` تاريخ الإنشاء UTC+08:00 تلقائي و`End date` عند الدمج، لا إدخال يدوي.
  - `PR Type` يعلن `- Type:` واحدًا يطابق العنوان. العنوان قياسي؛ المتن يقبل أسماء الوسوم والبدائل: `fix` و`bug` و`bug fix` و`bugfix` و`hotfix` كلها `fix`. تحول `PR Automation` النوع لوسم مثل fix إلى bug.
  - تختار `Project Automation` `Status` حسب ربط الوسوم ونوع PR وتجعله `Done` عند الإغلاق/الدمج؛ لا تدخل الحالة يدويًا.
  - `Summary` يصف التغيير؛ `Risk and Rollback` يحتوي `Risk` و`Rollback` واحدًا غير فارغ لكل منهما.
  - كل `Validation` يبدأ بـ`- Status:` مستقل بقيمة `passed` أو `failed` أو `not run` بالضبط. passed/failed يحتاجان `Command` و`Result` خاصين غير فارغين؛ not run يحتاج `Reason` خاصًا. لا تكفي حقول غيره. اذكر الفشل بصدق بـfailed.
  - `Related Issue` إما يغلق مسألة بكلمة مثل `Closes #123` ويضيف `development` أو يكون `None` تمامًا.
  - `AI Attribution` يعلن `- Agent:` واحدًا غير فارغ. غير `None` يحتاج `- Co-authored-by: Name <email>` مطابقًا وفي trailer لإيداع واحد على الأقل ويضيف `ai-assisted`.

  مثال العنوان: `fix(ci): validate every PR metadata entry`

  مثال المتن (اكتب نتائجك الفعلية):

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

  مثال التاريخ: إنشاؤه 2026-10-05 ودمجه 2026-10-12 (UTC+08:00). الحقول الآلية في التعليق توضح قيم Project ولا تُدخل. تحدث الأتمتة GitHub Project وPR Timeline لا تعليقات المثال.

  | التاريخ | عند الإنشاء (2026-10-05) | بعد الدمج (2026-10-12) | المصدر |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | إدخال مطلوب |
  | `Target date` | 2026-10-12 | 2026-10-12 | إدخال مطلوب |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | إنشاء تلقائي |
  | `End date` | فارغ | 2026-10-12 | دمج تلقائي |

- يفحص `PR Quality` الصيغة ولا يُدمج الفاشل؛ ثم تضيف `PR Automation` الوسوم والتعيين.
- شغّل `cd mac && swift test` لتغييرات macOS واذكر تحقق الواجهة اليدوي نصيًا.
- يمكن أن يكون PR وملاحظات الإصدار نصًا فقط دون صور أو أغلفة.
- حدّث الوثائق الرسمية ومساعدة الموقع في التصحيح نفسه للميزات والسلوك والافتراضيات والبناء والإصدار؛ نص الموقع بكل 17 لغة باستخدام البنية والدليل المركزي القائمين.
- لا تودع `.build` أو `dist` أو تنزيلات أو سجلات أو رموزًا أو توقيعًا أو بيانات شخصية.
- `main` و`publish-v*` محميان ويُحدثان عبر PR مراجع ناجح فقط.

## تخطي CI

يمكن للمشرفين والمراجعين المطلوبين تخطي ما لا يؤثر فيه التغيير، كتصحيح وثائق فقط. ضع التوجيه منفردًا في تعليق PR:

| التوجيه | الأثر |
| --- | --- |
| `skip-all` | يتخطى كل تدفقات `.github/ci-skip.json`. |
| `skip-<workflow>` | يتخطى واحدًا بالاسم أو الملف أو البديل مثل `skip-swift` و`skip-web-ci` و`skip-Web CI`. |
| `unskip-all` | يمسح جميع توجيهات التخطي. |
| `unskip-<workflow>` | يعيد تدفقًا واحدًا. |

- نص حر بعدها مثل `skip-all: documentation only change`.
- الاسم المعروض في GitHub مع الفراغات صالح؛ `skip-CI Lint` و`skip-lint` متساويان. أطول تطابق يفوز والباقي ملاحظة.
- يقبل مالك المستودع وعضو المنظمة والمتعاون والمراجع المطلوب فقط؛ يتجاهل الروبوتات.
- يلغي `CI Skip` الجاري ويسجل المتخطى ناجحًا للشروط المطلوبة ويضيف `skip-ci` ويحدث تعليق ملخص واحدًا.
- يعاد تشغيل سجل التعليقات عند كل تعليق، فالأحدث يفوز.
- ينتهي التوجيه عند دفع إيداع أحدث لأنه يخص ما رآه صاحبه، وإلا يسمح دمج غير مبني. كل push يعيد `CI Skip` ويزيل الوسم ويعيد الفحوص ويذكر المنتهي. أعد التعليق لتخطي الجديد.
- يمكن إعادة القرار من **Actions -> CI Skip -> Run workflow** برقم PR دون تعليق.
- يربط `.github/ci-skip.json` التدفقات بأسماء الفحوص؛ الانحراف يفشل `CI Checks`.

## الفحوص بحسب المسار

تعمل فحوص المنصة فقط عند لمس الملفات التي تبنيها؛ الوثائق حسب مسارها:

| التدفق | مسارات التغيير المشغلة |
| --- | --- |
| `Swift Tests` | `mac/**`، `Makefile`، `.swiftformat`، `.github/**` |
| `Web CI` | `web/**`، `promo/**`، `docs/**`، `.github/**` |

- `paths` في `.github/ci-skip.json` يحدد النطاق؛ غير المحدد دائم. لذلك `CI Lint` و`PR Quality Gates` و`CodeQL` و`Dependency Review` لكل PR. نظافة المستودع وفحص skills في `CI Checks`؛ البدائل القديمة `hygiene` و`skills` غير مستخدمة.
- تغيير `.github/` يشغّل الجميع لاختبار CI على كل منصة.
- التخطي بشرط job لا مرشح `paths:` للتدفق، فيرجع نجاحًا بدل انتظار دائم.
- يطابق المعاد تسميته مساره القديم والجديد دون حساسية لحالة الأحرف.
