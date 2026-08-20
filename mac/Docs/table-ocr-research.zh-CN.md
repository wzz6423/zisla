# 表格识别与导出调研

调研日期：2026-08-20。以下仅采用厂商官方 API 文档或官方产品文档。

## 主流工具的共同模型

Google Document AI 将表格定义为类似 HTML 的表格结构：`headerRows`、`bodyRows`、行内 `cells`；每个单元格具备 `rowSpan`、`colSpan`，文字由 `layout.textAnchor` 指向原文。Azure Document Intelligence 同样返回完整网格（`rowCount`、`columnCount`、`cells`），每格含 `rowIndex`、`columnIndex`、`rowSpan`、`columnSpan`、`content` 及 `kind`（内容、行/列表头等）。

这说明可靠表格识别的输出不是“按 OCR 文本框排序”，而是：二维单元格网格、每格坐标、跨度和文字。合并单元格的内容只写入左上角锚点，并保留其跨行/跨列范围。

来源：

- [Google Document AI `Document.Page.Table` 协议](https://github.com/googleapis/googleapis/blob/master/google/cloud/documentai/v1/document.proto#L360-L395)
- [Google Document AI `Document` REST 资源](https://cloud.google.com/document-ai/docs/reference/rest/v1/Document)
- [Azure `DocumentTable` / `DocumentTableCell` OpenAPI](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/ai/data-plane/DocumentIntelligence/stable/2024-11-30/DocumentIntelligence.json#L4208-L4381)
- [Azure Analyze Document REST 参考](https://learn.microsoft.com/en-us/rest/api/aiservices/document-models/analyze-document?view=rest-aiservices-v4.0%20(2024-11-30))

## 导出格式

CSV 只定义记录和字段，不能表示单元格合并；因此 CSV 只能作为扁平兼容格式，无法满足“保留合并单元格”。Excel 的范围 API 将合并作为工作表范围的独立操作，这与上述二维网格加跨度的模型一致。

- [RFC 4180：CSV 格式](https://www.rfc-editor.org/rfc/rfc4180)
- [Microsoft Graph `Range: merge`](https://learn.microsoft.com/en-us/graph/api/range-merge?view=graph-rest-1.0)：将范围内单元格合并为一个区域
- [Adobe Acrobat：导出 PDF 到 Microsoft Excel 等格式](https://helpx.adobe.com/acrobat/using/exporting-pdfs-file-formats.html)

建议默认导出 `.xlsx`，以写入单元格值和 merge ranges；保留 CSV 作为“扁平 CSV”可选项。若暂时不引入 XLSX 写入器，界面必须明确 CSV 不保留合并信息，不能将其称为合并单元格导出。

## macOS 保存交互

`NSSavePanel` 是用户选择保存位置和文件名的系统界面；可作为指定窗口的 sheet（`beginSheetModal(for:completionHandler:)`），也可独立显示。截图编辑器窗口当前使用 `.screenSaver` 层级，而独立 `panel.begin` 的保存面板在普通层级，因而会被全屏截图窗口遮挡，直到截图窗口关闭才显现。

来源：[Apple `NSSavePanel`](https://developer.apple.com/documentation/appkit/nssavepanel)。

对 `mac/Sources/Zisla/ScreenshotEditorView.swift` 的最小改进建议：

1. 点击“表格识别”即展示 `NSSavePanel`，确认保存地址后再后台 OCR 并写入该 URL；保存意图得到即时反馈，且不会在识别完成后被截图窗口遮挡。
2. 若保留识别完成后才选位置的流程，则必须使用 `panel.beginSheetModal(for:completionHandler:)`，使保存面板附着到截图编辑器窗口并在其上方显示；无父窗口时才回退 `panel.begin`。
3. 用表格模型替换 `tableText(from:)` 的“按行拼 TSV”中间表示。至少先补全空单元格为规则网格；要真正处理图片中的合并范围，须增加表格线/单元格边界检测，或接入返回 `rowSpan`/`columnSpan` 的表格识别服务。仅靠 `VNRecognizeTextRequest` 的文字框无法可靠推导合并范围。
