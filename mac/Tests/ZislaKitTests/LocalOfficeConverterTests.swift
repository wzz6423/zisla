import Foundation
import Testing
@testable import ZislaKit

struct LocalOfficeConverterTests {
    @Test(arguments: ["docx", "pptx", "xlsx", "ods", "csv"])
    func recognizesSupportedOfficeFormats(extensionName: String) {
        let url = URL(fileURLWithPath: "/tmp/document.\(extensionName)")
        #expect(LocalOfficeConverter.supports(url))
    }

    @Test
    func rejectsFormatsOutsideTheLocalOfficeContract() {
        #expect(!LocalOfficeConverter.supports(URL(fileURLWithPath: "/tmp/document.pdf")))
        #expect(!LocalOfficeConverter.supports(URL(fileURLWithPath: "/tmp/document.pages")))
    }

    @Test
    func usesAnIsolatedLibreOfficeProfileForEachConversion() {
        let arguments = LocalOfficeConverter.conversionArguments(
            input: URL(fileURLWithPath: "/tmp/input.docx"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true),
            profileDirectory: URL(fileURLWithPath: "/tmp/profile", isDirectory: true)
        )

        #expect(arguments.first == "-env:UserInstallation=file:///tmp/profile/")
        #expect(arguments.contains("--headless"))
        #expect(arguments.suffix(3) == ["--outdir", "/tmp/output", "/tmp/input.docx"])
    }

    @Test
    func conversionDrainsLargeProcessOutputAndMovesTheGeneratedPDF() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-office-converter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("soffice")
        try writeExecutable(
            """
            #!/bin/sh
            output_directory=''
            input=''
            while [ "$#" -gt 0 ]; do
                if [ "$1" = '--outdir' ]; then
                    shift
                    output_directory="$1"
                fi
                input="$1"
                shift
            done
            /usr/bin/yes output | /usr/bin/head -c 300000
            /usr/bin/yes diagnostic | /usr/bin/head -c 300000 >&2
            name=$(/usr/bin/basename "$input")
            stem=${name%.*}
            /usr/bin/printf 'converted' > "$output_directory/$stem.pdf"
            """,
            to: executable
        )
        let input = root.appendingPathComponent("input.docx")
        let output = root.appendingPathComponent("result.pdf")
        try Data("office".utf8).write(to: input)

        try LocalOfficeConverter(executableCandidates: [executable])
            .convertToPDF(input, outputURL: output)

        #expect(try Data(contentsOf: output) == Data("converted".utf8))
    }

    @Test
    func conversionFailureKeepsBoundedDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-office-converter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("soffice")
        try writeExecutable(
            """
            #!/bin/sh
            /usr/bin/yes diagnostic | /usr/bin/head -c 300000 >&2
            exit 9
            """,
            to: executable
        )
        let input = root.appendingPathComponent("input.docx")
        let output = root.appendingPathComponent("result.pdf")
        try Data("office".utf8).write(to: input)

        do {
            try LocalOfficeConverter(executableCandidates: [executable])
                .convertToPDF(input, outputURL: output)
            Issue.record("失败的转换进程不应被视为成功")
        } catch let error as LocalOfficeConverterError {
            guard case let .conversionFailed(diagnostics) = error else {
                Issue.record("应保留 conversionFailed 错误语义，实际为 \(error)")
                return
            }
            #expect(diagnostics.hasPrefix("diagnostic\n"))
            #expect(diagnostics.utf8.count == 256 * 1_024)
        }
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
