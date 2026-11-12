import SwiftUI
import ZislaCore
import ZislaKit

struct ImageTransformControls: View {
    @Binding var options: ImageTransformOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(AppLocalization.text("旋转角度"), selection: $options.rotation) {
                ForEach(ImageRotation.allCases) { rotation in
                    AppLocalizedText(rotation.title).tag(rotation)
                }
            }
            .pickerStyle(.menu)
            Toggle(AppLocalization.text("水平镜像"), isOn: $options.flipHorizontal)
            Toggle(AppLocalization.text("垂直镜像"), isOn: $options.flipVertical)
        }
    }
}
