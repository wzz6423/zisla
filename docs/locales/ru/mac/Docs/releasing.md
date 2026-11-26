# Проектирование подписи и выпуска

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **Русский** | [Другие языки](../../../README.md)

Полный процесс выпуска, два канала обновлений и синхронизация ресурсов GitHub/Gitee поддерживаются в [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Здесь описаны только ограничения подписи, нотарификации и пакетов обновлений; при публикации следуйте этому skill.

Оба выбранных канала используют Sparkle для проверки подписанных ZIP и appcast перед заменой и перезапуском. За запуск приложение однократно определяет страну публичного выхода: `CN` проверяет Gitee первым и повторяет GitHub ровно один раз; остальные страны — GitHub первым, Gitee один раз; недоступное определение сохраняет Gitee первым. `package-release.sh` требует `SPARKLE_GENERATE_APPCAST` с путём к `generate_appcast` Sparkle 2.9.4 и создаёт `appcast-gitee.xml`/`appcast-github.xml` рядом с ZIP/DMG. Каждая лента подписывается отдельно и указывает ZIP этого запуска на собственном сайте. `build-package.sh` запускает скрипт по архитектурам, создавая три пары: универсальная публикуется как `appcast.xml` для старых приложений, одноархитектурные — `appcast-arm64.xml` и `appcast-x86_64.xml`. Одноархитектурная установка меняет URL Info.plist на ленту выполняемой архитектуры; транслируемый x86_64 запрашивает `arm64`, сохраняя свою архитектуру вместо универсальной сборки. Универсальная установка считает собственные архитектуры, сохраняет общее имя и остаётся универсальной. Gitee использует постоянные `update-release` (Release) и `preview` (Preview); GitHub — `latest` для Release и постоянный предварительный `preview` для Preview. Неинтерактивная публикация задаёт `SPARKLE_ED_KEY_FILE` для защищённого закрытого ключа EdDSA; без него используется учётная запись `zisla-update-ed25519` в login keychain. Закрытый ключ никогда не включается в репозиторий. Стабильные выпуски используют один самоподписанный сертификат для устойчивого designated requirement и сохранения разрешений macOS. Они не нотарифицированы. Пакеты Developer ID следует нотарифицировать; бесплатные ad-hoc previews также нельзя нотарифицировать.

## Предварительные условия

- Идентичность `zisla Release Signing` в отдельном keychain выпуска либо сертификат Developer ID Application
- Учётные данные нотарификации Apple при Developer ID
- Официальный помощник `yt-dlp`, полученный и проверенный через `Scripts/fetch-yt-dlp.sh`

## 1. Сборка подписанного приложения

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Стабильный выпуск по умолчанию использует `RELEASE_SIGNING_MODE=selfsigned`, читает `zisla Release Signing` из `~/Library/Keychains/zisla-release-signing.keychain-db` и разблокирует его через элемент `dev.wzz.zisla.release-signing-keychain` в login keychain. Это не удаляет предупреждение первого запуска Gatekeeper, но сохраняет требование на основе сертификата вместо cdhash конкретной сборки.

С сертификатом Developer ID явно выберите нотарифицируемый путь:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Результат:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Бесплатное распространение Preview

Без Apple Developer Program соберите предварительную версию с ad-hoc подписью:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Пакет не нотарифицирован и не содержит entitlement WeatherKit. После публикации подписанного appcast в постоянной ленте Preview Sparkle проверяет, скачивает, проверяет подпись, устанавливает и перезапускает обновления Preview. Первый запуск всё ещё может требовать **System Settings > Privacy & Security > Open Anyway**. Developer ID и нотарификация остаются рекомендуемым способом распространения без предупреждений безопасности.

## 2. Нотарификация

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

## 3. Публикация и проверка

Загрузите ZIP, DMG, контрольные суммы и appcast GitHub в один версионный tag GitHub с именами `appcast.xml` (универсальный), `appcast-arm64.xml` и `appcast-x86_64.xml`; соответствующие ресурсы и appcast Gitee — с теми же именами в тот же tag Gitee. Стабильный выпуск не отмечается предварительным. Скопируйте все три appcast Gitee в постоянный `update-release`; appcast Preview — в постоянный `preview` обоих сайтов. Канал проверяет Gitee→GitHub для `CN` и GitHub→Gitee для остальных стран.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Обычные выпуски сохраняют проверки локальных ресурсов, подписи, сумм, структуры пакета, appcast, ресурсов двух сайтов, постоянных лент и метаданных выпуска. Повторное скачивание пакетов, проверки установки и реальное принятие обновления Sparkle выполняются лишь по явному запросу.

При запросе приёмки обновления используйте старую версию для проверки новой. Подтвердите порядок выбранной ленты Gitee и одного повтора GitHub для автоматических/ручных проверок публичного выхода `CN`; остальные выходы — GitHub и один повтор Gitee. Проверьте установку и перезапуск ZIP выполняемой архитектуры Sparkle, сохраняя одну архитектуру в одноархитектурной установке. Проверьте Release→Preview, Preview→Release и обновления внутри канала. Незапрошенные проверки обозначаются `Not verified` и не являются условием завершения выпуска.

## 4. Синхронизация cask Homebrew

Стабильный выпуск заканчивается Homebrew. Preview прекращается перед этим шагом: tap содержит только стабильные версии, поэтому `brew upgrade` не переводит пользователя на предварительный выпуск.

После публикации ресурсов выполните из корня:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Скрипт переписывает `version` и обе `sha256` в `Casks/zisla.rb`, читая суммы из `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` и соответствующего `x86_64`-файла при их наличии, иначе из опубликованных ресурсов GitHub. Cask определяет `#{arch}` для машины, поэтому Apple Silicon/Intel скачивают свою архитектуру; проверка отвергает одинаковую сумму двух архитектур. Cask, не прошедший `homebrew-cask.rb verify`, не записывается; затем файл зеркалируется в `wzz6423/homebrew-tap`. Без `PUBLISH_TAP` пробный запуск меняет только cask репозитория.

Cask содержит `auto_updates true`, поскольку Sparkle управляет обновлениями: `brew upgrade` заменяет приложение лишь когда установленная версия действительно старее tap, что Homebrew 5.1.6+ определяет чтением версии внутри приложения. `brew upgrade --cask zisla` и `--greedy` используют записи установки Homebrew, поэтому могут отменить обновление Sparkle, вернув версию tap. Коммитьте переписанный cask вместе с обновлением `latestRelease` сайта: несовпадение версий вызывает ошибку CI. Проверка из корня:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Скачивание, установка, обновление и `livecheck` Homebrew выполняются только по явному запросу. Пример приёмки установки:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Незапрошенные проверки Homebrew записываются как `Not verified` и не являются условием завершения выпуска.
