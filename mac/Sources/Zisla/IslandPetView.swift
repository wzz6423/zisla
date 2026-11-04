import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

/// Island pet view rendered beside the expanded island or within the collapsed island.
///
/// Responsible only for rendering a programmatic idle animation based on `activity`; tap triggers a happy reaction.
struct IslandPetView: View {
    var sprite: PetSprite?
    var behavior: PetBehaviorController
    var side: PetSide
    var size = CGSize(width: 56, height: 56)

    var body: some View {
        ZStack {
            if let sprite {
                PetCompanionView(sprite: sprite, size: size, behavior: behavior)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size.height * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
