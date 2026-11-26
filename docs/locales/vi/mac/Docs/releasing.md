# Thiết kế ký và phát hành

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../../../README.md)

Toàn bộ quy trình phát hành, hai kênh cập nhật và đồng bộ tài sản GitHub/Gitee được quản lý trong [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Trang này chỉ mô tả giới hạn thiết kế chữ ký, công chứng và gói cập nhật; khi phát hành hãy theo skill đó.

Cả hai kênh chọn dùng Sparkle xác minh ZIP và appcast đã ký trước thay ứng dụng và mở lại. Mỗi lần chạy tra quốc gia đầu ra công khai một lần: `CN` Gitee trước rồi GitHub đúng một lần; nơi khác GitHub trước rồi Gitee một lần, lỗi tra giữ Gitee trước. `package-release.sh` cần `SPARKLE_GENERATE_APPCAST` trỏ `generate_appcast` Sparkle 2.9.4 và tạo `appcast-gitee.xml`/`appcast-github.xml` cạnh ZIP/DMG. Mỗi appcast ký riêng, trỏ ZIP của lần chạy đó trên chính trang của nó. `build-package.sh` chạy theo kiến trúc nên có ba cặp: universal là `appcast.xml` cho ứng dụng trước cập nhật theo kiến trúc, đơn là `appcast-arm64.xml`/`appcast-x86_64.xml`. Bản đơn sửa URL feed Info.plist theo slice chạy, x86_64 phiên dịch yêu cầu `arm64`, giữ kiến trúc không thành universal. Universal đếm slice, giữ tên chung và vẫn universal. Gitee giữ `update-release` cho Release và `preview` cho Preview lâu dài; GitHub `latest` Release và tiền phát hành `preview` lâu dài. Không tương tác đặt `SPARKLE_ED_KEY_FILE` trỏ khóa EdDSA riêng bảo vệ, hoặc để trống dùng `zisla-update-ed25519` ở login keychain. Không đưa khóa riêng vào kho. Ổn định mặc định một chứng chỉ tự ký để designated requirement ổn định và giữ quyền macOS; vẫn chưa công chứng. Developer ID nên công chứng; ad-hoc Preview miễn phí cũng không công chứng được.

## Điều kiện

- `zisla Release Signing` trong keychain phát hành riêng hoặc chứng chỉ Developer ID Application
- Thông tin công chứng Apple nếu Developer ID
- Helper `yt-dlp` chính thức đã tải/xác minh qua `Scripts/fetch-yt-dlp.sh`

## 1. Xây ứng dụng đã ký

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Ổn định mặc định `RELEASE_SIGNING_MODE=selfsigned`, đọc `zisla Release Signing` từ `~/Library/Keychains/zisla-release-signing.keychain-db`, mở khóa qua mục `dev.wzz.zisla.release-signing-keychain` trong login keychain. Không bỏ cảnh báo Gatekeeper lần đầu nhưng requirement dựa chứng chỉ thay cdhash từng build.

Developer ID chọn đường công chứng rõ:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Đầu ra:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Phát Preview miễn phí

Không Apple Developer Program, xây ad-hoc Preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Gói chưa công chứng và không có entitlement WeatherKit. Sau xuất appcast ký lên feed Preview lâu dài, Sparkle kiểm tra/tải/xác minh/cài/mở cập nhật. Lần đầu có thể **System Settings > Privacy & Security > Open Anyway**. Developer ID và công chứng vẫn khuyến nghị để phân phối không cảnh báo an toàn.

## 2. Công chứng

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

## 3. Phát hành và xác minh

Tải ZIP/DMG/checksum/appcast GitHub lên cùng tag phiên bản, tên `appcast.xml` universal, `appcast-arm64.xml`, `appcast-x86_64.xml`. Tải tài sản phù hợp và Gitee appcast ba tên đó lên cùng tag Gitee. Không đánh dấu ổn định là prerelease. Sao ba Gitee appcast sang `update-release` lâu dài; Preview sang `preview` lâu dài hai trang. Kênh `CN` Gitee rồi GitHub, quốc gia khác ngược.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Phát hành thường giữ kiểm tra tài sản cục bộ, ký, checksum, cấu trúc gói, appcast, tài sản hai trang, feed lâu dài và metadata. Tải lại gói, kiểm tra cài và thử nâng Sparkle thật chỉ khi yêu cầu rõ.

Nếu yêu cầu nghiệm thu cập nhật, dùng phiên bản cũ kiểm tra mới. Xác nhận tự động/thủ công từ đầu ra `CN` dùng Gitee chọn trước rồi GitHub một lần, nơi khác đảo lại. Xác minh Sparkle cài/mở ZIP đúng kiến trúc chạy, bản đơn vẫn đơn. Kiểm Release→Preview, Preview→Release và cùng kênh. Kiểm tra không yêu cầu ghi `Not verified`, không là điều kiện hoàn tất phát hành.

## 4. Đồng bộ Homebrew cask

Ổn định kết thúc ở Homebrew. Preview dừng trước: tap chỉ ổn định nên `brew upgrade` không chuyển người dùng sang prerelease.

Từ gốc sau khi tài sản công bố:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Tập lệnh viết `version` và hai `sha256` trong `Casks/zisla.rb`, lấy digest `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` cùng `x86_64` tại máy nếu có, không thì tài sản GitHub đã phát. Cask giải `#{arch}` mỗi máy, Apple Silicon/Intel chỉ tải slice mình; kiểm tra từ chối chung một digest. Không ghi nếu `homebrew-cask.rb verify` thất bại, sau đó mirror sang `wzz6423/homebrew-tap`. Bỏ `PUBLISH_TAP` để dry run chỉ cask trong kho.

`auto_updates true` vì Sparkle quản lý cập nhật: `brew upgrade` chỉ thay bundle thật cũ hơn tap, Homebrew 5.1.6+ đọc version trong ứng dụng. `brew upgrade --cask zisla`/`--greedy` dùng hồ sơ Homebrew, có thể hoàn tác Sparkle bằng bản tap. Commit cask cùng `latestRelease` website, khác phiên bản gây CI lỗi. Xác minh từ gốc:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Tải/cài/nâng/`livecheck` Homebrew chỉ nếu yêu cầu. Ví dụ nghiệm thu cài:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Kiểm Homebrew không yêu cầu ghi `Not verified`, không phải điều kiện kết thúc phát hành.
