# ร่วมพัฒนา zisla

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **ไทย** | [ภาษาอื่น](../README.md)

ขอบคุณที่ร่วมพัฒนา zisla

## รายงานปัญหา

ขอบคุณที่เปิด Issue ค้น Issues/Discussions ที่มีแล้วก่อนเพื่อไม่รายงานซ้ำ

- บั๊กใช้ `[Bug] Short problem description` เช่น `[Bug] Voice input is not written to the current text field` ระบุ zisla/macOS/device วิธีติดตั้ง ขั้นเกิดซ้ำ คาดหวังและจริง
- ขอฟีเจอร์ `[Feature] Short request description` เช่น `[Feature] Support custom voice-organization prompts` อธิบายปัญหา วิธีเสนอ และทางอื่นพิจารณา
- เลือก **Area** หนึ่งบังคับ กำหนด `area:*`: `Feature Development` `Bug Fix` `CI & Build` `Documentation` `Community & Discussion` แบบจีนย่อมีตัวเลือก/labels เดียว
- ลบ token บัญชี path ส่วนตัว ข้อมูลอ่อนไหวจาก logs ภาพและบันทึก
- ช่องโหว่แจ้งส่วนตัว [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) ไม่ Issue public
- automation ให้ `bug`/`enhancement` กับ `area:*` ตรง เก็บ label อื่น ชื่อ prefix/ช่องต้องมีผิดเพิ่ม `needs-more-info` และ comment เดียวบอกขาด แก้ Issue แล้ว comment ปรับ

## พัฒนา

macOS อยู่ `mac/` ต้อง macOS 14+ Swift 6 / Xcode 16+

```bash
cd mac
swift test
```

ลบ binary ทดสอบ สร้าง แพ็กก่อน commit

ทุก commit/amend รัน `make format` root ด้วย SwiftFormat 0.64.7 ตรง CI ตรวจ diff เก็บเฉพาะ format งานนี้

## สาขาและ commit

- แตกจาก `main` ล่าสุด prefix ชนิด PR `feat/`/`feature/` `fix/` `docs/` `style/` `refactor/` `perf/` `test/` `chore/` `build/` `ci/` `revert/` เช่น `fix/download-timeout`/`ci/skip-directive-timing`
- ภาษาอังกฤษ [Conventional Commits](https://www.conventionalcommits.org/) `type(scope): description` เช่น `fix(ui): resolve layout issue in notch area`
- หนึ่ง branch/PR หนึ่งเป้าชัด ไม่ format-only/refactor อื่น
- `publish-v*` เฉพาะบำรุงปล่อย อื่นส่ง `main`

## คำขอรวมโค้ด

ขอบคุณที่ส่ง PR ตรวจข้อกำหนดระหว่างรอ review

- **ชื่อ PR** English Conventional Commit เช่น:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  ชนิดได้ `feat` `fix` `docs` `style` `refactor` `perf` `test` `chore` `build` `ci` `revert`

- **เนื้อ PR** อังกฤษ มี `Summary` `GitHub Project` `PR Type` `Validation` `Risk and Rollback` `Related Issue` `AI Attribution` จาก `.github/PULL_REQUEST_TEMPLATE.md`
  - `GitHub Project` คง `- Project: zisla Development` เพื่อ `Project Automation` ลง board ร่วม
  - `Start date`/`Target date` ต้องมีแต่ละครั้งเดียววันจริง `YYYY-MM-DD` เป้าหลัง/เท่าต้น ไม่มี ว่าง comment ซ้ำ ผิด ล้ม `PR Quality` `Submitted date` auto วันที่สร้าง UTC+08:00 `End date` auto merge ไม่ป้อนเอง
  - `PR Type` หนึ่ง `- Type:` ตรงชื่อ ชื่อ canonical เนื้อรับ aliases `fix` `bug` `bug fix` `bugfix` `hotfix` ทั้งหมด fix `PR Automation` แปลง label เช่น fix→bug
  - `Project Automation` เลือก `Status` ตาม label/type และ `Done` เมื่อปิด/merge ไม่ป้อน
  - `Summary` อธิบาย `Risk and Rollback` ต้อง `Risk`/`Rollback` ไม่ว่างอย่างละหนึ่ง
  - แต่ละ `Validation` มี `- Status:` ของตนตรง `passed` `failed` `not run` passed/failed ต้อง `Command`/`Result` ของตนไม่ว่าง not run `Reason` ของตน ไม่ใช้ข้าม รายงานผิดด้วย failed
  - `Related Issue` ปิดเช่น `Closes #123` เพิ่ม `development` หรือเท่ากับ `None`
  - `AI Attribution` หนึ่ง `- Agent:` ไม่ว่าง ไม่ None ต้องคู่ `- Co-authored-by: Name <email>` และ trailer อย่างน้อยหนึ่ง commit เพิ่ม `ai-assisted`

  ชื่อตัวอย่าง `fix(ci): validate every PR metadata entry`

  เนื้อตัวอย่าง (ผลตรวจจริง):

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

  สมมติสร้าง 2026-10-05 merge 2026-10-12 UTC+08:00 ช่อง auto ใน code comment แสดง Project ไม่ input automation เปลี่ยน Project/PR Timeline ไม่ comment ตัวอย่าง

  | วันที่ | สร้าง (2026-10-05) | หลัง merge (2026-10-12) | ที่มา |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | ต้องป้อน |
  | `Target date` | 2026-10-12 | 2026-10-12 | ต้องป้อน |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | สร้างอัตโนมัติ |
  | `End date` | ว่าง | 2026-10-12 | merge อัตโนมัติ |

- `PR Quality` ตรวจรูปแบบ ผิด merge ไม่ได้ `PR Automation` ให้ label/assign
- macOS รัน `cd mac && swift test` UI บอกผล manual เป็นข้อความ
- PR/release notes text-only ได้ ไม่ต้องภาพ/ปก
- ฟีเจอร์ พฤติกรรม default build/release ต้อง sync docs จริงและเว็บ patch เดียว เว็บ 17 ภาษา ใช้โครง help/directory เดิม
- ไม่ commit `.build` `dist` downloads logs tokens signing หรือข้อมูลส่วนตัว
- `main`/`publish-v*` ป้องกัน อัปเดตผ่าน reviewed passing PR

## ข้าม CI

maintainers/reviewers ที่ขอข้ามเมื่อไม่กระทบเช่น docs-only ใส่บรรทัดเดี่ยวใน comment PR

| คำสั่ง | ผล |
| --- | --- |
| `skip-all` | ข้ามทุก workflow ใน `.github/ci-skip.json` |
| `skip-<workflow>` | ข้ามหนึ่งชื่อ/ไฟล์/alias `skip-swift` `skip-web-ci` `skip-Web CI` |
| `unskip-all` | ล้างข้ามทั้งหมด |
| `unskip-<workflow>` | คืนหนึ่ง workflow |

- ต่อข้อความได้ `skip-all: documentation only change`
- ชื่อแสดง GitHub มี space ได้ `skip-CI Lint`=`skip-lint` ตรงยาวสุดชนะ คำเหลือ note
- รับ owner/member/collaborator/requested reviewer เท่านั้น bot ไม่รับ
- `CI Skip` ยกเลิกรัน แสดงข้ามเป็น success required ให้ `skip-ci` แก้ summary เดียว
- replay thread ทุก comment ใหม่สุดชนะ
- push commit ใหม่หมดอายุทันทีเพราะใช้โค้ดที่เห็นเท่านั้น ไม่ให้ใหม่ unbuilt merge ทุก push CI Skip ลบ label/คืนตรวจและบอก expired ต้อง comment ใหม่เพื่อข้ามใหม่
- maintainer reapply **Actions -> CI Skip -> Run workflow** ด้วยเลข PR ไม่ต้อง comment
- `.github/ci-skip.json` map workflow/check names ต่างจากไฟล์ทำ `CI Checks` ผิด

## ตรวจตาม path

platform รันเมื่อ PR แตะไฟล์สร้าง docs ตามที่อยู่

| workflow | path กระตุ้น |
| --- | --- |
| `Swift Tests` | `mac/**` `Makefile` `.swiftformat` `.github/**` |
| `Web CI` | `web/**` `promo/**` `docs/**` `.github/**` |

- `paths` ใน `.github/ci-skip.json` กำหนด ไม่มีรันเสมอ `CI Lint` `PR Quality Gates` `CodeQL` `Dependency Review` ทุก PR hygiene/skill เป็น `CI Checks` alias เก่า `hygiene`/`skills` ไม่ใช้
- `.github/` เปลี่ยนรันทุก platform
- ข้าม job condition ไม่ workflow `paths:` เพื่อ required success ไม่ pending
- rename match old/new ไม่สน case
