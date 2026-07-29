//
//  MoveToSkyApp.swift
//  MoveToSky
//
//  Created by 秋星桥 on 5/23/25.
//

import SkyLightWindow
import SwiftUI

@main
struct MoveToSkyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .moveToSky()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
