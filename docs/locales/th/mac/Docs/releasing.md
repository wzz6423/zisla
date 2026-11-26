# การออกแบบการลงนามและเผยแพร่

[English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | **ไทย** | [ภาษาอื่น](../../../README.md)

ขั้นตอนเผยแพร่ทั้งหมด ช่องอัปเดตคู่ และซิงก์ไฟล์ GitHub/Gitee ดูแลโดย [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md) หน้านี้ระบุข้อจำกัดลายเซ็น notarization และแพ็กเกจอัปเดตเท่านั้น เผยแพร่ตาม skill นี้

ทั้งสองช่องใช้ Sparkle ตรวจ ZIP/appcast ลงนามก่อนแทนและเปิดแอปใหม่ ตรวจรหัสประเทศขาออกสาธารณะหนึ่งครั้งต่อการรัน `CN` เริ่ม Gitee และลอง GitHub อีกครั้งเดียว อื่นเริ่ม GitHub แล้ว Gitee ครั้งเดียว ไม่ทราบคง Gitee `package-release.sh` ต้อง `SPARKLE_GENERATE_APPCAST` ชี้ `generate_appcast` Sparkle 2.9.4 สร้าง `appcast-gitee.xml`/`appcast-github.xml` ข้าง ZIP/DMG แต่ละไฟล์ลงนามแยกและชี้ ZIP จากรอบนั้นบนเว็บไซต์ตน `build-package.sh` รันต่อสถาปัตยกรรม สามคู่คือ universal `appcast.xml` ให้รุ่นก่อนแยกอัปเดต และ `appcast-arm64.xml`/`appcast-x86_64.xml` สำหรับเดี่ยว การติดตั้งเดี่ยวแก้ feed URL ใน Info.plist ให้ slice ที่ทำงาน (x86_64 แปลขอ `arm64`) จึงไม่โตเป็น universal แบบ universal นับ slice และคงชื่อร่วม Gitee มี `update-release`/`preview` ถาวร GitHub `latest` Release และ prerelease `preview` ถาวร งานไม่โต้ตอบใช้ `SPARKLE_ED_KEY_FILE` ชี้ EdDSA private ที่เก็บปลอดภัย ไม่ตั้งอ่านบัญชี `zisla-update-ed25519` ใน login keychain ห้าม private key เข้าคลัง เสถียรใช้ self-signed เดียวคง designated requirement และ permissions macOS แต่ยังไม่ notarized Developer ID ควร notarize; ad-hoc Preview ฟรีทำไม่ได้

## สิ่งที่ต้องมี

- `zisla Release Signing` ใน keychain เผยแพร่เฉพาะ หรือ Developer ID Application certificate
- ข้อมูล notarization Apple หากใช้ Developer ID
- `yt-dlp` ทางการดึง/ตรวจผ่าน `Scripts/fetch-yt-dlp.sh`

## 1. สร้างแอปลงนาม

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

เสถียรเดิม `RELEASE_SIGNING_MODE=selfsigned` อ่าน `zisla Release Signing` จาก `~/Library/Keychains/zisla-release-signing.keychain-db` ปลดด้วย `dev.wzz.zisla.release-signing-keychain` ใน login keychain ไม่ลบคำเตือน Gatekeeper แรก แต่ designated requirement อิง certificate แทน cdhash เปลี่ยนทุก build

Developer ID เลือกทาง notarize ชัด:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

ผลลัพธ์:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### แจก Preview ฟรี

ไม่มี Apple Developer Program สร้าง ad-hoc preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

ไม่ notarized และไม่มี WeatherKit entitlement เมื่อเผยแพร่ signed appcast ใน Preview ถาวร Sparkle ตรวจ ดาวน์โหลด ยืนยัน ติดตั้ง เปิดใหม่ ครั้งแรกอาจ **System Settings > Privacy & Security > Open Anyway** Developer ID/notarization เป็นทางแนะนำเพื่อแจกไม่ถูกเตือน

## 2. รับรองโดย Apple

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

## 3. เผยแพร่และตรวจ

อัปโหลด ZIP DMG sums และ appcast GitHub สู่ tag เวอร์ชันเดียว ชื่อ `appcast.xml` universal, `appcast-arm64.xml`, `appcast-x86_64.xml` ไฟล์และ appcast Gitee ตรงกันชื่อเดียว tag เดียว ห้ามเสถียรเป็น prerelease คัดลอก Gitee ทั้งสามไป `update-release` ถาวร Preview ไป `preview` ถาวรสองเว็บ ช่องใช้ Gitee→GitHub `CN` และกลับกันประเทศอื่น

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

เผยแพร่ปกติตรวจไฟล์ local ลายเซ็น sums layout appcast รายการสองเว็บ feed ถาวร metadata ดาวน์โหลดซ้ำ ติดตั้ง และ Sparkle upgrade จริงเฉพาะขอชัด

เมื่อขอตรวจอัปเดต ใช้เก่าตรวจใหม่ ยืนยัน auto/manual ขาออก `CN` อ่าน Gitee ของช่องก่อนและ GitHub ครั้งเดียว อื่นกลับกัน ตรวจ Sparkle ลงและเปิด ZIP สถาปัตยกรรมที่ทำงาน การติดตั้งเดี่ยวยังเดี่ยว ทดสอบ Release→Preview/Preview→Release/ช่องเดียว สิ่งไม่ขอบันทึก `Not verified` ไม่เป็นเงื่อนไขจบเผยแพร่

## 4. ซิงก์ Homebrew cask

เสถียรจบที่ Homebrew Preview หยุดก่อนขั้นนี้ tap เสถียรอย่างเดียวจึง `brew upgrade` ไม่ไป prerelease

จาก root หลังปล่อยไฟล์:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

สคริปต์แก้ `version` และ `sha256` สองตัว `Casks/zisla.rb` อ่าน `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` และคู่ `x86_64` หากมี ไม่มีก็ดึง GitHub cask `#{arch}` ต่อเครื่อง Apple Silicon/Intel ดึงของตน ตรวจไม่ให้ใช้ digest เดียวทั้งคู่ ไม่เขียนถ้า `homebrew-cask.rb verify` ผิด ผ่านค่อย mirror `wzz6423/homebrew-tap` ไม่ `PUBLISH_TAP` ทดลองเฉพาะ cask ใน repo

`auto_updates true` เพราะ Sparkle ดูแลอัปเดต `brew upgrade` จะแทนเมื่อ bundle เก่ากว่า tap จริง Homebrew 5.1.6+ อ่าน version ภายใน `brew upgrade --cask zisla`/`--greedy` ใช้ประวัติ Homebrew จึงย้อน Sparkle กลับ tap ได้ commit cask พร้อม `latestRelease` เว็บ ต่างกัน CI ผิด ตรวจ root:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

ดาวน์โหลด ติดตั้ง อัปเกรด `livecheck` เฉพาะขอ ตัวอย่างติดตั้ง:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

ตรวจ Homebrew ไม่ขอเขียน `Not verified` ไม่เป็นเงื่อนไขเผยแพร่เสร็จ
