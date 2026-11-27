import SwiftUI
import ZislaKit

struct PetPreviewView: View {
    let petID: String
    let size: CGSize
    var userPetsDirectory: URL?
    @State private var loaded: (id: String, sprite: PetSprite?)?

    var body: some View {
        Group {
            if loaded?.id == petID, let sprite = loaded?.sprite {
                PetSpriteView(sprite: sprite, activity: .idle, size: size)
            } else {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: petID, initial: true) { _, id in
            let directory = userPetsDirectory ?? PetLibrary.userPetsDirectory
            loaded = (id, PetLibrary.loadSprite(for: id, userPetsDirectory: directory))
        }
    }
}
