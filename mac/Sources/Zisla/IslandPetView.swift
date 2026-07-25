import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

/// 岛内宠物视图：嵌入灵动岛表面，受 `IslandSilhouette()` 裁剪，读起来像「在岛里面」。
///
/// 只负责按 `activity` 渲染程序化 idle；点击触发开心反馈。
struct IslandPetView: View {
    var sprite: PetSprite?
    var behavior: PetBehaviorController
    var side: PetSide
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let sprite {
                PetCompanionView(sprite: sprite, size: size, behavior: behavior)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
