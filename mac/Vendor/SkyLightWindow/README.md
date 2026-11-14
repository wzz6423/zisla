# SkyLightWindow

**English** | [简体中文](README.zh-CN.md)

A powerful macOS framework that enables views to be displayed above all other windows using private SkyLight APIs.

![Preview](https://raw.githubusercontent.com/Lakr233/SkyLightWindow/b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb/Resources/%E6%88%AA%E5%B1%8F2025-05-23%2020.18.33.png)

## Features

- 🚀 **Always on Top**: Display windows above all other applications, even fullscreen apps
- 🎯 **SwiftUI Integration**: Simple `.moveToSky()` modifier for any SwiftUI view
- 🔒 **System-Level Positioning**: Uses SkyLight framework for maximum window level control
- 🖥️ **Multi-Screen Support**: Works seamlessly across multiple displays
- 🎨 **Transparent Windows**: Support for transparent backgrounds and custom styling

## Installation

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"),
]
```

Platform compatibility:

- macOS 11.0+

## Usage

### SwiftUI Integration

1. **Import the framework**

```swift
import SwiftUI
import SkyLightWindow
```

2. **Apply the modifier to any view**

```swift
struct ContentView: View {
    var body: some View {
        Text("This view is always on top!")
            .moveToSky()
    }
}
```

### AppKit Usage

You can also create topmost windows programmatically:

```swift
import SkyLightWindow

let screen = NSScreen.main!
let view = AnyView(Text("Overlay Content"))
let controller = SkyLightOperator.shared.delegateView(view, toScreen: screen)

// or you can just delegate a window
```

## How It Works

SkyLightWindow uses macOS's private SkyLight framework to:

1. Create a special space at the highest system level
2. Move target windows to this space
3. Ensure windows remain visible above all other content

The framework handles:
- Connection to the SkyLight service
- Space creation and management
- Window delegation and positioning
- SwiftUI integration through view modifiers

## Important Notes

⚠️ **Privacy & Security**: This framework uses private APIs and may require special entitlements for distribution outside the Mac App Store.

⚠️ **System Compatibility**: Tested on macOS 11.0+ but may work on earlier versions. Private APIs can change between system updates.

## Example

Check out the included example project to see SkyLightWindow in action:

```bash
cd Example
open MoveToSky.xcworkspace
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

Copyright 2025 © Lakr Aream. All rights reserved.
