import SwiftUI

struct ScreenRecordingInspectorSection<Content: View, Actions: View>: View {
    let title: String
    let symbol: String
    private let content: Content
    private let actions: Actions
    private let isExpanded: Binding<Bool>?
    @State private var expanded: Bool

    init(_ title: String, symbol: String, expanded: Bool = true, isExpanded: Binding<Bool>? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.symbol = symbol
        self.content = content()
        self.actions = actions()
        self.isExpanded = isExpanded
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    disclosure
                    Spacer(minLength: 8)
                    actions.fixedSize()
                }
                VStack(alignment: .trailing, spacing: 8) {
                    disclosure
                    actions
                }
            }
            if (isExpanded ?? $expanded).wrappedValue {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dividerSubtle, lineWidth: 1))
        .controlSize(.small)
    }

    private var disclosure: some View {
        DisclosureGroup(isExpanded: isExpanded ?? $expanded) {} label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
        }
    }
}

extension ScreenRecordingInspectorSection where Actions == EmptyView {
    init(_ title: String, symbol: String, expanded: Bool = true, isExpanded: Binding<Bool>? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, expanded: expanded, isExpanded: isExpanded,
                  content: content, actions: { EmptyView() })
    }
}

struct ScreenRecordingNumberField: View {
    let title: String
    @Binding var value: Double
    let identifier: String
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TextField(title, value: $value, format: .number.locale(locale).precision(.fractionLength(0...3)))
                .font(.system(size: 12, design: .monospaced)).multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 84)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }.frame(minHeight: 26)
    }
}

struct ScreenRecordingParameterRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let identifier: String

    var body: some View {
        VStack(spacing: 4) {
            ScreenRecordingNumberField(title: title, value: $value, identifier: identifier)
            Slider(value: $value, in: range).controlSize(.small)
                .accessibilityLabel(title).accessibilityIdentifier(identifier + ".slider")
        }
    }
}
