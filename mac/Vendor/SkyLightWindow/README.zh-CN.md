# SkyLightWindow

[English](README.md) | **简体中文**

一个使用私有 SkyLight API 的 macOS 框架，可将视图显示在其他所有窗口之上。

![预览](https://raw.githubusercontent.com/Lakr233/SkyLightWindow/b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb/Resources/%E6%88%AA%E5%B1%8F2025-05-23%2020.18.33.png)

## 功能

- 🚀 **始终置顶**：窗口显示在其他所有应用之上，包括全屏应用。
- 🎯 **SwiftUI 集成**：任意 SwiftUI 视图都可使用简单的 `.moveToSky()` 修饰符。
- 🔒 **系统级窗口定位**：通过 SkyLight 框架控制窗口层级。
- 🖥️ **多显示器支持**：支持跨多个显示器使用。
- 🎨 **透明窗口**：支持透明背景和自定义样式。

## 安装

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"),
]
```

平台兼容性：

- macOS 11.0+

## 使用

### SwiftUI 集成

1. **导入框架**

```swift
import SwiftUI
import SkyLightWindow
```

2. **为任意视图添加修饰符**

```swift
struct ContentView: View {
    var body: some View {
        Text("This view is always on top!")
            .moveToSky()
    }
}
```

### AppKit 使用

也可以通过代码创建置顶窗口：

```swift
import SkyLightWindow

let screen = NSScreen.main!
let view = AnyView(Text("Overlay Content"))
let controller = SkyLightOperator.shared.delegateView(view, toScreen: screen)

// or you can just delegate a window
```

## 工作原理

SkyLightWindow 使用 macOS 私有 SkyLight 框架来：

1. 创建一个位于系统最高层级的特殊空间。
2. 将目标窗口移入此空间。
3. 确保窗口始终显示在其他内容之上。

框架负责：

- 连接 SkyLight 服务。
- 创建和管理空间。
- 托管和定位窗口。
- 通过视图修饰符与 SwiftUI 集成。

## 注意事项

⚠️ **隐私与安全**：该框架使用私有 API，在 Mac App Store 以外分发时可能需要特殊权限声明。

⚠️ **系统兼容性**：已在 macOS 11.0+ 上测试，也可能适用于更早版本。私有 API 可能随系统更新而变化。

## 示例

可通过附带的示例项目查看 SkyLightWindow 的使用方式：

```bash
cd Example
open MoveToSky.xcworkspace
```

## 许可证

本项目采用 MIT 许可证，详见 LICENSE 文件。

---

Copyright 2025 © Lakr Aream. All rights reserved.
