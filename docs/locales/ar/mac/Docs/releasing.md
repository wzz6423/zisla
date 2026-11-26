# تصميم التوقيع والإصدار

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **العربية** | [اللغات الأخرى](../../../README.md)

تُدار عملية الإصدار كاملة وقناتا التحديث ومزامنة GitHub/Gitee في [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). توثق هذه الصفحة قيود التوقيع والتوثيق وحزم التحديث فقط؛ اتبع المهارة عند النشر.

تستخدم القناتان Sparkle للتحقق من ZIP وappcast الموقعين قبل الاستبدال وإعادة التشغيل. يحدد التطبيق بلد الخروج العام مرة: `CN` يبدأ Gitee ثم يحاول GitHub مرة واحدة بالضبط؛ الآخر يبدأ GitHub ثم Gitee مرة؛ الغياب يبقي Gitee أولًا. يتطلب `package-release.sh` أن يشير `SPARKLE_GENERATE_APPCAST` إلى `generate_appcast` من Sparkle 2.9.4 ويكتب `appcast-gitee.xml` و`appcast-github.xml` بجوار ZIP وDMG. توقع كل خلاصة مستقلة وتشير إلى ZIP التشغيل نفسه على موقعها. يشغل `build-package.sh` السكربت لكل معمارية لتنتج ثلاثة أزواج: الشامل باسم `appcast.xml` الذي تطلبه النسخ القديمة، والأحاديان `appcast-arm64.xml` و`appcast-x86_64.xml`. تعدل الأحادية URL في Info.plist حسب الشريحة العاملة؛ x86_64 المترجمة تطلب `arm64`، فلا تتحول إلى شامل. تعد الشاملة شرائحها وتبقى على الاسم المشترك. لدى Gitee خلاصتا `update-release` و`preview` الدائمتان، ولدى GitHub `latest` للمستقر و`preview` الدائم التجريبي. للنشر غير التفاعلي اضبط `SPARKLE_ED_KEY_FILE` لملف EdDSA الخاص المحمي، أو اتركه لحساب `zisla-update-ed25519` في login keychain. لا يدخل المفتاح الخاص المستودع مطلقًا. المستقر يستخدم شهادة ذاتية واحدة لإبقاء designated requirement ثابتًا وحفظ أذونات macOS، لكنه غير موثق. حزم Developer ID ينبغي توثيقها؛ معاينة ad-hoc المجانية لا يمكن توثيقها.

## المتطلبات

- هوية `zisla Release Signing` في سلسلة مفاتيح الإصدار المخصصة أو شهادة Developer ID Application
- بيانات توثيق Apple عند استخدام Developer ID
- مساعد `yt-dlp` الرسمي مجلوب ومتحقق عبر `Scripts/fetch-yt-dlp.sh`

## 1. بناء تطبيق موقع

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

للمستقر الافتراضي `RELEASE_SIGNING_MODE=selfsigned`، ويقرأ `zisla Release Signing` من `~/Library/Keychains/zisla-release-signing.keychain-db` ويفتحها بعنصر `dev.wzz.zisla.release-signing-keychain` في login keychain. لا يزيل إنذار Gatekeeper الأول لكنه يبقي متطلبًا مبنيًا على الشهادة لا cdhash لكل بناء.

مع Developer ID اختر مسار التوثيق صراحة:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

الخرج:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### توزيع المعاينة المجانية

دون Apple Developer Program ابنِ معاينة بتوقيع ad-hoc:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

الحزمة غير موثقة ولا تتضمن entitlement WeatherKit. بعد نشر appcast الموقع إلى Preview الدائمة يفحص Sparkle ويجلب ويتحقق ويثبت ويعيد التشغيل. قد يحتاج أول فتح **System Settings > Privacy & Security > Open Anyway**. Developer ID والتوثيق يظلان الطريق الموصى به بلا إنذارات أمن.

## 2. التوثيق

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

## 3. النشر والتحقق

ارفع ZIP وDMG والمجاميع وخلاصات GitHub إلى وسم نسخة واحد بأسماء `appcast.xml` للشامل و`appcast-arm64.xml` و`appcast-x86_64.xml`؛ ارفع المطابق وخلاصات Gitee بالأسماء نفسها إلى وسم Gitee نفسه. لا يُعلّم المستقر كتجريبي. انسخ خلاصات Gitee الثلاث إلى `update-release` الدائمة ومعاينات Preview إلى `preview` في الموقعين. تختار القناة Gitee ثم GitHub لـ`CN` والعكس للآخر.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

تحتفظ الإصدارات الروتينية بفحوص الأصول المحلية والتوقيع والمجاميع والتخطيط والخلاصات والموقعين والخلاصات الدائمة وبيانات الإصدار. إعادة تنزيل الحزم وفحص التثبيت وقبول ترقية Sparkle الفعلية فقط عند الطلب الصريح.

للقبول المطلوب استخدم نسخة أقدم لفحص الجديد. تأكد أن الفحص اليدوي والآلي لخروج `CN` يبدآن بخلاصة Gitee المختارة ويحاولان GitHub مرة، والعكس لبقية المخارج. تحقق أن Sparkle يثبت ويعيد تشغيل ZIP المعمارية العاملة ويبقي الأحادية أحادية. اختبر Release→Preview وPreview→Release والتحديث داخل القناة. غير المطلوب يسجل `Not verified` وليس شرط إكمال الإصدار.

## 4. مزامنة cask Homebrew

ينتهي المستقر عند Homebrew. المعاينة تتوقف قبل الخطوة: tap للمستقر فقط فلا ينقل `brew upgrade` إلى تجريبي.

من جذر المستودع بعد نشر الأصول:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

يعيد السكربت `version` و`sha256` كليهما في `Casks/zisla.rb`، يقرأ `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` ونظير `x86_64` محليًا إن وجدا وإلا من GitHub. يحدد cask `#{arch}` لكل جهاز فيجلب شريحته؛ يرفض التحقق إعادة المجموع نفسه للاثنين. لا يكتب cask فاشل `homebrew-cask.rb verify` ثم ينسخه إلى `wzz6423/homebrew-tap`. احذف `PUBLISH_TAP` لتجربة تحدث النسخة بالمستودع فقط.

يحمل `auto_updates true` لأن Sparkle يملك التحديث: يستبدل `brew upgrade` فقط إذا كانت الحزمة أقدم فعلًا، وفق قراءة Homebrew 5.1.6+ نسخة التطبيق. `brew upgrade --cask zisla` و`--greedy` يعتمدان سجلات Homebrew وقد يعيدان نسخة tap ويلغيان تحديث Sparkle. أودع cask مع رفع `latestRelease` للموقع؛ اختلاف النسختين يفشل CI. تحقق من الجذر:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

تنزيل Homebrew وتثبيته وترقيته و`livecheck` عند الطلب فقط. مثال قبول التثبيت:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

فحوص Homebrew غير المطلوبة تسجل `Not verified` وليست شروط إكمال الإصدار.
