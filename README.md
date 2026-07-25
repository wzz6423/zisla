# zisla

zisla 是面向桌面的跨平台动态工作空间。它把各平台实现放在独立目录中，让截图、录屏、桌面宠物等后续能力可以共享产品方向，同时保留各平台原生交互与技术栈。

## 仓库结构

- `mac/`：当前的 macOS 实现，使用 Swift、AppKit 和 SwiftUI 构建。
- `Web/`：zisla 官网页面。
- `windows/`：预留给未来 Windows 实现；目录将在该实现开始时加入仓库。

## macOS 开发

```bash
cd mac
swift run zisla
```

macOS Swift target、Bundle ID、本地数据目录和 `zislactl` 均使用 zisla 标识。升级时会自动迁移此前版本的本地数据和偏好设置。macOS 的功能、构建和测试说明见 [`mac/README.md`](mac/README.md)。
