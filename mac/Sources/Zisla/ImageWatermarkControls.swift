import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct ImageWatermarkControls: View {
    private enum ContentType { case text, image }
    @Binding var options: ImageWatermarkOptions
    @State private var type: ContentType
    @State private var text: String
    @State private var imageURL: URL?

    init(options: Binding<ImageWatermarkOptions>) {
        _options = options
        switch options.wrappedValue.content {
        case let .text(value):
            _type = State(initialValue: .text)
            _text = State(initialValue: value)
            _imageURL = State(initialValue: nil)
        case let .image(url):
            _type = State(initialValue: .image)
            _text = State(initialValue: "")
            _imageURL = State(initialValue: url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(AppLocalization.text("类型"), selection: $type) {
                AppLocalizedText("文字水印").tag(ContentType.text)
                AppLocalizedText("图片水印").tag(ContentType.image)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if type == .text {
                TextField(AppLocalization.text("水印文字"), text: Binding(get: { text }, set: {
                    text = $0
                    options.content = .text($0)
                }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                HStack {
                    AppLocalizedText("文字颜色")
                    TextField("#FFFFFF", text: $options.color).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(AppLocalization.text("文字颜色"))
                }
            } else {
                HStack(spacing: 8) {
                    Button(AppLocalization.text(imageURL == nil ? "选择水印图片" : "更换水印图片")) { chooseImage() }
                    Text(imageURL?.lastPathComponent ?? AppLocalization.text("未选择"))
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Picker(AppLocalization.text("水印位置"), selection: $options.position) {
                ForEach(ImageWatermarkPosition.allCases) { position in AppLocalizedText(position.title).tag(position) }
            }
            .pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 4) {
                HStack { AppLocalizedText("大小"); Spacer(); Text(options.scale, format: .percent.precision(.fractionLength(0))) }
                Slider(value: $options.scale, in: 0.01...1, step: 0.01).accessibilityLabel(AppLocalization.text("大小"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { AppLocalizedText("透明度"); Spacer(); Text(options.opacity, format: .percent.precision(.fractionLength(0))) }
                Slider(value: $options.opacity, in: 0...1, step: 0.01).accessibilityLabel(AppLocalization.text("透明度"))
            }
        }
        .onChange(of: type) { _, type in
            options.content = type == .text ? .text(text) : imageURL.map(ImageWatermarkContent.image) ?? .text("")
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageProcessingService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        WindowPlacement.prepareModal(panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageURL = url
        options.content = .image(url)
    }
}
