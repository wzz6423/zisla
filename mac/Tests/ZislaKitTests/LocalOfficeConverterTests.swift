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
}
