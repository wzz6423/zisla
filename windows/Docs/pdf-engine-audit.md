# Windows PDF 引擎审计

核查日期：2026-08-03。

## 目标范围

本审计只覆盖 macOS 已经向用户提供的第一阶段 PDF 工具：合并、拆分、页面导出、旋转、裁剪、元数据、加密和解除密码、文本导出、PNG/JPEG 渲染、图片转 PDF、文字/图片水印、页码，以及调用用户本机 LibreOffice 的 Office 转 PDF。

所有文档在本机处理。引擎不得上传文档、运行时下载二进制文件，或以网络服务替代本地能力。

## 候选结论

| 候选 | 许可证与来源 | 可覆盖内容 | 不能单独覆盖的内容 | 结论 |
| --- | --- | --- | --- | --- |
| QPDF 12.3.2 | Apache-2.0；上游固定发布标签 `v12.3.2` | 页面选择/重组、合并拆分、旋转、页面框、元数据、加解密和安全重写 | 页面像素渲染、可靠文字提取、绘制文字或图片内容 | 采用为结构和安全适配器 |
| PDFium 153.0.7988.0 | PDFium BSD/Apache 许可证及全部随包第三方通知；发行包装层 MIT | 加载密码 PDF、页数/元数据、文本提取、位图渲染、页裁剪、文字与图片页面对象、创建图片 PDF、保存副本 | 没有可作为产品承诺的密码设置接口 | 采用为渲染、文本和页面绘制适配器 |
| `Windows.Data.Pdf` | Windows 系统 API | 在已打包 Windows 应用中加载与渲染页面 | 不提供完整编辑或文字提取接口 | 仅可作为 PDFium 不可用时的预览回退，不承担功能对齐 |
| libharu 2.4.6 | zlib/libpng 风格许可证 | 生成简单 PDF、文字和 PNG/JPEG 图像页 | 不读取或编辑任意既有 PDF，也不提供渲染和文字提取 | 不作为主引擎；只有 PDFium 页面创建路径失败时才重新评估 |

QPDF 和 PDFium 是互补关系，不应让 UI 分别调用两套库。`PDFProcessing` Core 只保存跨引擎的页码、参数和输出安全规则；已实现的串行 `PDFProcessingService` 在后台选择适配器，并向已接线的 WinUI 工具页提供不可变快照。

## 推荐执行结构

```text
WinUI PDF 页面
        |
PDFProcessingService（串行后台队列、进度、取消、临时输出）
        |
        +-- QPDFAdapter   合并/拆分/导出/旋转/裁剪/元数据/加解密
        +-- PDFiumAdapter 文本/渲染/图片转 PDF/文字图片水印/页码
        +-- LibreOfficeAdapter 仅发现并调用用户已安装的 soffice.exe
```

- 文件写入前统一调用 Core 的输出校验：输出不能与输入相同、不能覆盖已有文件、拆分任务的输出不能重复。
- 适配器不向 XAML 暴露 QPDF、PDFium、COM 或 WinRT 类型。
- PDFium 的文字绘制必须在 Windows 实机验证中覆盖中文字体嵌入；不能以仅支持英文 Standard 14 字体宣称完成水印或页码。
- PDFium 适配器以固定 zlib/libjpeg-turbo 编码 PNG/JPEG；视觉验收必须检查渲染像素而不是只检查输出文件存在。

## 固定依赖状态与后续门槛

QPDF `v12.3.2` 完整源码已经固定在 `windows/Vendor/qpdf/12.3.2/`。其 zlib `1.3.2` 和 libjpeg-turbo `3.2.0` 直接依赖也分别固定在 `windows/Vendor/`。来源、发布资产 SHA-256、tag 提交、许可证、通知文件和关键文件哈希已记录在各自的 `ORIGIN.md` 与 `Dependencies.lock.json`。

PDFium `153.0.7988.0` 的 x64/ARM64 发布资产已固定在 `windows/Vendor/pdfium/153.0.7988.0/`。来源是 `bblanchon/pdfium-binaries` 的 `chromium/7988` 发布，两个归档哈希、发行提交、DLL、导入库和许可证文件哈希见其 `ORIGIN.md` 与 `Dependencies.lock.json`。`PDFium.props` 按 MSBuild 平台映射 x64/ARM64，`App.vcxproj` 链接导入库并把 `pdfium.dll` 作为 MSIX 内容复制；运行时不下载依赖。

QPDF 结构/加密适配器、PDFium 文本/渲染/绘制适配器、LibreOffice 本地调用适配器、串行 C++ 服务和 WinUI 工具页面均已接线。跨平台 UT 覆盖文字导出、PNG/JPEG 渲染、图片转 PDF、文字/图片水印、页码、输出冲突、临时文件清理、服务分派及缺失 LibreOffice 的失败路径；这仍不替代 Windows 实机验证。

### 当前可移植验证

2026-08-03 已在 macOS 的临时目录中用 Apple Clang 21 完成 zlib、libjpeg-turbo（JPEG 8 兼容模式）和 QPDF 的静态构建。QPDF 配置显式使用这两个临时静态库，并设置 `USE_IMPLICIT_CRYPTO=OFF` 与 `REQUIRE_CRYPTO_NATIVE=ON`；`qpdf --version` 和 `qpdf --show-crypto` 均通过，后者只显示 `native`。

该验证只证明固定源码和 C++20 构建路径可用，不替代 Windows x64/ARM64 的 MSVC、WinUI、MSIX 和实际 PDF 操作验证。

Windows 实机验证前必须满足下列条件：

1. 用已固定的 zlib 与 libjpeg-turbo 源码完成 QPDF 的 x64/ARM64 静态构建配置；使用原生加密后端，避免让 OpenSSL 或 GnuTLS 成为浮动依赖。
2. QPDF/PDFium 都要在 x64 和 ARM64 的 MSVC Release 构建中验证；PDFium 的 GN/Ninja/`depot_tools` 只属于开发机临时工具，不能成为产品运行时依赖。
3. 确认 MSIX 内含与目标架构一致的 `pdfium.dll`，并验证 WinUI XAML 文件选择、输出目录和服务状态更新。
4. 完成加密、错误密码、损坏 PDF、非 ASCII 路径、中文水印、多页渲染、Office 安装/未安装和输入/输出冲突的实机测试，再把功能清单标为完成。

## 一手资料

- QPDF 12.3.2 发布：<https://github.com/qpdf/qpdf/releases/tag/v12.3.2>
- QPDF 许可证：<https://github.com/qpdf/qpdf/blob/v12.3.2/LICENSE.txt>
- QPDF 命令与页面/加密选项：<https://qpdf.readthedocs.io/en/stable/cli.html>
- QPDF C++ Job 接口：<https://qpdf.readthedocs.io/en/stable/qpdf-job.html>
- PDFium 主许可证：<https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE>
- PDFium 构建说明：<https://pdfium.googlesource.com/pdfium/+/refs/heads/main/docs/build.md>
- PDFium 公开文字接口：<https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_text.h>
- PDFium 公开编辑接口：<https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_edit.h>
- 固定 PDFium 发行：<https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/7988>
- 固定 PDFium x64 资产：<https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/7988/pdfium-win-x64.tgz>
- 固定 PDFium ARM64 资产：<https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/7988/pdfium-win-arm64.tgz>
- Windows `PdfDocument`：<https://learn.microsoft.com/uwp/api/windows.data.pdf.pdfdocument>
- Windows `PdfPage.RenderToStreamAsync`：<https://learn.microsoft.com/uwp/api/windows.data.pdf.pdfpage.rendertostreamasync>
- libharu 2.4.6 发布：<https://github.com/libharu/libharu/releases/tag/v2.4.6>
- libharu 许可证：<https://github.com/libharu/libharu/blob/v2.4.6/LICENSE>
