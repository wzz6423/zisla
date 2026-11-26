# 서명, 공증과 릴리스

**한국어** | [English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | [다른 언어](../../../README.md)

전체 릴리스 절차, 두 업데이트 채널과 GitHub·Gitee 자산 동기화는 [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md)에서 관리합니다. 이 페이지는 서명, 공증과 업데이트 패키지의 설계 제약만 설명합니다. 릴리스를 게시할 때는 해당 스킬을 따릅니다.

모든 업데이트 패키지는 Sparkle을 사용하며 ZIP은 EdDSA로 서명합니다. 선택한 채널은 실행마다 공개 IP의 국가 코드를 한 번 확인합니다. `CN`은 Gitee를 먼저, 다른 국가는 GitHub를 먼저 사용하며 국가 조회가 불가능하면 Gitee를 먼저 유지합니다. `package-release.sh`는 `SPARKLE_GENERATE_APPCAST`가 Sparkle 2.9.4의 `generate_appcast`를 가리켜야 하며 ZIP·DMG 옆에 `appcast-gitee.xml`과 `appcast-github.xml`을 만듭니다. 각 appcast는 별도로 서명하고 같은 실행에서 생성된 ZIP을 자기 사이트에서 참조해야 합니다.

`build-package.sh`는 아키텍처마다 한 번 실행해 세 쌍을 만듭니다. Universal 쌍은 `appcast.xml`로 업로드해 이전 버전의 앱도 계속 사용하게 합니다. 단일 아키텍처 쌍은 `appcast-arm64.xml`과 `appcast-x86_64.xml`로 올립니다. 단일 설치는 Info.plist의 feed URL을 실행 중인 slice에 맞게 바꾸며 변환 실행된 x86_64는 `arm64`를 요청합니다. 따라서 Universal로 커지지 않고 해당 아키텍처를 유지합니다. Universal 설치는 자체 slice를 세어 공통 이름을 사용합니다.

Gitee는 Release의 `update-release`와 Preview의 `preview` 영구 feed를 사용합니다. GitHub는 Release의 `latest`와 영구 prerelease `preview`를 사용합니다. 비대화형 게시에는 비공개 EdDSA 키 파일을 `SPARKLE_ED_KEY_FILE`로 지정합니다. 지정하지 않으면 로그인 키체인의 `zisla-update-ed25519` 계정을 사용합니다. 개인키는 저장소에 넣으면 안 됩니다. 안정 릴리스는 하나의 자체 서명 인증서를 기본 사용해 지정 요구사항과 macOS 권한을 업데이트 후 유지하지만 공증되지는 않습니다. Developer ID 패키지는 공증해야 하며 무료 ad-hoc Preview도 공증할 수 없습니다.

## 준비 조건

- 전용 릴리스 키체인의 `zisla Release Signing` 또는 Developer ID Application 인증서
- Developer ID를 쓰는 경우 Apple 공증 자격 증명
- `Scripts/fetch-yt-dlp.sh`로 다운로드하고 검증한 공식 `yt-dlp` 도우미

## 1. 서명한 앱 빌드

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

안정 릴리스는 기본 `RELEASE_SIGNING_MODE=selfsigned`를 사용합니다. `~/Library/Keychains/zisla-release-signing.keychain-db`에서 `zisla Release Signing`을 읽고 로그인 키체인의 `dev.wzz.zisla.release-signing-keychain` 항목으로 잠금을 풉니다. 첫 실행의 Gatekeeper 경고는 없어지지 않지만 빌드마다 다른 cdhash 대신 인증서 기반 지정 요구사항을 유지합니다.

Developer ID 인증서가 있으면 공증 가능한 경로를 명시적으로 선택합니다:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

출력:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### 무료 Preview 배포

Apple Developer Program 없이 ad-hoc 서명 Preview를 만들 수 있습니다:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

이 패키지는 공증되지 않고 WeatherKit 권한을 포함하지 않습니다. 서명한 appcast를 영구 Preview feed에 게시하면 Sparkle이 확인, 다운로드, 검증, 설치와 재시작을 수행합니다. 첫 실행에는 **시스템 설정 > 개인정보 보호 및 보안 > 그래도 열기**가 필요할 수 있습니다. 보안 경고 없는 배포에는 Developer ID와 공증을 권장합니다.

## 2. 공증

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

## 3. 게시와 검증

ZIP, DMG, 체크섬과 GitHub appcast를 같은 GitHub 버전 태그에 업로드합니다. 이름은 Universal의 `appcast.xml`, `appcast-arm64.xml`, `appcast-x86_64.xml`입니다. 같은 자산과 Gitee appcast를 동일한 Gitee 태그에 같은 이름으로 올립니다. 안정 릴리스는 prerelease로 표시하지 않습니다. Gitee appcast 세 개를 영구 `update-release`에 복사하고 Preview appcast는 두 사이트의 영구 `preview`에 복사합니다. 채널은 `CN`에서 Gitee→GitHub, 다른 국가에서 GitHub→Gitee로 확인합니다.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

일반 릴리스에는 로컬 결과물, 서명, 체크섬, 패키지 배치와 appcast 검사, 두 사이트 자산·영구 feed 및 메타데이터 검증을 유지합니다. 패키지 재다운로드, 설치와 실제 Sparkle 업그레이드 검사는 명시적으로 요청받은 경우에만 수행합니다.

요청한 업데이트 검증은 이전 앱 버전에서 시작합니다. 공개 IP가 `CN`이면 자동·수동 확인이 선택한 Gitee feed를 먼저 사용하고 GitHub를 한 번 재시도하는지 확인합니다. 다른 국가는 반대입니다. Sparkle이 현재 아키텍처의 ZIP을 설치·재시작하며 단일 아키텍처가 그대로 남는지 검사합니다. Release→Preview, Preview→Release와 같은 채널의 업데이트도 확인합니다. 요청하지 않은 검사는 `Not verified`로 기록하며 릴리스 완료의 필수 조건이 아닙니다.

## 4. Homebrew cask 동기화

안정 릴리스는 Homebrew 동기화로 마무리합니다. Preview는 이 단계 전에 멈춥니다. tap은 안정 버전만 제공하므로 `brew upgrade`가 사용자를 prerelease로 이동시키지 않습니다.

릴리스 자산 게시 후 저장소 루트에서 실행합니다:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

스크립트는 `Casks/zisla.rb`의 `version`과 두 `sha256`을 갱신합니다. `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256`과 x86_64 파일이 있으면 그 값을 읽고, 없으면 GitHub 자산을 사용합니다. cask는 기기별 `#{arch}`를 결정해 Apple Silicon·Intel이 자기 slice만 받게 합니다. 두 아키텍처에 같은 digest를 쓰면 검증이 실패합니다. `homebrew-cask.rb verify` 실패 시 쓰지 않으며 통과하면 `wzz6423/homebrew-tap`으로 복사합니다. `PUBLISH_TAP`을 빼면 저장소 cask만 바꾸는 시험 실행입니다.

Sparkle이 업데이트를 담당하므로 cask에 `auto_updates true`를 넣습니다. Homebrew 5.1.6 이상은 앱 내부 버전을 읽어 `brew upgrade`가 tap보다 오래된 앱만 교체하게 합니다. 반면 `brew upgrade --cask zisla`와 `--greedy`는 설치 기록을 기준으로 tap 버전을 복원해 Sparkle 업데이트를 되돌릴 수 있습니다. cask 변경과 사이트의 `latestRelease` 변경을 함께 커밋합니다. 두 버전이 다르면 CI가 실패합니다. 루트에서 검증합니다:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew 다운로드, 설치, 업그레이드와 `livecheck`는 명시적 요청이 있을 때만 수행합니다. 설치 검증 예제:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

요청하지 않은 Homebrew 검사는 `Not verified`이며 릴리스 완료의 필수 조건이 아닙니다.
