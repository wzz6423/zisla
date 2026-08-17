//
//  TopmostWindowController.swift
//  Halloween24
//
//  Created by Lakr Aream on 2024/10/31.
//

import AppKit

class TopmostWindowController: NSWindowController {
    init(screen: NSScreen) {
        let window = TopmostWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}
