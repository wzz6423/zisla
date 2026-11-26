# 署名とリリースの設計

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **日本語** | [他の言語](../../../README.md)

全リリース手順、二つの更新チャンネル、GitHub/Gitee 資産同期は [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md) が管理します。本書は署名、公証、更新パッケージの設計制約を説明します。公開するときは skill に従います。

両チャンネルの更新は EdDSA 署名済み ZIP を使用し、Sparkle で ZIP と appcast を検証してアプリを置き換え再起動します。出口の国コードを実行ごとに一度取得し、`CN` は Gitee の後に GitHub を一回、他は逆、取得不能は Gitee 優先です。`package-release.sh` は `SPARKLE_GENERATE_APPCAST` に Sparkle 2.9.4 の `generate_appcast` を要求し、ZIP/DMG と `appcast-gitee.xml`、`appcast-github.xml` を作ります。各 appcast は別々に署名し、その実行の自ホスト ZIP を参照します。

`build-package.sh` は各アーキテクチャで一度実行して三つの appcast の組を作ります。アーキテクチャ別更新より前のアプリが要求する Universal の組を `appcast.xml`、単一版を `appcast-arm64.xml`、`appcast-x86_64.xml` として公開します。単一版は Info.plist の feed を実行 slice に合わせ（変換中の x86_64 は arm64）、Universal に増大しません。Universal は slice 数を確認して共有名を保持します。Gitee の常設は Release `update-release`、Preview `preview`、GitHub は Release `latest`、Preview の常設 prerelease `preview` です。

非対話公開では `SPARKLE_ED_KEY_FILE` に保護された EdDSA 秘密鍵を指定するか、省略してログイン Keychain の `zisla-update-ed25519` を使います。秘密鍵はリポジトリーに含めません。安定版は同じ自己署名証明書で指定要件を保ち、更新後も権限を維持しますが、公証されません。Developer ID 版は公証すべきで、無料 ad-hoc Preview も公証できません。

## 前提

- 専用 Keychain の `zisla Release Signing` または Developer ID Application 証明書。
- Developer ID 用 Apple 公証認証情報。
- `Scripts/fetch-yt-dlp.sh` で取得・検証した公式 helper。

## 1. 署名済みアプリを作る

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

安定版の既定は `RELEASE_SIGNING_MODE=selfsigned`。`~/Library/Keychains/zisla-release-signing.keychain-db` の証明書を使い、ログイン Keychain の `dev.wzz.zisla.release-signing-keychain` で解除します。初回 Gatekeeper 警告は残りますが、ビルド固有 cdhash の代わりに証明書の指定要件を維持します。

Developer ID の公証可能な経路：

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

出力：

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### 無料 Preview の配布

Developer Program がない場合は ad-hoc で作ります：

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

未公証で WeatherKit entitlement はありません。署名 feed 公開後は Sparkle が Preview を確認、取得、検証、導入、再起動します。初回は **システム設定 > プライバシーとセキュリティ > このまま開く** が必要な場合があります。警告のない配布には Developer ID と公証を推奨します。

## 2. 公証する

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

## 3. 公開して検証する

同じ版 tag へ ZIP、DMG、ハッシュと GitHub appcast を上記三名で置き、Gitee にも同じ資産と自ホスト feed を置きます。安定版は prerelease にしません。Gitee Release 三 feed は常設 `update-release`、両サイト Preview は常設 `preview` にコピーします。国に応じた確認順を保ちます。

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

通常リリースではローカル成果物、署名、ハッシュ、パッケージと feed、二サイト資産、常設 feed とメタデータを確認します。再ダウンロード、導入、実際の Sparkle 更新確認は明示された場合だけ行います。

実更新の確認では古いアプリから、新版へ自動・手動、CN とその他、Release→Preview と Preview→Release、同チャンネルを試します。Sparkle が実行アーキテクチャの ZIP を導入し再起動、単一版が単一版のままか確認します。依頼されていない検証は `Not verified` とし、完了条件に加えません。

## 4. Homebrew cask の同期

安定版だけが対象で、Preview はこの手順の前で終了します。tap は安定版のみなので通常更新で prerelease に移行しません。資産公開後、リポジトリールートで：

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

`Casks/zisla.rb` の `version` と二つの `sha256` を更新します。`$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` と対応する x86_64 ファイルがあれば読み、なければ GitHub 公開資産を使います。`#{arch}` で機器別 slice を選び、同じ hash を再利用する cask は拒否します。`homebrew-cask.rb verify` を通過した後、`wzz6423/homebrew-tap` に反映します。`PUBLISH_TAP` なしはリポジトリー内だけのドライランです。

`auto_updates true` により Sparkle が主で、Homebrew 5.1.6+ の `brew upgrade` は bundle が tap より古いときだけ置き換えます。`brew upgrade --cask zisla` や `--greedy` は導入記録を使い、Sparkle 更新を戻す場合があります。cask とサイトの `latestRelease` を同時 commit し、版の不一致は CI が失敗します。

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew のダウンロード、導入、更新、`livecheck` は明示した場合だけです。以下は導入確認の例です：

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

未依頼の Homebrew 実機確認も `Not verified` とし、公開完了の条件にしません。
