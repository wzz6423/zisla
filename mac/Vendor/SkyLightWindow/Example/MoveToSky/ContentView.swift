//
//  ContentView.swift
//  MoveToSky
//
//  Created by 秋星桥 on 5/23/25.
//

import SwiftUI

struct ContentView: View {
    @State var count = 1
    var body: some View {
        Text("积累了 \(count) 的功德")
            .contentTransition(.numericText())
            .animation(.interactiveSpring, value: count)
            .font(.largeTitle)
            .padding(64)
            .onTapGesture { count += 1 }
    }
}
