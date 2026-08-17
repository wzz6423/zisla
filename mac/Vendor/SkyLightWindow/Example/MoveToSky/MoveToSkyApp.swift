//
//  MoveToSkyApp.swift
//  MoveToSky
//
//  Created by Lakr Aream on 5/23/25.
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
