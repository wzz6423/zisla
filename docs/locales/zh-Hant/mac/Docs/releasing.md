# 簽名與發佈設計

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **繁體中文** | [其他語言](../../../README.md)

項目的完整發佈流程、雙更新通道和 GitHub/Gitee 的資產同步由倉庫根目錄的 [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md) 統一維護。本頁只說明簽名、公證和更新包的設計約束；發佈時以該技能為準。

當前選擇的兩個更新通道都使用 Sparkle：先驗簽 ZIP 和 appcast，再替換並重啓應用。應用會在本次運行中解析一次公網出口國家碼：`CN` 先檢查 Gitee，再自動重試一次 GitHub；其他國家碼先檢查 GitHub，再回退一次 Gitee；無法獲取國家碼時保留 Gitee 優先。`package-release.sh` 要求通過 `SPARKLE_GENERATE_APPCAST` 指向 Sparkle 2.9.4 的 `generate_appcast`，並會在 ZIP、DMG 同目錄寫出 `appcast-gitee.xml` 和 `appcast-github.xml`。兩份 appcast 都必須獨立簽名，且只能指向各自站點、本次構建那一套架構的 ZIP。`build-package.sh` 按架構各跑一次腳本，因此一次發佈有三對：Universal 那對上傳為 `appcast.xml`，也就是按架構更新之前發佈的版本仍在請求的名字；單架構那兩對上傳為 `appcast-arm64.xml` 和 `appcast-x86_64.xml`。單架構安裝會把 Info.plist 里的 feed 地址改寫為運行 slice 對應的 appcast（Rosetta 下的 x86_64 slice 按 `arm64` 請求），因此始終更新到同一架構，不會在一次應用內更新後變成 Universal；Universal 安裝按自身 slice 數判定，保留共享名字，更新後仍是 Universal。上傳目標：Gitee 的 Release/Preview 永久 feed 分別為 `update-release` 和 `preview`；GitHub 的 Release 使用 `latest`，Preview 使用永久 prerelease `preview`。非交互發佈時設定 `SPARKLE_ED_KEY_FILE` 指向私下保管的 EdDSA 私鑰檔案；不設定則讀取登錄鑰匙串的 `zisla-update-ed25519` 賬戶。私鑰絕不能進入倉庫。正式版預設使用同一張自簽名證書，使指定要求穩定並在更新後保留 macOS 權限授予，但仍未公證。Developer ID 發佈包應完成公證；免費 ad-hoc Preview 同樣不能公證。

## 前提

- 獨立發佈鑰匙串中的 `zisla Release Signing` 身份，或 Developer ID Application 證書
- 使用 Developer ID 時所需的 Apple 公證憑據
- 官方 `yt-dlp` Helper 已通過 `Scripts/fetch-yt-dlp.sh` 獲取並校驗

## 1. 構建簽名應用

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

正式版預設使用 `RELEASE_SIGNING_MODE=selfsigned`，從 `~/Library/Keychains/zisla-release-signing.keychain-db` 讀取 `zisla Release Signing`，並通過登錄鑰匙串中的 `dev.wzz.zisla.release-signing-keychain` 項解鎖。這不會消除 Gatekeeper 的首次打開提示，但指定要求會基於證書，而不是每次構建都變化的 cdhash。

使用 Developer ID 證書時，必須顯式選擇可公證路徑：

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

輸出：

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### 免費預覽分發

不使用 Apple Developer Program 時，可以用 ad-hoc 簽名構建預覽包：

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

該包不經過公證，且不包含 WeatherKit 權限。將已簽名 appcast 發佈到永久 Preview feed 後，應用會通過 Sparkle 檢查、下載、驗簽、安裝並重啓 Preview 更新。首次打開仍需在 **系統設定 > 隱私與安全性** 中選擇 **仍要打開**。
Developer ID 和公證仍是面向普通用戶無攔截分發的推薦方式。

## 2. 公證

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

## 3. 發佈與驗證

將三套 ZIP、DMG、校驗檔案和三份 GitHub appcast 上傳到 GitHub 的同一版本 tag Release，分別命名為 `appcast.xml`（Universal）、`appcast-arm64.xml` 和 `appcast-x86_64.xml`；將匹配資產和三份 Gitee appcast 以同樣的三個名字上傳到 Gitee 的同一 tag。正式版不能標記為 prerelease。Gitee 的三份正式 appcast 還必須複製到永久 `update-release`；Preview 的 appcast 必須複製到兩端永久 `preview`。客戶端按選擇的通道對 `CN` 使用 Gitee→GitHub，對其他國家碼使用 GitHub→Gitee。

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

每次發版保留本地產物、簽名、校驗和、包結構、appcast、雙端資產清單、永久 feed 和發佈元資料校驗。額外下載發佈包、安裝驗證和 Sparkle 真實升級驗收僅在用戶明確要求時執行。

用戶要求更新驗收時，使用舊版本檢查新 Release，確認中國大陸公網出口上的自動檢查和手動檢查都先讀取所選 Gitee feed、再回退一次 GitHub；其他公網出口先讀取 GitHub、再回退一次 Gitee。驗證 Sparkle 能驗簽、安裝並重啓運行架構對應的 ZIP，單架構安裝更新後仍只含本機架構。還要驗證 Release→Preview、Preview→Release 和同通道更新。未要求的檢查記錄為 `Not verified`（未驗證），不作為發版完成的前置條件。

## 4. 同步 Homebrew cask

正式版的最後一站是 Homebrew。Preview 版本到上一步為止：tap 只提供正式版，`brew upgrade` 因此不會把用戶帶到預發佈版本。

發佈資產上傳完成後，在倉庫根目錄執行：

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

腳本會改寫 `Casks/zisla.rb` 中的 `version` 與兩個 `sha256`：`$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` 及其 `x86_64` 同名檔案存在時讀本地摘要，否則從已發佈的 GitHub 資產拉取。cask 按 `#{arch}` 逐機解析下載地址，Apple Silicon 與 Intel 各自只取對應架構的包；兩個架構復用同一摘要會被校驗拒絕。未通過 `homebrew-cask.rb verify` 的 cask 不會被寫回，通過後再鏡像到 `wzz6423/homebrew-tap`。不帶 `PUBLISH_TAP` 即為試運行，只更新倉庫內的 cask。

cask 聲明 `auto_updates true`，因為更新鏈路歸 Sparkle 所有：這樣 `brew upgrade` 只在已裝的包確實舊於 tap 時才替換它，Homebrew 5.1.6 起靠讀取應用內的版本號來判斷。`brew upgrade --cask zisla` 與 `--greedy` 依據的是 Homebrew 自己的安裝記錄，會把 tap 的版本裝回去，可能撤銷一次 Sparkle 更新。改寫後的 cask 必須與官網 `latestRelease` 的版本一起提交——兩者版本不一致時 CI 會失敗。在倉庫根目錄核對 cask 與官網元資料：

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew 下載、安裝、升級與 `livecheck` 驗收僅在用戶明確要求時執行。安裝驗收示例：

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

未要求的 Homebrew 驗收記錄為 `Not verified`（未驗證），不作為發版完成的前置條件。
