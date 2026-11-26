# Đóng góp cho zisla

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../README.md)

Cảm ơn bạn đóng góp cho zisla.

## Báo cáo vấn đề

Cảm ơn bạn mở issue. Tìm Issues và Discussions có sẵn trước để tránh trùng báo cáo.

- Báo lỗi dùng `[Bug] Short problem description`, ví dụ `[Bug] Voice input is not written to the current text field`. Ghi phiên bản zisla, macOS, thiết bị, cách cài, bước tái hiện, mong muốn và thực tế.
- Đề xuất dùng `[Feature] Short request description` như `[Feature] Support custom voice-organization prompts`. Nêu vấn đề, giải pháp và lựa chọn khác đã cân nhắc.
- Chọn một **Area** bắt buộc định nhãn `area:*`: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation`, `Community & Discussion`. Biểu mẫu Trung giản thể cùng lựa chọn và nhãn.
- Xóa token, tài khoản, đường dẫn cục bộ và dữ liệu nhạy cảm khỏi log/ảnh/ghi.
- Báo lỗ hổng riêng qua [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), không issue công khai.
- Tự động thêm `bug`/`enhancement` và `area:*` tương ứng, giữ nhãn khác. Sai tiền tố/thiếu trường thêm `needs-more-info`, một bình luận ghi thiếu; sửa issue cập nhật bình luận.

## Phát triển

macOS ở `mac/`, cần macOS 14+ và Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Xóa binary kiểm thử/xây/đóng gói trước commit.

Trước mỗi commit/amend chạy `make format` từ gốc với SwiftFormat 0.64.7 giống CI. Xem diff, chỉ giữ định dạng cần cho tác vụ.

## Nhánh và commit

- Tạo từ `main` mới nhất, tiền tố đúng loại PR: `feat/` hoặc `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`, như `fix/download-timeout`/`ci/skip-directive-timing`.
- Dùng [Conventional Commits](https://www.conventionalcommits.org/) tiếng Anh, `type(scope): description` hoặc `fix(ui): resolve layout issue in notch area`.
- Một nhánh/một PR một mục tiêu, tránh chỉ định dạng hoặc refactor không liên quan.
- `publish-v*` dành bảo trì phát hành, đóng góp khác đến `main`.

## Yêu cầu hợp nhất

Cảm ơn mở PR. Kiểm các yêu cầu khi chờ xét.

- **Tiêu đề PR** là Conventional Commit tiếng Anh, ví dụ:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Loại cho phép `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`, `revert`.

- **Nội dung PR** tiếng Anh, có `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` của `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` giữ `- Project: zisla Development`; `Project Automation` dùng đưa PR vào bảng chung.
  - `Start date` và `Target date` bắt buộc mỗi trường một ngày thật `YYYY-MM-DD`; mục tiêu sau/bằng bắt đầu. Thiếu, trống, comment, trùng, ngày sai làm `PR Quality` lỗi. `Submitted date` tự ngày tạo UTC+08:00; `End date` tự khi merge, không nhập.
  - `PR Type` một `- Type:` khớp loại tiêu đề. Tiêu đề chuẩn; nội dung nhận nhãn/bí danh `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` đều fix. `PR Automation` đổi loại thành nhãn như fix→bug.
  - `Project Automation` chọn `Status` theo nhãn gồm loại PR, đặt `Done` khi đóng/merge; không điền tay.
  - `Summary` nêu thay đổi; `Risk and Rollback` đúng một `Risk` và một `Rollback` không trống.
  - Mỗi `Validation` bắt đầu `- Status:` riêng với `passed`, `failed`, `not run` chính xác. passed/failed cần `Command`/`Result` riêng không trống; not run cần `Reason` riêng. Không mượn trường mục khác; báo lỗi trung thực failed.
  - `Related Issue` đóng issue như `Closes #123`, thêm `development`, hoặc chính xác `None`.
  - `AI Attribution` một `- Agent:` không trống. Khác `None` phải có `- Co-authored-by: Name <email>` khớp, trailer trong ít nhất một commit, thêm `ai-assisted`.

  Tiêu đề mẫu `fix(ci): validate every PR metadata entry`

  Nội dung mẫu (ghi kết quả thật):

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

  Ngày ví dụ: tạo 2026-10-05, merge 2026-10-12 UTC+08:00. Trường tự trong comment chỉ minh họa giá trị Project, không đầu vào. Tự động cập nhật Project/PR Timeline, không comment mẫu.

  | Ngày | Khi tạo (2026-10-05) | Sau merge (2026-10-12) | Nguồn |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Bắt buộc nhập |
  | `Target date` | 2026-10-12 | 2026-10-12 | Bắt buộc nhập |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Tự ngày tạo |
  | `End date` | Trống | 2026-10-12 | Tự ngày merge |

- `PR Quality` xác minh, không merge khi lỗi; `PR Automation` sau đó nhãn/giao.
- macOS chạy `cd mac && swift test`, UI mô tả kiểm thủ công bằng chữ.
- PR/release notes chỉ chữ được, không cần ảnh/cover.
- Đổi tính năng/hành vi/mặc định/build/release phải cập nhật tài liệu chính thức/trợ giúp cùng patch. Website đủ 17 ngôn ngữ, tái dùng cấu trúc/trang dịch có sẵn.
- Không commit `.build`, `dist`, tải, log, token, khóa ký, dữ liệu cá nhân.
- `main`/`publish-v*` bảo vệ, chỉ PR xét và kiểm qua.

## Bỏ qua CI

Người duy trì/reviewer được yêu cầu có thể bỏ kiểm không ảnh hưởng, như chỉ tài liệu. Viết chỉ thị dòng riêng bình luận PR:

| Chỉ thị | Tác dụng |
| --- | --- |
| `skip-all` | Bỏ mọi workflow trong `.github/ci-skip.json`. |
| `skip-<workflow>` | Bỏ một tên/tệp/bí danh như `skip-swift`, `skip-web-ci`, `skip-Web CI`. |
| `unskip-all` | Xóa mọi skip. |
| `unskip-<workflow>` | Khôi phục một workflow. |

- Có chữ tự do sau như `skip-all: documentation only change`.
- Tên GitHub có khoảng trắng, `skip-CI Lint` và `skip-lint` giống nhau; tên khớp dài nhất thắng, phần dư ghi chú.
- Chỉ chủ kho, thành viên tổ chức, cộng tác viên, reviewer yêu cầu; bỏ bot.
- `CI Skip` hủy đang chạy, báo skip thành công để required thỏa, nhãn `skip-ci` và sửa một comment tóm tắt.
- Mỗi comment phát lại cả chuỗi, mới nhất thắng.
- Commit mới làm hết hiệu lực ngay vì chỉ mã người viết đã thấy, tránh merge mới chưa build. Mỗi push `CI Skip` bỏ nhãn/phục hồi kiểm, liệt kê hết hạn. Bình luận lại để bỏ commit mới.
- Có thể áp lại **Actions -> CI Skip -> Run workflow** bằng số PR, không comment.
- `.github/ci-skip.json` map workflow/check, lệch tệp gây `CI Checks` lỗi.

## Kiểm theo đường dẫn

Workflow nền tảng chỉ kiểm khi PR chạm tệp nó xây; tài liệu theo vị trí:

| Workflow | Đường dẫn kích hoạt |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- `paths` trong `.github/ci-skip.json` quy định; không khai luôn chạy. `CI Lint`, `PR Quality Gates`, `CodeQL`, `Dependency Review` mỗi PR. Vệ sinh kho/skill trong `CI Checks`; `hygiene`/`skills` cũ không dùng.
- Đổi `.github/` chạy hết vì CI phải chứng minh mọi nền tảng.
- Bỏ bằng job condition không workflow `paths:` để required thành công không chờ mãi.
- Đổi tên so đường cũ/mới, không phân hoa thường.
